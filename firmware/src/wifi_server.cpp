#include "wifi_server.h"
#include "config.h"

// Mandatory HTTP Header registration for RFC 7233 Range Support
static const char* HTTP_COLLECT_HEADERS[] = {"Range", "Accept-Ranges", "If-Range"};
static const size_t HTTP_COLLECT_HEADERS_COUNT = sizeof(HTTP_COLLECT_HEADERS) / sizeof(char*);

// Custom RequestHandler to catch unhandled routes and prevent log noise
class CatchAllRequestHandler : public RequestHandler {
public:
    CatchAllRequestHandler(WifiServerManager& manager) : _manager(manager) {}

    bool canHandle(HTTPMethod method, String uri) override {
        (void)method;
        (void)uri;
        return true;
    }

    bool handle(WebServer& server, HTTPMethod requestMethod, String requestUri) override {
        (void)server;
        (void)requestMethod;
        (void)requestUri;
        _manager.handleCatchAll();
        return true;
    }

private:
    WifiServerManager& _manager;
};

WifiServerManager::WifiServerManager(StorageManager& storageRef)
    : _storage(storageRef), _server(HTTP_SERVER_PORT), _ssid(WIFI_AP_SSID), _pass(WIFI_AP_PASS),
      _active(false), _routesConfigured(false), _lastRequestTime(0), _softApStartTime(0) {}

void WifiServerManager::setupRoutes() {
    if (_routesConfigured) return;

    _server.enableCORS(true);
    _server.collectHeaders(HTTP_COLLECT_HEADERS, HTTP_COLLECT_HEADERS_COUNT);

    // Register WebServer API & Dashboard Routes
    _server.on("/", HTTP_GET, [this]() { notifyActivity(); handleRoot(); });
    _server.on("/api/clips", HTTP_GET, [this]() { notifyActivity(); handleApiClips(); });
    _server.on("/api/download", HTTP_GET, [this]() { notifyActivity(); handleApiDownload(); });
    _server.on("/api/delete", HTTP_POST, [this]() { notifyActivity(); handleApiDelete(); });
    _server.on("/api/delete", HTTP_GET, [this]() { notifyActivity(); handleApiDelete(); });
    _server.on("/api/complete", HTTP_POST, [this]() { notifyActivity(); handleApiDelete(); });
    _server.on("/api/clear", HTTP_GET, [this]() { notifyActivity(); handleApiClear(); });
    _server.on("/api/clear", HTTP_POST, [this]() { notifyActivity(); handleApiClear(); });
    _server.on("/api/status", HTTP_GET, [this]() { notifyActivity(); handleStatus(); });

    // Explicit CORS Preflight (OPTIONS)
    _server.on("/", HTTP_OPTIONS, [this]() { notifyActivity(); handleOptions(); });
    _server.on("/api/clips", HTTP_OPTIONS, [this]() { notifyActivity(); handleOptions(); });
    _server.on("/api/download", HTTP_OPTIONS, [this]() { notifyActivity(); handleOptions(); });
    _server.on("/api/delete", HTTP_OPTIONS, [this]() { notifyActivity(); handleOptions(); });
    _server.on("/api/complete", HTTP_OPTIONS, [this]() { notifyActivity(); handleOptions(); });
    _server.on("/api/clear", HTTP_OPTIONS, [this]() { notifyActivity(); handleOptions(); });
    _server.on("/api/status", HTTP_OPTIONS, [this]() { notifyActivity(); handleOptions(); });

    // Favicon & Browser Icons (204 No Content to avoid 302 redirect loops)
    _server.on("/favicon.ico", HTTP_ANY, [this]() { notifyActivity(); handleFavicon(); });
    _server.on("/apple-touch-icon.png", HTTP_ANY, [this]() { notifyActivity(); handleFavicon(); });
    _server.on("/apple-touch-icon-precomposed.png", HTTP_ANY, [this]() { notifyActivity(); handleFavicon(); });

    // Captive Portal Probes
    _server.on("/generate_204", HTTP_ANY, [this]() { notifyActivity(); handleCaptivePortal(); });
    _server.on("/gen_204", HTTP_ANY, [this]() { notifyActivity(); handleCaptivePortal(); });
    _server.on("/hotspot-detect.html", HTTP_ANY, [this]() { notifyActivity(); handleCaptivePortal(); });
    _server.on("/canonical.html", HTTP_ANY, [this]() { notifyActivity(); handleCaptivePortal(); });
    _server.on("/ncsi.txt", HTTP_ANY, [this]() { notifyActivity(); handleCaptivePortal(); });
    _server.on("/connecttest.txt", HTTP_ANY, [this]() { notifyActivity(); handleCaptivePortal(); });
    _server.on("/success.txt", HTTP_ANY, [this]() { notifyActivity(); handleCaptivePortal(); });
    _server.on("/mobile/status.txt", HTTP_ANY, [this]() { notifyActivity(); handleCaptivePortal(); });
    _server.on("/check_network_status.txt", HTTP_ANY, [this]() { notifyActivity(); handleCaptivePortal(); });

    // Catch-All Handler
    _server.addHandler(new CatchAllRequestHandler(*this));
    _server.onNotFound([this]() { handleCatchAll(); });

    _routesConfigured = true;
}

