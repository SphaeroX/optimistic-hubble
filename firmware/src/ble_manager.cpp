#include "ble_manager.h"
#include "led_indicator.h"
#include <LittleFS.h>

static bool extractJsonString(const char* json, const char* key, char* out, size_t maxLen) {
    char pattern[32];
    snprintf(pattern, sizeof(pattern), "\"%s\":\"", key);
    const char* pos = strstr(json, pattern);
    if (!pos) return false;
    pos += strlen(pattern);
    const char* end = strchr(pos, '\"');
    if (!end) return false;
    size_t len = end - pos;
    if (len >= maxLen) len = maxLen - 1;
    strncpy(out, pos, len);
    out[len] = '\0';
    return true;
}

static int extractJsonInt(const char* json, const char* key, int defaultVal = 0) {
    char pattern[32];
    snprintf(pattern, sizeof(pattern), "\"%s\":", key);
    const char* pos = strstr(json, pattern);
    if (!pos) return defaultVal;
    pos += strlen(pattern);
    while (*pos == ' ' || *pos == '\t') pos++;
    return atoi(pos);
}

static bool extractJsonBool(const char* json, const char* key, bool defaultVal = false) {
    char pattern[32];
    snprintf(pattern, sizeof(pattern), "\"%s\":", key);
    const char* pos = strstr(json, pattern);
    if (!pos) return defaultVal;
    pos += strlen(pattern);
    while (*pos == ' ' || *pos == '\t') pos++;
    if (strncmp(pos, "true", 4) == 0 || strncmp(pos, "1", 1) == 0) return true;
    if (strncmp(pos, "false", 5) == 0 || strncmp(pos, "0", 1) == 0) return false;
    return defaultVal;
}

BleManager::BleManager(LedIndicator* leds)
    : _pServer(nullptr), _pService(nullptr), _pCharState(nullptr),
      _pCharAudio(nullptr), _pCharTap(nullptr), _pCharCmd(nullptr),
      _leds(leds), _connected(false), _currentState(STATE_IDLE), _pendingCmd(CMD_NONE),
      _cmdParam(0), _cmdClipId(0), _cmdOffset(0) {
    memset(&_hotspotConfig, 0, sizeof(_hotspotConfig));
}

void BleManager::onConnect(NimBLEServer* pServer) {
    _connected = true;
    Serial.println(F("[BLE] Client connected!"));
}

void BleManager::onConnect(NimBLEServer* pServer, ble_gap_conn_desc* desc) {
    _connected = true;
    Serial.println(F("[BLE] Client connected (BLE 5.0 High-Throughput negotiation)!"));
    if (desc != nullptr) {
        // Negotiate 7.5ms - 15ms connection interval for maximum throughput
        pServer->updateConnParams(desc->conn_handle, 6, 12, 0, 400);
    }
}

void BleManager::onDisconnect(NimBLEServer* pServer) {
    _connected = false;
    Serial.println(F("[BLE] Client disconnected. Restarting advertising..."));
    NimBLEDevice::startAdvertising();
}

void BleManager::onWrite(NimBLECharacteristic* pCharacteristic, ble_gap_conn_desc* desc) {
    (void)desc;
    handleCharacteristicWrite(pCharacteristic);
}

