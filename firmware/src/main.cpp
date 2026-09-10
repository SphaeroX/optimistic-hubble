#include <Arduino.h>
#include "config.h"
#include "i2c_scanner.h"
#include "imu_driver.h"
#include "i2s_mic_driver.h"
#include "tap_detector.h"
#include "shake_detector.h"
#include "audio_recorder.h"
#include "storage_manager.h"
#include "ble_manager.h"
#include "wifi_server.h"
#include "wifi_uploader.h"
#include "power_manager.h"
#include "led_indicator.h"
#include "spi_flash_driver.h"

// Global Hardware Modules
static ImuDriver imu;
static I2sMicDriver stereoMic;
static TapDetector tapDetector(TAP_JERK_THRESHOLD_G, TAP_DEBOUNCE_MS, DOUBLE_TAP_WINDOW_MIN_MS, DOUBLE_TAP_WINDOW_MAX_MS);
static ShakeDetector shakeDetector(SHAKE_THRESHOLD_G, SHAKE_WINDOW_MS, SHAKE_REVERSALS_REQUIRED, SHAKE_COOLDOWN_MS);
static LedIndicator leds(PIN_STATUS_LED, PIN_LED_GREEN);
static AudioRecorder recorder(0xFF); // LED indicator managed exclusively by LedIndicator
static StorageManager storage;
static SpiFlashDriver extFlash(PIN_FLASH_SCK, PIN_FLASH_MISO, PIN_FLASH_MOSI, PIN_FLASH_CS);
static BleManager ble(&leds);
static WifiServerManager wifiServer(storage, &leds);
static WifiUploader wifiUploader(storage, &leds);
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
    Serial.println(F("  ESP32-C3-MINI-1 - Audio Vault (V2 Production Design)"));
    Serial.println(F("  Dual ICS-43434 • LSM6DSL IMU • W25Q128 16MB SPI Flash"));
    Serial.println(F("  IMA-ADPCM 4:1 (8 KB/s) • Dual Active-LOW LEDs"));
    Serial.println(F("========================================================"));
}

void pushTelemetryUpdate(DeviceState state, uint32_t audioBytes = 0) {
    if (!ble.isConnected()) return;

    ImuMetricData imuMetrics{};
    bool hasImu = imu.readSensorData(imuMetrics);
    float mag = hasImu 
        ? sqrtf(imuMetrics.accelX_g * imuMetrics.accelX_g + 
                imuMetrics.accelY_g * imuMetrics.accelY_g + 
                imuMetrics.accelZ_g * imuMetrics.accelZ_g)
        : 1.0f;

    ble.sendTelemetry(
        state,
        audioBytes,
        AUDIO_SAMPLE_RATE,
        4180, // 4.18V nominal
        98,   // 98%
        true, // USB Powered
        ESP.getFreeHeap(),
        storage.getUsedBytes(),
        extFlash.isConnected() ? (uint32_t)extFlash.getCapacityBytes() : storage.getTotalBytes(),
        storage.getClipCount(),
        (int16_t)(imuMetrics.accelX_g * 1000.0f),
        (int16_t)(imuMetrics.accelY_g * 1000.0f),
        (int16_t)(imuMetrics.accelZ_g * 1000.0f),
        (uint16_t)(mag * 1000.0f),
        totalTapEvents
    );
}

void startActiveRecording() {
    power.notifyActivity();

    // 1. Start Stereo I2S Microphones on-demand
    if (!stereoMic.isInitialized()) {
        stereoMic.begin(PIN_I2S_SCK, PIN_I2S_WS, PIN_I2S_SD, AUDIO_SAMPLE_RATE);
    }

    // 2. Ensure IMU is in normal high-performance mode
    imu.setPowerMode(true);

    // 3. Start Recording Clip and set LED indicator
    uint16_t nextId = storage.getNextClipId();
    recorder.startRecording(nextId);
    leds.setMode(ble.isConnected() ? LedMode::RECORDING_CONNECTED : LedMode::RECORDING);
    pushTelemetryUpdate(STATE_RECORDING, 0);

    Serial.printf("\n[RECORD START] Clip #%u recording started!\n", nextId);
}

