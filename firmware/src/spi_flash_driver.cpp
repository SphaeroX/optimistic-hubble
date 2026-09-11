#include "spi_flash_driver.h"

SpiFlashDriver::SpiFlashDriver(int8_t sck, int8_t miso, int8_t mosi, int8_t cs)
    : _sck(sck),
      _miso(miso),
      _mosi(mosi),
      _cs(cs),
      _initialized(false),
      _busInitialized(false),
      _jedecId(0),
      _chipSize(0),
      _extChip(nullptr),
      _partition(nullptr) {}

SpiFlashDriver::~SpiFlashDriver() {
    end();
}

bool SpiFlashDriver::begin() {
    if (_initialized) return true;

    // 1. Bit-bang hardware stabilization, wake-up from Deep Power-Down (0xAB) and reset (0x66, 0x99)
    // CS is on GPIO 21 (UART0 TX at boot), SCK on GPIO 20 (UART0 RX at boot).
    // Drive CS HIGH immediately to deselect flash before configuring the bus.
    pinMode(_cs, OUTPUT);
    digitalWrite(_cs, HIGH);
    pinMode(_sck, OUTPUT);
    digitalWrite(_sck, LOW);
    pinMode(_mosi, OUTPUT);
    digitalWrite(_mosi, LOW);
    pinMode(_miso, INPUT_PULLUP);
    delay(5);

    // Send Release Power-Down (0xAB)
    digitalWrite(_cs, LOW);
    delayMicroseconds(2);
    for (int i = 7; i >= 0; i--) {
        digitalWrite(_mosi, (0xAB >> i) & 1);
        digitalWrite(_sck, HIGH);
        delayMicroseconds(1);
        digitalWrite(_sck, LOW);
        delayMicroseconds(1);
    }
    digitalWrite(_cs, HIGH);
    delayMicroseconds(100); // tRES1 is max 30 us on W25Q128

    // Send Software Reset Enable (0x66)
    digitalWrite(_cs, LOW);
    delayMicroseconds(2);
    for (int i = 7; i >= 0; i--) {
        digitalWrite(_mosi, (0x66 >> i) & 1);
        digitalWrite(_sck, HIGH);
        delayMicroseconds(1);
        digitalWrite(_sck, LOW);
        delayMicroseconds(1);
    }
    digitalWrite(_cs, HIGH);
    delayMicroseconds(10);

    // Send Software Reset (0x99)
    digitalWrite(_cs, LOW);
    delayMicroseconds(2);
    for (int i = 7; i >= 0; i--) {
        digitalWrite(_mosi, (0x99 >> i) & 1);
        digitalWrite(_sck, HIGH);
        delayMicroseconds(1);
        digitalWrite(_sck, LOW);
        delayMicroseconds(1);
    }
    digitalWrite(_cs, HIGH);
    delayMicroseconds(100); // tRST is max 30 us

    // Probe JEDEC ID (0x9F) via bit-bang to verify hardware presence and response
    digitalWrite(_cs, LOW);
    delayMicroseconds(2);
    for (int i = 7; i >= 0; i--) {
        digitalWrite(_mosi, (0x9F >> i) & 1);
        digitalWrite(_sck, HIGH);
        delayMicroseconds(1);
        digitalWrite(_sck, LOW);
        delayMicroseconds(1);
    }
    uint32_t bitbangId = 0;
    for (int i = 23; i >= 0; i--) {
        digitalWrite(_sck, HIGH);
        delayMicroseconds(1);
        int b = digitalRead(_miso);
        bitbangId = (bitbangId << 1) | (b ? 1 : 0);
        digitalWrite(_sck, LOW);
        delayMicroseconds(1);
    }
    digitalWrite(_cs, HIGH);
    Serial.printf("[FLASH] Pre-init bit-bang probed JEDEC ID: 0x%06X\n", (unsigned int)bitbangId);

    // Reset SPI pins before attaching to ESP-IDF SPI driver
    gpio_reset_pin((gpio_num_t)_cs);
    gpio_reset_pin((gpio_num_t)_sck);
    gpio_reset_pin((gpio_num_t)_mosi);
    gpio_reset_pin((gpio_num_t)_miso);
    gpio_set_pull_mode((gpio_num_t)_cs, GPIO_PULLUP_ONLY);

    // 2. Configure and initialize SPI2 bus
    spi_bus_config_t bus_cfg = {};
    bus_cfg.mosi_io_num = _mosi;
    bus_cfg.miso_io_num = _miso;
    bus_cfg.sclk_io_num = _sck;
    bus_cfg.quadwp_io_num = -1;
    bus_cfg.quadhd_io_num = -1;
    bus_cfg.max_transfer_sz = 4096;

    esp_err_t err = spi_bus_initialize(SPI2_HOST, &bus_cfg, SPI_DMA_CH_AUTO);
    if (err == ESP_OK) {
        _busInitialized = true;
    } else if (err != ESP_ERR_INVALID_STATE) {
        Serial.printf("[FLASH] spi_bus_initialize failed: 0x%X\n", err);
        return false;
    }

    // 3. Configure SPI flash device on bus (10 MHz matches working hardware diagnostic suite)
    esp_flash_spi_device_config_t dev_cfg = {};
    dev_cfg.host_id = SPI2_HOST;
    dev_cfg.cs_io_num = _cs;
    dev_cfg.io_mode = SPI_FLASH_SLOWRD; // Robust standard read
    dev_cfg.speed = ESP_FLASH_10MHZ;
    dev_cfg.cs_id = 0;

    err = spi_bus_add_flash_device(&_extChip, &dev_cfg);
    if (err != ESP_OK || !_extChip) {
        Serial.printf("[FLASH] spi_bus_add_flash_device failed: 0x%X\n", err);
        return false;
    }

    // 4. Initialize flash chip
    err = esp_flash_init(_extChip);
    if (err != ESP_OK) {
        Serial.printf("[FLASH] esp_flash_init failed: 0x%X\n", err);
        spi_bus_remove_flash_device(_extChip);
        _extChip = nullptr;
        return false;
    }

    // 5. Read JEDEC ID and probed size
    err = esp_flash_read_id(_extChip, &_jedecId);
    if (err != ESP_OK || _jedecId == 0x000000 || _jedecId == 0xFFFFFF) {
        if (bitbangId != 0 && bitbangId != 0xFFFFFF) {
            Serial.printf("[FLASH] Using bit-bang probed JEDEC ID: 0x%06X\n", (unsigned int)bitbangId);
            _jedecId = bitbangId;
        } else {
            Serial.printf("[FLASH] esp_flash_read_id invalid: 0x%06X (err: 0x%X)\n", (unsigned int)_jedecId, err);
            spi_bus_remove_flash_device(_extChip);
            _extChip = nullptr;
            return false;
        }
    }
    _chipSize = _extChip->size;
    if (_chipSize == 0) {
        _chipSize = getCapacityBytes();
    }
    _extChip->size = _chipSize; // Synchronize struct so esp_partition_register_external passes size validation

    // 6. Register partition with ESP-IDF partition table for LittleFS (subtype 0x82 / SPIFFS)
    err = esp_partition_register_external(_extChip, 0, _chipSize, "ext_flash",
                                         ESP_PARTITION_TYPE_DATA,
                                         ESP_PARTITION_SUBTYPE_DATA_SPIFFS,
                                         &_partition);
    if (err != ESP_OK) {
        Serial.printf("[FLASH] esp_partition_register_external failed: 0x%X\n", err);
        _partition = nullptr;
        spi_bus_remove_flash_device(_extChip);
        _extChip = nullptr;
        return false;
    }

    _initialized = true;
    Serial.printf("[FLASH] External SPI2 Flash registered: %s (JEDEC: 0x%06X, %u MB, Partition: OK)\n",
                  getChipName(), (unsigned int)_jedecId, (unsigned int)(getCapacityBytes() / (1024 * 1024)));
    return true;
}

