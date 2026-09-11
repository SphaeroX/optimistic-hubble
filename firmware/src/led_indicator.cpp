#include "led_indicator.h"

LedIndicator::LedIndicator(uint8_t redPin, uint8_t greenPin)
    : _redPin(redPin),
      _greenPin(greenPin),
      _redState(false),
      _greenState(false),
      _currentMode(LedMode::IDLE),
      _lastBlinkTime(0),
      _blinkPhase(false),
      _redLastBlinkTime(0),
      _redBlinkPhase(false),
      _greenLastBlinkTime(0),
      _greenBlinkPhase(false) {}

void LedIndicator::begin() {
    pinMode(_redPin, OUTPUT);
    pinMode(_greenPin, OUTPUT);
    writePin(_redPin, false);
    writePin(_greenPin, false);
}

void LedIndicator::writePin(uint8_t pin, bool on) {
    // Active-LOW: LOW turns LED ON, HIGH turns LED OFF
    digitalWrite(pin, on ? LED_LEVEL_ON : LED_LEVEL_OFF);
    if (pin == _redPin) _redState = on;
    if (pin == _greenPin) _greenState = on;
}

void LedIndicator::setRed(bool on) {
    writePin(_redPin, on);
}

void LedIndicator::setGreen(bool on) {
    writePin(_greenPin, on);
}

void LedIndicator::setMode(LedMode mode) {
    _currentMode = mode;
    _blinkPhase = false;
    unsigned long now = millis();
    _lastBlinkTime = now;
    _redLastBlinkTime = now;
    _greenLastBlinkTime = now;

    switch (_currentMode) {
        case LedMode::RECORDING:
        case LedMode::RECORDING_CONNECTED:
            // Recording: Starts with Red ON, Green OFF (200ms ON / 800ms OFF handled in update)
            _redBlinkPhase = true;
            writePin(_redPin, true);
            writePin(_greenPin, false);
            break;
        case LedMode::BLE_CONNECTED:
            // Red OFF, Solid Green
            writePin(_redPin, false);
            writePin(_greenPin, true);
            break;
        case LedMode::SYNCING:
            // Alternating blink starting with Green ON, Red OFF
            _blinkPhase = true;
            writePin(_greenPin, true);
            writePin(_redPin, false);
            break;
        case LedMode::IDLE:
            // Awake / Standby: Starts with Green ON (100ms ON / 900ms OFF handled in update), Red OFF
            _greenBlinkPhase = true;
            writePin(_greenPin, true);
            writePin(_redPin, false);
            break;
        case LedMode::SERVICE_MODE:
            // Permanent Solid Green for Flash / Service Mode, Red OFF
            writePin(_redPin, false);
            writePin(_greenPin, true);
            break;
        case LedMode::WIFI_AP:
        case LedMode::ERROR:
            // Handled dynamically in update()
            break;
    }
}

void LedIndicator::blink(uint8_t pin, uint8_t times, uint16_t delayMs) {
    for (uint8_t i = 0; i < times; ++i) {
        writePin(pin, true);
        delay(delayMs);
        writePin(pin, false);
        delay(delayMs);
    }
}

void LedIndicator::blinkBoth(uint8_t times, uint16_t delayMs) {
    for (uint8_t i = 0; i < times; ++i) {
        writePin(_redPin, true);
        writePin(_greenPin, true);
        delay(delayMs);
        writePin(_redPin, false);
        writePin(_greenPin, false);
        delay(delayMs);
    }
}

void LedIndicator::showSingleTapFeedback() {
    // 3x rapid green blink (60ms ON / 60ms OFF)
    blink(_greenPin, 3, 60);
    setMode(_currentMode);
}

void LedIndicator::showDoubleTapFeedback() {
    // 3x rapid red blink (60ms ON / 60ms OFF)
    blink(_redPin, 3, 60);
    setMode(_currentMode);
}

void LedIndicator::showTiltFeedback() {
    // 3x rapid both LEDs blink (80ms ON / 80ms OFF)
    blinkBoth(3, 80);
    setMode(_currentMode);
}

void LedIndicator::bootSequence() {
    // Alternating boot flash sequence: Red -> Green -> Both
    writePin(_redPin, true);
    delay(70);
    writePin(_redPin, false);
    writePin(_greenPin, true);
    delay(70);
    writePin(_greenPin, false);
    delay(50);
    writePin(_redPin, true);
    writePin(_greenPin, true);
    delay(90);
    writePin(_redPin, false);
    writePin(_greenPin, false);
}

void LedIndicator::errorSequence() {
    // Rapid 4x red blink
    blink(_redPin, 4, 60);
}

void LedIndicator::turnOffAll() {
    writePin(_redPin, false);
    writePin(_greenPin, false);
    // Put into high-impedance mode for deep sleep to avoid leakage
    pinMode(_redPin, INPUT);
    pinMode(_greenPin, INPUT);
}

void LedIndicator::update() {
    unsigned long now = millis();

    if (_currentMode == LedMode::RECORDING || _currentMode == LedMode::RECORDING_CONNECTED) {
        // Red blinks asymmetrically: 200ms ON / 800ms OFF (1 Hz beacon), Green is OFF
        writePin(_greenPin, false);
        unsigned long interval = _redBlinkPhase ? 200 : 800;
        if (now - _redLastBlinkTime >= interval) {
            _redLastBlinkTime = now;
            _redBlinkPhase = !_redBlinkPhase;
            writePin(_redPin, _redBlinkPhase);
        }
    } else if (_currentMode == LedMode::IDLE) {
        // Green blinks asymmetrically: 100ms ON / 900ms OFF (1 Hz alive heartbeat), Red is OFF
        writePin(_redPin, false);
        unsigned long interval = _greenBlinkPhase ? 100 : 900;
        if (now - _greenLastBlinkTime >= interval) {
            _greenLastBlinkTime = now;
            _greenBlinkPhase = !_greenBlinkPhase;
            writePin(_greenPin, _greenBlinkPhase);
        }
    } else if (_currentMode == LedMode::SYNCING) {
        // Alternating blink: Green ON / Red OFF <-> Green OFF / Red ON (150ms phase)
        if (now - _lastBlinkTime >= 150) {
            _lastBlinkTime = now;
            _blinkPhase = !_blinkPhase;
            writePin(_greenPin, _blinkPhase);
            writePin(_redPin, !_blinkPhase);
        }
    } else if (_currentMode == LedMode::WIFI_AP) {
        // Blink Green at 2 Hz (250ms ON / 250ms OFF) to indicate SoftAP active
        if (now - _lastBlinkTime >= 250) {
            _lastBlinkTime = now;
            _blinkPhase = !_blinkPhase;
            writePin(_greenPin, _blinkPhase);
            writePin(_redPin, false);
        }
    } else if (_currentMode == LedMode::ERROR) {
        // Rapid Red blink at 5 Hz (100ms ON / 100ms OFF)
        if (now - _lastBlinkTime >= 100) {
            _lastBlinkTime = now;
            _blinkPhase = !_blinkPhase;
            writePin(_redPin, _blinkPhase);
            writePin(_greenPin, false);
        }
    }
}
