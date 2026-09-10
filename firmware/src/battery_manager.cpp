#include "battery_manager.h"
#include <esp_attr.h>

// Persist battery state across ESP32-C3 deep sleep in RTC slow memory
RTC_DATA_ATTR static float rtcBatteryPercent = -1.0f;

BatteryManager::BatteryManager()
    : _percent(85.0f),
      _voltageMilliVolts(3950),
      _isCharging(false),
      _lastUpdateMs(0),
      _lastPersistMs(0) {}

void BatteryManager::begin() {
    _lastUpdateMs = millis();
    _lastPersistMs = millis();

    // Check if we have a valid state from previous deep sleep
    if (rtcBatteryPercent >= 0.0f && rtcBatteryPercent <= 100.0f) {
        _percent = rtcBatteryPercent;
        Serial.printf("[BATTERY] Restored state from RTC memory: %.1f%%\n", _percent);
    } else {
        // Otherwise restore from non-volatile Flash storage (Preferences)
        _prefs.begin("pwr_mgr", false);
        _percent = _prefs.getFloat("soc_pct", 85.0f); // 85% default nominal storage charge
        _prefs.end();
        if (_percent < 0.0f || _percent > 100.0f) {
            _percent = 85.0f;
        }
        rtcBatteryPercent = _percent;
        Serial.printf("[BATTERY] Restored state from NVS Flash: %.1f%%\n", _percent);
    }

    calculateVoltageFromPercent();
    Serial.printf("[BATTERY] Initialized: %.1f%% (%u mV)\n", _percent, _voltageMilliVolts);
}

void BatteryManager::update(DeviceState state, bool isUsbConnected) {
    unsigned long now = millis();
    if (_lastUpdateMs == 0) {
        _lastUpdateMs = now;
        return;
    }

    unsigned long elapsedMs = now - _lastUpdateMs;
    if (elapsedMs < 200) {
        return; // Run update at most every 200 ms
    }
    _lastUpdateMs = now;

    _isCharging = isUsbConnected;
    float deltaHours = (float)elapsedMs / 3600000.0f;

    if (_isCharging) {
        updateCharge(deltaHours);
    } else {
        updateDischarge(state, deltaHours);
    }

    calculateVoltageFromPercent();
    rtcBatteryPercent = _percent;

    // Periodically save to Flash every 30 seconds
    if ((now - _lastPersistMs) >= 30000UL) {
        persistState();
        _lastPersistMs = now;
    }
}

void BatteryManager::updateCharge(float deltaHours) {
    if (_percent >= 100.0f) {
        _percent = 100.0f;
        return;
    }

    // TP4054 500mA charge profile:
    // CC (Constant Current) mode up to ~85%, then CV taper
    float currentMa = (_percent < 85.0f) ? CHARGE_CURRENT_MA : (CHARGE_CURRENT_MA * 0.35f);
    float deltaPercent = (currentMa / BATTERY_CAPACITY_MAH) * 100.0f * deltaHours;

    _percent += deltaPercent;
    if (_percent > 100.0f) {
        _percent = 100.0f;
    }
}

void BatteryManager::updateDischarge(DeviceState state, float deltaHours) {
    if (_percent <= 0.0f) {
        _percent = 0.0f;
        return;
    }

    float currentMa = CURRENT_IDLE_MA;
    switch (state) {
        case STATE_RECORDING:
            currentMa = CURRENT_RECORDING_MA;
            break;
        case STATE_WIFI_ACTIVE:
        case STATE_TRANSFERRING:
            currentMa = CURRENT_WIFI_MA;
            break;
        case STATE_SLEEPING:
            currentMa = CURRENT_SLEEP_MA;
            break;
        case STATE_IDLE:
        case STATE_DONE:
        default:
            currentMa = CURRENT_IDLE_MA;
            break;
    }

    float deltaPercent = (currentMa / BATTERY_CAPACITY_MAH) * 100.0f * deltaHours;
    _percent -= deltaPercent;
    if (_percent < 0.0f) {
        _percent = 0.0f;
    }
}

void BatteryManager::calculateVoltageFromPercent() {
    // Piecewise linear interpolation of 1S 3.7V LiPo discharge curve
    struct Point { float pct; uint16_t mv; };
    static const Point curve[] = {
        { 100.0f, 4200 },
        {  90.0f, 4100 },
        {  80.0f, 3980 },
        {  70.0f, 3900 },
        {  60.0f, 3820 },
        {  50.0f, 3780 },
        {  40.0f, 3740 },
        {  30.0f, 3700 },
        {  20.0f, 3650 },
        {  10.0f, 3550 },
        {   0.0f, 3400 }
    };
    static const int numPoints = sizeof(curve) / sizeof(curve[0]);

    if (_percent >= 100.0f) {
        _voltageMilliVolts = 4200;
        return;
    }
    if (_percent <= 0.0f) {
        _voltageMilliVolts = 3400;
        return;
    }

    for (int i = 0; i < numPoints - 1; ++i) {
        if (_percent <= curve[i].pct && _percent >= curve[i + 1].pct) {
            float rangePct = curve[i].pct - curve[i + 1].pct;
            float factor = (_percent - curve[i + 1].pct) / rangePct;
            _voltageMilliVolts = curve[i + 1].mv + (uint16_t)(factor * (curve[i].mv - curve[i + 1].mv));
            return;
        }
    }

    _voltageMilliVolts = 3700;
}

void BatteryManager::persistState() {
    _prefs.begin("pwr_mgr", false);
    _prefs.putFloat("soc_pct", _percent);
    _prefs.end();
}
