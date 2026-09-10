#include "power_manager.h"
#include "spi_flash_driver.h"
#include <WiFi.h>
#include <driver/rtc_io.h>

PowerManager::PowerManager()
    : _wakeupSource(WAKEUP_COLD_BOOT),
      _lastActivityTime(0),
      _rawCause(ESP_SLEEP_WAKEUP_UNDEFINED),
      _gpioWakeupMask(0),
      _preventSleep(false) {}

void PowerManager::begin() {
    _lastActivityTime = millis();
    _rawCause = esp_sleep_get_wakeup_cause();

    if (_rawCause == ESP_SLEEP_WAKEUP_GPIO) {
        _gpioWakeupMask = esp_sleep_get_gpio_wakeup_status();
        if (_gpioWakeupMask & (1ULL << PIN_IMU_INT)) {
            _wakeupSource = WAKEUP_IMU_SHOCK;
        } else {
            _wakeupSource = WAKEUP_IMU_SHOCK; // Default RTC GPIO trigger (GPIO 0-5)
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

#if ARDUINO_USB_MODE
#include <HWCDC.h>
#endif

bool PowerManager::isUsbConnected() const {
#if ARDUINO_USB_MODE
    return HWCDC::isPlugged() || (bool)Serial;
#else
    return (bool)Serial;
#endif
}

void PowerManager::enterDeepSleep(ImuDriver& imu, SpiFlashDriver* extFlash, float shockThresholdG) {
    if (_preventSleep) {
        Serial.println(F("[POWER] Deep Sleep blocked by Service/Flash mode lock."));
        return;
    }

    if (isUsbConnected()) {
        Serial.println(F("[POWER] Deep Sleep blocked: USB cable is connected to a host PC!"));
        return;
    }

    Serial.println(F("\n========================================================"));
    Serial.println(F("  ENTERING ULTRA-LOW-POWER DEEP SLEEP (< 10 uA)..."));
    Serial.printf("  Arming IMU for shock detection (> %.2f g on GPIO 5 / INT1)\n", shockThresholdG);
    Serial.println(F("  ESP32-C3 CPU and Radios shutting down."));
    Serial.println(F("========================================================\n"));
    Serial.flush();

    // 1. Turn off Status LEDs (Active-LOW: Write HIGH before setting to INPUT to prevent flash)
    digitalWrite(PIN_STATUS_LED, LED_LEVEL_OFF);
    digitalWrite(PIN_LED_GREEN, LED_LEVEL_OFF);
    pinMode(PIN_STATUS_LED, INPUT);
    pinMode(PIN_LED_GREEN, INPUT);

    // 2. Put external SPI Flash to deep sleep to save current
    if (extFlash != nullptr && extFlash->isConnected()) {
        extFlash->sleep();
    }

    // 3. Configure IMU for ultra-low-power motion detection on INT1
    if (imu.isConnected()) {
        imu.configureLowPowerWakeup(shockThresholdG);
    }

    // 4. Ensure Wi-Fi radio is completely powered off
    WiFi.disconnect(true);
    WiFi.mode(WIFI_OFF);
    delay(20);

    // 5. Configure ESP32-C3 RTC GPIO wakeup on IMU INT pin (GPIO 5, Active High)
    pinMode(PIN_IMU_INT, INPUT_PULLDOWN);
    esp_deep_sleep_enable_gpio_wakeup(1ULL << PIN_IMU_INT, ESP_GPIO_WAKEUP_GPIO_HIGH);

    // 6. Enter Deep Sleep (draws ~5-8 uA)
    Serial.println(F("[POWER] Going to deep sleep now..."));
    Serial.flush();
    esp_deep_sleep_start();
}

