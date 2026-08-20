#pragma once
#include <Arduino.h>
#include "imu_driver.h"

class TapDetector {
public:
    TapDetector(float thresholdG = 1.3f, unsigned long debounceMs = 500);

    void setThreshold(float thresholdG) { _thresholdG = thresholdG; }
    void setDebounce(unsigned long debounceMs) { _debounceMs = debounceMs; }

    bool update(const ImuMetricData& data, float* shockMagnitudeOut = nullptr);
    void reset();

private:
    float _thresholdG;
    unsigned long _debounceMs;
    unsigned long _lastTapTime;
    float _lastMagnitude;
    bool _hasPrevious;
};
