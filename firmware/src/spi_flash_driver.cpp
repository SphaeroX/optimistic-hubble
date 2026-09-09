#include "spi_flash_driver.h"

static const SPISettings FLASH_SPI_SETTINGS(20000000, MSBFIRST, SPI_MODE0);

SpiFlashDriver::SpiFlashDriver(int8_t sck, int8_t miso, int8_t mosi, int8_t cs)
    : _sck(sck),
      _miso(miso),
      _mosi(mosi),
      _cs(cs),
      _initialized(false),
      _jedecId(0),
      _spi(nullptr) {}

bool SpiFlashDriver::begin() {
    pinMode(_cs, OUTPUT);
    deselect();

    if (!_spi) {
        _spi = new SPIClass(FSPI);
    }
    _spi->begin(_sck, _miso, _mosi, _cs);

    // Wakeup in case it was in power-down mode
    wakeup();
    delay(5);

    _jedecId = readJedecId();
    uint8_t mfg = (_jedecId >> 16) & 0xFF;

    if (mfg == 0xEF || mfg == 0xC8 || mfg == 0x20 || mfg == 0x0B) {
        _initialized = true;
        Serial.printf("[FLASH] External SPI2 Flash detected: %s (JEDEC: 0x%06X, %u MB)\n",
                      getChipName(), _jedecId, (unsigned int)(getCapacityBytes() / (1024 * 1024)));
        return true;
    }

    Serial.printf("[FLASH] External SPI Flash not responding or invalid ID: 0x%06X (mfg=0x%02X)\n", 
                  _jedecId, mfg);
    _initialized = false;
    return false;
}

void SpiFlashDriver::end() {
    if (_spi) {
        _spi->end();
        delete _spi;
        _spi = nullptr;
    }
    pinMode(_cs, INPUT);
    _initialized = false;
}

uint32_t SpiFlashDriver::readJedecId() {
    _spi->beginTransaction(FLASH_SPI_SETTINGS);
    select();
    _spi->transfer(W25Q_CMD_JEDEC_ID);
    uint8_t b1 = _spi->transfer(0x00);
    uint8_t b2 = _spi->transfer(0x00);
    uint8_t b3 = _spi->transfer(0x00);
    deselect();
    _spi->endTransaction();

    return ((uint32_t)b1 << 16) | ((uint32_t)b2 << 8) | (uint32_t)b3;
}

size_t SpiFlashDriver::getCapacityBytes() const {
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

uint8_t SpiFlashDriver::readStatus1() {
    _spi->beginTransaction(FLASH_SPI_SETTINGS);
    select();
    _spi->transfer(W25Q_CMD_READ_STATUS_1);
    uint8_t status = _spi->transfer(0x00);
    deselect();
    _spi->endTransaction();
    return status;
}

bool SpiFlashDriver::writeEnable() {
    _spi->beginTransaction(FLASH_SPI_SETTINGS);
    select();
    _spi->transfer(W25Q_CMD_WRITE_ENABLE);
    deselect();
    _spi->endTransaction();

    uint8_t status = readStatus1();
    return (status & W25Q_STATUS_WEL_BIT) != 0;
}

bool SpiFlashDriver::waitBusy(uint32_t timeoutMs) {
    unsigned long start = millis();
    while (millis() - start < timeoutMs) {
        if ((readStatus1() & W25Q_STATUS_BUSY_BIT) == 0) {
            return true;
        }
        delay(1);
    }
    return false;
}

bool SpiFlashDriver::read(uint32_t address, uint8_t* buffer, size_t length) {
    if (!_initialized || !buffer || length == 0) return false;

    _spi->beginTransaction(FLASH_SPI_SETTINGS);
    select();
    _spi->transfer(W25Q_CMD_READ_DATA);
    _spi->transfer((address >> 16) & 0xFF);
    _spi->transfer((address >> 8) & 0xFF);
    _spi->transfer(address & 0xFF);

    _spi->transferBytes(nullptr, buffer, length);

    deselect();
    _spi->endTransaction();
    return true;
}

bool SpiFlashDriver::writePage(uint32_t address, const uint8_t* data, size_t length) {
    if (!_initialized || !data || length == 0 || length > W25Q_PAGE_SIZE) return false;

    if (!waitBusy()) return false;
    if (!writeEnable()) return false;

    _spi->beginTransaction(FLASH_SPI_SETTINGS);
    select();
    _spi->transfer(W25Q_CMD_PAGE_PROGRAM);
    _spi->transfer((address >> 16) & 0xFF);
    _spi->transfer((address >> 8) & 0xFF);
    _spi->transfer(address & 0xFF);

    _spi->transferBytes(const_cast<uint8_t*>(data), nullptr, length);

    deselect();
    _spi->endTransaction();

    return waitBusy(100);
}

bool SpiFlashDriver::eraseSector(uint32_t address) {
    if (!_initialized) return false;

    if (!waitBusy()) return false;
    if (!writeEnable()) return false;

    _spi->beginTransaction(FLASH_SPI_SETTINGS);
    select();
    _spi->transfer(W25Q_CMD_SECTOR_ERASE_4K);
    _spi->transfer((address >> 16) & 0xFF);
    _spi->transfer((address >> 8) & 0xFF);
    _spi->transfer(address & 0xFF);
    deselect();
    _spi->endTransaction();

    return waitBusy(800); // 4KB sector erase typically ~45ms, max 400ms
}

bool SpiFlashDriver::eraseChip() {
    if (!_initialized) return false;

    if (!waitBusy()) return false;
    if (!writeEnable()) return false;

    _spi->beginTransaction(FLASH_SPI_SETTINGS);
    select();
    _spi->transfer(W25Q_CMD_CHIP_ERASE);
    deselect();
    _spi->endTransaction();

    return waitBusy(100000); // Chip erase can take tens of seconds
}

void SpiFlashDriver::sleep() {
    if (!_initialized) return;
    waitBusy();
    _spi->beginTransaction(FLASH_SPI_SETTINGS);
    select();
    _spi->transfer(W25Q_CMD_POWER_DOWN);
    deselect();
    _spi->endTransaction();
}

void SpiFlashDriver::wakeup() {
    if (!_spi) return;
    _spi->beginTransaction(FLASH_SPI_SETTINGS);
    select();
    _spi->transfer(W25Q_CMD_RELEASE_POWER_DOWN);
    deselect();
    _spi->endTransaction();
    delayMicroseconds(50);
}
