#include "i2c_scanner.h"

void I2cScanner::begin(int sdaPin, int sclPin, uint32_t frequency) {
    Wire.begin(sdaPin, sclPin, frequency);
}

I2cScanResult I2cScanner::scanBus() {
    I2cScanResult result;
    result.count = 0;
    result.hasBmi160 = false;
    result.bmi160Address = 0x00;

    for (uint8_t address = 1; address < 127; ++address) {
        Wire.beginTransmission(address);
        uint8_t error = Wire.endTransmission();

        if (error == 0) {
            if (result.count < 16) {
                result.addresses[result.count++] = address;
            }
            if (address == 0x6A || address == 0x68 || address == 0x69 || address == 0x6B) {
                result.hasBmi160 = true;
                result.bmi160Address = address;
            }
        }
    }
    return result;
}

void I2cScanner::printScanReport(const I2cScanResult& result) {
    Serial.println(F("--------------------------------------------------"));
    Serial.println(F("[I2C SCAN] Scanning I2C bus (SDA: D4/GPIO6, SCL: D5/GPIO7)..."));

    if (result.count == 0) {
        Serial.println(F("  [!] ERROR: No I2C devices found!"));
        Serial.println(F("      Check: VCC (3.3V), GND, SDA, and SCL connections."));
    } else {
        Serial.printf("  [+] Found %u I2C device(s):\n", result.count);
        for (uint8_t i = 0; i < result.count; ++i) {
            uint8_t addr = result.addresses[i];
            Serial.printf("      - Device #%u: 0x%02X", i + 1, addr);
            if (addr == 0x6A) {
                Serial.print(F(" (ST LSM6DS-series IMU @ Primary 0x6A)"));
            } else if (addr == 0x68) {
                Serial.print(F(" (Bosch BMI160 / MPU IMU @ Primary 0x68)"));
            } else if (addr == 0x69 || addr == 0x6B) {
                Serial.print(F(" (Alternate IMU Address)"));
            }
            Serial.println();
        }
    }
    Serial.println(F("--------------------------------------------------"));
}
