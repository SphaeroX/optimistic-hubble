#include <Arduino.h>
#include "config.h"
#include "i2c_scanner.h"
#include "imu_driver.h"
#include "i2s_mic_driver.h"
#include "tap_detector.h"
#include "audio_recorder.h"
#include "storage_manager.h"
#include "ble_manager.h"
#include "wifi_server.h"

// Global Modules
static ImuDriver imu;
static I2sMicDriver stereoMic;
static TapDetector tapDetector(TAP_JERK_THRESHOLD_G, TAP_DEBOUNCE_MS);
static AudioRecorder recorder(PIN_STATUS_LED);
static StorageManager storage;
static BleManager ble;
static WifiServerManager wifiServer(storage);

static unsigned long lastTelemetryTime = 0;
static const unsigned long TELEMETRY_INTERVAL_MS = 1000;

void printBanner() {
    Serial.println(F("\n========================================================"));
    Serial.println(F("  XIAO ESP32C3 - Real-Time Direct-to-Flash Voice Vault"));
    Serial.println(F("  Stream to LittleFS (Up to 5 min) -> High-Speed Wi-Fi"));
    Serial.println(F("========================================================"));
}

void setup() {
    Serial.begin(SERIAL_BAUD_RATE);
    unsigned long start = millis();
    while (!Serial && (millis() - start < 2500)) delay(10);

    printBanner();

    // 1. Initialize I2C & IMU
    Serial.println(F("[1/6] Probing 6-Axis IMU (LSM6DS3 / BMI160)..."));
    I2cScanner::begin(PIN_I2C_SDA, PIN_I2C_SCL, I2C_FREQUENCY);
    delay(50);
    bool imuOk = imu.begin();
    if (imuOk) {
        Serial.printf("  [PASS] Identified IMU: %s @ 0x%02X\n", imu.getChipName(), imu.getAddress());
    } else {
        Serial.println(F("  [WARN] IMU not found! Tap detection may be inactive."));
    }

    // 2. Initialize Stereo I2S Microphones
    Serial.println(F("[2/6] Starting Stereo I2S Microphones (16 kHz)..."));
    bool micOk = stereoMic.begin(PIN_I2S_SCK, PIN_I2S_WS, PIN_I2S_SD, AUDIO_SAMPLE_RATE);
    if (micOk) {
        Serial.println(F("  [PASS] I2S Microphone Driver active."));
    } else {
        Serial.println(F("  [FAIL] Failed to start I2S Driver!"));
    }

    // 3. Initialize Persistent Flash Storage (LittleFS)
    Serial.println(F("[3/6] Mounting 4MB Flash Storage (LittleFS)..."));
    bool fsOk = storage.begin(true);
    if (fsOk) {
        Serial.printf("  [PASS] Flash Storage ready. Existing clips: %u | Free: %u KB\n",
                      storage.getClipCount(), (storage.getTotalBytes() - storage.getUsedBytes()) / 1024);
    } else {
        Serial.println(F("  [FAIL] Could not mount LittleFS Flash Storage!"));
    }

    // 4. Initialize Audio Recorder & Status LED
    Serial.println(F("[4/6] Initializing Stream Recorder & Status LED..."));
    bool recOk = recorder.begin();
    if (recOk) {
        Serial.println(F("  [PASS] Stream Recorder ready."));
        recorder.blinkLed(3, 80);
    }

    // 5. Initialize Wi-Fi Hotspot & Sync Server
    Serial.println(F("[5/6] Starting Wi-Fi Hotspot & Sync Server..."));
    bool wifiOk = wifiServer.begin(WIFI_AP_SSID, WIFI_AP_PASS, HTTP_SERVER_PORT);
    if (wifiOk) {
        Serial.printf("  [PASS] Hotspot \"%s\" (PW: %s) -> http://%s\n",
                      WIFI_AP_SSID, WIFI_AP_PASS, wifiServer.getIp().toString().c_str());
    }

    // 6. Initialize BLE GATT Server
    Serial.println(F("[6/6] Starting BLE GATT Server (Signaling)..."));
    bool bleOk = ble.begin(BLE_DEVICE_NAME);
    if (bleOk) {
        Serial.println(F("  [PASS] BLE advertising active as \"XIAO-Audio-Recorder\"."));
    }

    Serial.println(F("\n========================================================"));
    Serial.println(F("  SYSTEM READY:"));
    Serial.println(F("  1. Tap breadboard to START recording (LED turns ON)."));
    Serial.println(F("  2. Speak into microphone (streams straight to Flash)."));
    Serial.println(F("  3. Tap again to STOP -> Finalized WAV saved to Flash!"));
    Serial.println(F("  4. Connect to \"XIAO-Audio-Hotspot\" -> http://192.168.4.1"));
    Serial.println(F("========================================================\n"));
}

void handleStopAndSave() {
    recorder.stopRecording();
    size_t totalClips = storage.getClipCount();
    uint16_t clipId = recorder.getCurrentClipId();

    Serial.printf("\n[RECORD STOP] Clip #%u saved! Total in Flash: %u (Free: %u KB)\n", 
                  clipId, totalClips, (storage.getTotalBytes() - storage.getUsedBytes()) / 1024);

    // Notify BLE client
    ble.updateState(STATE_DONE, clipId, totalClips);
}

void loop() {
    // 1. Process Web Server requests (High priority, non-blocking)
    wifiServer.handleClient();

    // 2. Process Active Real-Time Recording Stream
    if (recorder.isRecording()) {
        bool stillRecording = recorder.processRecording(stereoMic);

        // Check if user tapped again to stop
        ImuMetricData imuData;
        if (imu.readSensorData(imuData)) {
            float shock = 0.0f;
            if (tapDetector.update(imuData, &shock)) {
                Serial.printf("\n[TAP DETECTED] Stop trigger! Shock: %.2f g\n", shock);
                ble.notifyTap(shock);
                handleStopAndSave();
                return;
            }
        }

        if (!stillRecording) {
            handleStopAndSave();
            return;
        }

        delay(1);
        return;
    }

    // 3. IDLE State: Non-blocking IMU monitoring for Start Tap
    ImuMetricData imuData;
    bool imuOk = imu.readSensorData(imuData);
    if (imuOk) {
        float shock = 0.0f;
        if (tapDetector.update(imuData, &shock)) {
            Serial.printf("\n[TAP DETECTED] Start trigger! Shock: %.2f g -> STREAMING TO FLASH...\n", shock);
            ble.notifyTap(shock);
            ble.updateState(STATE_RECORDING);
            
            uint16_t nextId = storage.getClipCount() + 1;
            recorder.startRecording(nextId);
            return;
        }
    }

    // 4. Periodic lightweight heartbeat
    unsigned long now = millis();
    if (now - lastTelemetryTime >= TELEMETRY_INTERVAL_MS) {
        lastTelemetryTime = now;

        Serial.printf("[STATUS] BLE: %s | Flash: %u clips (Free: %u KB) | AP: http://192.168.4.1\n",
                      ble.isConnected() ? "CONNECTED" : "STANDBY  ",
                      storage.getClipCount(),
                      (storage.getTotalBytes() - storage.getUsedBytes()) / 1024);
    }
}
