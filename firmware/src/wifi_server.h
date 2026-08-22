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

    bool begin(const char* ssid = WIFI_AP_SSID, const char* pass = WIFI_AP_PASS, uint16_t port = HTTP_SERVER_PORT);
    bool stop();
    void handleClient();
    void checkWatchdog();
    
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
    unsigned long _softApStartTime;

    void setupRoutes();
    void handleRoot();
    void handleApiClips();
    void handleApiDownload();
    void handleApiDelete();
    void handleApiClear();
    void handleHandshake();
    void handleStatus();
    void handleOptions();
    void handleFavicon();
    void handleCaptivePortal();
    void handleNotFound();
    bool isLocalIp(const String& host) const;
};