bool WifiServerManager::begin(const char* ssid, const char* pass, uint16_t port) {
    if (_active) return true;

    _ssid = ssid;
    _pass = pass;
    _lastRequestTime = millis();
    _softApStartTime = millis();

    WiFi.disconnect(true);
    delay(50);
    WiFi.mode(WIFI_AP);
    delay(50);

    IPAddress localIp(192, 168, 4, 1);
    IPAddress gateway(192, 168, 4, 1);
    IPAddress subnet(255, 255, 255, 0);

    WiFi.softAPConfig(localIp, gateway, subnet);
    bool apOk = WiFi.softAP(_ssid, _pass, 1, 0, 4);

    if (!apOk) {
        Serial.println(F("[WIFI] Warning: SoftAP start with password failed, starting open AP..."));
        apOk = WiFi.softAP(_ssid);
    }

    WiFi.setSleep(false);
    WiFi.setTxPower(WIFI_POWER_19_5dBm);

    // Start DNS Server for Captive Portal
    _dnsServer.start(53, "*", localIp);

    Serial.println(F("--------------------------------------------------"));
    Serial.printf("[WIFI AP ACTIVE] SSID: \"%s\" | Password: \"%s\"\n", _ssid, _pass);
    Serial.printf("[WIFI AP ACTIVE] High-Speed Sync Endpoint: http://%s/api/download\n", WiFi.softAPIP().toString().c_str());
    Serial.println(F("--------------------------------------------------"));

    setupRoutes();
    _server.begin(port);
    _active = true;
    return true;
}

bool WifiServerManager::stop() {
    if (!_active) return true;

    _dnsServer.stop();
    _server.close();
    _server.stop();

    WiFi.softAPdisconnect(true);
    WiFi.disconnect(true);
    WiFi.mode(WIFI_OFF);

    _active = false;
    Serial.println(F("[WIFI] SoftAP turned OFF to save battery (~150 mA)."));
    return true;
}

void WifiServerManager::notifyActivity() {
    _lastRequestTime = millis();
}

unsigned long WifiServerManager::getInactivityMs() const {
    if (!_active) return 0;
    return millis() - _lastRequestTime;
}

bool WifiServerManager::isInactive(unsigned long timeoutMs) const {
    if (!_active) return false;
    return (millis() - _lastRequestTime) >= timeoutMs;
}

