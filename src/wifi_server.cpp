#include "wifi_server.h"
#include "config.h"

WifiServerManager::WifiServerManager(StorageManager& storageRef)
    : _storage(storageRef), _server(HTTP_SERVER_PORT), _ssid(WIFI_AP_SSID), _pass(WIFI_AP_PASS) {}

bool WifiServerManager::begin(const char* ssid, const char* pass, uint16_t port) {
    _ssid = ssid;
    _pass = pass;

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
    _server.on("/", HTTP_GET, [this]() { handleRoot(); });
    _server.on("/api/clips", HTTP_GET, [this]() { handleApiClips(); });
    _server.on("/api/download", HTTP_GET, [this]() { handleApiDownload(); });
    _server.on("/api/clear", HTTP_GET, [this]() { handleApiClear(); });
    _server.on("/api/clear", HTTP_POST, [this]() { handleApiClear(); });
    _server.on("/api/status", HTTP_GET, [this]() { handleStatus(); });

    // Captive Portal probes
    _server.on("/generate_204", HTTP_GET, [this]() { handleCaptivePortal(); });
    _server.on("/gen_204", HTTP_GET, [this]() { handleCaptivePortal(); });
    _server.on("/hotspot-detect.html", HTTP_GET, [this]() { handleCaptivePortal(); });
    _server.on("/ncsi.txt", HTTP_GET, [this]() { handleCaptivePortal(); });
    _server.on("/connecttest.txt", HTTP_GET, [this]() { handleCaptivePortal(); });

    _server.onNotFound([this]() { handleOptions(); });

    _server.begin();
    Serial.println(F("[HTTP] Sync Server & Captive Portal listening on port 80."));
    return true;
}

void WifiServerManager::handleClient() {
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
                  "<title>XIAO Dual-Mic Voice Vault</title>"
                  "<style>"
                  "body{font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif;background:#0b0f17;color:#f8fafc;padding:16px;margin:0;}"
                  ".container{max-width:540px;margin:0 auto;}"
                  ".card{background:#131b26;border:1px solid #273549;border-radius:14px;padding:18px;margin-bottom:14px;box-shadow:0 4px 12px rgba(0,0,0,0.4);}"
                  "h1{font-size:1.25rem;margin:0 0 4px;color:#38bdf8;}p{font-size:0.82rem;color:#94a3b8;margin:0 0 12px;}"
                  ".stat{font-family:monospace;font-size:0.8rem;background:#1c2738;padding:8px 12px;border-radius:8px;margin-bottom:14px;display:flex;justify-content:space-between;}"
                  ".clip{display:flex;align-items:center;justify-content:space-between;padding:10px 12px;background:#1c2738;border:1px solid #273549;border-radius:10px;margin-bottom:10px;}"
                  ".clip-title{font-weight:600;font-size:0.9rem;}.clip-meta{font-size:0.75rem;color:#94a3b8;font-family:monospace;}"
                  "button{background:#0284c7;color:#fff;border:none;border-radius:6px;padding:8px 12px;font-weight:600;cursor:pointer;font-size:0.82rem;}"
                  ".btn-danger{background:#e11d48;margin-top:10px;width:100%;}"
                  "</style></head><body><div class='container'>"
                  "<div class='card'><h1>XIAO Voice Vault</h1>"
                  "<p>2-Kanal Stereo ADPCM (16 KB/s) &bull; Dual-Mic Beamforming & ANC</p>"
                  "<div class='stat'><span>Aufnahmen: <strong>" + String(clips.size()) + "</strong></span>"
                  "<span>Speicher: <strong>" + String(usedKb) + " / " + String(totalKb) + " KB</strong></span></div>";

    if (clips.empty()) {
        html += "<p style='text-align:center;padding:20px 0;color:#64748b;'>Noch keine Aufnahmen im Flash gespeichert.<br>Hau auf das Breadboard, um aufzunehmen!</p>";
    } else {
        for (int i = clips.size() - 1; i >= 0; --i) {
            html += "<div class='clip'><div>"
                    "<div class='clip-title'>Aufnahme #" + String(clips[i].id) + "</div>"
                    "<div class='clip-meta'>" + String(clips[i].duration, 1) + "s &bull; " + String(clips[i].fileSize / 1024) + " KB (Stereo)</div>"
                    "</div>"
                    "<div style='display:flex;align-items:center;gap:6px;'>"
                    "<button onclick=\"playStereoAdpcm('/api/download?id=" + String(clips[i].id) + "')\">▶ Beamforming Play</button>"
                    "<a href='/api/download?id=" + String(clips[i].id) + "' download><button>⬇</button></a>"
                    "</div></div>";
        }
        html += "<form method='POST' action='/api/clear' onsubmit='return confirm(\"Wirklich alle Aufnahmen löschen?\");'>"
                "<button type='submit' class='btn-danger'>Alle Aufnahmen vom Flash löschen</button></form>";
    }

    html += "</div></div><script>"
            "let actx = null;"
            "const stepT = [7,8,9,10,11,12,13,14,16,17,19,21,23,25,28,31,34,37,41,45,50,55,60,66,73,80,88,97,107,118,130,143,157,173,190,209,230,253,279,307,337,371,408,449,494,544,598,658,724,796,876,963,1060,1166,1282,1411,1552,1707,1878,2066,2272,2499,2749,3024,3327,3660,4026,4428,4871,5358,5894,6484,7132,7845,8630,9493,10442,11487,12635,13899,15289,16818,18500,20350,22385,24623,27086,29794,32767];"
            "const idxT = [-1,-1,-1,-1,2,4,6,8,-1,-1,-1,-1,2,4,6,8];"
            "async function playStereoAdpcm(url){"
            "  if(!actx) actx = new (window.AudioContext||window.webkitAudioContext)();"
            "  const res = await fetch(url); const buf = await res.arrayBuffer();"
            "  const raw = new Uint8Array(buf, 60);"
            "  const numFrames = raw.length;"
            "  const pcm = new Float32Array(numFrames);"
            "  let pL=0, sL=0, pR=0, sR=0;"
            "  function dec(n, isL){"
            "    let step = stepT[isL ? sL : sR], dq = step >> 3;"
            "    if(n & 4) dq += step; if(n & 2) dq += (step >> 1); if(n & 1) dq += (step >> 2);"
            "    let p = isL ? pL : pR;"
            "    if(n & 8) p -= dq; else p += dq;"
            "    if(p > 32767) p = 32767; else if(p < -32768) p = -32768;"
            "    let nxt = (isL ? sL : sR) + idxT[n & 15]; if(nxt < 0) nxt = 0; else if(nxt > 88) nxt = 88;"
            "    if(isL){ pL = p; sL = nxt; } else { pR = p; sR = nxt; }"
            "    return p / 32768.0;"
            "  }"
            "  for(let i=0; i<numFrames; i++){"
            "    let s0 = dec(raw[i] & 15, true);"
            "    let s1 = dec((raw[i] >> 4) & 15, false);"
            "    pcm[i] = (s0 + s1) / 2.0;" // Dual-Mic Beamforming
            "  }"
            "  const ab = actx.createBuffer(1, numFrames, 16000);"
            "  ab.getChannelData(0).set(pcm);"
            "  const src = actx.createBufferSource(); src.buffer = ab; src.connect(actx.destination); src.start();"
            "}"
            "</script></body></html>";

    _server.send(200, "text/html", html);
}
