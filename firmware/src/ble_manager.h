#pragma once
#include <Arduino.h>
#include <NimBLEDevice.h>
#include "config.h"

class BleManager : public NimBLEServerCallbacks, public NimBLECharacteristicCallbacks {
public:
    BleManager();

    bool begin(const char* deviceName = BLE_DEVICE_NAME);
    bool stop();
    bool isConnected() const { return _connected; }
    
    void updateState(DeviceState state, uint32_t totalAudioBytes = 0, uint16_t sampleRate = AUDIO_SAMPLE_RATE);
    void notifyTap(float shockMagnitude);
    bool transmitAudio(const uint8_t* audioData, size_t totalBytes, uint16_t sampleRate);

    bool hasPendingCommand() const { return _pendingCmd != CMD_NONE; }
    BleCommand getPendingCommand();
    void clearPendingCommand() { _pendingCmd = CMD_NONE; }

    // NimBLE Server Callbacks
    void onConnect(NimBLEServer* pServer) override;
    void onDisconnect(NimBLEServer* pServer) override;

    // NimBLE Characteristic Callbacks
    void onWrite(NimBLECharacteristic* pCharacteristic) override;

private:
    NimBLEServer* _pServer;
    NimBLEService* _pService;
    NimBLECharacteristic* _pCharState;
    NimBLECharacteristic* _pCharAudio;
    NimBLECharacteristic* _pCharTap;
    NimBLECharacteristic* _pCharCmd;
    
    bool _connected;
    DeviceState _currentState;
    volatile BleCommand _pendingCmd;
};
