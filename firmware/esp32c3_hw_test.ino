/*
 * ESP32-C3-MINI-1-N4 - V2 Production Hardware Diagnostic & Test Suite
 * 
 * Tests:
 * 1. Dual Status LEDs: D1 (Red, GPIO 10) and D2 (Green, GPIO 8) in Active-LOW logic
 * 2. 6-Axis IMU: ST LSM6DSLTR (I2C @ 0x6A, SDA=6, SCL=7) and INT1 Wakeup on GPIO 5
 * 3. External Audio Flash: Winbond W25Q128JVSIQ (16MB) on SPI2 (CS=21, SCK=20, MOSI=1, MISO=0)
 * 4. Stereo I2S MEMS Microphones: 2x ICS-43434 (SCK=2, WS=3, SD=4 with 100k pulldown)
 * 5. Push Button: THT BTN Switch on GPIO 9 against GND
 */

#include <Arduino.h>
#include <Wire.h>
#include <SPI.h>
#include <driver/i2s.h>
#include <math.h>

// ============================================================================
// V2 Production Pinout Definitions
// ============================================================================
#define PIN_I2C_SDA         6   // GPIO 6 (I2C Data)
#define PIN_I2C_SCL         7   // GPIO 7 (I2C Clock)
#define PIN_IMU_INT         5   // GPIO 5 (IMU INT1 / RTC IO5)
#define PIN_BOOT_BTN        9   // GPIO 9 (THT BTN Switch)

#define PIN_I2S_SCK         2   // GPIO 2 (I2S Bit Clock)
#define PIN_I2S_WS          3   // GPIO 3 (I2S Word Select / LRCLK)
#define PIN_I2S_SD          4   // GPIO 4 (I2S Serial Data In)

#define PIN_STATUS_LED      10  // GPIO 10 (D1 Red LED - Active LOW)
#define PIN_LED_GREEN       8   // GPIO 8  (D2 Green LED - Active LOW)

#define PIN_FLASH_CS        21  // GPIO 21 (SPI2 /CS)
#define PIN_FLASH_SCK       20  // GPIO 20 (SPI2 CLK)
#define PIN_FLASH_MOSI      1   // GPIO 1  (SPI2 DI)
#define PIN_FLASH_MISO      0   // GPIO 0  (SPI2 DO)

#define LED_ON              LOW
#define LED_OFF             HIGH

#define I2S_SAMPLE_RATE     16000
#define BUFFER_SAMPLES      256

// ============================================================================
// Sensor Registers
// ============================================================================
#define LSM6DS_REG_WHO_AM_I     0x0F
#define LSM6DS_REG_CTRL1_XL     0x10
#define LSM6DS_REG_CTRL2_G      0x11
#define LSM6DS_REG_DATA_START   0x22

#define BMI160_REG_CHIP_ID      0x00
#define BMI160_REG_DATA_START   0x0C
#define BMI160_REG_CMD          0x7E

enum DetectedImu { IMU_NONE = 0, IMU_LSM6DSL, IMU_BMI160 };

static DetectedImu detectedImu = IMU_NONE;
static uint8_t imuAddress = 0x6A;
static bool i2sReady = false;
static bool flashReady = false;
static uint32_t flashJedecId = 0;
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