void BleManager::handleCharacteristicWrite(NimBLECharacteristic* pCharacteristic) {
    if (!pCharacteristic) return;

    NimBLEAttValue val = pCharacteristic->getValue();
    if (val.size() == 0) return;

    const uint8_t* data = val.data();
    if (!data) return;

    // Check for JSON payload (e.g. from sendConnectHotspotCommand)
    if (data[0] == '{' || (val.size() > 1 && data[0] == (uint8_t)CMD_CONNECT_HOTSPOT && data[1] == '{')) {
        const char* jsonStr = (data[0] == '{') ? (const char*)data : (const char*)&data[1];
        if (strstr(jsonStr, "\"ssid\"") != nullptr) {
            _pendingCmd = CMD_CONNECT_HOTSPOT;
            memset(&_hotspotConfig, 0, sizeof(_hotspotConfig));
            extractJsonString(jsonStr, "ssid", _hotspotConfig.ssid, sizeof(_hotspotConfig.ssid));
            extractJsonString(jsonStr, "pass", _hotspotConfig.pass, sizeof(_hotspotConfig.pass));
            extractJsonString(jsonStr, "ip", _hotspotConfig.serverIp, sizeof(_hotspotConfig.serverIp));
            _hotspotConfig.serverPort = (uint16_t)extractJsonInt(jsonStr, "port", 8080);
            _hotspotConfig.clipId = (uint16_t)extractJsonInt(jsonStr, "id", 0);
            _hotspotConfig.autoDelete = extractJsonBool(jsonStr, "del", false);

            Serial.printf("\n[BLE] >>> Received Hotspot Config: SSID=\"%s\", Server=%s:%u, Clip=%u, AutoDelete=%s <<<\n",
                          _hotspotConfig.ssid, _hotspotConfig.serverIp, _hotspotConfig.serverPort,
                          _hotspotConfig.clipId, _hotspotConfig.autoDelete ? "YES" : "NO");
            return;
        }
    }

    uint8_t cmdByte = data[0];
    _pendingCmd = (BleCommand)cmdByte;

    // Parse optional parameters for commands
    if (val.size() >= 2) {
        _cmdParam = data[1];
    } else {
        _cmdParam = 0;
    }

    if (val.size() >= 3) {
        _cmdClipId = (uint16_t)(data[1] | (data[2] << 8));
    } else {
        _cmdClipId = 0;
    }

    if (val.size() >= 7) {
        _cmdOffset = (uint32_t)(data[3] | (data[4] << 8) | (data[5] << 16) | (data[6] << 24));
    } else {
        _cmdOffset = 0;
    }

    Serial.printf("\n[BLE] >>> Command received: %u (Param: %u, Clip: %u, Offset: %lu) from %s <<<\n",
                  cmdByte, _cmdParam, _cmdClipId, _cmdOffset, pCharacteristic->getUUID().toString().c_str());
}

BleCommand BleManager::getPendingCommand() {
    BleCommand cmd = _pendingCmd;
    _pendingCmd = CMD_NONE;
    return cmd;
}

bool BleManager::begin(const char* deviceName) {
    if (!NimBLEDevice::getInitialized()) {
        NimBLEDevice::init(deviceName);
        NimBLEDevice::setMTU(512);
        NimBLEDevice::setPower(ESP_PWR_LVL_P9); // +9 dBm for maximum range

        _pServer = NimBLEDevice::createServer();
        _pServer->setCallbacks(this);

        _pService = _pServer->createService(BLE_SERVICE_UUID);

        // State / Telemetry Characteristic: Read, Write, Notify
        _pCharState = _pService->createCharacteristic(
            BLE_CHAR_STATE_UUID,
            NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::NOTIFY
        );
        _pCharState->setCallbacks(this);

        // Audio Stream Characteristic: Notify
        _pCharAudio = _pService->createCharacteristic(
            BLE_CHAR_AUDIO_UUID,
            NIMBLE_PROPERTY::NOTIFY
        );

        // Tap Event Characteristic: Notify
        _pCharTap = _pService->createCharacteristic(
            BLE_CHAR_TAP_UUID,
            NIMBLE_PROPERTY::NOTIFY
        );

        // Command Characteristic: Write
        _pCharCmd = _pService->createCharacteristic(
            BLE_CHAR_CMD_UUID,
            NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR
        );
        _pCharCmd->setCallbacks(this);

        // Initial State Payload
        uint8_t initPayload[7] = {0, 0, 0, 0, 0, (uint8_t)(AUDIO_SAMPLE_RATE & 0xFF), (uint8_t)((AUDIO_SAMPLE_RATE >> 8) & 0xFF)};
        _pCharState->setValue(initPayload, sizeof(initPayload));

        _pService->start();

        // Initialize NimBLE L2CAP CoC Server on SPSM 0x0081
        NimBleL2CapServer::getInstance().begin(BLE_L2CAP_AUDIO_PSM, L2CAP_COC_MTU);

        // Configure Advertising
        NimBLEAdvertising* pAdvertising = NimBLEDevice::getAdvertising();
        pAdvertising->addServiceUUID(BLE_SERVICE_UUID);
        pAdvertising->setScanResponse(true);
        pAdvertising->setMinPreferred(0x10); // ~20ms interval
        pAdvertising->setMaxPreferred(0x20); // ~40ms interval
    }

    NimBLEAdvertising* pAdvertising = NimBLEDevice::getAdvertising();
    if (pAdvertising) {
        pAdvertising->start();
    }
    Serial.printf("[BLE] Server active. Advertising as \"%s\"...\n", deviceName);

    return true;
}

bool BleManager::stop() {
    if (NimBLEDevice::getInitialized()) {
        NimBLEAdvertising* pAdvertising = NimBLEDevice::getAdvertising();
        if (pAdvertising) {
            pAdvertising->stop();
        }
    }
    _connected = false;
    return true;
}

