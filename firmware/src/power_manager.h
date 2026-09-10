#pragma once
#include <Arduino.h>
#include <esp_sleep.h>
#include "config.h"
#include "imu_driver.h"

class SpiFlashDriver;

enum WakeupSource {
    WAKEUP_COLD_BOOT = 0,
    WAKEUP_IMU_SHOCK = 1,
    WAKEUP_BOOT_BUTTON = 2,
    WAKEUP_TIMER = 3,
    WAKEUP_OTHER = 4
};

class PowerManager {
public:
    PowerManager();

    void begin();

    WakeupSource getWakeupSource() const { return _wakeupSource; }
    const char* getWakeupReasonString() const;
    bool wasWokenByMotion() const { return _wakeupSource == WAKEUP_IMU_SHOCK; }
    bool wasWokenByButton() const { return _wakeupSource == WAKEUP_BOOT_BUTTON; }
    bool isColdBoot() const { return _wakeupSource == WAKEUP_COLD_BOOT; }

    void notifyActivity();
    unsigned long getInactivityMs() const;
    bool isIdleTimeoutExpired(unsigned long timeoutMs = INACTIVITY_SLEEP_TIMEOUT_MS) const;

    // Sleep prevention & USB connection check
    bool isUsbConnected() const;
    void setPreventSleep(bool prevent) { _preventSleep = prevent; }
    bool isSleepPrevented() const { return _preventSleep; }

    void enterDeepSleep(ImuDriver& imu, SpiFlashDriver* extFlash = nullptr, float shockThresholdG = IMU_WAKEUP_THRESHOLD_G);

private:
    WakeupSource _wakeupSource;
    unsigned long _lastActivityTime;
    esp_sleep_wakeup_cause_t _rawCause;
    uint64_t _gpioWakeupMask;
    bool _preventSleep;
};

