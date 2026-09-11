#include "wifi_uploader.h"
#include "led_indicator.h"
#include <WiFiClient.h>

WifiUploader::WifiUploader(StorageManager& storageRef, LedIndicator* leds)
    : _storage(storageRef), _leds(leds), _aborted(false) {}

bool WifiUploader::connectToHotspot(const char* ssid, const char* pass, uint32_t timeoutMs) {
    if (ssid == nullptr || strlen(ssid) == 0) {
        Serial.println(F("[WIFI UPLOADER] Invalid SSID provided"));
        return false;
    }

    Serial.printf("[WIFI UPLOADER] Connecting to Phone Hotspot: \"%s\"...\n", ssid);

    WiFi.disconnect(true);
    delay(50);
    WiFi.mode(WIFI_STA);
    WiFi.setSleep(true); // Mandatory for ESP32 Wi-Fi + BLE Coexistence
    WiFi.setTxPower(WIFI_POWER_19_5dBm);

    if (pass != nullptr && strlen(pass) > 0) {
        WiFi.begin(ssid, pass);
    } else {
        WiFi.begin(ssid);
    }

    unsigned long start = millis();
    while (WiFi.status() != WL_CONNECTED && (millis() - start < timeoutMs)) {
        if (_leds) _leds->update();
        delay(150);
        Serial.print('.');
    }
    Serial.println();

    if (WiFi.status() == WL_CONNECTED) {
        Serial.printf("[WIFI UPLOADER] Connected! IP: %s | Gateway/Host: %s | RSSI: %d dBm\n",
                      WiFi.localIP().toString().c_str(),
                      WiFi.gatewayIP().toString().c_str(),
                      WiFi.RSSI());
        return true;
    } else {
        Serial.printf("[WIFI UPLOADER] Connection timeout or failed (Status: %d)\n", (int)WiFi.status());
        return false;
    }
}

bool WifiUploader::uploadSingleClip(const char* host, uint16_t port, const ClipInfo& clip, bool autoDelete) {
    if (_aborted) return false;

    File file = _storage.getClipFile(clip.id);
    if (!file || file.isDirectory()) {
        Serial.printf("[WIFI UPLOADER] Failed to open Clip #%u\n", clip.id);
        return false;
    }

    size_t fileSize = file.size();
    if (fileSize == 0) {
        file.close();
        Serial.printf("[WIFI UPLOADER] Clip #%u is empty (0 bytes)\n", clip.id);
        return false;
    }

    Serial.printf("[WIFI UPLOADER] Uploading Clip #%u (%u bytes, %.1fs) to http://%s:%u/api/upload...\n",
                  clip.id, (unsigned int)fileSize, clip.duration, host, port);

    WiFiClient client;
    if (!client.connect(host, port, 6000)) {
        Serial.printf("[WIFI UPLOADER] Failed to connect to server at %s:%u\n", host, port);
        file.close();
        return false;
    }

    // Send HTTP POST Request Headers with relative ageSec for timestamp reconstruction
    uint32_t ageSec = _storage.getClipAgeSeconds(clip.id);
    char path[160];
    snprintf(path, sizeof(path), "/api/upload?id=%u&size=%u&duration=%.2f&sampleRate=%u&ageSec=%u",
             clip.id, (unsigned int)fileSize, clip.duration, clip.sampleRate, (unsigned int)ageSec);

    client.printf("POST %s HTTP/1.1\r\n", path);
    client.printf("Host: %s:%u\r\n", host, port);
    client.printf("Content-Type: audio/wav\r\n");
    client.printf("Content-Length: %u\r\n", (unsigned int)fileSize);
    client.printf("Connection: close\r\n\r\n");

    // Double-buffered stream chunk (2 x TCP MSS = 2920 bytes) for > 2.0 MB/s throughput
    uint8_t streamBuffer[2920];
    size_t bytesRemaining = fileSize;
    unsigned long uploadStart = millis();

    while (client.connected() && bytesRemaining > 0 && !_aborted) {
        if (_leds) _leds->update();
        size_t bytesToRead = (bytesRemaining > sizeof(streamBuffer)) ? sizeof(streamBuffer) : bytesRemaining;
        size_t bytesRead = file.read(streamBuffer, bytesToRead);
        if (bytesRead > 0) {
            size_t written = client.write(streamBuffer, bytesRead);
            bytesRemaining -= written;
        } else {
            break;
        }
    }

    file.close();

    if (_aborted) {
        client.stop();
        Serial.println(F("[WIFI UPLOADER] Upload aborted by user"));
        return false;
    }

    // Read HTTP Response
    unsigned long respStart = millis();
    while (client.connected() && !client.available() && (millis() - respStart < 6000)) {
        delay(10);
    }

    String statusLine = client.readStringUntil('\n');
    bool uploadSuccess = (statusLine.indexOf("200") != -1);
    client.stop();

    unsigned long elapsed = millis() - uploadStart;
    float speedMb = (elapsed > 0) ? ((float)fileSize / (1024.0f * 1024.0f)) / ((float)elapsed / 1000.0f) : 0.0f;

    if (uploadSuccess) {
        Serial.printf("[WIFI UPLOADER] Clip #%u uploaded successfully! Speed: %.2f MB/s (%lu ms)\n",
                      clip.id, speedMb, elapsed);
        if (autoDelete) {
            _storage.deleteClip(clip.id);
            _storage.refresh();
            Serial.printf("[WIFI UPLOADER] Clip #%u deleted from Flash upon autoDelete request\n", clip.id);
        }
        return true;
    } else {
        Serial.printf("[WIFI UPLOADER] Server response error for Clip #%u: %s\n", clip.id, statusLine.c_str());
        return false;
    }
}

