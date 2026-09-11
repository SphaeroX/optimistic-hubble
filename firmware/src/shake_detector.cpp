#include "shake_detector.h"
#include <math.h>

ShakeDetector::ShakeDetector(float thresholdG, unsigned long windowMs,
                             uint8_t requiredReversals, unsigned long cooldownMs)
    : _thresholdG(thresholdG),
      _windowMs(windowMs),
      _requiredReversals(requiredReversals),
      _cooldownMs(cooldownMs),
      _lastShakeTime(0),
      _firstPeakTime(0),
      _reversalCount(0),
      _lastSign(0),
      _dominantAxis(0),
      _maxIntensity(0.0f),
      _gravX(0.0f),
      _gravY(0.0f),
      _gravZ(1.0f),
      _shakeStartGravY(0.0f),
      _initialized(false) {}

void ShakeDetector::reset() {
    _reversalCount = 0;
    _lastSign = 0;
    _firstPeakTime = 0;
    _maxIntensity = 0.0f;
    _dominantAxis = 0;
    _shakeStartGravY = 0.0f;
    _initialized = false;
}

void ShakeDetector::initializeBaseline(const ImuMetricData& data) {
    _gravX = data.accelX_g;
    _gravY = data.accelY_g;
    _gravZ = data.accelZ_g;
    _shakeStartGravY = _gravY;
    _initialized = true;
}

bool ShakeDetector::isInCooldown() const {
    return (millis() - _lastShakeTime < _cooldownMs);
}

bool ShakeDetector::isArmUp(float thresholdG) const {
    // When arm is raised to mouth (hand UP), Y-axis gravity points down (-1g Earth gravity).
    // When arm hangs at side (hand DOWN), Y-axis gravity points up (+1g Earth gravity).
    // Only return true when the frozen pre-shake orientation was strictly arm UP.
    return (_shakeStartGravY <= thresholdG);
}

ShakeEventType ShakeDetector::update(const ImuMetricData& data, float* shakeIntensityOut) {
    unsigned long now = millis();

    // 1. Initialize or update low-pass filtered gravity baseline
    if (!_initialized) {
        _gravX = data.accelX_g;
        _gravY = data.accelY_g;
        _gravZ = data.accelZ_g;
        _shakeStartGravY = _gravY;
        _initialized = true;
        if (shakeIntensityOut) *shakeIntensityOut = 0.0f;
        return ShakeEventType::NONE;
    }

    // Only update gravity baseline when near 1g steady state (prevents shake contamination)
    float totalMag = sqrtf(data.accelX_g * data.accelX_g +
                           data.accelY_g * data.accelY_g +
                           data.accelZ_g * data.accelZ_g);
    if (totalMag >= 0.70f && totalMag <= 1.30f) {
        const float alpha = 0.05f;
        _gravX = (1.0f - alpha) * _gravX + alpha * data.accelX_g;
        _gravY = (1.0f - alpha) * _gravY + alpha * data.accelY_g;
        _gravZ = (1.0f - alpha) * _gravZ + alpha * data.accelZ_g;
    }

    // 2. Dynamic linear acceleration (removing DC gravity)
    float dynX = data.accelX_g - _gravX;
    float dynY = data.accelY_g - _gravY;
    float dynZ = data.accelZ_g - _gravZ;

    float dynMag = sqrtf(dynX * dynX + dynY * dynY + dynZ * dynZ);
    if (shakeIntensityOut) {
        *shakeIntensityOut = dynMag;
    }

    // 3. Check refractory cooldown
    if (now - _lastShakeTime < _cooldownMs) {
        _reversalCount = 0;
        _lastSign = 0;
        return ShakeEventType::NONE;
    }

    // 4. Check if sequence window timed out
    if (_reversalCount > 0 && (now - _firstPeakTime > _windowMs)) {
        _reversalCount = 0;
        _lastSign = 0;
    }

    // 5. Finite State Machine for Shake Pattern
    if (dynMag >= _thresholdG) {
        // Find dominant deflection axis
        float absX = fabsf(dynX);
        float absY = fabsf(dynY);
        float absZ = fabsf(dynZ);

        uint8_t axis = 0;
        float maxVal = dynX;
        if (absY > absX && absY >= absZ) {
            axis = 1;
            maxVal = dynY;
        } else if (absZ > absX && absZ > absY) {
            axis = 2;
            maxVal = dynZ;
        }

        int8_t currentSign = (maxVal >= 0.0f) ? 1 : -1;

        if (_reversalCount == 0) {
            // First peak of shake gesture: freeze orientation before shake!
            _shakeStartGravY = _gravY;
            _firstPeakTime = now;
            _reversalCount = 1;
            _lastSign = currentSign;
            _dominantAxis = axis;
            _maxIntensity = dynMag;
        } else {
            // Check for directional reversal
            if (currentSign != _lastSign) {
                _reversalCount++;
                _lastSign = currentSign;
                if (dynMag > _maxIntensity) _maxIntensity = dynMag;

                if (_reversalCount >= _requiredReversals) {
                    // Shake pattern successfully verified!
                    _lastShakeTime = now;
                    _reversalCount = 0;
                    _lastSign = 0;
                    if (shakeIntensityOut) {
                        *shakeIntensityOut = _maxIntensity;
                    }
                    return ShakeEventType::SHAKE_DETECTED;
                }
            }
        }
    }

    return ShakeEventType::NONE;
}
