#include "imu_driver.h"

// ----------------------------------------------------------------------------
// Register Definitions
// ----------------------------------------------------------------------------

// BMI160
#define BMI160_REG_CHIP_ID      0x00
#define BMI160_CHIP_ID_VAL      0xD8
#define BMI160_REG_DATA_START   0x0C
#define BMI160_REG_ACCEL_RANGE  0x41
#define BMI160_REG_GYRO_RANGE   0x43
#define BMI160_REG_CMD          0x7E

// LSM6DS Series (LSM6DS3 / LSM6DSO / LSM6DSL)
#define LSM6DS_REG_WHO_AM_I     0x0F
#define LSM6DS_REG_CTRL1_XL     0x10 // Accel control
#define LSM6DS_REG_CTRL2_G      0x11 // Gyro control
#define LSM6DS_REG_DATA_START   0x22 // Gyro X, Y, Z (0x22-0x27), Accel X, Y, Z (0x28-0x2D)

// MPU-6050
#define MPU_REG_WHO_AM_I        0x75
#define MPU_REG_PWR_MGMT_1      0x6B
#define MPU_REG_ACCEL_CONFIG    0x1C
#define MPU_REG_GYRO_CONFIG     0x1B
#define MPU_REG_DATA_START      0x3B // Accel (0x3B-0x40), Temp (0x41-0x42), Gyro (0x43-0x48)

ImuDriver::ImuDriver()
    : _type(IMU_TYPE_NONE), _address(0x00), _chipId(0x00), _initialized(false) {}

bool ImuDriver::writeRegister(uint8_t reg, uint8_t value) {
    Wire.beginTransmission(_address);
    Wire.write(reg);
    Wire.write(value);
    return (Wire.endTransmission() == 0);
}

bool ImuDriver::readRegisters(uint8_t reg, uint8_t* buffer, size_t length) {
    Wire.beginTransmission(_address);
    Wire.write(reg);
    if (Wire.endTransmission(false) != 0) {
        return false;
    }
    size_t received = Wire.requestFrom(_address, (uint8_t)length);
    if (received != length) {
        return false;
    }
    for (size_t i = 0; i < length; ++i) {
        buffer[i] = Wire.read();
    }
    return true;
}

const char* ImuDriver::getChipName() const {
    switch (_type) {
        case IMU_TYPE_BMI160: return "Bosch BMI160";
        case IMU_TYPE_LSM6DS: 
            if (_chipId == 0x69) return "ST LSM6DS3";
            if (_chipId == 0x6C) return "ST LSM6DSO";
            if (_chipId == 0x6A) return "ST LSM6DSL";
            return "ST LSM6DS-Family IMU";
        case IMU_TYPE_MPU6050: return "InvenSense MPU-6050/6500";
        default: return "Unknown / Not Connected";
    }
}

bool ImuDriver::tryInitBmi160(uint8_t addr) {
    _address = addr;
    uint8_t id = 0x00;
    if (!readRegisters(BMI160_REG_CHIP_ID, &id, 1) || id != BMI160_CHIP_ID_VAL) {
        return false;
    }

    _chipId = id;
    writeRegister(BMI160_REG_CMD, 0xB6); // Soft reset
    delay(20);
    writeRegister(BMI160_REG_CMD, 0x11); // Accel normal mode
    delay(10);
    writeRegister(BMI160_REG_CMD, 0x15); // Gyro normal mode
    delay(80);
    writeRegister(BMI160_REG_ACCEL_RANGE, 0x03); // +/- 2g
    writeRegister(BMI160_REG_GYRO_RANGE, 0x00);  // +/- 2000 dps

    _type = IMU_TYPE_BMI160;
    _initialized = true;
    return true;
}

bool ImuDriver::tryInitLsm6ds(uint8_t addr) {
    _address = addr;
    uint8_t id = 0x00;
    if (!readRegisters(LSM6DS_REG_WHO_AM_I, &id, 1)) {
        return false;
    }

    // Common LSM6DS series IDs: 0x69 (LSM6DS3), 0x6C (LSM6DSO), 0x6A (LSM6DSL), 0x68 (LSM6DS33)
    if (id != 0x69 && id != 0x6C && id != 0x6A && id != 0x68 && id != 0x6B) {
        return false;
    }

    _chipId = id;
    // Set Accel: 104 Hz ODR, +/- 2g (0x40)
    writeRegister(LSM6DS_REG_CTRL1_XL, 0x40);
    delay(10);
    // Set Gyro: 104 Hz ODR, 2000 dps (0x4C or 0x40)
    writeRegister(LSM6DS_REG_CTRL2_G, 0x4C);
    delay(20);

    _type = IMU_TYPE_LSM6DS;
    _initialized = true;
    return true;
}

bool ImuDriver::tryInitMpu6050(uint8_t addr) {
    _address = addr;
    uint8_t id = 0x00;
    if (!readRegisters(MPU_REG_WHO_AM_I, &id, 1) || (id != 0x68 && id != 0x70 && id != 0x72)) {
        return false;
    }

    _chipId = id;
    writeRegister(MPU_REG_PWR_MGMT_1, 0x00); // Wake up
    delay(20);
    writeRegister(MPU_REG_ACCEL_CONFIG, 0x00); // +/- 2g
    writeRegister(MPU_REG_GYRO_CONFIG, 0x18);  // +/- 2000 dps

    _type = IMU_TYPE_MPU6050;
    _initialized = true;
    return true;
}