void BleManager::updateState(DeviceState state, uint32_t totalAudioBytes, uint16_t sampleRate) {
    _currentState = state;
    if (_pCharState == nullptr) return;

    uint8_t payload[7];
    payload[0] = (uint8_t)state;
    payload[1] = (uint8_t)(totalAudioBytes & 0xFF);
    payload[2] = (uint8_t)((totalAudioBytes >> 8) & 0xFF);
    payload[3] = (uint8_t)((totalAudioBytes >> 16) & 0xFF);
    payload[4] = (uint8_t)((totalAudioBytes >> 24) & 0xFF);
    payload[5] = (uint8_t)(sampleRate & 0xFF);
    payload[6] = (uint8_t)((sampleRate >> 8) & 0xFF);

    _pCharState->setValue(payload, sizeof(payload));
    if (_connected) {
        _pCharState->notify();
    }
}

void BleManager::sendTelemetry(
    DeviceState state,
    uint32_t totalAudioBytes,
    uint16_t sampleRate,
    uint16_t batteryMilliVolts,
    uint8_t batteryPercent,
    bool isCharging,
    uint32_t freeHeapBytes,
    uint32_t usedStorageBytes,
    uint32_t totalStorageBytes,
    uint16_t totalClips,
    int16_t accelX_mg,
    int16_t accelY_mg,
    int16_t accelZ_mg,
    uint16_t motionMagnitude_mg,
    uint16_t tapCount
) {
    _currentState = state;
    if (_pCharState == nullptr) return;

    uint8_t payload[35];
    payload[0] = (uint8_t)state;
    payload[1] = (uint8_t)(totalAudioBytes & 0xFF);
    payload[2] = (uint8_t)((totalAudioBytes >> 8) & 0xFF);
    payload[3] = (uint8_t)((totalAudioBytes >> 16) & 0xFF);
    payload[4] = (uint8_t)((totalAudioBytes >> 24) & 0xFF);
    payload[5] = (uint8_t)(sampleRate & 0xFF);
    payload[6] = (uint8_t)((sampleRate >> 8) & 0xFF);
    payload[7] = (uint8_t)(batteryMilliVolts & 0xFF);
    payload[8] = (uint8_t)((batteryMilliVolts >> 8) & 0xFF);
    payload[9] = batteryPercent;
    payload[10] = isCharging ? 1 : 0;
    payload[11] = (uint8_t)(freeHeapBytes & 0xFF);
    payload[12] = (uint8_t)((freeHeapBytes >> 8) & 0xFF);
    payload[13] = (uint8_t)((freeHeapBytes >> 16) & 0xFF);
    payload[14] = (uint8_t)((freeHeapBytes >> 24) & 0xFF);
    payload[15] = (uint8_t)(usedStorageBytes & 0xFF);
    payload[16] = (uint8_t)((usedStorageBytes >> 8) & 0xFF);
    payload[17] = (uint8_t)((usedStorageBytes >> 16) & 0xFF);
    payload[18] = (uint8_t)((usedStorageBytes >> 24) & 0xFF);
    payload[19] = (uint8_t)(totalStorageBytes & 0xFF);
    payload[20] = (uint8_t)((totalStorageBytes >> 8) & 0xFF);
    payload[21] = (uint8_t)((totalStorageBytes >> 16) & 0xFF);
    payload[22] = (uint8_t)((totalStorageBytes >> 24) & 0xFF);
    payload[23] = (uint8_t)(totalClips & 0xFF);
    payload[24] = (uint8_t)((totalClips >> 8) & 0xFF);
    payload[25] = (uint8_t)(accelX_mg & 0xFF);
    payload[26] = (uint8_t)((accelX_mg >> 8) & 0xFF);
    payload[27] = (uint8_t)(accelY_mg & 0xFF);
    payload[28] = (uint8_t)((accelY_mg >> 8) & 0xFF);
    payload[29] = (uint8_t)(accelZ_mg & 0xFF);
    payload[30] = (uint8_t)((accelZ_mg >> 8) & 0xFF);
    payload[31] = (uint8_t)(motionMagnitude_mg & 0xFF);
    payload[32] = (uint8_t)((motionMagnitude_mg >> 8) & 0xFF);
    payload[33] = (uint8_t)(tapCount & 0xFF);
    payload[34] = (uint8_t)((tapCount >> 8) & 0xFF);

    _pCharState->setValue(payload, sizeof(payload));
    if (_connected) {
        _pCharState->notify();
    }
}

