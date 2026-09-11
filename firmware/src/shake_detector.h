#pragma once
#include <Arduino.h>
#include "imu_driver.h"

enum class ShakeEventType : uint8_t {
    NONE = 0,
    SHAKE_DETECTED = 1
};

class ShakeDetector {
public:
    ShakeDetector(float thresholdG = 1.6f,
                  unsigned long windowMs = 650,
                  uint8_t requiredReversals = 2,
                  unsigned long cooldownMs = 1200);

    void setThreshold(float thresholdG) { _thresholdG = thresholdG; }
    void setWindowMs(unsigned long windowMs) { _windowMs = windowMs; }
    void setRequiredReversals(uint8_t count) { _requiredReversals = count; }
    void setCooldownMs(unsigned long cooldownMs) { _cooldownMs = cooldownMs; }

    ShakeEventType update(const ImuMetricData& data, float* shakeIntensityOut = nullptr);
    void reset();
    void initializeBaseline(const ImuMetricData& data);
    bool isInCooldown() const;

    // Orientation checks (arm raised / mouth pose: Y gravity is negative)
    bool isArmUp(float thresholdG = -0.45f) const;
    float getGravityY() const { return _gravY; }
    float getShakeStartGravityY() const { return _shakeStartGravY; }

private:
    float _thresholdG;
    unsigned long _windowMs;
    uint8_t _requiredReversals;
    unsigned long _cooldownMs;

    unsigned long _lastShakeTime;
    unsigned long _firstPeakTime;
    uint8_t _reversalCount;
    int8_t _lastSign;
    uint8_t _dominantAxis;
    float _maxIntensity;

    // Running gravity / baseline estimate (low-pass filter)
    float _gravX, _gravY, _gravZ;
    float _shakeStartGravY;
    bool _initialized;
};
