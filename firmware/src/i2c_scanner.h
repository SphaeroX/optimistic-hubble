#pragma once
#include <Arduino.h>
#include <Wire.h>

struct I2cScanResult {
    uint8_t count;
    uint8_t addresses[16];
    bool hasBmi160;
    uint8_t bmi160Address;
};

class I2cScanner {
public:
    static void begin(int sdaPin, int sclPin, uint32_t frequency = 100000);
    static I2cScanResult scanBus();
    static void printScanReport(const I2cScanResult& result);
};
