#pragma once
#include <Arduino.h>
#include <WiFi.h>
#include <WebServer.h>
#include <DNSServer.h>
#include "config.h"
#include "storage_manager.h"

class WifiServerManager {
public:
    WifiServerManager(StorageManager& storageRef);

    bool begin(const char* ssid = "XIAO-Audio-Hotspot", const char* pass = "xiaoesp32c3", uint16_t port = 80);
    bool stop();
    void handleClient();
    
    bool isActive() const { return _active; }
    void notifyActivity();
    unsigned long getInactivityMs() const;
    bool isInactive(unsigned long timeoutMs = WIFI_INACTIVITY_TIMEOUT_MS) const;

    IPAddress getIp() const { return WiFi.softAPIP(); }
    const char* getSsid() const { return _ssid; }

    void handleCatchAll();

private:
    StorageManager& _storage;
    WebServer _server;
    DNSServer _dnsServer;
    const char* _ssid;
    const char* _pass;
    bool _active;
    bool _routesConfigured;
    unsigned long _lastRequestTime;

    void setupRoutes();
    void handleRoot();
    void handleApiClips();
    void handleApiDownload();
    void handleApiClear();
    void handleStatus();
    void handleOptions();
    void handleFavicon();
    void handleCaptivePortal();
    void handleNotFound();
    bool isLocalIp(const String& host) const;
};
