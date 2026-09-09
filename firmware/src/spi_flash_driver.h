#pragma once
#include <Arduino.h>
#include <SPI.h>
#include "config.h"

// W25Q128 Standard Commands
#define W25Q_CMD_WRITE_ENABLE       0x06
#define W25Q_CMD_WRITE_DISABLE      0x04
#define W25Q_CMD_READ_STATUS_1      0x05
#define W25Q_CMD_READ_STATUS_2      0x35
#define W25Q_CMD_READ_STATUS_3      0x15
#define W25Q_CMD_READ_DATA          0x03
#define W25Q_CMD_FAST_READ          0x0B
#define W25Q_CMD_PAGE_PROGRAM       0x02
#define W25Q_CMD_SECTOR_ERASE_4K    0x20
#define W25Q_CMD_BLOCK_ERASE_32K    0x52
#define W25Q_CMD_BLOCK_ERASE_64K    0xD8
#define W25Q_CMD_CHIP_ERASE         0xC7
#define W25Q_CMD_JEDEC_ID           0x9F
#define W25Q_CMD_POWER_DOWN         0xB9
#define W25Q_CMD_RELEASE_POWER_DOWN 0xAB

#define W25Q_STATUS_BUSY_BIT        0x01
#define W25Q_STATUS_WEL_BIT         0x02

#define W25Q128_JEDEC_ID            0xEF4018
#define W25Q128_CAPACITY_BYTES      (16UL * 1024UL * 1024UL) // 16 MB
#define W25Q_PAGE_SIZE              256
#define W25Q_SECTOR_SIZE            4096

class SpiFlashDriver {
public:
    SpiFlashDriver(int8_t sck = PIN_FLASH_SCK,
                   int8_t miso = PIN_FLASH_MISO,
                   int8_t mosi = PIN_FLASH_MOSI,
                   int8_t cs = PIN_FLASH_CS);

    bool begin();
    void end();

    uint32_t readJedecId();
    bool isConnected() const { return _initialized; }
    uint32_t getJedecId() const { return _jedecId; }
    size_t getCapacityBytes() const;
    const char* getChipName() const;

    bool read(uint32_t address, uint8_t* buffer, size_t length);
    bool writePage(uint32_t address, const uint8_t* data, size_t length);
    bool eraseSector(uint32_t address);
    bool eraseChip();

    void sleep();
    void wakeup();

private:
    int8_t _sck;
    int8_t _miso;
    int8_t _mosi;
    int8_t _cs;
    bool _initialized;
    uint32_t _jedecId;
    SPIClass* _spi;

    inline void select() {
        digitalWrite(_cs, LOW);
    }

    inline void deselect() {
        digitalWrite(_cs, HIGH);
    }

    uint8_t readStatus1();
    bool writeEnable();
    bool waitBusy(uint32_t timeoutMs = 2000);
};