void WifiServerManager::checkWatchdog() {
    if (!_active || WiFi.getMode() != WIFI_AP) return;

    int stationCount = WiFi.softAPgetStationNum();
    unsigned long now = millis();

    // Condition 1: 0 stations connected after initial setup timeout (60s)
    if (stationCount == 0 && (now - _softApStartTime > SOFTAP_CONNECT_TIMEOUT_MS)) {
        Serial.println(F("[WATCHDOG] SoftAP 60s timeout with 0 clients. Shutting down Wi-Fi."));
        stop();
        return;
    }

    // Condition 2: Inactivity timeout after transfers complete (30s)
    if (stationCount > 0 && (now - _lastRequestTime > SOFTAP_IDLE_TIMEOUT_MS)) {
        Serial.println(F("[WATCHDOG] SoftAP idle timeout (>30s). Shutting down Wi-Fi to preserve battery."));
        stop();
    }
}

void WifiServerManager::handleClient() {
    if (!_active) return;
    _dnsServer.processNextRequest();
    _server.handleClient();
}

bool WifiServerManager::isLocalIp(const String& host) const {
    IPAddress apIp = WiFi.softAPIP();
    String apIpStr = apIp.toString();
    if (host.length() == 0) return true;
    if (host == apIpStr || host.startsWith(apIpStr + ":") || host == "localhost" || host.startsWith("localhost:")) {
        return true;
    }
    return false;
}

void WifiServerManager::handleCatchAll() {
    notifyActivity();
    if (_server.method() == HTTP_OPTIONS) {
        handleOptions();
        return;
    }

    String host = _server.hostHeader();
    if (!isLocalIp(host)) {
        handleCaptivePortal();
        return;
    }

    handleNotFound();
}

void WifiServerManager::handleFavicon() {
    _server.sendHeader("Access-Control-Allow-Origin", "*");
    _server.send(204, "image/x-icon", "");
}

void WifiServerManager::handleCaptivePortal() {
    _server.sendHeader("Location", "http://192.168.4.1/", true);
    _server.send(302, "text/plain", "");
}

void WifiServerManager::handleOptions() {
    _server.sendHeader("Access-Control-Allow-Origin", "*");
    _server.sendHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS, DELETE");
    _server.sendHeader("Access-Control-Allow-Headers", "Origin, X-Requested-With, Content-Type, Accept, Range");
    _server.sendHeader("Access-Control-Expose-Headers", "Content-Range, Accept-Ranges, Content-Length");
    _server.send(204);
}

void WifiServerManager::handleNotFound() {
    _server.sendHeader("Access-Control-Allow-Origin", "*");
    String message = "404 Not Found: " + _server.uri();
    _server.send(404, "text/plain", message);
}

void WifiServerManager::handleStatus() {
    _server.sendHeader("Access-Control-Allow-Origin", "*");
    _server.sendHeader("Content-Type", "application/json");

    size_t total = _storage.getTotalBytes();
    size_t used = _storage.getUsedBytes();
    size_t count = _storage.getClipCount();

    char json[180];
    snprintf(json, sizeof(json),
             "{\"totalClips\":%u,\"usedBytes\":%u,\"totalBytes\":%u,\"freeBytes\":%u,\"usedKb\":%u,\"totalKb\":%u}",
             count, used, total, (total > used) ? (total - used) : 0, used / 1024, total / 1024);

    _server.send(200, "application/json", json);
}

void WifiServerManager::handleApiClips() {
    _server.sendHeader("Access-Control-Allow-Origin", "*");
    _server.sendHeader("Content-Type", "application/json");

    std::vector<ClipInfo> clips = _storage.listClips();

    String json = "{\"clips\":[";
    for (size_t i = 0; i < clips.size(); ++i) {
        if (i > 0) json += ",";
        json += "{\"id\":" + String(clips[i].id) +
                ",\"filename\":\"" + String(clips[i].filename) + "\"" +
                ",\"size\":" + String(clips[i].fileSize) +
                ",\"duration\":" + String(clips[i].duration, 2) +
                ",\"sampleRate\":" + String(clips[i].sampleRate) + "}";
    }
    json += "]}";

    _server.send(200, "application/json", json);
}

