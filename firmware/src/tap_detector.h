#pragma once
#include <Arduino.h>
#include "imu_driver.h"

enum class TapEventType : uint8_t {
    NONE = 0,
    SINGLE_TAP = 1,
    DOUBLE_TAP = 2
};

class TapDetector {
public:
    TapDetector(float thresholdG = 0.55f, 
                unsigned long rawDebounceMs = 120,
                unsigned long minDoubleTapIntervalMs = 120,
                unsigned long maxDoubleTapIntervalMs = 650);

    void setThreshold(float thresholdG) { _thresholdG = thresholdG; }
    void setRawDebounce(unsigned long ms) { _rawDebounceMs = ms; }
    void setDoubleTapWindow(unsigned long minMs, unsigned long maxMs) {
        _minDoubleTapIntervalMs = minMs;
        _maxDoubleTapIntervalMs = maxMs;
    }

    TapEventType update(const ImuMetricData& data, float* shockMagnitudeOut = nullptr);
    TapEventType checkTimeout();

    bool isWaitingForSecondTap() const { return _waitingForSecondTap; }
    unsigned long getLastTapTime() const { return _lastTapTime; }
    void reset();

private:
    float _thresholdG;
    unsigned long _rawDebounceMs;
    unsigned long _minDoubleTapIntervalMs;
    unsigned long _maxDoubleTapIntervalMs;

    unsigned long _lastTapTime;
    unsigned long _firstTapTime;
    float _lastMagnitude;
    float _firstTapShock;
    bool _hasPrevious;
    bool _waitingForSecondTap;
};

