#include "spi_flash_driver.h"
#include "esp_rom_gpio.h"
#include "soc/gpio_sig_map.h"
#include "driver/gpio.h"

static bool isKnownFlashId(uint32_t id) {
    if (id == 0x000000 || id == 0xFFFFFF) return false;
    uint8_t mfg = (id >> 16) & 0xFF;
    // Winbond (0xEF), GigaDevice (0xC8), Micron/ST (0x20), Macronix (0xC2), Puya (0x85), Boya (0x68), SST (0xBF), XTX (0x0B)
    return (mfg == 0xEF || mfg == 0xC8 || mfg == 0x20 || mfg == 0xC2 || 
            mfg == 0x85 || mfg == 0x68 || mfg == 0xBF || mfg == 0x0B);
}

static uint32_t probeFlashJedecBitbang(int cs, int sck, int mosi, int miso, bool mode3 = false) {
    // 1. Detach any peripheral / UART0 routing from pins
    esp_rom_gpio_connect_out_signal((gpio_num_t)cs, SIG_GPIO_OUT_IDX, false, false);
    esp_rom_gpio_connect_out_signal((gpio_num_t)sck, SIG_GPIO_OUT_IDX, false, false);
    esp_rom_gpio_connect_out_signal((gpio_num_t)mosi, SIG_GPIO_OUT_IDX, false, false);

    pinMode(cs, OUTPUT);
    digitalWrite(cs, HIGH);
    pinMode(sck, OUTPUT);
    digitalWrite(sck, mode3 ? HIGH : LOW);
    pinMode(mosi, OUTPUT);
    digitalWrite(mosi, HIGH);
    pinMode(miso, INPUT_PULLUP);
    delayMicroseconds(50);

    // 2. Exit Continuous Read Mode / Reset XIP (16 clocks with CS low and MOSI high)
    digitalWrite(cs, LOW);
    digitalWrite(mosi, HIGH);
    delayMicroseconds(2);
    for (int i = 0; i < 16; i++) {
        digitalWrite(sck, mode3 ? LOW : HIGH);
        delayMicroseconds(1);
        digitalWrite(sck, mode3 ? HIGH : LOW);
        delayMicroseconds(1);
    }
    digitalWrite(cs, HIGH);
    delayMicroseconds(10);

    // 3. Exit QPI Mode (Send 0xFF with CS low)
    digitalWrite(cs, LOW);
    delayMicroseconds(2);
    for (int i = 7; i >= 0; i--) {
        digitalWrite(mosi, HIGH);
        digitalWrite(sck, mode3 ? LOW : HIGH);
        delayMicroseconds(1);
        digitalWrite(sck, mode3 ? HIGH : LOW);
        delayMicroseconds(1);
    }
    digitalWrite(cs, HIGH);
    delayMicroseconds(10);

    // 4. Release from Deep Power-Down (0xAB)
    digitalWrite(cs, LOW);
    delayMicroseconds(2);
    for (int i = 7; i >= 0; i--) {
        digitalWrite(mosi, (0xAB >> i) & 1);
        digitalWrite(sck, mode3 ? LOW : HIGH);
        delayMicroseconds(1);
        digitalWrite(sck, mode3 ? HIGH : LOW);
        delayMicroseconds(1);
    }
    digitalWrite(cs, HIGH);
    delayMicroseconds(40); // tRES1 is max 30 us on W25Q128

    // 5. Software Reset: Enable Reset (0x66) then Reset (0x99)
    digitalWrite(cs, LOW);
    delayMicroseconds(2);
    for (int i = 7; i >= 0; i--) {
        digitalWrite(mosi, (0x66 >> i) & 1);
        digitalWrite(sck, mode3 ? LOW : HIGH);
        delayMicroseconds(1);
        digitalWrite(sck, mode3 ? HIGH : LOW);
        delayMicroseconds(1);
    }
    digitalWrite(cs, HIGH);
    delayMicroseconds(5);

    digitalWrite(cs, LOW);
    delayMicroseconds(2);
    for (int i = 7; i >= 0; i--) {
        digitalWrite(mosi, (0x99 >> i) & 1);
        digitalWrite(sck, mode3 ? LOW : HIGH);
        delayMicroseconds(1);
        digitalWrite(sck, mode3 ? HIGH : LOW);
        delayMicroseconds(1);
    }
    digitalWrite(cs, HIGH);
    delayMicroseconds(50); // tRST is max 30 us

    // 6. Probe JEDEC ID (0x9F)
    digitalWrite(cs, LOW);
    delayMicroseconds(2);
    for (int i = 7; i >= 0; i--) {
        digitalWrite(mosi, (0x9F >> i) & 1);
        digitalWrite(sck, mode3 ? LOW : HIGH);
        delayMicroseconds(1);
        digitalWrite(sck, mode3 ? HIGH : LOW);
        delayMicroseconds(1);
    }
    digitalWrite(mosi, LOW);

    uint32_t id = 0;
    for (int i = 23; i >= 0; i--) {
        digitalWrite(sck, mode3 ? LOW : HIGH);
        delayMicroseconds(1);
        int bit = digitalRead(miso);
        id = (id << 1) | (bit ? 1 : 0);
        digitalWrite(sck, mode3 ? HIGH : LOW);
        delayMicroseconds(1);
    }
    digitalWrite(cs, HIGH);
    return id;
}

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

    // 1. First probe configured flash pinout (fast path)
    uint32_t bitbangId = probeFlashJedecBitbang(_cs, _sck, _mosi, _miso, false);
    bool foundWorkingPinout = (bitbangId != 0x000000 && bitbangId != 0xFFFFFF);

    if (foundWorkingPinout) {
        Serial.printf("[FLASH] Pre-init bit-bang probed JEDEC ID: 0x%06X (CS=%d, SCK=%d, MOSI=%d, MISO=%d)\n",
                      (unsigned int)bitbangId, _cs, _sck, _mosi, _miso);
    } else {
        Serial.println(F("[FLASH] Configured pinout returned no response. Running 24-permutation scanner..."));
        const int p[4] = { 21, 20, 1, 0 };

        // Scan all 24 permutations (Mode 0)
        for (int i0 = 0; i0 < 4 && !foundWorkingPinout; i0++) {
            for (int i1 = 0; i1 < 4 && !foundWorkingPinout; i1++) {
                if (i1 == i0) continue;
                for (int i2 = 0; i2 < 4 && !foundWorkingPinout; i2++) {
                    if (i2 == i0 || i2 == i1) continue;
                    for (int i3 = 0; i3 < 4 && !foundWorkingPinout; i3++) {
                        if (i3 == i0 || i3 == i1 || i3 == i2) continue;
                        int cs = p[i0], sck = p[i1], mosi = p[i2], miso = p[i3];
                        uint32_t id = probeFlashJedecBitbang(cs, sck, mosi, miso, false);
                        if (id != 0x000000 && id != 0xFFFFFF) {
                            Serial.printf("[FLASH] *** SUCCESS! Found response at CS=%d, SCK=%d, MOSI=%d, MISO=%d -> JEDEC: 0x%06X ***\n",
                                          cs, sck, mosi, miso, (unsigned int)id);
                            _cs = cs; _sck = sck; _mosi = mosi; _miso = miso;
                            bitbangId = id;
                            foundWorkingPinout = true;
                            break;
                        }
                    }
                }
            }
        }

        // Fallback: Scan all 24 permutations with Mode 3 if Mode 0 had no response
        if (!foundWorkingPinout) {
            for (int i0 = 0; i0 < 4 && !foundWorkingPinout; i0++) {
                for (int i1 = 0; i1 < 4 && !foundWorkingPinout; i1++) {
                    if (i1 == i0) continue;
                    for (int i2 = 0; i2 < 4 && !foundWorkingPinout; i2++) {
                        if (i2 == i0 || i2 == i1) continue;
                        for (int i3 = 0; i3 < 4 && !foundWorkingPinout; i3++) {
                            if (i3 == i0 || i3 == i1 || i3 == i2) continue;
                            int cs = p[i0], sck = p[i1], mosi = p[i2], miso = p[i3];
                            uint32_t id = probeFlashJedecBitbang(cs, sck, mosi, miso, true);
                            if (id != 0x000000 && id != 0xFFFFFF) {
                                Serial.printf("[FLASH] *** SUCCESS! Mode 3 response at CS=%d, SCK=%d, MOSI=%d, MISO=%d -> JEDEC: 0x%06X ***\n",
                                              cs, sck, mosi, miso, (unsigned int)id);
                                _cs = cs; _sck = sck; _mosi = mosi; _miso = miso;
                                bitbangId = id;
                                foundWorkingPinout = true;
                                break;
                            }
                        }
                    }
                }
            }
        }

        if (!foundWorkingPinout) {
            Serial.println(F("[FLASH] All 24 permutations returned no response (0xFFFFFF / 0x000000)."));
            Serial.println(F("[FLASH] Running electrical pin diagnostics on GPIO 0, 1, 20, 21..."));
            
            // 1. Test Floating / Pull state of each pin
            const int testPins[] = { 0, 1, 20, 21 };
            for (int p_pin : testPins) {
                pinMode(p_pin, INPUT_PULLUP);
                delayMicroseconds(20);
                int pu = digitalRead(p_pin);
                pinMode(p_pin, INPUT_PULLDOWN);
                delayMicroseconds(20);
                int pd = digitalRead(p_pin);
                Serial.printf("  - GPIO %2d: PU=%d, PD=%d -> %s\n", 
                              p_pin, pu, pd,
                              (pu == 1 && pd == 0) ? "FLOATING (OK)" :
                              (pu == 1 && pd == 1) ? "TIED/PULLED TO 3V3" :
                              (pu == 0 && pd == 0) ? "SHORTED TO GND" : "UNKNOWN");
            }

            // 2. Test Output Driver on each pin
            for (int p_pin : testPins) {
                pinMode(p_pin, OUTPUT);
                digitalWrite(p_pin, HIGH);
                delayMicroseconds(10);
                int highRead = digitalRead(p_pin);
                digitalWrite(p_pin, LOW);
                delayMicroseconds(10);
                int lowRead = digitalRead(p_pin);
                Serial.printf("  - GPIO %2d output drive: Set HIGH -> Read %d, Set LOW -> Read %d (%s)\n",
                              p_pin, highRead, lowRead, (highRead == 1 && lowRead == 0) ? "PASS" : "FAIL");
            }

            // 3. Test for Shorts between pins
            for (size_t a = 0; a < 4; a++) {
                for (size_t b = a + 1; b < 4; b++) {
                    int pinA = testPins[a];
                    int pinB = testPins[b];
                    pinMode(pinA, OUTPUT);
                    pinMode(pinB, INPUT_PULLDOWN);
                    digitalWrite(pinA, HIGH);
                    delayMicroseconds(10);
                    int bWhenAHigh = digitalRead(pinB);
                    digitalWrite(pinA, LOW);
                    delayMicroseconds(10);
                    int bWhenALow = digitalRead(pinB);
                    if (bWhenAHigh == 1 && bWhenALow == 0) {
                        Serial.printf("  [WARN] SHORT DETECTED between GPIO %d and GPIO %d!\n", pinA, pinB);
                    }
                }
            }
        }
    }

    // 2. Cleanly reset pins and decouple from peripheral matrix before attaching to ESP-IDF SPI driver
    for (int p_pin : { _cs, _sck, _mosi, _miso }) {
        if (p_pin >= 0) {
            gpio_reset_pin((gpio_num_t)p_pin);
            esp_rom_gpio_connect_out_signal((gpio_num_t)p_pin, SIG_GPIO_OUT_IDX, false, false);
        }
    }
    gpio_set_pull_mode((gpio_num_t)_cs, GPIO_PULLUP_ONLY);

    // 3. Configure and initialize SPI2 bus
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

    // 4. Configure SPI flash device on bus (10 MHz matches working hardware diagnostic suite)
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

    // 5. Initialize flash chip
    err = esp_flash_init(_extChip);
    if (err != ESP_OK) {
        // Fallback: retry at 5 MHz if 10 MHz failed
        spi_bus_remove_flash_device(_extChip);
        _extChip = nullptr;
        dev_cfg.speed = ESP_FLASH_5MHZ;
        if (spi_bus_add_flash_device(&_extChip, &dev_cfg) == ESP_OK && _extChip) {
            err = esp_flash_init(_extChip);
        }
    }

    if (err != ESP_OK) {
        Serial.printf("[FLASH] esp_flash_init failed: 0x%X\n", err);
        if (_extChip) {
            spi_bus_remove_flash_device(_extChip);
            _extChip = nullptr;
        }
        return false;
    }

    // 6. Read JEDEC ID and probed size
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

    // 7. Register partition with ESP-IDF partition table for LittleFS (subtype 0x82 / SPIFFS)
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
    Serial.printf("[FLASH] External SPI2 Flash registered: %s (JEDEC: 0x%06X, %u MB, CS=%d, SCK=%d, MOSI=%d, MISO=%d, Partition: OK)\n",
                  getChipName(), (unsigned int)_jedecId, (unsigned int)(getCapacityBytes() / (1024 * 1024)),
                  _cs, _sck, _mosi, _miso);
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
