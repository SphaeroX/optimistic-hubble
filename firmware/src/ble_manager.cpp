#include "ble_manager.h"

BleManager::BleManager()
    : _pServer(nullptr), _pService(nullptr), _pCharState(nullptr),
      _pCharAudio(nullptr), _pCharTap(nullptr), _pCharCmd(nullptr),
      _connected(false), _currentState(STATE_IDLE), _pendingCmd(CMD_NONE) {}

void BleManager::onConnect(NimBLEServer* pServer) {
    _connected = true;
    Serial.println(F("[BLE] Client connected!"));
}

void BleManager::onDisconnect(NimBLEServer* pServer) {
    _connected = false;
    Serial.println(F("[BLE] Client disconnected. Restarting advertising..."));
    NimBLEDevice::startAdvertising();
}

void BleManager::onWrite(NimBLECharacteristic* pCharacteristic) {
    handleCharacteristicWrite(pCharacteristic);
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

    uint8_t cmdByte = data[0];
    _pendingCmd = (BleCommand)cmdByte;
    Serial.printf("\n[BLE] >>> Command received: %u (from characteristic: %s) <<<\n",
                  cmdByte, pCharacteristic->getUUID().toString().c_str());
}

BleCommand BleManager::getPendingCommand() {
    BleCommand cmd = _pendingCmd;
    _pendingCmd = CMD_NONE;
    return cmd;
}

bool BleManager::begin(const char* deviceName) {
    if (!NimBLEDevice::getInitialized()) {
        NimBLEDevice::init(deviceName);
        NimBLEDevice::setPower(ESP_PWR_LVL_P9); // +9 dBm for strong stable signal

        _pServer = NimBLEDevice::createServer();
        _pServer->setCallbacks(this);

        _pService = _pServer->createService(BLE_SERVICE_UUID);

        // State / Control Characteristic: Read, Write, Notify
        _pCharState = _pService->createCharacteristic(
            BLE_CHAR_STATE_UUID,
            NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::NOTIFY
        );
        _pCharState->setCallbacks(this);

        // Audio Data Stream Characteristic: Notify
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

        // Set initial values
        uint8_t initPayload[7] = {0, 0, 0, 0, 0, (uint8_t)(AUDIO_SAMPLE_RATE & 0xFF), (uint8_t)((AUDIO_SAMPLE_RATE >> 8) & 0xFF)};
        _pCharState->setValue(initPayload, sizeof(initPayload));

        _pService->start();

        // Configure Advertising for maximum Windows compatibility
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
    payload[0] = 0x01; // Tap flag
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
    delay(50);

    const size_t CHUNK_PAYLOAD_SIZE = 240; // 240 bytes audio payload
    size_t totalChunks = (totalBytes + CHUNK_PAYLOAD_SIZE - 1) / CHUNK_PAYLOAD_SIZE;

    Serial.printf("[BLE] Transmitting %u bytes of audio in %u chunks...\n", totalBytes, totalChunks);

    uint8_t packet[6 + CHUNK_PAYLOAD_SIZE];

    for (size_t chunkIdx = 0; chunkIdx < totalChunks; ++chunkIdx) {
        if (!_connected) {
            Serial.println(F("[BLE] Disconnected during audio transfer!"));
            return false;
        }

        size_t offset = chunkIdx * CHUNK_PAYLOAD_SIZE;
        size_t thisPayload = (totalBytes - offset > CHUNK_PAYLOAD_SIZE) ? CHUNK_PAYLOAD_SIZE : (totalBytes - offset);

        // Header: [ChunkIndex(2), TotalChunks(2), PayloadLen(2)]
        packet[0] = (uint8_t)(chunkIdx & 0xFF);
        packet[1] = (uint8_t)((chunkIdx >> 8) & 0xFF);
        packet[2] = (uint8_t)(totalChunks & 0xFF);
        packet[3] = (uint8_t)((totalChunks >> 8) & 0xFF);
        packet[4] = (uint8_t)(thisPayload & 0xFF);
        packet[5] = (uint8_t)((thisPayload >> 8) & 0xFF);

        memcpy(&packet[6], &audioData[offset], thisPayload);

        _pCharAudio->setValue(packet, 6 + thisPayload);
        _pCharAudio->notify();

        delay(8); // Safe spacing for Windows BLE link layer
    }

    Serial.println(F("[BLE] Audio transmission complete!"));
    delay(50);
    updateState(STATE_DONE, totalBytes, sampleRate);
    delay(100);
    updateState(STATE_IDLE);

    return true;
}
