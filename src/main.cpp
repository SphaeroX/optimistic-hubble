#include <Arduino.h>
#include "config.h"
#include "i2c_scanner.h"
#include "bmi160_driver.h"
#include "i2s_mic_driver.h"

// Global Hardware Drivers
static Bmi160Driver bmi160;
static I2sMicDriver stereoMic;

// Display Modes
enum DisplayMode {
    MODE_MONITOR = 0,
    MODE_PLOTTER = 1
};

static DisplayMode currentMode = MODE_MONITOR;
static unsigned long lastPrintTime = 0;
static const unsigned long PRINT_INTERVAL_MS = 100; // 10 Hz refresh rate for smooth display

void printBanner() {
    Serial.println(F("\n========================================================"));
    Serial.println(F("  Seeed Studio XIAO ESP32C3 - Hardware Test Suite"));
    Serial.println(F("  Target: 2x I2S MEMS Microphones + BMI160 6-Axis IMU"));
    Serial.println(F("========================================================"));
}

void printHelpMenu() {
    Serial.println(F("\n[COMMANDS] Send any of these characters via Serial:"));
    Serial.println(F("  'm' -> Switch to Dashboard / Monitor Mode (Default)"));
    Serial.println(F("  'p' -> Switch to Arduino Serial Plotter Mode"));
    Serial.println(F("  'i' -> Re-scan I2C Bus & Test Hardware"));
    Serial.println(F("  'h' -> Show this Help Menu\n"));
}

bool runHardwareSelfTest() {
    printBanner();
    Serial.println(F("[1/3] Initializing I2C Bus on SDA (D4/GPIO6) and SCL (D5/GPIO7)..."));
    I2cScanner::begin(PIN_I2C_SDA, PIN_I2C_SCL, I2C_FREQUENCY);
    delay(50);

    I2cScanResult scanResult = I2cScanner::scanBus();
    I2cScanner::printScanReport(scanResult);

    Serial.println(F("[2/3] Initializing BMI160 6-Axis IMU Sensor..."));
    uint8_t targetAddr = scanResult.hasBmi160 ? scanResult.bmi160Address : BMI160_DEFAULT_ADDR;
    bool bmiOk = bmi160.begin(targetAddr);

    if (bmiOk) {
        Serial.printf("  [PASS] BMI160 initialized successfully at 0x%02X!\n", targetAddr);
        Serial.printf("         Chip ID: 0x%02X (Expected: 0xD8)\n", bmi160.readChipId());
    } else {
        Serial.printf("  [FAIL] Could not initialize BMI160 at 0x%02X (Chip ID read: 0x%02X)\n", 
                      targetAddr, bmi160.readChipId());
        Serial.println(F("         Check: SDA, SCL, VCC(3.3V), GND and SDO pins."));
    }

    Serial.println(F("\n[3/3] Initializing Stereo I2S MEMS Microphones..."));
    Serial.printf("      Pins: SCK=D0(GPIO%d), WS=D1(GPIO%d), SD=D2(GPIO%d)\n", 
                  PIN_I2S_SCK, PIN_I2S_WS, PIN_I2S_SD);
    bool micOk = stereoMic.begin(PIN_I2S_SCK, PIN_I2S_WS, PIN_I2S_SD, I2S_SAMPLE_RATE);

    if (micOk) {
        Serial.println(F("  [PASS] I2S Stereo Receiver started successfully (16 kHz, 24/32-bit)."));
    } else {
        Serial.println(F("  [FAIL] Failed to install I2S driver!"));
    }

    Serial.println(F("\n========================================================"));
    Serial.println(F("                 SELF-TEST SUMMARY"));
    Serial.println(F("========================================================"));
    Serial.printf("  - I2C Bus & Devices:     [%s] (%u devices)\n", (scanResult.count > 0) ? "PASS" : "FAIL", scanResult.count);
    Serial.printf("  - BMI160 IMU:            [%s]\n", bmiOk ? "PASS" : "FAIL");
    Serial.printf("  - Stereo I2S Microphones: [%s]\n", micOk ? "PASS" : "FAIL");
    Serial.println(F("========================================================"));

    printHelpMenu();
    return (bmiOk && micOk);
}