void BleManager::notifyTap(float shockMagnitude) {
    if (_pCharTap == nullptr || !_connected) return;

    uint8_t payload[5];
    payload[0] = 0x01;
    int32_t fixedShock = (int32_t)(shockMagnitude * 1000.0f);
    payload[1] = (uint8_t)(fixedShock & 0xFF);
    payload[2] = (uint8_t)((fixedShock >> 8) & 0xFF);
    payload[3] = (uint8_t)((fixedShock >> 16) & 0xFF);
    payload[4] = (uint8_t)((fixedShock >> 24) & 0xFF);

    _pCharTap->setValue(payload, sizeof(payload));
    _pCharTap->notify();
}

bool BleManager::transmitAudio(const uint8_t* audioData, size_t totalBytes, uint16_t sampleRate) {
    if (_pCharAudio == nullptr || !_connected || audioData == nullptr || totalBytes == 0) {
        return false;
    }

    updateState(STATE_TRANSFERRING, totalBytes, sampleRate);
    if (_leds) _leds->setMode(LedMode::SYNCING);
    delay(50);

    const size_t CHUNK_PAYLOAD_SIZE = 240;
    size_t totalChunks = (totalBytes + CHUNK_PAYLOAD_SIZE - 1) / CHUNK_PAYLOAD_SIZE;

    Serial.printf("[BLE] Transmitting %u bytes of audio in %u chunks...\n", totalBytes, totalChunks);

    uint8_t packet[6 + CHUNK_PAYLOAD_SIZE];

    for (size_t chunkIdx = 0; chunkIdx < totalChunks; ++chunkIdx) {
        if (_leds) _leds->update();
        if (!_connected) {
            Serial.println(F("[BLE] Disconnected during audio transfer!"));
            if (_leds) _leds->setMode(LedMode::IDLE);
            return false;
        }

        size_t offset = chunkIdx * CHUNK_PAYLOAD_SIZE;
        size_t thisPayload = (totalBytes - offset > CHUNK_PAYLOAD_SIZE) ? CHUNK_PAYLOAD_SIZE : (totalBytes - offset);

        packet[0] = (uint8_t)(chunkIdx & 0xFF);
        packet[1] = (uint8_t)((chunkIdx >> 8) & 0xFF);
        packet[2] = (uint8_t)(totalChunks & 0xFF);
        packet[3] = (uint8_t)((totalChunks >> 8) & 0xFF);
        packet[4] = (uint8_t)(thisPayload & 0xFF);
        packet[5] = (uint8_t)((thisPayload >> 8) & 0xFF);

        memcpy(&packet[6], &audioData[offset], thisPayload);

        _pCharAudio->setValue(packet, 6 + thisPayload);
        _pCharAudio->notify();

        delay(8);
    }

    Serial.println(F("[BLE] Audio transmission complete!"));
    delay(50);
    updateState(STATE_DONE, totalBytes, sampleRate);
    delay(100);
    updateState(STATE_IDLE);
    if (_leds) _leds->setMode(_connected ? LedMode::BLE_CONNECTED : LedMode::IDLE);

    return true;
}

