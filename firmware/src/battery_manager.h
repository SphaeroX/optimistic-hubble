#pragma once
#include <Arduino.h>
#include <Preferences.h>
#include "config.h"

// Battery estimation constants for Custom PCB V2 (300 mAh LiPo + TP4054 Charger)
#ifndef BATTERY_CAPACITY_MAH
#define BATTERY_CAPACITY_MAH 300.0f
#endif

#ifndef CHARGE_CURRENT_MA
#define CHARGE_CURRENT_MA 500.0f // TP4054 (R9 = 2k) charges at 500 mA
#endif

// Power draw estimates per operational state in mA
#define CURRENT_IDLE_MA       16.0f // BLE active, CPU @ 160MHz
#define CURRENT_RECORDING_MA  26.0f // CPU + Stereo I2S Microphones + SPI2 Flash write
#define CURRENT_WIFI_MA      125.0f // Wi-Fi SoftAP / HTTP transfer active
#define CURRENT_SLEEP_MA       0.01f // Deep Sleep (< 10 uA)

class BatteryManager {
public:
    BatteryManager();

    // Initialize Preferences & restore previous state of charge
    void begin();

    // Periodic update with current device operational state and USB power presence
    void update(DeviceState state, bool isUsbConnected);

    // Getters for BLE telemetry payload
    uint16_t getVoltageMilliVolts() const { return _voltageMilliVolts; }
    uint8_t getPercent() const { return (uint8_t)(_percent + 0.5f); }
    bool isCharging() const { return _isCharging; }

    // Persist current state of charge to NVS / Flash
    void persistState();

private:
    float _percent;              // 0.0f to 100.0f
    uint16_t _voltageMilliVolts; // 3400 to 4200 mV
    bool _isCharging;
    unsigned long _lastUpdateMs;
    unsigned long _lastPersistMs;
    Preferences _prefs;

    void updateCharge(float deltaHours);
    void updateDischarge(DeviceState state, float deltaHours);
    void calculateVoltageFromPercent();
};