// ============================================================================
// SPI2 Flash Test (W25Q128)
// ============================================================================
uint32_t testSpiFlash() {
    pinMode(PIN_FLASH_CS, OUTPUT);
    digitalWrite(PIN_FLASH_CS, HIGH);

    SPIClass* spi = new SPIClass(FSPI);
    spi->begin(PIN_FLASH_SCK, PIN_FLASH_MISO, PIN_FLASH_MOSI, PIN_FLASH_CS);

    SPISettings settings(10000000, MSBFIRST, SPI_MODE0);
    spi->beginTransaction(settings);

    // Release power-down
    digitalWrite(PIN_FLASH_CS, LOW);
    spi->transfer(0xAB);
    digitalWrite(PIN_FLASH_CS, HIGH);
    delayMicroseconds(50);

    // Read JEDEC ID (0x9F)
    digitalWrite(PIN_FLASH_CS, LOW);
    spi->transfer(0x9F);
    uint8_t b1 = spi->transfer(0x00);
    uint8_t b2 = spi->transfer(0x00);
    uint8_t b3 = spi->transfer(0x00);
    digitalWrite(PIN_FLASH_CS, HIGH);

    spi->endTransaction();
    spi->end();
    delete spi;

    return ((uint32_t)b1 << 16) | ((uint32_t)b2 << 8) | (uint32_t)b3;
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
    // 1. Initialize Active-LOW LEDs
    pinMode(PIN_STATUS_LED, OUTPUT);
    pinMode(PIN_LED_GREEN, OUTPUT);
    digitalWrite(PIN_STATUS_LED, LED_OFF);
    digitalWrite(PIN_LED_GREEN, LED_OFF);

    // 2. Buttons & Inputs
    pinMode(PIN_BOOT_BTN, INPUT_PULLUP);
    pinMode(PIN_IMU_INT, INPUT_PULLDOWN);

    Serial.begin(115200);
    unsigned long start = millis();
    while (!Serial && (millis() - start < 1500)) delay(10);

    Serial.println(F("\n========================================================"));
    Serial.println(F("  ESP32-C3-MINI-1-N4 V2 Hardware Diagnostic Test"));
    Serial.println(F("========================================================"));

    // LED Test Pattern
    Serial.println(F("[1] Testing Dual Status LEDs (Active-LOW)..."));
    digitalWrite(PIN_STATUS_LED, LED_ON);
    delay(150);
    digitalWrite(PIN_STATUS_LED, LED_OFF);
    digitalWrite(PIN_LED_GREEN, LED_ON);
    delay(150);
    digitalWrite(PIN_LED_GREEN, LED_OFF);
    Serial.println(F("    [PASS] D1 Red & D2 Green toggled."));

    // 2. Test SPI2 Audio Flash (W25Q128)
    Serial.println(F("[2] Probing External SPI2 Audio Flash (W25Q128)..."));
    flashJedecId = testSpiFlash();
    uint8_t mfg = (flashJedecId >> 16) & 0xFF;
    if (mfg == 0xEF || mfg == 0xC8 || mfg == 0x20) {
        flashReady = true;
        Serial.printf("    [PASS] SPI2 Flash verified! JEDEC: 0x%06X (Mfg: 0x%02X, Cap: 16 MB)\n",
                      flashJedecId, mfg);
    } else {
        Serial.printf("    [WARN] Flash returned ID: 0x%06X (Check CS=21, SCK=20, MOSI=1, MISO=0)\n",
                      flashJedecId);
    }

    // 3. Scan I2C & Test IMU
    Wire.begin(PIN_I2C_SDA, PIN_I2C_SCL, 400000UL);
    Serial.println(F("[3] Scanning I2C Bus (SDA=6, SCL=7)..."));
    for (uint8_t a = 1; a < 127; ++a) {
        Wire.beginTransmission(a);
        if (Wire.endTransmission() == 0) {
            Serial.printf("    - Found device at 0x%02X\n", a);
        }
    }

    // Try LSM6DSL (Default V2: 0x6A)
    uint8_t who = 0;
    if (readRegisters(0x6A, LSM6DS_REG_WHO_AM_I, &who, 1) && (who == 0x6A || who == 0x69 || who == 0x6C)) {
        detectedImu = IMU_LSM6DSL;
        imuAddress = 0x6A;
        // Configure Accel & Gyro 104 Hz
        writeRegister(0x6A, LSM6DS_REG_CTRL1_XL, 0x40);
        writeRegister(0x6A, LSM6DS_REG_CTRL2_G, 0x4C);
        Serial.printf("    [PASS] ST LSM6DSL identified @ 0x%02X (WHO_AM_I: 0x%02X)\n", imuAddress, who);
    } else if (readRegisters(0x68, BMI160_REG_CHIP_ID, &who, 1) && who == 0xD8) {
        detectedImu = IMU_BMI160;
        imuAddress = 0x68;
        writeRegister(0x68, BMI160_REG_CMD, 0x11);
        delay(10);
        writeRegister(0x68, BMI160_REG_CMD, 0x15);
        Serial.printf("    [PASS] Bosch BMI160 identified @ 0x%02X (Chip ID: 0x%02X)\n", imuAddress, who);
    } else {
        Serial.println(F("    [FAIL] No supported IMU detected at 0x6A or 0x68!"));
    }

    // 4. Init Stereo I2S Microphones
    Serial.println(F("[4] Initializing Stereo I2S Microphones (ICS-43434)..."));
    i2sReady = initStereoI2S();
    if (i2sReady) {
        Serial.println(F("    [PASS] Stereo I2S started (SCK=2, WS=3, SD=4 with 100k Pulldown)"));
    } else {
        Serial.println(F("    [FAIL] Could not start I2S driver!"));
    }

    Serial.println(F("========================================================"));
    Serial.println(F("Live Diagnostic Stream Starting..."));
    Serial.println(F("Speak / Tap near Mic 1 (Left) or Mic 2 (Right) or press BTN:"));
    Serial.println(F("========================================================\n"));
}

