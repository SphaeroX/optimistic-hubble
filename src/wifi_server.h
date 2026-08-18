#pragma once
#include <Arduino.h>
#include <WiFi.h>
#include <WebServer.h>
#include "audio_recorder.h"

class WifiServerManager {
public:
    WifiServerManager(AudioRecorder& recorderRef);

    bool begin(const char* ssid = WIFI_AP_SSID, const char* pass = WIFI_AP_PASS, uint16_t port = HTTP_SERVER_PORT);
    void handleClient();
    IPAddress getIp() const { return WiFi.softAPIP(); }
    const char* getSsid() const { return _ssid; }

private:
    AudioRecorder& _recorder;
    WebServer _server;
    const char* _ssid;
    const char* _pass;

    void handleRoot();
    void handleAudioWav();
    void handleStatus();
    void handleOptions();
};
