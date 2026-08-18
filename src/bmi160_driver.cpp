#include "bmi160_driver.h"
#include "config.h"

#define BMI160_REG_CHIP_ID      0x00
#define BMI160_REG_DATA_START    0x0C // Starts with Gyro (0x0C..0x11) followed by Accel (0x12..0x17)
#define BMI160_REG_ACCEL_CONF   0x40
#define BMI160_REG_ACCEL_RANGE  0x41
#define BMI160_REG_GYRO_CONF    0x42
#define BMI160_REG_GYRO_RANGE   0x43
#define BMI160_REG_CMD          0x7E

#define BMI160_CMD_SOFT_RESET   0xB6
#define BMI160_CMD_ACCEL_NORMAL 0x11
#define BMI160_CMD_GYRO_NORMAL  0x15

// Scale factors for +/- 2g range (16384 LSB/g) and +/- 2000 deg/s range (16.4 LSB/dps)
static const float ACCEL_SCALE_2G = 1.0f / 16384.0f;
static const float GYRO_SCALE_2000DPS = 1.0f / 16.4f;

Bmi160Driver::Bmi160Driver(uint8_t i2cAddress)
    : _address(i2cAddress), _initialized(false) {}

bool Bmi160Driver::writeRegister(uint8_t reg, uint8_t value) {
    Wire.beginTransmission(_address);
    Wire.write(reg);
    Wire.write(value);
    return (Wire.endTransmission() == 0);
}

bool Bmi160Driver::readRegisters(uint8_t reg, uint8_t* buffer, size_t length) {
    Wire.beginTransmission(_address);
    Wire.write(reg);
    if (Wire.endTransmission(false) != 0) { // repeated start
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

uint8_t Bmi160Driver::readChipId() {
    uint8_t chipId = 0x00;
    if (readRegisters(BMI160_REG_CHIP_ID, &chipId, 1)) {
        return chipId;
    }
    return 0x00;
}

bool Bmi160Driver::begin(uint8_t i2cAddress) {
    _address = i2cAddress;
    _initialized = false;

    // Check Chip ID
    uint8_t chipId = readChipId();
    if (chipId != BMI160_CHIP_ID) {
        return false;
    }

    // Step 1: Soft reset sensor
    writeRegister(BMI160_REG_CMD, BMI160_CMD_SOFT_RESET);
    delay(20);

    // Step 2: Set Accel to normal power mode
    writeRegister(BMI160_REG_CMD, BMI160_CMD_ACCEL_NORMAL);
    delay(10);

    // Step 3: Set Gyro to normal power mode
    writeRegister(BMI160_REG_CMD, BMI160_CMD_GYRO_NORMAL);
    delay(80); // Wait for gyro startup

    // Step 4: Configure Accel range (+/- 2g) and Gyro range (+/- 2000 deg/s)
    writeRegister(BMI160_REG_ACCEL_RANGE, 0x03); // +/- 2g
    delay(2);
    writeRegister(BMI160_REG_GYRO_RANGE, 0x00);  // +/- 2000 deg/s
    delay(2);

    _initialized = true;
    return true;
}

bool Bmi160Driver::readSensorData(Bmi160MetricData& metricData, Bmi160RawData* rawDataOut) {
    if (!_initialized) {
        return false;
    }

    // Burst read 12 bytes from register 0x0C (Gyro: 6 bytes, Accel: 6 bytes)
    uint8_t rawBuffer[12];
    if (!readRegisters(BMI160_REG_DATA_START, rawBuffer, 12)) {
        return false;
    }

    Bmi160RawData raw;
    raw.gyroX = (int16_t)(((uint16_t)rawBuffer[1] << 8) | rawBuffer[0]);
    raw.gyroY = (int16_t)(((uint16_t)rawBuffer[3] << 8) | rawBuffer[2]);
    raw.gyroZ = (int16_t)(((uint16_t)rawBuffer[5] << 8) | rawBuffer[4]);

    raw.accelX = (int16_t)(((uint16_t)rawBuffer[7] << 8) | rawBuffer[6]);
    raw.accelY = (int16_t)(((uint16_t)rawBuffer[9] << 8) | rawBuffer[8]);
    raw.accelZ = (int16_t)(((uint16_t)rawBuffer[11] << 8) | rawBuffer[10]);

    if (rawDataOut != nullptr) {
        *rawDataOut = raw;
    }

    // Convert raw values to physical units
    metricData.accelX_g = (float)raw.accelX * ACCEL_SCALE_2G;
    metricData.accelY_g = (float)raw.accelY * ACCEL_SCALE_2G;
    metricData.accelZ_g = (float)raw.accelZ * ACCEL_SCALE_2G;

    metricData.gyroX_dps = (float)raw.gyroX * GYRO_SCALE_2000DPS;
    metricData.gyroY_dps = (float)raw.gyroY * GYRO_SCALE_2000DPS;
    metricData.gyroZ_dps = (float)raw.gyroZ * GYRO_SCALE_2000DPS;

    return true;
}
