#include <Arduino.h>
#include "config.h"
#include "i2c_scanner.h"
#include "imu_driver.h"
#include "i2s_mic_driver.h"
#include "tap_detector.h"
#include "audio_recorder.h"
#include "ble_manager.h"
#include "wifi_server.h"

// Global Modules
static ImuDriver imu;
static I2sMicDriver stereoMic;
static TapDetector tapDetector(TAP_JERK_THRESHOLD_G, TAP_DEBOUNCE_MS);
static AudioRecorder recorder(PIN_STATUS_LED);
static BleManager ble;
static WifiServerManager wifiServer(recorder);

static unsigned long lastTelemetryTime = 0;
static const unsigned long TELEMETRY_INTERVAL_MS = 100;

void printBanner() {
    Serial.println(F("\n========================================================"));
    Serial.println(F("  XIAO ESP32C3 - Hybrid BLE + Wi-Fi Voice Assistant"));
    Serial.println(F("  Tap to Record -> Speak -> Tap to Send via High-Speed Wi-Fi"));
    Serial.println(F("========================================================"));
}

void setup() {
    Serial.begin(SERIAL_BAUD_RATE);
    unsigned long start = millis();
    while (!Serial && (millis() - start < 2500)) delay(10);

    printBanner();

    // 1. Initialize I2C and IMU
    Serial.println(F("[1/5] Starting I2C & Probing 6-Axis IMU..."));
    I2cScanner::begin(PIN_I2C_SDA, PIN_I2C_SCL, I2C_FREQUENCY);
    delay(50);
    bool imuOk = imu.begin();
    if (imuOk) {
        Serial.printf("  [PASS] Identified IMU: %s @ 0x%02X\n", imu.getChipName(), imu.getAddress());
    } else {
        Serial.println(F("  [WARN] IMU not found! Tap detection might be inactive."));
    }

    // 2. Initialize Stereo I2S Microphones
    Serial.println(F("[2/5] Initializing Stereo I2S Microphones..."));
    bool micOk = stereoMic.begin(PIN_I2S_SCK, PIN_I2S_WS, PIN_I2S_SD, AUDIO_SAMPLE_RATE);
    if (micOk) {
        Serial.println(F("  [PASS] I2S Driver started (16 kHz, 24/32-bit)."));
    } else {
        Serial.println(F("  [FAIL] Failed to install I2S Driver!"));
    }

    // 3. Initialize Audio Recorder & Status LED
    Serial.println(F("[3/5] Initializing Audio Recorder & Status LED..."));
    bool recOk = recorder.begin();
    if (recOk) {
        Serial.printf("  [PASS] Audio Buffer allocated (%u bytes for ~%u sec).\n", 
                      recorder.getRecordedBytes(), AUDIO_MAX_SECONDS);
        recorder.blinkLed(3, 80);
    } else {
        Serial.println(F("  [FAIL] Could not allocate Audio Buffer!"));
    }

    // 4. Initialize Wi-Fi Hotspot & Web Server
    Serial.println(F("[4/5] Starting Wi-Fi SoftAP & High-Speed Audio Server..."));
    bool wifiOk = wifiServer.begin(WIFI_AP_SSID, WIFI_AP_PASS, HTTP_SERVER_PORT);
    if (wifiOk) {
        Serial.printf("  [PASS] Hotspot: \"%s\" (PW: %s) -> http://%s/audio.wav\n", 
                      WIFI_AP_SSID, WIFI_AP_PASS, wifiServer.getIp().toString().c_str());
    }

    // 5. Initialize BLE GATT Server (Signaling)
    Serial.println(F("[5/5] Starting BLE GATT Server & Advertising..."));
    bool bleOk = ble.begin(BLE_DEVICE_NAME);
    if (bleOk) {
        Serial.println(F("  [PASS] BLE signaling active as \"XIAO-Audio-Recorder\"."));
    }

    Serial.println(F("\n========================================================"));
    Serial.println(F("  SYSTEM READY:"));
    Serial.println(F("  1. Tap breadboard firmly to START recording (LED turns ON)."));
    Serial.println(F("  2. Speak into microphone."));
    Serial.println(F("  3. Tap breadboard again to STOP -> High-speed Wi-Fi stream available!"));
    Serial.println(F("========================================================\n"));
}

void handleStopAndTransfer() {
    recorder.stopRecording();
    Serial.printf("\n[RECORD] Finished: %u samples (%.2f s, %u bytes)\n", 
                  recorder.getRecordedSamples(), 
                  recorder.getDurationSeconds(), 
                  recorder.getRecordedBytes());

    // Notify BLE client that clip is ready for instant Wi-Fi download
    ble.updateState(STATE_DONE, recorder.getRecordedBytes(), recorder.getSampleRate());
    Serial.println(F("[WIFI] New audio clip ready at http://192.168.4.1/audio.wav"));
}

void loop() {
    // 1. Handle incoming Wi-Fi HTTP requests (e.g. /audio.wav downloads)
    wifiServer.handleClient();

    // 2. Process Active Recording
    if (recorder.isRecording()) {
        bool stillRecording = recorder.processRecording(stereoMic);

        // Check if user tapped again to stop early
        ImuMetricData imuData;
        if (imu.readSensorData(imuData)) {
            float shock = 0.0f;
            if (tapDetector.update(imuData, &shock)) {
                Serial.printf("\n[TAP DETECTED] Stop trigger! Shock: %.2f g\n", shock);
                ble.notifyTap(shock);
                handleStopAndTransfer();
                return;
            }
        }

        // If recording reached max time limit
        if (!stillRecording) {
            handleStopAndTransfer();
            return;
        }

        delay(1);
        return;
    }

    // 3. IDLE State: Monitor IMU for Start Tap
    ImuMetricData imuData;
    bool imuOk = imu.readSensorData(imuData);
    if (imuOk) {
        float shock = 0.0f;
        if (tapDetector.update(imuData, &shock)) {
            Serial.printf("\n[TAP DETECTED] Start trigger! Shock: %.2f g -> STARTING RECORDING...\n", shock);
            ble.notifyTap(shock);
            ble.updateState(STATE_RECORDING);
            recorder.startRecording();
            return;
        }
    }

    // 4. Periodic Telemetry (when Idle)
    unsigned long now = millis();
    if (now - lastTelemetryTime >= TELEMETRY_INTERVAL_MS) {
        lastTelemetryTime = now;

        StereoAudioMetrics audio;
        stereoMic.readMetrics(audio);

        char vuL[24], vuR[24];
        I2sMicDriver::formatVuBar(vuL, sizeof(vuL), audio.leftRms, 50000.0f, 10);
        I2sMicDriver::formatVuBar(vuR, sizeof(vuR), audio.rightRms, 50000.0f, 10);

        Serial.printf("[BLE: %s] [WIFI: 192.168.4.1] [MIC-L] %s RMS:%5.0f | [MIC-R] %s RMS:%5.0f\r",
                      ble.isConnected() ? "CONNECTED   " : "DISCONNECTED",
                      vuL, audio.leftRms,
                      vuR, audio.rightRms);
    }
}
