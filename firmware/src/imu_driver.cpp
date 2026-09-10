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
#define BMI160_REG_INT_EN_0     0x50
#define BMI160_REG_INT_OUT_CTRL 0x53
#define BMI160_REG_INT_MAP_0    0x55
#define BMI160_REG_INT_MOTION_0 0x5F
#define BMI160_REG_INT_MOTION_1 0x60
#define BMI160_REG_CMD          0x7E

// LSM6DS Series (LSM6DS3 / LSM6DSO / LSM6DSL)
#define LSM6DS_REG_WHO_AM_I     0x0F
#define LSM6DS_REG_CTRL1_XL     0x10 // Accel control
#define LSM6DS_REG_CTRL2_G      0x11 // Gyro control
#define LSM6DS_REG_CTRL6_C      0x15 // Accel low power mode
#define LSM6DS_REG_WAKE_UP_SRC  0x1B // Wake-up source (reading clears latched WU interrupt)
#define LSM6DS_REG_TAP_SRC      0x1C // Tap source (reading clears latched TAP interrupt)
#define LSM6DS_REG_STATUS_REG   0x1E // Status register
#define LSM6DS_REG_DATA_START   0x22 // Gyro X, Y, Z (0x22-0x27), Accel X, Y, Z (0x28-0x2D)
#define LSM6DS_REG_TAP_CFG      0x58 // Interrupt enable
#define LSM6DS_REG_TAP_CFG0     0x56 // Tap config 0 (LSM6DSO: TAP_X/Y/Z enable, LIR)
#define LSM6DS_REG_TAP_CFG1     0x57 // Tap config 1 (LSM6DSO: TAP_THS_X)
#define LSM6DS_REG_TAP_THS_6D   0x59 // Tap threshold Z / 6D
#define LSM6DS_REG_INT_DUR2     0x5A // Tap durations (DUR, QUIET, SHOCK)
#define LSM6DS_REG_WAKE_UP_THS  0x5B // Wake-up threshold & SINGLE_DOUBLE_TAP
#define LSM6DS_REG_WAKE_UP_DUR  0x5C // Wake-up duration
#define LSM6DS_REG_MD1_CFG      0x5E // Route wake-up to INT1

// MPU-6050
#define MPU_REG_WHO_AM_I        0x75
#define MPU_REG_PWR_MGMT_1      0x6B
#define MPU_REG_PWR_MGMT_2      0x6C
#define MPU_REG_ACCEL_CONFIG    0x1C
#define MPU_REG_GYRO_CONFIG     0x1B
#define MPU_REG_INT_PIN_CFG     0x37
#define MPU_REG_INT_ENABLE      0x38
#define MPU_REG_MOT_THR         0x1F
#define MPU_REG_MOT_DUR         0x20
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
    if (Wire.endTransmission(true) != 0) {
        return false;
    }
    size_t received = Wire.requestFrom((int)_address, (int)length, (int)true);
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
    // Clear any previous interrupt configuration
    writeRegister(LSM6DS_REG_TAP_CFG, 0x00);
    writeRegister(LSM6DS_REG_MD1_CFG, 0x00);
    writeRegister(LSM6DS_REG_CTRL6_C, 0x00); // High-performance mode

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

