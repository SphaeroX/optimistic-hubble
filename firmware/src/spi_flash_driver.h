#pragma once
#include <Arduino.h>
#include "config.h"
#include "esp_flash.h"
#include "esp_flash_spi_init.h"
#include "esp_partition.h"
#include "driver/spi_common.h"

// W25Q128 Standard Commands & Parameters
#define W25Q128_JEDEC_ID            0xEF4018
#define W25Q128_CAPACITY_BYTES      (16UL * 1024UL * 1024UL) // 16 MB

class SpiFlashDriver {
public:
    SpiFlashDriver(int8_t sck = PIN_FLASH_SCK,
                   int8_t miso = PIN_FLASH_MISO,
                   int8_t mosi = PIN_FLASH_MOSI,
                   int8_t cs = PIN_FLASH_CS);
    ~SpiFlashDriver();

    bool begin();
    void end();

    bool isConnected() const { return _initialized; }
    bool isPartitionRegistered() const { return _partition != nullptr; }
    const esp_partition_t* getPartition() const { return _partition; }
    const char* getPartitionLabel() const { return "ext_flash"; }
    uint32_t getJedecId() const { return _jedecId; }
    size_t getCapacityBytes() const;
    const char* getChipName() const;

    bool read(uint32_t address, uint8_t* buffer, size_t length);
    bool write(uint32_t address, const uint8_t* data, size_t length);
    bool eraseRegion(uint32_t address, size_t length);
    bool eraseChip();

    void sleep();
    void wakeup();

private:
    int8_t _sck;
    int8_t _miso;
    int8_t _mosi;
    int8_t _cs;
    bool _initialized;
    bool _busInitialized;
    uint32_t _jedecId;
    size_t _chipSize;
    esp_flash_t* _extChip;
    const esp_partition_t* _partition;
};