void WifiUploader::sendCompleteSignal(const char* host, uint16_t port) {
    WiFiClient client;
    if (client.connect(host, port, 4000)) {
        client.printf("POST /api/complete HTTP/1.1\r\nHost: %s:%u\r\nContent-Length: 0\r\nConnection: close\r\n\r\n", host, port);
        unsigned long start = millis();
        while (client.connected() && !client.available() && (millis() - start < 3000)) {
            delay(10);
        }
        client.stop();
        Serial.println(F("[WIFI UPLOADER] Completion signal transmitted to phone."));
    }
}

bool WifiUploader::uploadClips(const HotspotUploadConfig& config) {
    _aborted = false;
    if (_leds) _leds->setMode(LedMode::SYNCING);

    bool connected = connectToHotspot(config.ssid, config.pass, 15000);
    if (!connected) {
        WiFi.disconnect(true);
        WiFi.mode(WIFI_OFF);
        return false;
    }

    // Resolve target server IP: Phone hotspot gateway is the primary target
    String serverHostStr;
    IPAddress gateway = WiFi.gatewayIP();
    if (gateway != INADDR_NONE && gateway != IPAddress(0, 0, 0, 0)) {
        serverHostStr = gateway.toString();
        Serial.printf("[WIFI UPLOADER] Using Phone Hotspot Gateway as target: %s\n", serverHostStr.c_str());
    } else if (strlen(config.serverIp) > 0) {
        serverHostStr = config.serverIp;
    } else {
        serverHostStr = "192.168.43.1";
    }

    const char* targetHost = serverHostStr.c_str();
    uint16_t targetPort = (config.serverPort > 0) ? config.serverPort : 8080;

    std::vector<ClipInfo> allClips = _storage.listClips();
    std::vector<ClipInfo> targetClips;

    if (config.clipId > 0) {
        for (const auto& c : allClips) {
            if (c.id == config.clipId) {
                targetClips.push_back(c);
                break;
            }
        }
    } else {
        targetClips = allClips;
    }

    if (targetClips.empty()) {
        Serial.println(F("[WIFI UPLOADER] No clips to upload."));
        sendCompleteSignal(targetHost, targetPort);
        WiFi.disconnect(true);
        WiFi.mode(WIFI_OFF);
        return true;
    }

    Serial.printf("[WIFI UPLOADER] Starting upload batch of %u clips...\n", (unsigned int)targetClips.size());

    bool allSuccess = true;
    for (const auto& clip : targetClips) {
        if (_aborted) {
            allSuccess = false;
            break;
        }

        bool ok = uploadSingleClip(targetHost, targetPort, clip, config.autoDelete);
        if (!ok) {
            allSuccess = false;
        }
        delay(20);
    }

    sendCompleteSignal(targetHost, targetPort);

    // Turn off Wi-Fi to preserve battery
    WiFi.disconnect(true);
    delay(20);
    WiFi.mode(WIFI_OFF);
    Serial.println(F("[WIFI UPLOADER] Wi-Fi turned OFF to save battery (~150 mA)."));

    return allSuccess;
}
