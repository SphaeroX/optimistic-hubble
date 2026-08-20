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
    if (pCharacteristic == _pCharCmd || pCharacteristic == _pCharState) {
        std::string val = pCharacteristic->getValue();
        if (!val.empty()) {
            uint8_t cmdByte = (uint8_t)val[0];
            _pendingCmd = (BleCommand)cmdByte;
            Serial.printf("[BLE] Command received: %u\n", cmdByte);
        }
    }
}

BleCommand BleManager::getPendingCommand() {
    BleCommand cmd = _pendingCmd;
    _pendingCmd = CMD_NONE;
    return cmd;
}

bool BleManager::begin(const char* deviceName) {
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
    
    pAdvertising->start();
    Serial.printf("[BLE] Server active. Advertising as \"%s\"...\n", deviceName);

    return true;
}

bool BleManager::stop() {
    if (NimBLEDevice::getInitialized()) {
        NimBLEDevice::getAdvertising()->stop();
        NimBLEDevice::deinit(true);
    }
    _connected = false;
    _pServer = nullptr;
    _pService = nullptr;
    _pCharState = nullptr;
    _pCharAudio = nullptr;
    _pCharTap = nullptr;
    _pCharCmd = nullptr;
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