void WifiServerManager::handleApiDownload() {
    _server.sendHeader("Access-Control-Allow-Origin", "*");
    _server.sendHeader("Access-Control-Expose-Headers", "Content-Range, Accept-Ranges, Content-Length");

    uint16_t clipId = 0;
    if (_server.hasArg("id")) {
        clipId = (uint16_t)_server.arg("id").toInt();
    }

    File file;
    if (clipId > 0) {
        file = _storage.getClipFile(clipId);
    } else {
        std::vector<ClipInfo> clips = _storage.listClips();
        if (!clips.empty()) {
            file = _storage.getClipFile(clips.back().id);
        }
    }

    if (!file || file.isDirectory()) {
        _server.send(404, "text/plain", "Clip not found!");
        return;
    }

    size_t totalFileSize = file.size();
    size_t startByte = 0;
    size_t endByte = (totalFileSize > 0) ? (totalFileSize - 1) : 0;
    bool isRangeRequest = false;

    // RFC 7233 Range header parsing
    if (_server.hasHeader("Range")) {
        String rangeHeader = _server.header("Range");
        int eqIdx = rangeHeader.indexOf('=');
        int dashIdx = rangeHeader.indexOf('-');
        if (eqIdx != -1 && dashIdx != -1) {
            isRangeRequest = true;
            startByte = rangeHeader.substring(eqIdx + 1, dashIdx).toInt();
            if (dashIdx + 1 < (int)rangeHeader.length()) {
                endByte = rangeHeader.substring(dashIdx + 1).toInt();
            }
        }
    }

    // Range bounds validation
    if (startByte > endByte || startByte >= totalFileSize) {
        _server.sendHeader("Content-Range", "bytes */" + String(totalFileSize));
        _server.send(416, "text/plain", "Requested Range Not Satisfiable");
        file.close();
        return;
    }

    if (endByte >= totalFileSize) {
        endByte = totalFileSize - 1;
    }

    size_t contentLength = (endByte - startByte) + 1;
    file.seek(startByte);

    char filename[32];
    snprintf(filename, sizeof(filename), "clip_%03u.wav", clipId);

    _server.sendHeader("Content-Type", "audio/wav");
    _server.sendHeader("Accept-Ranges", "bytes");
    _server.sendHeader("Content-Disposition", "attachment; filename=\"" + String(filename) + "\"");
    _server.sendHeader("Content-Length", String(contentLength));

    if (isRangeRequest) {
        _server.sendHeader("Content-Range", "bytes " + String(startByte) + "-" + String(endByte) + "/" + String(totalFileSize));
        _server.send(206, "audio/wav", "");
    } else {
        _server.send(200, "audio/wav", "");
    }

    // Double-buffered stream chunk (2 x TCP MSS = 2920 bytes) for > 1.8 MB/s throughput
    uint8_t streamBuffer[2920];
    WiFiClient client = _server.client();
    size_t bytesRemaining = contentLength;

    while (client.connected() && bytesRemaining > 0) {
        size_t bytesToRead = (bytesRemaining > sizeof(streamBuffer)) ? sizeof(streamBuffer) : bytesRemaining;
        size_t bytesRead = file.read(streamBuffer, bytesToRead);
        if (bytesRead > 0) {
            client.write(streamBuffer, bytesRead);
            bytesRemaining -= bytesRead;
        } else {
            break;
        }
    }

    file.close();
    notifyActivity();
}

void WifiServerManager::handleApiDelete() {
    _server.sendHeader("Access-Control-Allow-Origin", "*");
    _server.sendHeader("Content-Type", "application/json");

    if (!_server.hasArg("id")) {
        _server.send(400, "application/json", "{\"error\":\"Missing id parameter\"}");
        return;
    }

    uint16_t clipId = (uint16_t)_server.arg("id").toInt();
    bool deleted = _storage.deleteClip(clipId);
    _storage.refresh();

    if (deleted) {
        _server.send(200, "application/json", "{\"status\":\"success\",\"deletedId\":" + String(clipId) + "}");
    } else {
        _server.send(404, "application/json", "{\"error\":\"Clip not found or delete failed\"}");
    }
}

