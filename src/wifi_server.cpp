#include "wifi_server.h"
#include "config.h"

WifiServerManager::WifiServerManager(AudioRecorder& recorderRef)
    : _recorder(recorderRef), _server(HTTP_SERVER_PORT), _ssid(WIFI_AP_SSID), _pass(WIFI_AP_PASS) {}

bool WifiServerManager::begin(const char* ssid, const char* pass, uint16_t port) {
    _ssid = ssid;
    _pass = pass;

    WiFi.mode(WIFI_AP);
    IPAddress localIp(192, 168, 4, 1);
    IPAddress gateway(192, 168, 4, 1);
    IPAddress subnet(255, 255, 255, 0);

    WiFi.softAPConfig(localIp, gateway, subnet);
    bool apOk = WiFi.softAP(_ssid, _pass);

    if (!apOk) {
        Serial.println(F("[WIFI] Failed to start SoftAP!"));
        return false;
    }

    Serial.printf("[WIFI] SoftAP \"%s\" active at IP: %s\n", _ssid, WiFi.softAPIP().toString().c_str());

    // Register WebServer Routes
    _server.on("/", HTTP_GET, [this]() { handleRoot(); });
    _server.on("/audio.wav", HTTP_GET, [this]() { handleAudioWav(); });
    _server.on("/status", HTTP_GET, [this]() { handleStatus(); });
    _server.onNotFound([this]() { handleOptions(); });

    _server.begin();
    Serial.println(F("[HTTP] Audio Download Server listening on port 80."));
    return true;
}

void WifiServerManager::handleClient() {
    _server.handleClient();
}

void WifiServerManager::handleOptions() {
    // Universal CORS Preflight handler
    _server.sendHeader("Access-Control-Allow-Origin", "*");
    _server.sendHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    _server.sendHeader("Access-Control-Allow-Headers", "Origin, X-Requested-With, Content-Type, Accept");
    _server.send(204);
}

void WifiServerManager::handleRoot() {
    _server.sendHeader("Access-Control-Allow-Origin", "*");
    String html = "<!DOCTYPE html><html><head><meta charset='utf-8'><title>XIAO Audio Server</title></head>"
                  "<body style='font-family:sans-serif;padding:30px;background:#111;color:#eee;'>"
                  "<h2>XIAO ESP32C3 Audio Server</h2>"
                  "<p>Status: <strong>Ready</strong></p>"
                  "<p>Latest Recording: <a href='/audio.wav' style='color:#06b6d4;'>Download / Play audio.wav</a></p>"
                  "<p><a href='/status' style='color:#3b82f6;'>JSON Status</a></p>"
                  "</body></html>";
    _server.send(200, "text/html", html);
}

void WifiServerManager::handleStatus() {
    _server.sendHeader("Access-Control-Allow-Origin", "*");
    _server.sendHeader("Content-Type", "application/json");

    size_t samples = _recorder.getRecordedSamples();
    size_t bytes = _recorder.getRecordedBytes();
    float dur = _recorder.getDurationSeconds();
    bool isRec = _recorder.isRecording();

    char json[160];
    snprintf(json, sizeof(json), 
             "{\"recording\":%s,\"samples\":%u,\"bytes\":%u,\"duration\":%.2f,\"sampleRate\":%u}",
             isRec ? "true" : "false", samples, bytes, dur, _recorder.getSampleRate());

    _server.send(200, "application/json", json);
}

