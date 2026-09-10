#pragma once
#include <Arduino.h>
#include "config.h"

enum class LedMode : uint8_t {
    IDLE = 0,
    RECORDING,
    RECORDING_CONNECTED,
    WIFI_AP,
    BLE_CONNECTED,
    SYNCING,
    ERROR,
    SERVICE_MODE
};

class LedIndicator {
public:
    LedIndicator(uint8_t redPin = PIN_STATUS_LED, uint8_t greenPin = PIN_LED_GREEN);

    void begin();
    void setRed(bool on);
    void setGreen(bool on);
    void setMode(LedMode mode);

    void blink(uint8_t pin, uint8_t times, uint16_t delayMs);
    void bootSequence();
    void errorSequence();
    void turnOffAll();

    // Non-blocking tick for periodic LED patterns (call in loop)
    void update();

    bool isRedOn() const { return _redState; }
    bool isGreenOn() const { return _greenState; }
    LedMode getMode() const { return _currentMode; }

private:
    uint8_t _redPin;
    uint8_t _greenPin;
    bool _redState;
    bool _greenState;
    LedMode _currentMode;
    unsigned long _lastBlinkTime;
    bool _blinkPhase;

    void writePin(uint8_t pin, bool on);
};
