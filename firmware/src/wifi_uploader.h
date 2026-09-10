#pragma once
#include <Arduino.h>
#include <WiFi.h>
#include "config.h"
#include "storage_manager.h"
#include "ble_manager.h"

class LedIndicator;

class WifiUploader {
public:
    WifiUploader(StorageManager& storageRef, LedIndicator* leds = nullptr);

    void setLedIndicator(LedIndicator* leds) { _leds = leds; }
    bool uploadClips(const HotspotUploadConfig& config);
    bool isConnected() const { return WiFi.status() == WL_CONNECTED; }
    void abortUpload() { _aborted = true; }

private:
    StorageManager& _storage;
    LedIndicator* _leds;
    bool _aborted;

    bool connectToHotspot(const char* ssid, const char* pass, uint32_t timeoutMs = 15000);
    bool uploadSingleClip(const char* host, uint16_t port, const ClipInfo& clip, bool autoDelete);
    void sendCompleteSignal(const char* host, uint16_t port);
};
