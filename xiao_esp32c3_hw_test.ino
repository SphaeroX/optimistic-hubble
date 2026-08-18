/*
 * Seeed Studio XIAO ESP32C3 - Hardware Test Sketch
 * 
 * Tests:
 * 1. Two I2S MEMS Microphones in Stereo Configuration (Left & Right)
 * 2. Bosch BMI160 6-Axis IMU Sensor over I2C
 * 
 * Pinout:
 * - XIAO D0 (GPIO 2) -> SCK (Shared to Mic 1 & Mic 2)
 * - XIAO D1 (GPIO 3) -> WS  (Shared to Mic 1 & Mic 2)
 * - XIAO D2 (GPIO 4) -> SD  (Shared to Mic 1 & Mic 2)
 * - XIAO D4 (GPIO 6) -> SDA (BMI160 SDA)
 * - XIAO D5 (GPIO 7) -> SCL (BMI160 SCL)
 * - 3.3V             -> VCC / VDD (BMI160, Mic 1, Mic 2) + Mic 2 L/R pin (Right Channel)
 * - GND              -> GND (BMI160, Mic 1, Mic 2, BMI160 SDO) + Mic 1 L/R pin (Left Channel)
 */

#include <Arduino.h>
#include <Wire.h>
#include <driver/i2s.h>
#include <math.h>

// ============================================================================
// Pin Definitions
// ============================================================================
#define PIN_I2C_SDA         6   // XIAO D4
#define PIN_I2C_SCL         7   // XIAO D5
#define PIN_I2S_SCK         2   // XIAO D0
#define PIN_I2S_WS          3   // XIAO D1
#define PIN_I2S_SD          4   // XIAO D2

#define BMI160_ADDR_PRIMARY 0x68
#define BMI160_ADDR_ALT     0x69
#define BMI160_CHIP_ID      0xD8
#define I2S_SAMPLE_RATE     16000
#define BUFFER_SAMPLES      256

// ============================================================================
// BMI160 Registers & Variables
// ============================================================================
#define BMI160_REG_CHIP_ID      0x00
#define BMI160_REG_DATA_START   0x0C
#define BMI160_REG_ACCEL_RANGE  0x41
#define BMI160_REG_GYRO_RANGE   0x43
#define BMI160_REG_CMD          0x7E

static uint8_t bmi160Address = BMI160_ADDR_PRIMARY;
static bool bmi160Found = false;
static bool i2sReady = false;
static int32_t i2sRawBuffer[BUFFER_SAMPLES * 2]; // Interleaved Stereo buffer

// ============================================================================
// I2C Helper Functions
// ============================================================================
bool writeRegister(uint8_t addr, uint8_t reg, uint8_t val) {
    Wire.beginTransmission(addr);
    Wire.write(reg);
    Wire.write(val);
    return (Wire.endTransmission() == 0);
}

bool readRegisters(uint8_t addr, uint8_t reg, uint8_t* buf, size_t len) {
    Wire.beginTransmission(addr);
    Wire.write(reg);
    if (Wire.endTransmission(false) != 0) return false;
    if (Wire.requestFrom(addr, (uint8_t)len) != len) return false;
    for (size_t i = 0; i < len; ++i) {
        buf[i] = Wire.read();
    }
    return true;
}

uint8_t readChipId(uint8_t addr) {
    uint8_t id = 0x00;
    readRegisters(addr, BMI160_REG_CHIP_ID, &id, 1);
    return id;
}

bool initBMI160(uint8_t addr) {
    uint8_t id = readChipId(addr);
    if (id != BMI160_CHIP_ID) return false;

    // Soft reset
    writeRegister(addr, BMI160_REG_CMD, 0xB6);
    delay(20);

    // Accel normal mode (0x11) & Gyro normal mode (0x15)
    writeRegister(addr, BMI160_REG_CMD, 0x11);
    delay(10);
    writeRegister(addr, BMI160_REG_CMD, 0x15);
    delay(80);

    // Accel range +/- 2g (0x03), Gyro range +/- 2000 dps (0x00)
    writeRegister(addr, BMI160_REG_ACCEL_RANGE, 0x03);
    writeRegister(addr, BMI160_REG_GYRO_RANGE, 0x00);

    return true;
}

// ============================================================================
// I2S Stereo Setup
// ============================================================================
bool initStereoI2S() {
    i2s_config_t i2s_config = {
        .mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_RX),
        .sample_rate = I2S_SAMPLE_RATE,
        .bits_per_sample = I2S_BITS_PER_SAMPLE_32BIT,
        .channel_format = I2S_CHANNEL_FMT_RIGHT_LEFT,
        .communication_format = I2S_COMM_FORMAT_STAND_I2S,
        .intr_alloc_flags = ESP_INTR_FLAG_LEVEL1,
        .dma_buf_count = 4,
        .dma_buf_len = BUFFER_SAMPLES,
        .use_apll = false
    };

    i2s_pin_config_t pin_config = {
        .bck_io_num = PIN_I2S_SCK,
        .ws_io_num = PIN_I2S_WS,
        .data_out_num = I2S_PIN_NO_CHANGE,
        .data_in_num = PIN_I2S_SD
    };

    if (i2s_driver_install(I2S_NUM_0, &i2s_config, 0, NULL) != ESP_OK) return false;
    if (i2s_set_pin(I2S_NUM_0, &pin_config) != ESP_OK) return false;
    i2s_start(I2S_NUM_0);
    delay(100);
    return true;
}

