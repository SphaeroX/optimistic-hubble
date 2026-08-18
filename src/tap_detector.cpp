#include "tap_detector.h"
#include <math.h>

TapDetector::TapDetector(float thresholdG, unsigned long debounceMs)
    : _thresholdG(thresholdG), _debounceMs(debounceMs), _lastTapTime(0), _lastMagnitude(1.0f), _hasPrevious(false) {}

void TapDetector::reset() {
    _hasPrevious = false;
    _lastMagnitude = 1.0f;
    _lastTapTime = 0;
}

bool TapDetector::update(const ImuMetricData& data, float* shockMagnitudeOut) {
    float currentMag = sqrtf(data.accelX_g * data.accelX_g +
                             data.accelY_g * data.accelY_g +
                             data.accelZ_g * data.accelZ_g);

    if (!_hasPrevious) {
        _lastMagnitude = currentMag;
        _hasPrevious = true;
        if (shockMagnitudeOut) *shockMagnitudeOut = 0.0f;
        return false;
    }

    float delta = fabsf(currentMag - _lastMagnitude);
    _lastMagnitude = currentMag;

    if (shockMagnitudeOut) {
        *shockMagnitudeOut = delta;
    }

    unsigned long now = millis();
    if (delta >= _thresholdG && (now - _lastTapTime >= _debounceMs)) {
        _lastTapTime = now;
        return true;
    }

    return false;
}
