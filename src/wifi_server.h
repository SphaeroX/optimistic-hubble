#pragma once
#include <Arduino.h>
#include <WiFi.h>
#include <WebServer.h>
#include "storage_manager.h"

class WifiServerManager {
public:
    WifiServerManager(StorageManager& storageRef);

    bool begin(const char* ssid = "XIAO-Audio-Hotspot", const char* pass = "xiaoesp32c3", uint16_t port = 80);
    void handleClient();
    IPAddress getIp() const { return WiFi.softAPIP(); }
    const char* getSsid() const { return _ssid; }

private:
    StorageManager& _storage;
    WebServer _server;
    const char* _ssid;
    const char* _pass;

    void handleRoot();
    void handleApiClips();
    void handleApiDownload();
    void handleApiClear();
    void handleStatus();
    void handleOptions();
};
