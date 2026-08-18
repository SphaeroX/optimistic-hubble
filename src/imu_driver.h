#pragma once
#include <Arduino.h>
#include <Wire.h>

enum ImuType {
    IMU_TYPE_NONE = 0,
    IMU_TYPE_BMI160,
    IMU_TYPE_LSM6DS,
    IMU_TYPE_MPU6050
};

struct ImuRawData {
    int16_t accelX;
    int16_t accelY;
    int16_t accelZ;
    int16_t gyroX;
    int16_t gyroY;
    int16_t gyroZ;
};

struct ImuMetricData {
    float accelX_g;   // Acceleration in g
    float accelY_g;
    float accelZ_g;
    float gyroX_dps;  // Angular rate in deg/s
    float gyroY_dps;
    float gyroZ_dps;
};

class ImuDriver {
public:
    ImuDriver();

    bool begin(uint8_t forcedAddress = 0x00);
    bool readSensorData(ImuMetricData& metricData, ImuRawData* rawDataOut = nullptr);
    
    ImuType getType() const { return _type; }
    uint8_t getAddress() const { return _address; }
    uint8_t getChipId() const { return _chipId; }
    const char* getChipName() const;
    bool isConnected() const { return _initialized; }

private:
    ImuType _type;
    uint8_t _address;
    uint8_t _chipId;
    bool _initialized;

    bool writeRegister(uint8_t reg, uint8_t value);
    bool readRegisters(uint8_t reg, uint8_t* buffer, size_t length);
    
    bool tryInitBmi160(uint8_t addr);
    bool tryInitLsm6ds(uint8_t addr);
    bool tryInitMpu6050(uint8_t addr);
};