bool BleManager::streamAudioFileFromStorage(uint16_t clipId, uint32_t startOffset) {
    if (_pCharAudio == nullptr || !_connected) {
        Serial.println(F("[BLE] Cannot stream: BLE not connected"));
        return false;
    }

    char filename[32];
    snprintf(filename, sizeof(filename), "/clip_%03u.wav", clipId);

    if (!LittleFS.exists(filename)) {
        Serial.printf("[BLE] File not found: %s\n", filename);
        return false;
    }

    File file = LittleFS.open(filename, FILE_READ);
    if (!file || file.isDirectory()) {
        Serial.printf("[BLE] Failed to open %s\n", filename);
        return false;
    }

    size_t totalBytes = file.size();
    if (startOffset >= totalBytes) {
        file.close();
        return false;
    }

    file.seek(startOffset);

    const size_t CHUNK_PAYLOAD_SIZE = 240;
    size_t totalChunks = (totalBytes + CHUNK_PAYLOAD_SIZE - 1) / CHUNK_PAYLOAD_SIZE;
    size_t startChunk = startOffset / CHUNK_PAYLOAD_SIZE;

    updateState(STATE_TRANSFERRING, totalBytes, AUDIO_SAMPLE_RATE);
    if (_leds) _leds->setMode(LedMode::SYNCING);
    Serial.printf("[BLE] Streaming %s (%u bytes, %u chunks) via BLE GATT...\n",
                  filename, (unsigned int)totalBytes, (unsigned int)totalChunks);

    uint8_t packet[8 + CHUNK_PAYLOAD_SIZE];

    for (size_t chunkIdx = startChunk; chunkIdx < totalChunks && _connected; ++chunkIdx) {
        if (_leds) _leds->update();
        size_t bytesRead = file.read(&packet[8], CHUNK_PAYLOAD_SIZE);
        if (bytesRead == 0) break;

        // On-the-fly header auto-repair: ensure RIFF and data chunk sizes are accurate even if recording halted unexpectedly
        if (chunkIdx == 0 && bytesRead >= 44) {
            uint8_t* wavHdr = &packet[8];
            if (wavHdr[0] == 'R' && wavHdr[1] == 'I' && wavHdr[2] == 'F' && wavHdr[3] == 'F') {
                uint32_t riffLen = (totalBytes > 8) ? (uint32_t)(totalBytes - 8) : 0;
                wavHdr[4] = (uint8_t)(riffLen & 0xFF);
                wavHdr[5] = (uint8_t)((riffLen >> 8) & 0xFF);
                wavHdr[6] = (uint8_t)((riffLen >> 16) & 0xFF);
                wavHdr[7] = (uint8_t)((riffLen >> 24) & 0xFF);

                // Check for 60-byte ADPCM header or 44-byte PCM header
                if (bytesRead >= 60 && wavHdr[52] == 'd' && wavHdr[53] == 'a' && wavHdr[54] == 't' && wavHdr[55] == 'a') {
                    uint32_t dataLen = (totalBytes > 60) ? (uint32_t)(totalBytes - 60) : 0;
                    wavHdr[56] = (uint8_t)(dataLen & 0xFF);
                    wavHdr[57] = (uint8_t)((dataLen >> 8) & 0xFF);
                    wavHdr[58] = (uint8_t)((dataLen >> 16) & 0xFF);
                    wavHdr[59] = (uint8_t)((dataLen >> 24) & 0xFF);
                } else if (wavHdr[36] == 'd' && wavHdr[37] == 'a' && wavHdr[38] == 't' && wavHdr[39] == 'a') {
                    uint32_t dataLen = (totalBytes > 44) ? (uint32_t)(totalBytes - 44) : 0;
                    wavHdr[40] = (uint8_t)(dataLen & 0xFF);
                    wavHdr[41] = (uint8_t)((dataLen >> 8) & 0xFF);
                    wavHdr[42] = (uint8_t)((dataLen >> 16) & 0xFF);
                    wavHdr[43] = (uint8_t)((dataLen >> 24) & 0xFF);
                }
            }
        }

        packet[0] = (uint8_t)(chunkIdx & 0xFF);
        packet[1] = (uint8_t)((chunkIdx >> 8) & 0xFF);
        packet[2] = (uint8_t)(totalChunks & 0xFF);
        packet[3] = (uint8_t)((totalChunks >> 8) & 0xFF);
        packet[4] = (uint8_t)(bytesRead & 0xFF);
        packet[5] = (uint8_t)((bytesRead >> 8) & 0xFF);
        packet[6] = (uint8_t)(clipId & 0xFF);
        packet[7] = (uint8_t)((clipId >> 8) & 0xFF);

        _pCharAudio->setValue(packet, 8 + bytesRead);
        _pCharAudio->notify();

        delay(2);
    }

    file.close();
    Serial.printf("[BLE] Stream completed for clip #%u (%u bytes)\n", clipId, (unsigned int)totalBytes);

    updateState(STATE_DONE, totalBytes, AUDIO_SAMPLE_RATE);
    delay(50);
    updateState(STATE_IDLE);
    if (_leds) _leds->setMode(_connected ? LedMode::BLE_CONNECTED : LedMode::IDLE);
    return true;
}

bool BleManager::streamL2capClip(uint16_t clipId, uint32_t startOffset) {
    char filename[32];
    snprintf(filename, sizeof(filename), "/clip_%03u.wav", clipId);

    updateState(STATE_TRANSFERRING, 0, AUDIO_SAMPLE_RATE);
    if (_leds) _leds->setMode(LedMode::SYNCING);
    bool ok = NimBleL2CapServer::getInstance().streamAudioFile(filename, clipId, startOffset);
    updateState(ok ? STATE_DONE : STATE_IDLE);
    if (_leds) _leds->setMode(_connected ? LedMode::BLE_CONNECTED : LedMode::IDLE);
    return ok;
}
