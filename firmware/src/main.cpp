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
#include "battery_manager.h"
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
static BatteryManager battery;
static uint16_t totalTapEvents = 0;

static unsigned long lastTelemetryTime = 0;
static const unsigned long TELEMETRY_INTERVAL_MS = 100; // 10 Hz real-time telemetry stream

static unsigned long lastImuPollTime = 0;
static const unsigned long IMU_POLL_INTERVAL_MS = 20; // 50 Hz tap polling

static unsigned long lastButtonCheckTime = 0;
static bool lastButtonState = HIGH;

void printBanner() {
    Serial.println(F("\n========================================================"));
    Serial.println(F("  Audio Vault (Custom Production PCB V2)"));
    Serial.println(F("  ESP32-C3-MINI-1-N4 * Dual ICS-43434 * LSM6DSL IMU"));
    Serial.println(F("  Winbond W25Q128 16MB SPI Flash * TP4054 / AP2112K"));
    Serial.println(F("========================================================"));
}

void printSystemSummary() {
    printBanner();
    Serial.printf("[SYSTEM] Wake-up Cause: %s\n", power.getWakeupReasonString());
    Serial.printf("  IMU: %s @ 0x%02X\n", imu.getChipName(), imu.getAddress());
    Serial.printf("  Storage: %s (%u MB total) | Clips: %u | Free: %u KB\n",
                  storage.isExternalFlash() ? "External 16MB SPI Flash" : "Internal Flash",
                  (unsigned int)(storage.getTotalBytes() / (1024 * 1024)),
                  (unsigned int)storage.getClipCount(),
                  (unsigned int)((storage.getTotalBytes() - storage.getUsedBytes()) / 1024));
    Serial.printf("  Battery: %u mV (%u%%, %s) | Heap Free: %u bytes\n",
                  battery.getVoltageMilliVolts(), battery.getPercent(),
                  battery.isCharging() ? "Charging" : "Discharging",
                  ESP.getFreeHeap());
    Serial.printf("  BLE: %s | Wi-Fi SoftAP: %s | Service Mode: %s\n",
                  ble.isConnected() ? "Connected" : "Advertising",
                  wifiServer.isActive() ? "ON" : "OFF",
                  power.isSleepPrevented() ? "ENABLED" : "DISABLED");
    Serial.println(F("========================================================"));
    Serial.println(F("  Commands via Serial Monitor:"));
    Serial.println(F("    [r] -> Restart MCU (Software Reset)"));
    Serial.println(F("    [b] -> Reprint this System Summary / Banner"));
    Serial.println(F("    [w] -> Toggle Wi-Fi SoftAP"));
    Serial.println(F("    [s] -> Toggle Recording Start/Stop"));
    Serial.println(F("========================================================\n"));
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

    battery.update(state, power.isUsbConnected());

    ble.sendTelemetry(
        state,
        audioBytes,
        recorder.getSampleRate(),
        battery.getVoltageMilliVolts(),
        battery.getPercent(),
        battery.isCharging(),
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

void startActiveRecording() {
    power.notifyActivity();

    AudioQuality quality = storage.getQuality();
    uint32_t micRate = (quality == QUALITY_LOW) ? 8000 : AUDIO_SAMPLE_RATE;

    // 1. Start Stereo I2S Microphones on-demand
    if (!stereoMic.isInitialized() || stereoMic.getSampleRate() != micRate) {
        stereoMic.begin(PIN_I2S_SCK, PIN_I2S_WS, PIN_I2S_SD, micRate);
    }

    // 2. Ensure IMU is in normal high-performance mode
    imu.setPowerMode(true);

    // 3. Start Recording Clip and set LED indicator
    uint16_t nextId = storage.getNextClipId();
    recorder.startRecording(nextId, quality);
    leds.setMode(ble.isConnected() ? LedMode::RECORDING_CONNECTED : LedMode::RECORDING);
    pushTelemetryUpdate(STATE_RECORDING, 0);

    Serial.printf("\n[RECORD START] Clip #%u recording started (Quality: %u, Rate: %u Hz)!\n",
                  nextId, (unsigned int)quality, (unsigned int)micRate);
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
    battery.begin();

    Serial.begin(SERIAL_BAUD_RATE);
    if (power.isUsbConnected()) {
        unsigned long start = millis();
        while (!Serial && (millis() - start < 300)) delay(10);
    }
    delay(20); // Small buffer flush delay for CDC enumeration

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

    // 4. Initialize External SPI2 Flash Storage (Winbond W25Q128 16MB)
    bool extFlashOk = extFlash.begin();
    if (extFlashOk) {
        Serial.printf("  [PASS] External SPI2 Flash ready: %s (%u MB)\n", 
                      extFlash.getChipName(), (unsigned int)(extFlash.getCapacityBytes() / (1024 * 1024)));
    } else {
        Serial.println(F("  [INFO] External SPI2 Flash not detected or optional."));
    }

    // 5. Initialize Storage (Mount LittleFS on 16MB External Flash if available)
    bool fsOk = storage.begin(&extFlash, true);
    if (fsOk) {
        Serial.printf("  [PASS] %s ready (%u MB). Clips: %u | Free: %u KB\n",
                      storage.isExternalFlash() ? "External 16MB SPI Flash Storage" : "Internal Flash Storage",
                      (unsigned int)(storage.getTotalBytes() / (1024 * 1024)),
                      (unsigned int)storage.getClipCount(),
                      (unsigned int)((storage.getTotalBytes() - storage.getUsedBytes()) / 1024));
    } else {
        Serial.println(F("  [FAIL] Could not mount LittleFS Storage!"));
    }

    // 6. Initialize Audio Recorder
    bool recOk = recorder.begin();
    if (recOk) {
        Serial.println(F("  [PASS] Stream Recorder ready."));
    }

    // 7. Initialize BLE GATT Server
    bool bleOk = ble.begin(BLE_DEVICE_NAME);
    if (bleOk) {
        Serial.printf("  [PASS] BLE advertising active as \"%s\".\n", BLE_DEVICE_NAME);
    }

    // 8. Handle Wake-up Routing & LED Sequence
    if (power.wasWokenByMotion()) {
        ImuMetricData bootImu{};
        bool hasBootImu = imu.readSensorData(bootImu);
        if (hasBootImu) {
            shakeDetector.initializeBaseline(bootImu);
        }
        bool isArmUp = hasBootImu && (bootImu.accelY_g <= IMU_ARM_UP_Y_THRESHOLD_G);

        if (isArmUp) {
            Serial.printf("\n  >>> Woken from Deep Sleep with ARM UP / TILT (Y=%+.2f g)! <<<\n", bootImu.accelY_g);
            Serial.println(F("  >>> Arm-Up / Tilt Wakeup detected -> 3x Dual-LED placeholder!\n"));
            leds.showTiltFeedback();
        } else {
            Serial.printf("\n  >>> Woken from Deep Sleep with ARM DOWN (Y=%+.2f g). <<<\n", 
                          hasBootImu ? bootImu.accelY_g : 0.0f);
            Serial.println(F("  >>> MCU is now AWAKE (IDLE). Shake with arm UP to START recording."));
            Serial.println(F("  >>> (Device will return to Deep Sleep if idle for 15s)\n"));
        }
        leds.setMode(LedMode::IDLE);
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

    // 0.1 Handle Serial Input Commands (r = restart, b = summary banner, w = toggle wifi, s = toggle record)
    while (Serial.available() > 0) {
        char ch = (char)Serial.read();
        if (ch == 'r' || ch == 'R') {
            Serial.println(F("\n[SERIAL] Restart command received -> Rebooting ESP32-C3 now..."));
            Serial.flush();
            delay(200);
            ESP.restart();
        } else if (ch == 'b' || ch == 'B' || ch == '?') {
            power.notifyActivity();
            printSystemSummary();
        } else if (ch == 'w' || ch == 'W') {
            power.notifyActivity();
            if (wifiServer.isActive()) {
                Serial.println(F("\n[SERIAL] Stopping Wi-Fi SoftAP..."));
                wifiServer.stop();
                leds.setMode(ble.isConnected() ? LedMode::BLE_CONNECTED : LedMode::IDLE);
                ble.updateState(STATE_IDLE);
            } else {
                Serial.println(F("\n[SERIAL] Starting Wi-Fi SoftAP..."));
                wifiServer.begin(WIFI_AP_SSID, WIFI_AP_PASS, HTTP_SERVER_PORT);
                leds.setMode(LedMode::WIFI_AP);
                ble.updateState(STATE_WIFI_ACTIVE);
            }
        } else if (ch == 's' || ch == 'S') {
            power.notifyActivity();
            if (recorder.isRecording()) {
                Serial.println(F("\n[SERIAL] Stopping recording..."));
                handleStopAndSave();
            } else {
                Serial.println(F("\n[SERIAL] Starting recording..."));
                startActiveRecording();
            }
        }
    }

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
                break;
            }

            case CMD_SET_QUALITY:
            {
                AudioQuality newQuality = (AudioQuality)ble.getCommandParam();
                if (newQuality <= QUALITY_LOW) {
                    storage.setQuality(newQuality);
                    const char* qName = (newQuality == QUALITY_HIGH) ? "High (16kHz PCM)" :
                                        ((newQuality == QUALITY_LOW) ? "Low (8kHz ADPCM)" : "Medium (16kHz ADPCM)");
                    Serial.printf("\n[BLE CMD] Audio Recording Quality set to %u (%s)\n",
                                  (unsigned int)newQuality, qName);
                    pushTelemetryUpdate(recorder.isRecording() ? STATE_RECORDING : STATE_IDLE);
                }
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

                if (shakeDetector.isArmUp(IMU_ARM_UP_Y_THRESHOLD_G)) {
                    Serial.printf("\n[SHAKE DETECTED] Hand is UP (Pre-Shake GravY=%+.2f g, Intensity: %.2f g) -> STARTING RECORDING...\n",
                                  shakeDetector.getShakeStartGravityY(), intensity);
                    ble.notifyTap(intensity);
                    startActiveRecording();
                } else {
                    Serial.printf("\n[SHAKE DETECTED] Hand is DOWN (Pre-Shake GravY=%+.2f g, Intensity: %.2f g) -> Recording NOT started (Hand must be UP).\n",
                                  shakeDetector.getShakeStartGravityY(), intensity);
                }
            } else {
                // Monitor for Single Tap and Double Tap placeholders
                float shock = 0.0f;
                TapEventType tapEvt = tapDetector.update(imuData, &shock);
                if (tapEvt == TapEventType::SINGLE_TAP) {
                    power.notifyActivity();
                    Serial.printf("\n[IMU] Single-Tap detected! (Shock: %.2f g) -> Showing 3x Green placeholder\n", shock);
                    leds.showSingleTapFeedback();
                } else if (tapEvt == TapEventType::DOUBLE_TAP) {
                    power.notifyActivity();
                    Serial.printf("\n[IMU] Double-Tap detected! (Shock: %.2f g) -> Showing 3x Red placeholder\n", shock);
                    leds.showDoubleTapFeedback();
                }

                // Detect arm-up tilt gesture while awake (e.g. raising wrist to mouth)
                static bool prevArmWasDown = true;
                bool currentArmUp = (shakeDetector.getGravityY() <= IMU_ARM_UP_Y_THRESHOLD_G);
                bool currentArmDown = (shakeDetector.getGravityY() >= 0.20f);
                if (prevArmWasDown && currentArmUp && !shakeDetector.isInCooldown()) {
                    prevArmWasDown = false;
                    power.notifyActivity();
                    Serial.printf("\n[IMU] Arm raised to mouth / Tilt detected! (GravY=%+.2f g) -> Showing 3x Dual-LED placeholder\n",
                                  shakeDetector.getGravityY());
                    leds.showTiltFeedback();
                } else if (currentArmDown) {
                    prevArmWasDown = true;
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
                battery.persistState();
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
            size_t freeKb = (storage.getTotalBytes() > storage.getUsedBytes()) 
                ? ((storage.getTotalBytes() - storage.getUsedBytes()) / 1024) : 0;
            Serial.printf("[STATUS] BLE: %s | State: %s | Flash: %s (%u KB free) | IMU: X=%+.2f Y=%+.2f Z=%+.2f | Clips: %u\n",
                          ble.isConnected() ? "ONLINE " : "STANDBY",
                          recorder.isRecording() ? "RECORDING" : (wifiServer.isActive() ? "WIFI_AP  " : "IDLE     "),
                          storage.isExternalFlash() ? "EXT 16MB" : "INT 1.9MB",
                          (unsigned int)freeKb,
                          imuMetrics.accelX_g, imuMetrics.accelY_g, imuMetrics.accelZ_g,
                          storage.getClipCount());
        }

        static bool lastBleConnected = false;
        bool isBle = ble.isConnected();
        if (isBle != lastBleConnected) {
            lastBleConnected = isBle;
            if (isBle) {
                Serial.printf("[BLE] Client connected! Active Storage: %s (Total: %u KB, Used: %u KB, Clips: %u)\n",
                              storage.isExternalFlash() ? "External 16 MB SPI Flash" : "Internal Flash",
                              (unsigned int)(storage.getTotalBytes() / 1024),
                              (unsigned int)(storage.getUsedBytes() / 1024),
                              (unsigned int)storage.getClipCount());
            }
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