bool ImuDriver::configureLowPowerWakeup(float thresholdG) {
    if (!_initialized) return false;

    if (_type == IMU_TYPE_LSM6DS) {
        // 1. Power down Gyroscope to save ~4 mA
        writeRegister(LSM6DS_REG_CTRL2_G, 0x00);
        delay(10);

        // 2. Set Accelerometer to Low Power mode @ 52 Hz, +/- 2g
        writeRegister(LSM6DS_REG_CTRL1_XL, 0x30); // 52 Hz ODR for responsive tap detection
        writeRegister(LSM6DS_REG_CTRL6_C, 0x10);  // XL_HM_MODE = 1 (Low-Power Accel enabled)
        delay(10);

        // 3. Configure Hardware Double-Tap detection on X, Y, Z
        // Enable X, Y, Z tap axes and latched interrupt mode (LIR = 1)
        writeRegister(LSM6DS_REG_TAP_CFG0, 0x0F);   // TAP_X/Y/Z enable, LIR = 1
        writeRegister(LSM6DS_REG_TAP_CFG1, 0x0C);   // TAP_THS_X = 12 (~0.75g threshold)
        writeRegister(LSM6DS_REG_TAP_CFG, 0x8C);    // TAP_CFG2: INTERRUPTS_ENABLE = 1, TAP_THS_Y = 0.75g
        writeRegister(LSM6DS_REG_TAP_THS_6D, 0x0C); // TAP_THS_Z = 0.75g

        // 4. Configure Double-Tap Timing Window (INT_DUR2: DUR=7 -> ~430ms window, QUIET=2 -> 77ms, SHOCK=3 -> 115ms)
        writeRegister(LSM6DS_REG_INT_DUR2, 0x7B);

        // 5. Enable Double-Tap mode in WAKE_UP_THS (bit 7 = SINGLE_DOUBLE_TAP = 1)
        writeRegister(LSM6DS_REG_WAKE_UP_THS, 0x80);

        // 6. Route ONLY Double-Tap to INT1 pin (MD1_CFG: bit 3 = INT1_DOUBLE_TAP = 0x08)
        writeRegister(LSM6DS_REG_MD1_CFG, 0x08);

        // Clear any residual triggers so INT1 starts LOW
        clearInterrupts();

        Serial.println(F("[IMU] LSM6DS configured for Hardware Double-Tap Wake-up on INT1 (~26 uA)."));
        return true;
    }
    else if (_type == IMU_TYPE_BMI160) {
        // 1. Power down Gyroscope
        writeRegister(BMI160_REG_CMD, 0x14); // Gyro suspend mode
        delay(10);

        // 2. Configure Accelerometer to Low-Power mode
        writeRegister(BMI160_REG_CMD, 0x12); // Accel low-power mode
        delay(10);

        // 3. Configure Any-Motion Interrupt on X, Y, Z
        writeRegister(BMI160_REG_INT_EN_0, 0x07); // Any-motion X, Y, Z enable
        writeRegister(BMI160_REG_INT_OUT_CTRL, 0x0A); // INT1 output enable, active-high, push-pull
        writeRegister(BMI160_REG_INT_MAP_0, 0x04); // Map any-motion to INT1
        writeRegister(BMI160_REG_INT_MOTION_0, 0x00); // 1 consecutive violation

        // Threshold: 1 LSB = 3.91mg @ +/-2g
        uint16_t rawThs = (uint16_t)(thresholdG * 1000.0f / 3.91f);
        uint8_t ths = (rawThs > 255) ? 255 : (uint8_t)rawThs;
        writeRegister(BMI160_REG_INT_MOTION_1, ths);

        Serial.printf("[IMU] BMI160 configured for Low-Power Wake-up (~5 uA). Threshold: %.2f g (reg=0x%02X)\n", 
                      thresholdG, ths);
        return true;
    }
    else if (_type == IMU_TYPE_MPU6050) {
        // 1. Wake up MPU
        writeRegister(MPU_REG_PWR_MGMT_1, 0x00);
        delay(10);

        // 2. Configure Accel Only (Gyro standby)
        writeRegister(MPU_REG_PWR_MGMT_2, 0x07); // Accel ON, Gyro OFF
        writeRegister(MPU_REG_INT_PIN_CFG, 0x20); // 50us pulse, push-pull, active high
        writeRegister(MPU_REG_INT_ENABLE, 0x40);  // Motion detection interrupt

        // Threshold: 1 LSB = 32mg
        uint16_t rawThs = (uint16_t)(thresholdG * 1000.0f / 32.0f);
        uint8_t ths = (rawThs > 255) ? 255 : (uint8_t)rawThs;
        writeRegister(MPU_REG_MOT_THR, ths);
        writeRegister(MPU_REG_MOT_DUR, 0x01);

        // 3. Put MPU into cycle mode for low power
        writeRegister(MPU_REG_PWR_MGMT_1, 0x20); // Cycle mode

        Serial.printf("[IMU] MPU-6050 configured for Low-Power Wake-up. Threshold: %.2f g\n", thresholdG);
        return true;
    }

    return false;
}

void ImuDriver::clearInterrupts() {
    if (!_initialized) return;
    uint8_t dummy = 0;
    if (_type == IMU_TYPE_LSM6DS) {
        readRegisters(LSM6DS_REG_WAKE_UP_SRC, &dummy, 1);
        readRegisters(LSM6DS_REG_TAP_SRC, &dummy, 1);
        readRegisters(LSM6DS_REG_STATUS_REG, &dummy, 1);
        readRegisters(0x1A, &dummy, 1); // ALL_INT_SRC
    } else if (_type == IMU_TYPE_BMI160) {
        readRegisters(0x1C, &dummy, 1); // INT_STATUS_0
        readRegisters(0x1D, &dummy, 1); // INT_STATUS_1
    } else if (_type == IMU_TYPE_MPU6050) {
        readRegisters(0x3A, &dummy, 1); // INT_STATUS
    }
}

bool ImuDriver::setPowerMode(bool active) {
    if (!_initialized) return false;

    if (active) {
        // Restore high-performance 104 Hz sampling mode for active operation
        if (_type == IMU_TYPE_LSM6DS) {
            writeRegister(LSM6DS_REG_TAP_CFG0, 0x00);
            writeRegister(LSM6DS_REG_TAP_CFG1, 0x00);
            writeRegister(LSM6DS_REG_TAP_CFG, 0x00);
            writeRegister(LSM6DS_REG_INT_DUR2, 0x00);
            writeRegister(LSM6DS_REG_WAKE_UP_THS, 0x00);
            writeRegister(LSM6DS_REG_MD1_CFG, 0x00);
            writeRegister(LSM6DS_REG_CTRL6_C, 0x00); // High-performance mode
            writeRegister(LSM6DS_REG_CTRL1_XL, 0x40); // 104 Hz, +/- 2g
            delay(10);
            writeRegister(LSM6DS_REG_CTRL2_G, 0x4C);  // 104 Hz Gyro
            delay(10);
            clearInterrupts();
            return true;
        } else if (_type == IMU_TYPE_BMI160) {
            writeRegister(BMI160_REG_INT_EN_0, 0x00);
            writeRegister(BMI160_REG_CMD, 0x11); // Accel normal mode
            delay(10);
            writeRegister(BMI160_REG_CMD, 0x15); // Gyro normal mode
            delay(50);
            clearInterrupts();
            return true;
        } else if (_type == IMU_TYPE_MPU6050) {
            writeRegister(MPU_REG_INT_ENABLE, 0x00);
            writeRegister(MPU_REG_PWR_MGMT_1, 0x00);
            writeRegister(MPU_REG_PWR_MGMT_2, 0x00);
            delay(10);
            clearInterrupts();
            return true;
        }
    } else {
        return configureLowPowerWakeup(1.4f);
    }
    return false;
}