void WifiServerManager::handleAudioWav() {
    size_t pcmBytes = _recorder.getRecordedBytes();
    const uint8_t* pcmData = _recorder.getBuffer();

    if (pcmBytes == 0 || pcmData == nullptr) {
        _server.sendHeader("Access-Control-Allow-Origin", "*");
        _server.send(404, "text/plain", "No audio clip recorded yet. Tap breadboard to record!");
        return;
    }

    uint32_t sampleRate = _recorder.getSampleRate();
    uint16_t numChannels = 1;     // Mono
    uint16_t bitsPerSample = 16;  // 16-Bit
    uint32_t byteRate = (sampleRate * numChannels * bitsPerSample) / 8;
    uint16_t blockAlign = (numChannels * bitsPerSample) / 8;
    uint32_t totalFileSize = 44 + pcmBytes;

    // Generate 44-byte RIFF WAV Header
    uint8_t wavHeader[44];
    // RIFF Chunk
    wavHeader[0] = 'R'; wavHeader[1] = 'I'; wavHeader[2] = 'F'; wavHeader[3] = 'F';
    uint32_t chunkSize = 36 + pcmBytes;
    wavHeader[4] = (uint8_t)(chunkSize & 0xFF);
    wavHeader[5] = (uint8_t)((chunkSize >> 8) & 0xFF);
    wavHeader[6] = (uint8_t)((chunkSize >> 16) & 0xFF);
    wavHeader[7] = (uint8_t)((chunkSize >> 24) & 0xFF);
    wavHeader[8] = 'W'; wavHeader[9] = 'A'; wavHeader[10] = 'V'; wavHeader[11] = 'E';

    // fmt subchunk
    wavHeader[12] = 'f'; wavHeader[13] = 'm'; wavHeader[14] = 't'; wavHeader[15] = ' ';
    wavHeader[16] = 16; wavHeader[17] = 0; wavHeader[18] = 0; wavHeader[19] = 0; // Subchunk1Size = 16
    wavHeader[20] = 1;  wavHeader[21] = 0; // AudioFormat = 1 (PCM)
    wavHeader[22] = (uint8_t)(numChannels & 0xFF);
    wavHeader[23] = (uint8_t)((numChannels >> 8) & 0xFF);
    wavHeader[24] = (uint8_t)(sampleRate & 0xFF);
    wavHeader[25] = (uint8_t)((sampleRate >> 8) & 0xFF);
    wavHeader[26] = (uint8_t)((sampleRate >> 16) & 0xFF);
    wavHeader[27] = (uint8_t)((sampleRate >> 24) & 0xFF);
    wavHeader[28] = (uint8_t)(byteRate & 0xFF);
    wavHeader[29] = (uint8_t)((byteRate >> 8) & 0xFF);
    wavHeader[30] = (uint8_t)((byteRate >> 16) & 0xFF);
    wavHeader[31] = (uint8_t)((byteRate >> 24) & 0xFF);
    wavHeader[32] = (uint8_t)(blockAlign & 0xFF);
    wavHeader[33] = (uint8_t)((blockAlign >> 8) & 0xFF);
    wavHeader[34] = (uint8_t)(bitsPerSample & 0xFF);
    wavHeader[35] = (uint8_t)((bitsPerSample >> 8) & 0xFF);

    // data subchunk
    wavHeader[36] = 'd'; wavHeader[37] = 'a'; wavHeader[38] = 't'; wavHeader[39] = 'a';
    wavHeader[40] = (uint8_t)(pcmBytes & 0xFF);
    wavHeader[41] = (uint8_t)((pcmBytes >> 8) & 0xFF);
    wavHeader[42] = (uint8_t)((pcmBytes >> 16) & 0xFF);
    wavHeader[43] = (uint8_t)((pcmBytes >> 24) & 0xFF);

    // Stream out via HTTP
    _server.sendHeader("Access-Control-Allow-Origin", "*");
    _server.sendHeader("Content-Disposition", "inline; filename=\"audio.wav\"");
    _server.setContentLength(totalFileSize);
    _server.send(200, "audio/wav", "");

    WiFiClient client = _server.client();
    // Send 44-byte header
    client.write(wavHeader, 44);

    // Stream PCM audio in fast 2048-byte chunks
    const size_t CHUNK_SIZE = 2048;
    size_t bytesSent = 0;
    while (bytesSent < pcmBytes && client.connected()) {
        size_t toSend = (pcmBytes - bytesSent > CHUNK_SIZE) ? CHUNK_SIZE : (pcmBytes - bytesSent);
        client.write(&pcmData[bytesSent], toSend);
        bytesSent += toSend;
    }

    Serial.printf("[HTTP] Streamed audio.wav (%u bytes) to client in high-speed Wi-Fi mode!\n", totalFileSize);
}