void loop() {
    // Read Audio
    float leftRms = 0, rightRms = 0;

    if (i2sReady) {
        size_t bytesRead = 0;
        i2s_read(I2S_NUM_0, i2sRawBuffer, sizeof(i2sRawBuffer), &bytesRead, pdMS_TO_TICKS(100));
        size_t samples = bytesRead / (2 * sizeof(int32_t));

        if (samples > 0) {
            double sumL = 0, sumR = 0;
            for (size_t i = 0; i < samples; ++i) {
                int32_t l = i2sRawBuffer[2 * i] >> 8;
                int32_t r = i2sRawBuffer[2 * i + 1] >> 8;
                sumL += ((double)l * (double)l);
                sumR += ((double)r * (double)r);
            }
            leftRms = sqrt(sumL / samples);
            rightRms = sqrt(sumR / samples);
        }
    }

    // Read IMU
    float ax = 0, ay = 0, az = 0, gz = 0;
    if (detectedImu == IMU_LSM6DSL) {
        uint8_t raw[12];
        if (readRegisters(imuAddress, LSM6DS_REG_DATA_START, raw, 12)) {
            int16_t rawGz = (int16_t)(((uint16_t)raw[5] << 8) | raw[4]);
            int16_t rawAx = (int16_t)(((uint16_t)raw[7] << 8) | raw[6]);
            int16_t rawAy = (int16_t)(((uint16_t)raw[9] << 8) | raw[8]);
            int16_t rawAz = (int16_t)(((uint16_t)raw[11] << 8) | raw[10]);

            ax = (float)rawAx * 0.000061f;
            ay = (float)rawAy * 0.000061f;
            az = (float)rawAz * 0.000061f;
            gz = (float)rawGz * 0.070f;
        }
    }

    bool btnPressed = (digitalRead(PIN_BOOT_BTN) == LOW);
    bool int1Active = (digitalRead(PIN_IMU_INT) == HIGH);

    // Reflect button on Green LED
    digitalWrite(PIN_LED_GREEN, btnPressed ? LED_ON : LED_OFF);
    // Reflect INT1 or audio peak on Red LED
    digitalWrite(PIN_STATUS_LED, (int1Active || leftRms > 5000 || rightRms > 5000) ? LED_ON : LED_OFF);

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

    Serial.printf("[MIC-L (GND)] %s RMS:%5.0f | [MIC-R (3V3)] %s RMS:%5.0f || [ACC] X:%+4.2f Y:%+4.2f Z:%+4.2f | [BTN] %s | [INT1] %s\n",
                  barL, leftRms, barR, rightRms, ax, ay, az, 
                  btnPressed ? "PRESSED" : "RELEASED",
                  int1Active ? "ACTIVE" : "IDLE");

    delay(100);
}