void setup() {
    Serial.begin(SERIAL_BAUD_RATE);
    
    // Wait for USB Serial connection (up to 3 seconds)
    unsigned long start = millis();
    while (!Serial && (millis() - start < 3000)) {
        delay(10);
    }

    runHardwareSelfTest();
}

void processSerialInput() {
    while (Serial.available() > 0) {
        char cmd = (char)Serial.read();
        if (cmd == 'm' || cmd == 'M') {
            currentMode = MODE_MONITOR;
            Serial.println(F("\n[MODE] Switched to Monitor / Dashboard Mode."));
        } else if (cmd == 'p' || cmd == 'P') {
            currentMode = MODE_PLOTTER;
            Serial.println(F("\n[MODE] Switched to Serial Plotter Mode. Open Tools -> Serial Plotter!"));
        } else if (cmd == 'i' || cmd == 'I') {
            runHardwareSelfTest();
        } else if (cmd == 'h' || cmd == 'H') {
            printHelpMenu();
        }
    }
}

void loop() {
    processSerialInput();

    unsigned long now = millis();
    if (now - lastPrintTime < PRINT_INTERVAL_MS) {
        return;
    }
    lastPrintTime = now;

    // Read Audio Metrics
    StereoAudioMetrics audio;
    bool audioOk = stereoMic.readMetrics(audio);

    // Read IMU Data
    Bmi160MetricData imu;
    bool imuOk = bmi160.readSensorData(imu);

    if (currentMode == MODE_PLOTTER) {
        // Serial Plotter output format: "Label1:val1 Label2:val2 ..."
        Serial.printf("MicL_RMS:%.1f\tMicR_RMS:%.1f\tAccX_g:%.2f\tAccY_g:%.2f\tAccZ_g:%.2f\tGyrZ_dps:%.1f\n",
                      audioOk ? audio.leftRms : 0.0f,
                      audioOk ? audio.rightRms : 0.0f,
                      imuOk ? imu.accelX_g : 0.0f,
                      imuOk ? imu.accelY_g : 0.0f,
                      imuOk ? imu.accelZ_g : 0.0f,
                      imuOk ? imu.gyroZ_dps : 0.0f);
    } else {
        // Dashboard / Monitor format with visual VU meters
        char vuLeft[32];
        char vuRight[32];
        I2sMicDriver::formatVuBar(vuLeft, sizeof(vuLeft), audio.leftRms, 60000.0f, 12);
        I2sMicDriver::formatVuBar(vuRight, sizeof(vuRight), audio.rightRms, 60000.0f, 12);

        Serial.printf("[MIC-L (GND)] %s RMS:%6.0f (Pk:%6d) %s | [MIC-R (3V3)] %s RMS:%6.0f (Pk:%6d) %s\n",
                      vuLeft,
                      audioOk ? audio.leftRms : 0.0f,
                      audioOk ? audio.leftPeak : 0,
                      audio.leftActive ? "<*SOUND>" : "        ",
                      vuRight,
                      audioOk ? audio.rightRms : 0.0f,
                      audioOk ? audio.rightPeak : 0,
                      audio.rightActive ? "<*SOUND>" : "        ");

        if (imuOk) {
            Serial.printf("  --> [IMU ACCEL (g)] X:%+5.2f  Y:%+5.2f  Z:%+5.2f | [GYRO (dps)] X:%+6.1f  Y:%+6.1f  Z:%+6.1f\n",
                          imu.accelX_g, imu.accelY_g, imu.accelZ_g,
                          imu.gyroX_dps, imu.gyroY_dps, imu.gyroZ_dps);
        } else {
            Serial.println(F("  --> [IMU ERROR] BMI160 not responding! Check I2C wiring."));
        }
    }
}