static unsigned long postRecordingGracePeriodEnd = 0;

void handleStopAndSave() {
    recorder.stopRecording();
    
    // Stop I2S to save microphone power
    stereoMic.stop();

    // Prevent immediate return to deep sleep: guarantee 15s awake after recording stops
    postRecordingGracePeriodEnd = millis() + 15000UL;
    power.notifyActivity();

    // Update LED mode according to current connectivity
    leds.setMode(wifiServer.isActive() ? LedMode::WIFI_AP : (ble.isConnected() ? LedMode::BLE_CONNECTED : LedMode::IDLE));

    storage.refresh();
    size_t totalClips = storage.getClipCount();
    uint16_t clipId = recorder.getCurrentClipId();

    Serial.printf("\n[RECORD STOP] Clip #%u saved! Total in Flash: %u (Free: %u KB)\n", 
                  clipId, totalClips, (storage.getTotalBytes() - storage.getUsedBytes()) / 1024);
    Serial.println(F("[POWER] Post-recording 15s stay-awake grace period started."));

    pushTelemetryUpdate(STATE_DONE, 0);
}

void setup() {
    // 1. Boot Power Manager & Inspect Wake-up Reason
    power.begin();

    Serial.begin(SERIAL_BAUD_RATE);
    unsigned long start = millis();
    while (!Serial && (millis() - start < 600)) delay(5);

    printBanner();
    Serial.printf("[SYSTEM] Wake-up Cause: %s\n", power.getWakeupReasonString());

    // 2. Configure Hardware Pins & Dual Status LEDs
    pinMode(PIN_BOOT_BTN, INPUT_PULLUP);
    pinMode(PIN_IMU_INT, INPUT_PULLDOWN);
    leds.begin();

    // 3. Initialize I2C & IMU (ST LSM6DSL)
    I2cScanner::begin(PIN_I2C_SDA, PIN_I2C_SCL, I2C_FREQUENCY);
    delay(20);
    bool imuOk = imu.begin();
    if (imuOk) {
        Serial.printf("  [PASS] Identified IMU: %s @ 0x%02X\n", imu.getChipName(), imu.getAddress());
        // Clear any latched wake-up / tap interrupts to reset INT1 pin
        imu.clearInterrupts();
    } else {
        Serial.println(F("  [WARN] IMU not found! Tap detection may be inactive."));
    }

    // 4. Initialize Persistent Internal Flash Storage (LittleFS)
    bool fsOk = storage.begin(true);
    if (fsOk) {
        Serial.printf("  [PASS] Internal Flash Storage ready. Existing clips: %u | Free: %u KB\n",
                      storage.getClipCount(), (storage.getTotalBytes() - storage.getUsedBytes()) / 1024);
    } else {
        Serial.println(F("  [FAIL] Could not mount LittleFS Flash Storage!"));
    }

    // 5. Initialize External SPI2 Flash Storage (Winbond W25Q128 16MB)
    bool extFlashOk = extFlash.begin();
    if (extFlashOk) {
        Serial.printf("  [PASS] External SPI2 Flash ready: %s (%u MB)\n", 
                      extFlash.getChipName(), (unsigned int)(extFlash.getCapacityBytes() / (1024 * 1024)));
    } else {
        Serial.println(F("  [INFO] External SPI2 Flash not detected or optional."));
    }

    // 6. Initialize Audio Recorder
    bool recOk = recorder.begin();
    if (recOk) {
        Serial.println(F("  [PASS] Stream Recorder ready."));
    }

    // 7. Initialize BLE GATT Server
    bool bleOk = ble.begin(BLE_DEVICE_NAME);
    if (bleOk) {
        Serial.println(F("  [PASS] BLE advertising active as \"XIAO-Audio-Recorder\"."));
    }

    // 8. Handle Wake-up Routing & LED Sequence
    if (power.wasWokenByMotion()) {
        ImuMetricData bootImu{};
        bool hasBootImu = imu.readSensorData(bootImu);
        bool isArmUp = hasBootImu && (bootImu.accelY_g <= IMU_ARM_UP_Y_THRESHOLD_G);

        if (isArmUp) {
            Serial.printf("\n  >>> Woken from Deep Sleep with ARM UP (Y=%+.2f g)! <<<\n", bootImu.accelY_g);
            Serial.println(F("  >>> Starting recording immediately!\n"));
            startActiveRecording();
        } else {
            Serial.printf("\n  >>> Woken from Deep Sleep with ARM DOWN (Y=%+.2f g). <<<\n", 
                          hasBootImu ? bootImu.accelY_g : 0.0f);
            Serial.println(F("  >>> MCU is now AWAKE (IDLE). Shake with arm UP to START recording."));
            Serial.println(F("  >>> (Device will return to Deep Sleep if idle for 15s)\n"));
            // Acknowledge wake-up with quick double-blink green
            leds.blink(PIN_LED_GREEN, 2, 70);
            leds.setMode(LedMode::IDLE);
        }
    } else {
        leds.bootSequence();
        leds.setMode(LedMode::IDLE);
        Serial.println(F("\n========================================================"));
        Serial.println(F("  READY:"));
        Serial.println(F("  1. Shake device with ARM DOWN to WAKE from Deep Sleep."));
        Serial.println(F("  2. Shake device with ARM UP (Y-axis ~ -1g) to START recording."));
        Serial.println(F("  3. Shake device in ANY orientation to STOP recording."));
        Serial.println(F("  4. Press BTN button to toggle Wi-Fi, hold 2s for Flash Mode."));
        Serial.println(F("  5. Connect USB to keep permanently awake."));
        Serial.println(F("========================================================\n"));
    }
}

