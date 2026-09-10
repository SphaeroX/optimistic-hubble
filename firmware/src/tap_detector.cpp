#include "tap_detector.h"
#include <math.h>

TapDetector::TapDetector(float thresholdG, unsigned long rawDebounceMs,
                         unsigned long minDoubleTapIntervalMs, unsigned long maxDoubleTapIntervalMs)
    : _thresholdG(thresholdG),
      _rawDebounceMs(rawDebounceMs),
      _minDoubleTapIntervalMs(minDoubleTapIntervalMs),
      _maxDoubleTapIntervalMs(maxDoubleTapIntervalMs),
      _lastTapTime(0),
      _firstTapTime(0),
      _lastMagnitude(1.0f),
      _firstTapShock(0.0f),
      _hasPrevious(false),
      _waitingForSecondTap(false) {}

void TapDetector::reset() {
    _hasPrevious = false;
    _lastMagnitude = 1.0f;
    _lastTapTime = 0;
    _firstTapTime = 0;
    _firstTapShock = 0.0f;
    _waitingForSecondTap = false;
}

TapEventType TapDetector::checkTimeout() {
    if (_waitingForSecondTap) {
        unsigned long now = millis();
        if (now - _firstTapTime > _maxDoubleTapIntervalMs) {
            _waitingForSecondTap = false;
            return TapEventType::SINGLE_TAP;
        }
    }
    return TapEventType::NONE;
}

TapEventType TapDetector::update(const ImuMetricData& data, float* shockMagnitudeOut) {
    float currentMag = sqrtf(data.accelX_g * data.accelX_g +
                             data.accelY_g * data.accelY_g +
                             data.accelZ_g * data.accelZ_g);

    if (!_hasPrevious) {
        _lastMagnitude = currentMag;
        _hasPrevious = true;
        if (shockMagnitudeOut) *shockMagnitudeOut = 0.0f;
        return TapEventType::NONE;
    }

    float delta = fabsf(currentMag - _lastMagnitude);
    _lastMagnitude = currentMag;

    if (shockMagnitudeOut) {
        *shockMagnitudeOut = delta;
    }

    unsigned long now = millis();

    // Check if timeout on pending first tap has expired
    TapEventType timeoutEvent = TapEventType::NONE;
    if (_waitingForSecondTap && (now - _firstTapTime > _maxDoubleTapIntervalMs)) {
        _waitingForSecondTap = false;
        timeoutEvent = TapEventType::SINGLE_TAP;
    }

    // Check for a raw tap strike exceeding threshold and debounce
    if (delta >= _thresholdG && (now - _lastTapTime >= _rawDebounceMs)) {
        _lastTapTime = now;

        if (!_waitingForSecondTap) {
            // First tap registered: start window for second tap
            _waitingForSecondTap = true;
            _firstTapTime = now;
            _firstTapShock = delta;
            return TapEventType::NONE;
        } else {
            // Second tap candidate
            unsigned long interval = now - _firstTapTime;
            if (interval >= _minDoubleTapIntervalMs && interval <= _maxDoubleTapIntervalMs) {
                // Valid double tap registered!
                _waitingForSecondTap = false;
                if (shockMagnitudeOut) {
                    *shockMagnitudeOut = fmaxf(_firstTapShock, delta);
                }
                return TapEventType::DOUBLE_TAP;
            } else if (interval > _maxDoubleTapIntervalMs) {
                // Interval too long: this becomes the new first tap
                _firstTapTime = now;
                _firstTapShock = delta;
                return timeoutEvent;
            }
        }
    }

    return timeoutEvent;
}

