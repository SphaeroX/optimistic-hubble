#pragma once
#include <Arduino.h>
#include <NimBLEDevice.h>
#include "config.h"
#include "nimble_l2cap_server.h"

struct HotspotUploadConfig {
    char ssid[64];
    char pass[64];
    char serverIp[32];
    uint16_t serverPort;
    uint16_t clipId;
    bool autoDelete;
};

class LedIndicator;

class BleManager : public NimBLEServerCallbacks, public NimBLECharacteristicCallbacks {
public:
    BleManager(LedIndicator* leds = nullptr);

    void setLedIndicator(LedIndicator* leds) { _leds = leds; }
    bool begin(const char* deviceName = BLE_DEVICE_NAME);
    bool stop();
    bool isConnected() const { return _connected; }
    
    void updateState(DeviceState state, uint32_t totalAudioBytes = 0, uint16_t sampleRate = AUDIO_SAMPLE_RATE);
    void sendTelemetry(
        DeviceState state,
        uint32_t totalAudioBytes,
        uint16_t sampleRate,
        uint16_t batteryMilliVolts,
        uint8_t batteryPercent,
        bool isCharging,
        uint32_t freeHeapBytes,
        uint32_t usedStorageBytes,
        uint32_t totalStorageBytes,
        uint16_t totalClips,
        int16_t accelX_mg,
        int16_t accelY_mg,
        int16_t accelZ_mg,
        uint16_t motionMagnitude_mg,
        uint16_t tapCount
    );
    void notifyTap(float shockMagnitude);
    bool transmitAudio(const uint8_t* audioData, size_t totalBytes, uint16_t sampleRate);
    bool streamAudioFileFromStorage(uint16_t clipId, uint32_t startOffset = 0);
    bool streamL2capClip(uint16_t clipId, uint32_t startOffset = 0);

    bool hasPendingCommand() const { return _pendingCmd != CMD_NONE; }
    BleCommand getPendingCommand();
    uint8_t getCommandParam() const { return _cmdParam; }
    uint16_t getCommandClipId() const { return _cmdClipId; }
    uint32_t getCommandOffset() const { return _cmdOffset; }
    HotspotUploadConfig getHotspotUploadConfig() const { return _hotspotConfig; }
    void clearPendingCommand() { _pendingCmd = CMD_NONE; }

    // NimBLE Server Callbacks
    void onConnect(NimBLEServer* pServer) override;
    void onConnect(NimBLEServer* pServer, ble_gap_conn_desc* desc) override;
    void onDisconnect(NimBLEServer* pServer) override;

    // NimBLE Characteristic Callbacks
    void onWrite(NimBLECharacteristic* pCharacteristic, ble_gap_conn_desc* desc) override;

private:
    void handleCharacteristicWrite(NimBLECharacteristic* pCharacteristic);

    NimBLEServer* _pServer;
    NimBLEService* _pService;
    NimBLECharacteristic* _pCharState;
    NimBLECharacteristic* _pCharAudio;
    NimBLECharacteristic* _pCharTap;
    NimBLECharacteristic* _pCharCmd;
    
    LedIndicator* _leds;
    bool _connected;
    DeviceState _currentState;
    volatile BleCommand _pendingCmd;
    uint8_t _cmdParam;
    uint16_t _cmdClipId;
    uint32_t _cmdOffset;
    HotspotUploadConfig _hotspotConfig;
};
