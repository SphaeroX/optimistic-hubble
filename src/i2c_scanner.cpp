#include "i2c_scanner.h"
#include "config.h"

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
            if (address == BMI160_DEFAULT_ADDR || address == BMI160_ALT_ADDR) {
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
            if (addr == BMI160_DEFAULT_ADDR) {
                Serial.print(F(" (Likely BMI160 IMU @ Primary 0x68)"));
            } else if (addr == BMI160_ALT_ADDR) {
                Serial.print(F(" (Likely BMI160 IMU @ Alternate 0x69)"));
            }
            Serial.println();
        }
    }
    Serial.println(F("--------------------------------------------------"));
}