bool ImuDriver::begin(uint8_t forcedAddress) {
    _initialized = false;
    _type = IMU_TYPE_NONE;

    uint8_t probeList[6];
    uint8_t probeCount = 0;

    if (forcedAddress != 0x00) {
        probeList[probeCount++] = forcedAddress;
    } else {
        // Typical IMU addresses
        probeList[probeCount++] = 0x6A; // LSM6DS default
        probeList[probeCount++] = 0x68; // BMI160 default / MPU default
        probeList[probeCount++] = 0x69; // BMI160 alt / LSM6DS alt
        probeList[probeCount++] = 0x6B; // LSM6DS alt
    }

    for (uint8_t i = 0; i < probeCount; ++i) {
        uint8_t addr = probeList[i];
        if (tryInitBmi160(addr)) return true;
        if (tryInitLsm6ds(addr)) return true;
        if (tryInitMpu6050(addr)) return true;
    }

    return false;
}

bool ImuDriver::readSensorData(ImuMetricData& metricData, ImuRawData* rawDataOut) {
    if (!_initialized) return false;

    if (_type == IMU_TYPE_BMI160) {
        uint8_t rawBuf[12];
        if (!readRegisters(BMI160_REG_DATA_START, rawBuf, 12)) return false;

        ImuRawData raw;
        raw.gyroX  = (int16_t)(((uint16_t)rawBuf[1]  << 8) | rawBuf[0]);
        raw.gyroY  = (int16_t)(((uint16_t)rawBuf[3]  << 8) | rawBuf[2]);
        raw.gyroZ  = (int16_t)(((uint16_t)rawBuf[5]  << 8) | rawBuf[4]);
        raw.accelX = (int16_t)(((uint16_t)rawBuf[7]  << 8) | rawBuf[6]);
        raw.accelY = (int16_t)(((uint16_t)rawBuf[9]  << 8) | rawBuf[8]);
        raw.accelZ = (int16_t)(((uint16_t)rawBuf[11] << 8) | rawBuf[10]);

        if (rawDataOut) *rawDataOut = raw;
        metricData.accelX_g = (float)raw.accelX / 16384.0f;
        metricData.accelY_g = (float)raw.accelY / 16384.0f;
        metricData.accelZ_g = (float)raw.accelZ / 16384.0f;
        metricData.gyroX_dps = (float)raw.gyroX / 16.4f;
        metricData.gyroY_dps = (float)raw.gyroY / 16.4f;
        metricData.gyroZ_dps = (float)raw.gyroZ / 16.4f;
        return true;
    }
    else if (_type == IMU_TYPE_LSM6DS) {
        uint8_t rawBuf[12];
        if (!readRegisters(LSM6DS_REG_DATA_START, rawBuf, 12)) return false;

        ImuRawData raw;
        raw.gyroX  = (int16_t)(((uint16_t)rawBuf[1]  << 8) | rawBuf[0]);
        raw.gyroY  = (int16_t)(((uint16_t)rawBuf[3]  << 8) | rawBuf[2]);
        raw.gyroZ  = (int16_t)(((uint16_t)rawBuf[5]  << 8) | rawBuf[4]);
        raw.accelX = (int16_t)(((uint16_t)rawBuf[7]  << 8) | rawBuf[6]);
        raw.accelY = (int16_t)(((uint16_t)rawBuf[9]  << 8) | rawBuf[8]);
        raw.accelZ = (int16_t)(((uint16_t)rawBuf[11] << 8) | rawBuf[10]);

        if (rawDataOut) *rawDataOut = raw;
        // LSM6DS +/- 2g sensitivity: 0.061 mg/LSB -> / 16384.0f
        metricData.accelX_g = (float)raw.accelX * 0.000061f;
        metricData.accelY_g = (float)raw.accelY * 0.000061f;
        metricData.accelZ_g = (float)raw.accelZ * 0.000061f;
        // LSM6DS +/- 2000 dps sensitivity: 70 mdps/LSB
        metricData.gyroX_dps = (float)raw.gyroX * 0.070f;
        metricData.gyroY_dps = (float)raw.gyroY * 0.070f;
        metricData.gyroZ_dps = (float)raw.gyroZ * 0.070f;
        return true;
    }
    else if (_type == IMU_TYPE_MPU6050) {
        uint8_t rawBuf[14];
        if (!readRegisters(MPU_REG_DATA_START, rawBuf, 14)) return false;

        ImuRawData raw;
        // MPU is Big-Endian: MSB then LSB
        raw.accelX = (int16_t)(((uint16_t)rawBuf[0] << 8) | rawBuf[1]);
        raw.accelY = (int16_t)(((uint16_t)rawBuf[2] << 8) | rawBuf[3]);
        raw.accelZ = (int16_t)(((uint16_t)rawBuf[4] << 8) | rawBuf[5]);
        raw.gyroX  = (int16_t)(((uint16_t)rawBuf[8] << 8) | rawBuf[9]);
        raw.gyroY  = (int16_t)(((uint16_t)rawBuf[10] << 8) | rawBuf[11]);
        raw.gyroZ  = (int16_t)(((uint16_t)rawBuf[12] << 8) | rawBuf[13]);

        if (rawDataOut) *rawDataOut = raw;
        metricData.accelX_g = (float)raw.accelX / 16384.0f;
        metricData.accelY_g = (float)raw.accelY / 16384.0f;
        metricData.accelZ_g = (float)raw.accelZ / 16384.0f;
        metricData.gyroX_dps = (float)raw.gyroX / 16.4f;
        metricData.gyroY_dps = (float)raw.gyroY / 16.4f;
        metricData.gyroZ_dps = (float)raw.gyroZ / 16.4f;
        return true;
    }

    return false;
}
