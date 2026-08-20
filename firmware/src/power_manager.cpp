#include "power_manager.h"
#include <WiFi.h>
#include <driver/rtc_io.h>

PowerManager::PowerManager()
    : _wakeupSource(WAKEUP_COLD_BOOT),
      _lastActivityTime(0),
      _rawCause(ESP_SLEEP_WAKEUP_UNDEFINED),
      _gpioWakeupMask(0) {}

void PowerManager::begin() {
    _lastActivityTime = millis();
    _rawCause = esp_sleep_get_wakeup_cause();

    if (_rawCause == ESP_SLEEP_WAKEUP_GPIO) {
        _gpioWakeupMask = esp_sleep_get_gpio_wakeup_status();
        if (_gpioWakeupMask & (1ULL << PIN_IMU_INT)) {
            _wakeupSource = WAKEUP_IMU_SHOCK;
        } else if (_gpioWakeupMask & (1ULL << PIN_BOOT_BTN)) {
            _wakeupSource = WAKEUP_BOOT_BUTTON;
        } else {
            _wakeupSource = WAKEUP_IMU_SHOCK; // Default GPIO trigger
        }
    } else if (_rawCause == ESP_SLEEP_WAKEUP_TIMER) {
        _wakeupSource = WAKEUP_TIMER;
    } else {
        _wakeupSource = WAKEUP_COLD_BOOT;
    }

    Serial.printf("[POWER] Boot Reason: %s (Raw Cause: %d, GPIO Mask: 0x%llX)\n",
                  getWakeupReasonString(), (int)_rawCause, (unsigned long long)_gpioWakeupMask);
}

const char* PowerManager::getWakeupReasonString() const {
    switch (_wakeupSource) {
        case WAKEUP_IMU_SHOCK:   return "IMU Shock / Tap Wakeup";
        case WAKEUP_BOOT_BUTTON: return "Boot Button Wakeup";
        case WAKEUP_TIMER:       return "Timer Periodic Wakeup";
        case WAKEUP_COLD_BOOT:   return "Cold Power-On Boot";
        default:                 return "Unknown Reset";
    }
}

void PowerManager::notifyActivity() {
    _lastActivityTime = millis();
}

unsigned long PowerManager::getInactivityMs() const {
    return millis() - _lastActivityTime;
}

bool PowerManager::isIdleTimeoutExpired(unsigned long timeoutMs) const {
    return (millis() - _lastActivityTime) >= timeoutMs;
}

void PowerManager::enterDeepSleep(ImuDriver& imu, float shockThresholdG) {
    Serial.println(F("\n========================================================"));
    Serial.println(F("  ENTERING ULTRA-LOW-POWER DEEP SLEEP (< 10 uA)..."));
    Serial.printf("  Arming IMU for shock detection (> %.2f g on Pin D3/GPIO 5)\n", shockThresholdG);
    Serial.println(F("  ESP32-C3 CPU and Radios shutting down."));
    Serial.println(F("========================================================\n"));
    Serial.flush();

    // 1. Turn off Status LED
    digitalWrite(PIN_STATUS_LED, LOW);
    pinMode(PIN_STATUS_LED, INPUT);

    // 2. Configure IMU for ultra-low-power motion detection on INT1
    if (imu.isConnected()) {
        imu.configureLowPowerWakeup(shockThresholdG);
    }

    // 3. Ensure Wi-Fi radio is completely powered off
    WiFi.disconnect(true);
    WiFi.mode(WIFI_OFF);
    delay(20);

    // 4. Configure ESP32-C3 RTC GPIO wakeup on IMU INT pin (XIAO D3 = GPIO 5, Active High)
    pinMode(PIN_IMU_INT, INPUT_PULLDOWN);
    esp_deep_sleep_enable_gpio_wakeup(1ULL << PIN_IMU_INT, ESP_GPIO_WAKEUP_GPIO_HIGH);

    // 5. Enter Deep Sleep (draws ~5-8 uA)
    Serial.println(F("[POWER] Going to deep sleep now..."));
    Serial.flush();
    esp_deep_sleep_start();
}
