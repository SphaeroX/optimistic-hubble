#pragma once
#include <Arduino.h>
#include <Wire.h>

struct Bmi160RawData {
    int16_t accelX;
    int16_t accelY;
    int16_t accelZ;
    int16_t gyroX;
    int16_t gyroY;
    int16_t gyroZ;
};

struct Bmi160MetricData {
    float accelX_g;   // Acceleration in g
    float accelY_g;
    float accelZ_g;
    float gyroX_dps;  // Angular velocity in deg/sec
    float gyroY_dps;
    float gyroZ_dps;
};

class Bmi160Driver {
public:
    Bmi160Driver(uint8_t i2cAddress = 0x68);

    bool begin(uint8_t i2cAddress = 0x68);
    uint8_t readChipId();
    bool readSensorData(Bmi160MetricData& metricData, Bmi160RawData* rawDataOut = nullptr);
    uint8_t getAddress() const { return _address; }
    bool isConnected() const { return _initialized; }

private:
    uint8_t _address;
    bool _initialized;

    bool writeRegister(uint8_t reg, uint8_t value);
    bool readRegisters(uint8_t reg, uint8_t* buffer, size_t length);
};
