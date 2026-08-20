#pragma once
#include <Arduino.h>
#include <esp_sleep.h>
#include "config.h"
#include "imu_driver.h"

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

    void enterDeepSleep(ImuDriver& imu, float shockThresholdG = IMU_WAKEUP_THRESHOLD_G);

private:
    WakeupSource _wakeupSource;
    unsigned long _lastActivityTime;
    esp_sleep_wakeup_cause_t _rawCause;
    uint64_t _gpioWakeupMask;
};
