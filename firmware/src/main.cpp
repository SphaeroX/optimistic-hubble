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
#include "power_manager.h"

// Global Hardware Modules
static ImuDriver imu;
static I2sMicDriver stereoMic;
static TapDetector tapDetector(TAP_JERK_THRESHOLD_G, TAP_DEBOUNCE_MS);
static AudioRecorder recorder(PIN_STATUS_LED);
static StorageManager storage;
static BleManager ble;
static WifiServerManager wifiServer(storage);
static PowerManager power;
static uint16_t totalTapEvents = 0;

static unsigned long lastTelemetryTime = 0;
static const unsigned long TELEMETRY_INTERVAL_MS = 100; // 10 Hz real-time telemetry stream

static unsigned long lastImuPollTime = 0;
static const unsigned long IMU_POLL_INTERVAL_MS = 20; // 50 Hz tap polling

static unsigned long lastButtonCheckTime = 0;
static bool lastButtonState = HIGH;

void printBanner() {
    Serial.println(F("\n========================================================"));
    Serial.println(F("  XIAO ESP32C3 - Audio Vault (Active Debugging Mode)"));
    Serial.println(F("  IMA-ADPCM 4:1 (8 KB/s) • Continuous Standby & IMU Tap"));
    Serial.println(F("========================================================"));
}

void startActiveRecording() {
    power.notifyActivity();

    // 1. Start Stereo I2S Microphones on-demand
    if (!stereoMic.isInitialized()) {
        stereoMic.begin(PIN_I2S_SCK, PIN_I2S_WS, PIN_I2S_SD, AUDIO_SAMPLE_RATE);
    }

    // 2. Ensure IMU is in normal high-performance mode
    imu.setPowerMode(true);

    // 3. Start Recording Clip
    uint16_t nextId = storage.getNextClipId();
    recorder.startRecording(nextId);
    ble.updateState(STATE_RECORDING);

    Serial.printf("\n[RECORD START] Clip #%u recording started!\n", nextId);
}

void handleStopAndSave() {
    recorder.stopRecording();
    
    // Stop I2S to save microphone power
    stereoMic.stop();

    storage.refresh();
    size_t totalClips = storage.getClipCount();
    uint16_t clipId = recorder.getCurrentClipId();

    Serial.printf("\n[RECORD STOP] Clip #%u saved! Total in Flash: %u (Free: %u KB)\n", 
                  clipId, totalClips, (storage.getTotalBytes() - storage.getUsedBytes()) / 1024);

    ble.updateState(STATE_DONE, clipId, totalClips);
    power.notifyActivity();
}

void setup() {
    // 1. Boot Power Manager & Inspect Wake-up Reason
    power.begin();

    Serial.begin(SERIAL_BAUD_RATE);
    unsigned long start = millis();
    while (!Serial && (millis() - start < 600)) delay(5);

    printBanner();
    Serial.printf("[SYSTEM] Wake-up Cause: %s\n", power.getWakeupReasonString());

    // Configure Hardware Pins
    pinMode(PIN_BOOT_BTN, INPUT_PULLUP);
    pinMode(PIN_IMU_INT, INPUT_PULLDOWN);

    // 2. Initialize I2C & IMU
    I2cScanner::begin(PIN_I2C_SDA, PIN_I2C_SCL, I2C_FREQUENCY);
    delay(20);
    bool imuOk = imu.begin();
    if (imuOk) {
        Serial.printf("  [PASS] Identified IMU: %s @ 0x%02X\n", imu.getChipName(), imu.getAddress());
    } else {
        Serial.println(F("  [WARN] IMU not found! Tap detection may be inactive."));
    }

    // 3. Initialize Persistent Flash Storage (LittleFS)
    bool fsOk = storage.begin(true);
    if (fsOk) {
        Serial.printf("  [PASS] Flash Storage ready. Existing clips: %u | Free: %u KB\n",
                      storage.getClipCount(), (storage.getTotalBytes() - storage.getUsedBytes()) / 1024);
    } else {
        Serial.println(F("  [FAIL] Could not mount LittleFS Flash Storage!"));
    }

    // 4. Initialize Audio Recorder & Status LED
    bool recOk = recorder.begin();
    if (recOk) {
        Serial.println(F("  [PASS] Stream Recorder ready."));
    }

    // 5. Initialize BLE GATT Server
    bool bleOk = ble.begin(BLE_DEVICE_NAME);
    if (bleOk) {
        Serial.println(F("  [PASS] BLE advertising active as \"XIAO-Audio-Recorder\"."));
    }

    // 6. Handle Wake-up Routing
    if (power.wasWokenByMotion()) {
        Serial.println(F("  >>> Woken by SHOCK! Starting audio recording instantly..."));
        startActiveRecording();
    } else {
        recorder.blinkLed(3, 80);
        Serial.println(F("\n========================================================"));
        Serial.println(F("  READY:"));
        Serial.println(F("  1. Tap breadboard to RECORD (or wake from Deep Sleep)."));
        Serial.println(F("  2. Tap again to STOP & SAVE (ADPCM 8 KB/s)."));
        Serial.println(F("  3. Press Boot button (D7) or send BLE command to start Wi-Fi."));
        Serial.println(F("========================================================\n"));
    }
}