// ============================================================================
// Setup & Main Loop
// ============================================================================
void setup() {
    Serial.begin(115200);
    unsigned long start = millis();
    while (!Serial && (millis() - start < 2500)) delay(10);

    Serial.println(F("\n========================================================"));
    Serial.println(F("  XIAO ESP32C3 - MEMS Microphones & BMI160 IMU Check"));
    Serial.println(F("========================================================"));

    // 1. Scan I2C
    Wire.begin(PIN_I2C_SDA, PIN_I2C_SCL, 400000UL);
    Serial.println(F("[1] Scanning I2C Bus..."));
    uint8_t foundCount = 0;
    for (uint8_t a = 1; a < 127; ++a) {
        Wire.beginTransmission(a);
        if (Wire.endTransmission() == 0) {
            Serial.printf("    - Found device at 0x%02X\n", a);
            if (a == BMI160_ADDR_PRIMARY || a == BMI160_ADDR_ALT) {
                bmi160Address = a;
            }
            foundCount++;
        }
    }

    // 2. Init BMI160
    Serial.println(F("[2] Testing BMI160 IMU..."));
    bmi160Found = initBMI160(bmi160Address);
    if (bmi160Found) {
        Serial.printf("    [PASS] BMI160 ready at 0x%02X (Chip ID: 0x%02X)\n", bmi160Address, readChipId(bmi160Address));
    } else {
        Serial.printf("    [FAIL] BMI160 not found at 0x%02X! Check SDA/SCL/GND/3.3V.\n", bmi160Address);
    }

    // 3. Init Stereo I2S
    Serial.println(F("[3] Initializing Stereo I2S Microphones..."));
    i2sReady = initStereoI2S();
    if (i2sReady) {
        Serial.println(F("    [PASS] Stereo I2S started (SCK=D0, WS=D1, SD=D2)"));
    } else {
        Serial.println(F("    [FAIL] Could not start I2S driver!"));
    }

    Serial.println(F("========================================================"));
    Serial.println(F("Live Diagnostic Stream Starting..."));
    Serial.println(F("Speak / Tap near Mic 1 (Left) or Mic 2 (Right) or move board:"));
    Serial.println(F("========================================================\n"));
}

void loop() {
    // Read Audio
    float leftRms = 0, rightRms = 0;
    int32_t leftPk = 0, rightPk = 0;

    if (i2sReady) {
        size_t bytesRead = 0;
        i2s_read(I2S_NUM_0, i2sRawBuffer, sizeof(i2sRawBuffer), &bytesRead, pdMS_TO_TICKS(100));
        size_t samples = bytesRead / (2 * sizeof(int32_t));

        if (samples > 0) {
            double sumL = 0, sumR = 0;
            int32_t minL = INT32_MAX, maxL = INT32_MIN;
            int32_t minR = INT32_MAX, maxR = INT32_MIN;

            for (size_t i = 0; i < samples; ++i) {
                int32_t l = i2sRawBuffer[2 * i] >> 8;
                int32_t r = i2sRawBuffer[2 * i + 1] >> 8;

                if (l < minL) minL = l;
                if (l > maxL) maxL = l;
                if (r < minR) minR = r;
                if (r > maxR) maxR = r;

                sumL += ((double)l * (double)l);
                sumR += ((double)r * (double)r);
            }
            leftRms = sqrt(sumL / samples);
            rightRms = sqrt(sumR / samples);
            leftPk = (maxL > minL) ? (maxL - minL) : 0;
            rightPk = (maxR > minR) ? (maxR - minR) : 0;
        }
    }

    // Read IMU
    float ax = 0, ay = 0, az = 0, gx = 0, gy = 0, gz = 0;
    if (bmi160Found) {
        uint8_t raw[12];
        if (readRegisters(bmi160Address, BMI160_REG_DATA_START, raw, 12)) {
            int16_t rawGx = (int16_t)(((uint16_t)raw[1] << 8) | raw[0]);
            int16_t rawGy = (int16_t)(((uint16_t)raw[3] << 8) | raw[2]);
            int16_t rawGz = (int16_t)(((uint16_t)raw[5] << 8) | raw[4]);
            int16_t rawAx = (int16_t)(((uint16_t)raw[7] << 8) | raw[6]);
            int16_t rawAy = (int16_t)(((uint16_t)raw[9] << 8) | raw[8]);
            int16_t rawAz = (int16_t)(((uint16_t)raw[11] << 8) | raw[10]);

            ax = (float)rawAx / 16384.0f;
            ay = (float)rawAy / 16384.0f;
            az = (float)rawAz / 16384.0f;
            gx = (float)rawGx / 16.4f;
            gy = (float)rawGy / 16.4f;
            gz = (float)rawGz / 16.4f;
        }
    }

    // Visual Meter formatting
    char barL[16], barR[16];
    auto makeBar = [](char* b, float val) {
        int ticks = (int)(val / 3000.0f);
        if (ticks > 10) ticks = 10;
        b[0] = '[';
        for (int i = 0; i < 10; ++i) b[i + 1] = (i < ticks) ? '#' : '.';
        b[11] = ']';
        b[12] = '\0';
    };
    makeBar(barL, leftRms);
    makeBar(barR, rightRms);

    Serial.printf("[MIC-L (GND)] %s RMS:%5.0f | [MIC-R (3V3)] %s RMS:%5.0f || [ACC] X:%+4.2f Y:%+4.2f Z:%+4.2f | [GYR] Z:%+5.1f\n",
                  barL, leftRms, barR, rightRms, ax, ay, az, gz);

    delay(100);
}