void SpiFlashDriver::end() {
    if (_partition) {
        esp_partition_deregister_external(_partition);
        _partition = nullptr;
    }
    if (_extChip) {
        spi_bus_remove_flash_device(_extChip);
        _extChip = nullptr;
    }
    if (_busInitialized) {
        spi_bus_free(SPI2_HOST);
        _busInitialized = false;
    }
    _initialized = false;
}

size_t SpiFlashDriver::getCapacityBytes() const {
    if (_chipSize > 0) return _chipSize;
    uint8_t capCode = _jedecId & 0xFF;
    switch (capCode) {
        case 0x18: return 16UL * 1024UL * 1024UL; // W25Q128 (16MB)
        case 0x19: return 32UL * 1024UL * 1024UL; // W25Q256 (32MB)
        case 0x17: return 8UL * 1024UL * 1024UL;  // W25Q64 (8MB)
        case 0x16: return 4UL * 1024UL * 1024UL;  // W25Q32 (4MB)
        default:   return 16UL * 1024UL * 1024UL;
    }
}

const char* SpiFlashDriver::getChipName() const {
    uint8_t mfg = (_jedecId >> 16) & 0xFF;
    uint8_t cap = _jedecId & 0xFF;

    if (mfg == 0xEF) {
        if (cap == 0x18) return "Winbond W25Q128 (16MB)";
        if (cap == 0x19) return "Winbond W25Q256 (32MB)";
        if (cap == 0x17) return "Winbond W25Q64 (8MB)";
        return "Winbond SPI Flash";
    } else if (mfg == 0xC8) {
        return "GigaDevice SPI Flash";
    }
    return "Generic SPI NOR Flash";
}

bool SpiFlashDriver::read(uint32_t address, uint8_t* buffer, size_t length) {
    if (!_initialized || !_extChip || !buffer || length == 0) return false;
    return esp_flash_read(_extChip, buffer, address, length) == ESP_OK;
}

bool SpiFlashDriver::write(uint32_t address, const uint8_t* data, size_t length) {
    if (!_initialized || !_extChip || !data || length == 0) return false;
    return esp_flash_write(_extChip, data, address, length) == ESP_OK;
}

bool SpiFlashDriver::eraseRegion(uint32_t address, size_t length) {
    if (!_initialized || !_extChip) return false;
    return esp_flash_erase_region(_extChip, address, length) == ESP_OK;
}

bool SpiFlashDriver::eraseChip() {
    if (!_initialized || !_extChip) return false;
    return esp_flash_erase_chip(_extChip) == ESP_OK;
}

void SpiFlashDriver::sleep() {
    if (_extChip) {
        // Send Deep Power-Down command 0xB9
        spi_flash_trans_t t = {};
        t.command = 0xB9;
        _extChip->host->driver->common_command(_extChip->host, &t);
    }
}

void SpiFlashDriver::wakeup() {
    if (_extChip) {
        // Send Release Deep Power-Down command 0xAB
        spi_flash_trans_t t = {};
        t.command = 0xAB;
        _extChip->host->driver->common_command(_extChip->host, &t);
        delayMicroseconds(50);
    }
}