void WifiServerManager::handleApiClear() {
    _server.sendHeader("Access-Control-Allow-Origin", "*");
    _storage.clearAll();
    _server.send(200, "application/json", "{\"status\":\"success\",\"message\":\"All clips cleared\"}");
}

void WifiServerManager::handleRoot() {
    _server.sendHeader("Access-Control-Allow-Origin", "*");

    std::vector<ClipInfo> clips = _storage.listClips();
    size_t usedKb = _storage.getUsedBytes() / 1024;
    size_t totalKb = _storage.getTotalBytes() / 1024;

    String html = "<!DOCTYPE html><html lang='de'><head><meta charset='utf-8'>"
                  "<meta name='viewport' content='width=device-width,initial-scale=1.0'>"
                  "<title>XIAO Voice Vault</title>"
                  "<style>"
                  "body{font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif;background:#0b0f17;color:#f8fafc;padding:16px;margin:0;}"
                  ".container{max-width:560px;margin:0 auto;}"
                  ".card{background:#131b26;border:1px solid #273549;border-radius:14px;padding:18px;margin-bottom:14px;box-shadow:0 4px 12px rgba(0,0,0,0.4);}"
                  "h1{font-size:1.25rem;margin:0 0 4px;color:#38bdf8;}p{font-size:0.82rem;color:#94a3b8;margin:0 0 12px;}"
                  ".stat{font-family:monospace;font-size:0.8rem;background:#1c2738;padding:8px 12px;border-radius:8px;margin-bottom:14px;display:flex;justify-content:space-between;}"
                  ".clip{display:flex;align-items:center;justify-content:space-between;padding:10px 12px;background:#1c2738;border:1px solid #273549;border-radius:10px;margin-bottom:10px;}"
                  ".clip-title{font-weight:600;font-size:0.9rem;}.clip-meta{font-size:0.75rem;color:#94a3b8;font-family:monospace;}"
                  "button{background:#0284c7;color:#fff;border:none;border-radius:6px;padding:8px 12px;font-weight:600;cursor:pointer;font-size:0.82rem;}"
                  ".btn-secondary{background:#334155;}"
                  ".btn-danger{background:#e11d48;margin-top:10px;width:100%;}"
                  "</style></head><body><div class='container'>"
                  "<div class='card'><h1>XIAO Voice Vault</h1>"
                  "<p>Hardware Dual-Mic Filter (8 KB/s) &bull; RFC 7233 Range Resume</p>"
                  "<div class='stat'><span>Aufnahmen: <strong>" + String(clips.size()) + "</strong></span>"
                  "<span>Speicher: <strong>" + String(usedKb) + " / " + String(totalKb) + " KB</strong></span></div>";

    if (clips.empty()) {
        html += "<p style='text-align:center;padding:20px 0;color:#64748b;'>Noch keine Aufnahmen im Flash gespeichert.</p>";
    } else {
        for (int i = clips.size() - 1; i >= 0; --i) {
            html += "<div class='clip'><div>"
                    "<div class='clip-title'>Aufnahme #" + String(clips[i].id) + "</div>"
                    "<div class='clip-meta'>" + String(clips[i].duration, 1) + "s &bull; " + String(clips[i].fileSize / 1024) + " KB</div>"
                    "</div>"
                    "<div style='display:flex;align-items:center;gap:6px;'>"
                    "<a href='/api/download?id=" + String(clips[i].id) + "'><button class='btn-secondary'>⬇ Download</button></a>"
                    "</div></div>";
        }
        html += "<form method='POST' action='/api/clear' onsubmit='return confirm(\"Wirklich alle Aufnahmen löschen?\");'>"
                "<button type='submit' class='btn-danger'>Alle Aufnahmen vom Flash löschen</button></form>";
    }

    html += "</div></div></body></html>";
    _server.send(200, "text/html", html);
}
