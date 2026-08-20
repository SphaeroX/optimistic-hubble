#include "wifi_server.h"
#include "config.h"

WifiServerManager::WifiServerManager(StorageManager& storageRef)
    : _storage(storageRef), _server(HTTP_SERVER_PORT), _ssid(WIFI_AP_SSID), _pass(WIFI_AP_PASS),
      _active(false), _lastRequestTime(0) {}

bool WifiServerManager::begin(const char* ssid, const char* pass, uint16_t port) {
    if (_active) return true;

    _ssid = ssid;
    _pass = pass;
    _lastRequestTime = millis();

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

    WiFi.setTxPower(WIFI_POWER_19_5dBm);

    // Start DNS Server for Captive Portal
    _dnsServer.start(53, "*", localIp);

    Serial.println(F("--------------------------------------------------"));
    Serial.printf("[WIFI AP ACTIVE] SSID: \"%s\" | Password: \"%s\"\n", _ssid, _pass);
    Serial.printf("[WIFI AP ACTIVE] Web Dashboard: http://%s\n", WiFi.softAPIP().toString().c_str());
    Serial.println(F("--------------------------------------------------"));

    // Register WebServer Routes
    _server.on("/", HTTP_GET, [this]() { notifyActivity(); handleRoot(); });
    _server.on("/api/clips", HTTP_GET, [this]() { notifyActivity(); handleApiClips(); });
    _server.on("/api/download", HTTP_GET, [this]() { notifyActivity(); handleApiDownload(); });
    _server.on("/api/clear", HTTP_GET, [this]() { notifyActivity(); handleApiClear(); });
    _server.on("/api/clear", HTTP_POST, [this]() { notifyActivity(); handleApiClear(); });
    _server.on("/api/status", HTTP_GET, [this]() { notifyActivity(); handleStatus(); });

    // Captive Portal probes
    _server.on("/generate_204", HTTP_GET, [this]() { handleCaptivePortal(); });
    _server.on("/gen_204", HTTP_GET, [this]() { handleCaptivePortal(); });
    _server.on("/hotspot-detect.html", HTTP_GET, [this]() { handleCaptivePortal(); });
    _server.on("/ncsi.txt", HTTP_GET, [this]() { handleCaptivePortal(); });
    _server.on("/connecttest.txt", HTTP_GET, [this]() { handleCaptivePortal(); });

    _server.onNotFound([this]() { handleOptions(); });

    _server.begin();
    _active = true;
    Serial.println(F("[HTTP] Sync Server & Captive Portal listening on port 80."));
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
    Serial.println(F("[WIFI] Wi-Fi SoftAP and Web Server turned OFF to save battery (~150 mA)."));
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

void WifiServerManager::handleClient() {
    if (!_active) return;
    _dnsServer.processNextRequest();
    _server.handleClient();
}

void WifiServerManager::handleCaptivePortal() {
    _server.sendHeader("Location", "http://192.168.4.1/", true);
    _server.send(302, "text/plain", "");
}

void WifiServerManager::handleOptions() {
    String method = _server.method() == HTTP_OPTIONS ? "OPTIONS" : "UNKNOWN";
    if (method == "OPTIONS") {
        _server.sendHeader("Access-Control-Allow-Origin", "*");
        _server.sendHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS, DELETE");
        _server.sendHeader("Access-Control-Allow-Headers", "Origin, X-Requested-With, Content-Type, Accept");
        _server.send(204);
    } else {
        handleCaptivePortal();
    }
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

    char filename[32];
    snprintf(filename, sizeof(filename), "clip_%03u.wav", clipId);

    _server.sendHeader("Content-Disposition", "inline; filename=\"" + String(filename) + "\"");
    _server.streamFile(file, "audio/wav");
    file.close();
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
                  "<p>Hardware Dual-Mic Filter (8 KB/s) &bull; Universal Standard WAV</p>"
                  "<div class='stat'><span>Aufnahmen: <strong>" + String(clips.size()) + "</strong></span>"
                  "<span>Speicher: <strong>" + String(usedKb) + " / " + String(totalKb) + " KB</strong></span></div>";

    if (clips.empty()) {
        html += "<p style='text-align:center;padding:20px 0;color:#64748b;'>Noch keine Aufnahmen im Flash gespeichert.<br>Hau auf das Breadboard, um aufzunehmen!</p>";
    } else {
        for (int i = clips.size() - 1; i >= 0; --i) {
            html += "<div class='clip'><div>"
                    "<div class='clip-title'>Aufnahme #" + String(clips[i].id) + "</div>"
                    "<div class='clip-meta'>" + String(clips[i].duration, 1) + "s &bull; " + String(clips[i].fileSize / 1024) + " KB (8 KB/s)</div>"
                    "</div>"
                    "<div style='display:flex;align-items:center;gap:6px;'>"
                    "<button onclick=\"playMonoAdpcm('/api/download?id=" + String(clips[i].id) + "')\">▶ Abspielen</button>"
                    "<button class='btn-secondary' onclick=\"downloadPcmWav('/api/download?id=" + String(clips[i].id) + "', " + String(clips[i].id) + ")\">⬇ WAV</button>"
                    "</div></div>";
        }
        html += "<form method='POST' action='/api/clear' onsubmit='return confirm(\"Wirklich alle Aufnahmen löschen?\");'>"
                "<button type='submit' class='btn-danger'>Alle Aufnahmen vom Flash löschen</button></form>";
    }

    html += "</div></div><script>"
            "let actx = null;"
            "const stepT = [7,8,9,10,11,12,13,14,16,17,19,21,23,25,28,31,34,37,41,45,50,55,60,66,73,80,88,97,107,118,130,143,157,173,190,209,230,253,279,307,337,371,408,449,494,544,598,658,724,796,876,963,1060,1166,1282,1411,1552,1707,1878,2066,2272,2499,2749,3024,3327,3660,4026,4428,4871,5358,5894,6484,7132,7845,8630,9493,10442,11487,12635,13899,15289,16818,18500,20350,22385,24623,27086,29794,32767];"
            "const idxT = [-1,-1,-1,-1,2,4,6,8,-1,-1,-1,-1,2,4,6,8];"
            "function decodeMonoAdpcm(buf){"
            "  const raw = new Uint8Array(buf, 60);"
            "  const numSamples = raw.length * 2;"
            "  const pcm = new Int16Array(numSamples);"
            "  let pred = 0, stepIdx = 0;"
            "  function dec(n){"
            "    let step = stepT[stepIdx], dq = step >> 3;"
            "    if(n & 4) dq += step; if(n & 2) dq += (step >> 1); if(n & 1) dq += (step >> 2);"
            "    if(n & 8) pred -= dq; else pred += dq;"
            "    if(pred > 32767) pred = 32767; else if(pred < -32768) pred = -32768;"
            "    let nxt = stepIdx + idxT[n & 15]; if(nxt < 0) nxt = 0; else if(nxt > 88) nxt = 88;"
            "    stepIdx = nxt;"
            "    return pred;"
            "  }"
            "  let sIdx = 0;"
            "  for(let i=0; i<raw.length; i++){"
            "    pcm[sIdx++] = dec(raw[i] & 15);"
            "    pcm[sIdx++] = dec((raw[i] >> 4) & 15);"
            "  }"
            "  return { pcm, numSamples };"
            "}"
            "async function playMonoAdpcm(url){"
            "  if(!actx) actx = new (window.AudioContext||window.webkitAudioContext)();"
            "  const res = await fetch(url); const buf = await res.arrayBuffer();"
            "  const d = decodeMonoAdpcm(buf);"
            "  const ab = actx.createBuffer(1, d.numSamples, 16000);"
            "  const out = ab.getChannelData(0);"
            "  for(let i=0; i<d.numSamples; i++) out[i] = d.pcm[i] / 32768.0;"
            "  const src = actx.createBufferSource(); src.buffer = ab; src.connect(actx.destination); src.start();"
            "}"
            "async function downloadPcmWav(url, id){"
            "  const res = await fetch(url); const buf = await res.arrayBuffer();"
            "  const d = decodeMonoAdpcm(buf);"
            "  const dataBytes = d.numSamples * 2;"
            "  const totalSize = 44 + dataBytes;"
            "  const outBuf = new ArrayBuffer(totalSize);"
            "  const v = new DataView(outBuf);"
            "  v.setUint8(0,0x52);v.setUint8(1,0x49);v.setUint8(2,0x46);v.setUint8(3,0x46);"
            "  v.setUint32(4, 36 + dataBytes, true);"
            "  v.setUint8(8,0x57);v.setUint8(9,0x41);v.setUint8(10,0x56);v.setUint8(11,0x45);"
            "  v.setUint8(12,0x66);v.setUint8(13,0x6d);v.setUint8(14,0x74);v.setUint8(15,0x20);"
            "  v.setUint32(16, 16, true); v.setUint16(20, 1, true); v.setUint16(22, 1, true);" // 1 Channel Mono
            "  v.setUint32(24, 16000, true); v.setUint32(28, 32000, true); v.setUint16(32, 2, true); v.setUint16(34, 16, true);"
            "  v.setUint8(36,0x64);v.setUint8(37,0x61);v.setUint8(38,0x74);v.setUint8(39,0x61);"
            "  v.setUint32(40, dataBytes, true);"
            "  let off = 44;"
            "  for(let i=0; i<d.numSamples; i++){"
            "    v.setInt16(off, d.pcm[i], true); off += 2;"
            "  }"
            "  const blob = new Blob([v], {type:'audio/wav'});"
            "  const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = 'clip_' + id + '_pcm16.wav'; a.click();"
            "}"
            "</script></body></html>";

    _server.send(200, "text/html", html);
}