void loop() {
    unsigned long now = millis();

    // 1. Process Active Real-Time Recording Stream
    if (recorder.isRecording()) {
        bool stillRecording = recorder.processRecording(stereoMic);

        // Check IMU for stop tap at a clean 50 Hz interval
        if (now - lastImuPollTime >= IMU_POLL_INTERVAL_MS) {
            lastImuPollTime = now;

            ImuMetricData imuData;
            if (imu.readSensorData(imuData)) {
                float shock = 0.0f;
                if (tapDetector.update(imuData, &shock)) {
                    totalTapEvents++;
                    Serial.printf("\n[TAP DETECTED] Stop trigger! Shock: %.2f g\n", shock);
                    ble.notifyTap(shock);
                    handleStopAndSave();
                }
            }
        }

        if (!stillRecording) {
            handleStopAndSave();
        }
    }

    // 2. Check Remote BLE Commands
    if (ble.hasPendingCommand()) {
        BleCommand cmd = ble.getPendingCommand();
        power.notifyActivity();

        switch (cmd) {
            case CMD_START_WIFI:
                Serial.printf("\n[BLE CMD] Start Wi-Fi Hotspot requested! (Current SoftAP: %s)\n",
                              wifiServer.isActive() ? "ALREADY RUNNING" : "STARTING");
                if (!wifiServer.isActive()) {
                    wifiServer.begin(WIFI_AP_SSID, WIFI_AP_PASS, HTTP_SERVER_PORT);
                }
                ble.updateState(STATE_WIFI_ACTIVE);
                break;

            case CMD_STOP_WIFI:
                Serial.printf("\n[BLE CMD] Stop Wi-Fi Hotspot requested! (Current SoftAP: %s)\n",
                              wifiServer.isActive() ? "ACTIVE" : "ALREADY OFF");
                if (wifiServer.isActive()) {
                    wifiServer.stop();
                }
                ble.updateState(STATE_IDLE);
                break;

            case CMD_ENTER_SLEEP:
                Serial.println(F("\n[BLE CMD] Entering Deep Sleep upon user request..."));
                ble.updateState(STATE_SLEEPING);
                delay(100);
                power.enterDeepSleep(imu, IMU_WAKEUP_THRESHOLD_G);
                return;

            case CMD_START_RECORDING:
                if (!recorder.isRecording()) {
                    Serial.println(F("\n[BLE CMD] Start Recording requested..."));
                    startActiveRecording();
                }
                break;

            case CMD_STOP_RECORDING:
                if (recorder.isRecording()) {
                    Serial.println(F("\n[BLE CMD] Stop Recording requested..."));
                    handleStopAndSave();
                }
                break;

            case CMD_CLEAR_STORAGE:
                Serial.println(F("\n[BLE CMD] Clearing all audio clips from Flash..."));
                storage.clearAll();
                storage.refresh();
                ble.updateState(STATE_IDLE);
                break;

            case CMD_START_L2CAP_STREAM:
                Serial.printf("\n[BLE CMD] Start audio stream for clip #%u (Offset: %lu)...\n",
                              ble.getCommandClipId(), ble.getCommandOffset());
                ble.streamAudioFileFromStorage(ble.getCommandClipId(), ble.getCommandOffset());
                break;

            default:
                break;
        }
    }

    // 3. Check Boot Button (D7 / GPIO 9) for Manual Wi-Fi Toggle
    if (now - lastButtonCheckTime >= 50) {
        lastButtonCheckTime = now;
        bool btnState = digitalRead(PIN_BOOT_BTN);
        if (lastButtonState == HIGH && btnState == LOW) { // Button Pressed
            power.notifyActivity();
            if (wifiServer.isActive()) {
                Serial.println(F("[BUTTON] Toggling Wi-Fi OFF..."));
                wifiServer.stop();
                ble.updateState(STATE_IDLE);
            } else {
                Serial.println(F("[BUTTON] Toggling Wi-Fi ON..."));
                wifiServer.begin(WIFI_AP_SSID, WIFI_AP_PASS, HTTP_SERVER_PORT);
                ble.updateState(STATE_WIFI_ACTIVE);
            }
        }
        lastButtonState = btnState;
    }

    // 4. IDLE State: Handle WebServer, DNS requests, and SoftAP Watchdog (if Wi-Fi active)
    if (wifiServer.isActive()) {
        wifiServer.handleClient();
        wifiServer.checkWatchdog();
        power.notifyActivity();
    }

    // 5. IDLE State: Monitor IMU for Start Tap (when not recording and awake)
    if (!recorder.isRecording() && (now - lastImuPollTime >= IMU_POLL_INTERVAL_MS)) {
        lastImuPollTime = now;

        ImuMetricData imuData;
        if (imu.readSensorData(imuData)) {
            float shock = 0.0f;
            if (tapDetector.update(imuData, &shock)) {
                totalTapEvents++;
                Serial.printf("\n[TAP DETECTED] Start trigger! Shock: %.2f g -> RECORDING...\n", shock);
                ble.notifyTap(shock);
                startActiveRecording();
            }
        }
    }

    // 6. Automatic Deep Sleep Transition (Disabled for Debugging)
    if (ENABLE_DEEP_SLEEP_AUTO && !recorder.isRecording() && !wifiServer.isActive() && !ble.isConnected()) {
        if (power.isIdleTimeoutExpired(INACTIVITY_SLEEP_TIMEOUT_MS)) {
            Serial.printf("[POWER] Inactivity timeout (%u s) expired with no clients. Entering Deep Sleep...\n",
                          (unsigned int)(INACTIVITY_SLEEP_TIMEOUT_MS / 1000));
            ble.stop();
            power.enterDeepSleep(imu, IMU_WAKEUP_THRESHOLD_G);
            return;
        }
    }

    // 7. Periodic Telemetry (12.5 Hz BLE Stream + Serial)
    if (now - lastTelemetryTime >= TELEMETRY_INTERVAL_MS) {
        lastTelemetryTime = now;

        ImuMetricData imuMetrics{};
        bool hasImu = imu.readSensorData(imuMetrics);
        float mag = hasImu 
            ? sqrtf(imuMetrics.accelX_g * imuMetrics.accelX_g + 
                    imuMetrics.accelY_g * imuMetrics.accelY_g + 
                    imuMetrics.accelZ_g * imuMetrics.accelZ_g)
            : 1.0f;

        static unsigned long lastSerialPrintTime = 0;
        if (now - lastSerialPrintTime >= 500) {
            lastSerialPrintTime = now;
            Serial.printf("[STATUS] BLE: %s | State: %s | IMU: X=%+.2f Y=%+.2f Z=%+.2f (Mag=%.2fg) | Clips: %u | Taps: %u\n",
                          ble.isConnected() ? "ONLINE " : "STANDBY",
                          recorder.isRecording() ? "RECORDING" : (wifiServer.isActive() ? "WIFI_AP  " : "IDLE     "),
                          imuMetrics.accelX_g, imuMetrics.accelY_g, imuMetrics.accelZ_g, mag,
                          storage.getClipCount(), totalTapEvents);
        }

        if (ble.isConnected()) {
            DeviceState curState = recorder.isRecording() ? STATE_RECORDING : 
                                   (wifiServer.isActive() ? STATE_WIFI_ACTIVE : STATE_IDLE);

            ble.sendTelemetry(
                curState,
                recorder.isRecording() ? recorder.getRecordedBytes() : 0,
                AUDIO_SAMPLE_RATE,
                4180, // 4.18V USB-C / LiPo nominal
                98,   // 98%
                true, // USB Powered
                ESP.getFreeHeap(),
                storage.getUsedBytes(),
                storage.getTotalBytes(),
                storage.getClipCount(),
                (int16_t)(imuMetrics.accelX_g * 1000.0f),
                (int16_t)(imuMetrics.accelY_g * 1000.0f),
                (int16_t)(imuMetrics.accelZ_g * 1000.0f),
                (uint16_t)(mag * 1000.0f),
                totalTapEvents
            );
        }
    }
}