void loop() {
    unsigned long now = millis();

    // 0. Tick LED Indicator Animation/Blinking
    leds.update();

    // 1. Process Active Real-Time Recording Stream
    if (recorder.isRecording()) {
        bool stillRecording = recorder.processRecording(stereoMic);

        // Check IMU for stop shake gesture at a clean 50 Hz interval
        if (now - lastImuPollTime >= IMU_POLL_INTERVAL_MS) {
            lastImuPollTime = now;

            ImuMetricData imuData;
            if (imu.readSensorData(imuData)) {
                float intensity = 0.0f;
                ShakeEventType shakeEvt = shakeDetector.update(imuData, &intensity);
                if (shakeEvt == ShakeEventType::SHAKE_DETECTED) {
                    totalTapEvents++;
                    Serial.printf("\n[SHAKE DETECTED] Stop trigger! Intensity: %.2f g -> STOPPING RECORDING...\n", intensity);
                    ble.notifyTap(intensity);
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
                leds.setMode(LedMode::WIFI_AP);
                ble.updateState(STATE_WIFI_ACTIVE);
                break;

            case CMD_STOP_WIFI:
                Serial.printf("\n[BLE CMD] Stop Wi-Fi Hotspot requested! (Current SoftAP: %s)\n",
                              wifiServer.isActive() ? "ACTIVE" : "ALREADY OFF");
                if (wifiServer.isActive()) {
                    wifiServer.stop();
                }
                leds.setMode(ble.isConnected() ? LedMode::BLE_CONNECTED : LedMode::IDLE);
                ble.updateState(STATE_IDLE);
                break;

            case CMD_ENTER_SLEEP:
                Serial.println(F("\n[BLE CMD] Entering Deep Sleep upon user request..."));
                ble.updateState(STATE_SLEEPING);
                leds.turnOffAll();
                delay(100);
                power.enterDeepSleep(imu, &extFlash, IMU_WAKEUP_THRESHOLD_G);
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

            case CMD_CONNECT_HOTSPOT:
            {
                HotspotUploadConfig cfg = ble.getHotspotUploadConfig();
                Serial.printf("\n[BLE CMD] Connecting to Phone Hotspot \"%s\" for High-Speed Audio Upload...\n", cfg.ssid);
                ble.updateState(STATE_TRANSFERRING);
                leds.setMode(LedMode::SYNCING);
                bool uploadOk = wifiUploader.uploadClips(cfg);
                storage.refresh();
                ble.updateState(uploadOk ? STATE_DONE : STATE_IDLE, 0, AUDIO_SAMPLE_RATE);
                delay(100);
                ble.updateState(STATE_IDLE);
                leds.setMode(ble.isConnected() ? LedMode::BLE_CONNECTED : LedMode::IDLE);
                break;
            }

            case CMD_DELETE_CLIP:
            {
                uint16_t clipId = ble.getCommandClipId();
                Serial.printf("\n[BLE CMD] Delete Clip #%u requested from Flash...\n", clipId);
                bool ok = storage.deleteClip(clipId);
                storage.refresh();
                Serial.printf("[BLE CMD] Delete Clip #%u %s. Remaining clips in Flash: %u (Free: %u KB)\n",
                              clipId, ok ? "SUCCESSFUL" : "NOT FOUND",
                              storage.getClipCount(),
                              (storage.getTotalBytes() - storage.getUsedBytes()) / 1024);
                ble.updateState(STATE_IDLE);
                break;
            }

            default:
                break;
        }
    }

    // 3. Check Boot Button (GPIO 9 / BTN) for Wi-Fi Toggle (short press) or Flash Mode (long press >= 2s)
    static unsigned long buttonPressStartTime = 0;
    static bool buttonIsHeld = false;
    static bool longPressHandled = false;

    if (now - lastButtonCheckTime >= 20) {
        lastButtonCheckTime = now;
        bool btnState = digitalRead(PIN_BOOT_BTN);
        if (lastButtonState == HIGH && btnState == LOW) {
            // Button pressed down (Active LOW)
            buttonPressStartTime = now;
            buttonIsHeld = true;
            longPressHandled = false;
            power.notifyActivity();
        } else if (lastButtonState == LOW && btnState == LOW) {
            // Button being held down
            if (buttonIsHeld && !longPressHandled && (now - buttonPressStartTime >= 2000)) {
                longPressHandled = true;
                bool newPrevent = !power.isSleepPrevented();
                power.setPreventSleep(newPrevent);
                Serial.printf("\n[BUTTON] Long press! Service/Flash Mode: %s\n", 
                              newPrevent ? "ACTIVATED (Deep Sleep permanently locked off)" : "DEACTIVATED (Auto Deep Sleep restored)");
                if (newPrevent) {
                    leds.setMode(LedMode::SERVICE_MODE);
                } else {
                    leds.setMode(ble.isConnected() ? LedMode::BLE_CONNECTED : LedMode::IDLE);
                }
            }
        } else if (lastButtonState == LOW && btnState == HIGH) {
            // Button released
            buttonIsHeld = false;
            if (!longPressHandled) {
                // Short press: Toggle Wi-Fi SoftAP
                power.notifyActivity();
                if (wifiServer.isActive()) {
                    Serial.println(F("[BUTTON] Short press: Toggling Wi-Fi OFF..."));
                    wifiServer.stop();
                    leds.setMode(ble.isConnected() ? LedMode::BLE_CONNECTED : (power.isSleepPrevented() ? LedMode::SERVICE_MODE : LedMode::IDLE));
                    ble.updateState(STATE_IDLE);
                } else {
                    Serial.println(F("[BUTTON] Short press: Toggling Wi-Fi ON..."));
                    wifiServer.begin(WIFI_AP_SSID, WIFI_AP_PASS, HTTP_SERVER_PORT);
                    leds.setMode(LedMode::WIFI_AP);
                    ble.updateState(STATE_WIFI_ACTIVE);
                }
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

    // 5. IDLE State: Monitor IMU for Start Shake Gesture (when not recording and awake)
    if (!recorder.isRecording() && (now - lastImuPollTime >= IMU_POLL_INTERVAL_MS)) {
        lastImuPollTime = now;

        ImuMetricData imuData;
        if (imu.readSensorData(imuData)) {
            float intensity = 0.0f;
            ShakeEventType shakeEvt = shakeDetector.update(imuData, &intensity);
            if (shakeEvt == ShakeEventType::SHAKE_DETECTED) {
                totalTapEvents++;
                power.notifyActivity();

                if (imuData.accelY_g <= IMU_ARM_UP_Y_THRESHOLD_G) {
                    Serial.printf("\n[SHAKE DETECTED] Arm is UP (Y=%+.2f g, Intensity: %.2f g) -> STARTING RECORDING...\n",
                                  imuData.accelY_g, intensity);
                    ble.notifyTap(intensity);
                    startActiveRecording();
                } else {
                    Serial.printf("\n[SHAKE DETECTED] Arm is DOWN (Y=%+.2f g) -> Recording not started (raise arm to record).\n",
                                  imuData.accelY_g);
                }
            } else {
                // Keep device awake if any tap/motion is detected
                float shock = 0.0f;
                TapEventType tapEvt = tapDetector.update(imuData, &shock);
                if (tapEvt != TapEventType::NONE) {
                    power.notifyActivity();
                    Serial.println(F("[IMU] Tap detected while awake. Inactivity timer extended."));
                }
            }
        }
    }

    // 6. Automatic Deep Sleep Transition (Active only when on battery / USB disconnected)
    if (ENABLE_DEEP_SLEEP_AUTO && !recorder.isRecording() && !wifiServer.isActive() && !ble.isConnected()) {
        if (!power.isSleepPrevented()) {
            if (power.isUsbConnected()) {
                // Refresh activity so that the 15s timer starts cleanly when USB is unplugged
                power.notifyActivity();
                static unsigned long lastUsbLogTime = 0;
                if (now - lastUsbLogTime >= 10000) {
                    lastUsbLogTime = now;
                    Serial.println(F("[POWER] USB host connected -> Deep Sleep blocked. Device stays permanently awake for dev/flashing."));
                }
            } else if (now < postRecordingGracePeriodEnd) {
                // Guarantee at least 15s stay-awake after recording stops before deep sleep
                power.notifyActivity();
            } else if (power.isIdleTimeoutExpired(INACTIVITY_SLEEP_TIMEOUT_MS)) {
                Serial.printf("[POWER] Inactivity timeout (%u s) expired on battery. Entering Deep Sleep...\n",
                              (unsigned int)(INACTIVITY_SLEEP_TIMEOUT_MS / 1000));
                ble.stop();
                leds.turnOffAll();
                power.enterDeepSleep(imu, &extFlash, IMU_WAKEUP_THRESHOLD_G);
                return;
            }
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

        static bool lastBleConnected = false;
        bool isBle = ble.isConnected();
        if (isBle != lastBleConnected) {
            lastBleConnected = isBle;
            if (recorder.isRecording()) {
                leds.setMode(isBle ? LedMode::RECORDING_CONNECTED : LedMode::RECORDING);
            } else if (!wifiServer.isActive() && leds.getMode() != LedMode::SYNCING) {
                leds.setMode(isBle ? LedMode::BLE_CONNECTED : LedMode::IDLE);
            }
        }

        if (isBle) {
            DeviceState curState = recorder.isRecording() ? STATE_RECORDING : 
                                   (wifiServer.isActive() ? STATE_WIFI_ACTIVE : STATE_IDLE);
            pushTelemetryUpdate(curState, recorder.isRecording() ? recorder.getRecordedBytes() : 0);
        }
    }
}

