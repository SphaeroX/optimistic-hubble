#include "nimble_l2cap_server.h"
#include "nimble/nimble/host/include/host/ble_hs.h"
#include "nimble/nimble/host/include/host/ble_l2cap.h"
#include "nimble/nimble/host/include/host/ble_hs_mbuf.h"
#include "nimble/porting/nimble/include/os/os_mbuf.h"
#include "esp_log.h"

static const char* TAG = "NIMBLE_L2CAP";

NimBleL2CapServer::NimBleL2CapServer()
    : _psm(L2CAP_AUDIO_PSM), _mtu(L2CAP_COC_MTU), _initialized(false),
      _activeChan(nullptr), _isStreaming(false) {}

NimBleL2CapServer::~NimBleL2CapServer() {
    closeChannel();
}

NimBleL2CapServer& NimBleL2CapServer::getInstance() {
    static NimBleL2CapServer instance;
    return instance;
}

int NimBleL2CapServer::onL2capEvent(struct ble_l2cap_event *event, void *arg) {
    NimBleL2CapServer* server = (NimBleL2CapServer*)arg;
    if (!server) return 0;

    switch (event->type) {
        case BLE_L2CAP_EVENT_COC_CONNECTED:
            ESP_LOGI(TAG, "L2CAP CoC Connected! Status: %d", event->connect.status);
            if (event->connect.status == 0) {
                server->_activeChan = event->connect.chan;
            }
            break;

        case BLE_L2CAP_EVENT_COC_DISCONNECTED:
            ESP_LOGI(TAG, "L2CAP CoC Disconnected");
            server->_activeChan = nullptr;
            server->_isStreaming = false;
            break;

        case BLE_L2CAP_EVENT_COC_ACCEPT:
            ESP_LOGI(TAG, "L2CAP CoC Accept requested (Peer MTU: %d)", event->accept.peer_sdu_size);
            return 0; // 0 = accept connection

        case BLE_L2CAP_EVENT_COC_DATA_RECEIVED:
            ESP_LOGI(TAG, "L2CAP CoC Data received");
            if (event->receive.sdu_rx) {
                os_mbuf_free_chain(event->receive.sdu_rx);
            }
            break;

        default:
            break;
    }
    return 0;
}

bool NimBleL2CapServer::begin(uint16_t psm, uint16_t mtu) {
    if (_initialized) return true;

    _psm = psm;
    _mtu = mtu;

    int rc = ble_l2cap_create_server(_psm, _mtu, NimBleL2CapServer::onL2capEvent, this);
    if (rc != 0) {
        ESP_LOGE(TAG, "Failed to create NimBLE L2CAP CoC server (rc = %d)", rc);
        return false;
    }

    _initialized = true;
    ESP_LOGI(TAG, "NimBLE L2CAP CoC Server active on SPSM 0x%04X (MTU: %u)", _psm, _mtu);
    return true;
}

bool NimBleL2CapServer::isConnected() const {
    return (_activeChan != nullptr);
}

void NimBleL2CapServer::closeChannel() {
    _activeChan = nullptr;
    _isStreaming = false;
}

bool NimBleL2CapServer::streamAudioFile(const char* filePath, uint32_t fileId, uint32_t startOffset) {
    if (!_activeChan) {
        ESP_LOGE(TAG, "Cannot stream: No active L2CAP channel");
        return false;
    }

    if (!LittleFS.exists(filePath)) {
        ESP_LOGE(TAG, "File not found for L2CAP stream: %s", filePath);
        return false;
    }

    File file = LittleFS.open(filePath, "r");
    if (!file || file.isDirectory()) {
        ESP_LOGE(TAG, "Failed to open file: %s", filePath);
        return false;
    }

    size_t totalSize = file.size();
    if (startOffset >= totalSize) {
        file.close();
        return false;
    }

    _isStreaming = true;

    // Calculate full file CRC32
    uint32_t entireFileCrc = 0;
    uint8_t tempBuf[256];
    while (file.available()) {
        size_t r = file.read(tempBuf, sizeof(tempBuf));
        entireFileCrc = esp_rom_crc32_le(entireFileCrc, tempBuf, r);
    }

    // Seek to resume offset
    file.seek(startOffset);

    // Frame buffer: 32-byte header + 480 bytes payload = 512 bytes MTU
    const size_t CHUNK_PAYLOAD_SIZE = 480;
    uint8_t packetBuffer[32 + CHUNK_PAYLOAD_SIZE];

    SyncChunkHeader* header = (SyncChunkHeader*)packetBuffer;
    header->magic = 0xAA55;
    header->version = 0x01;
    header->frameType = (startOffset > 0) ? 0x04 : 0x01; // RESUME or DATA frame
    header->fileId = fileId;
    header->totalFileSize = (uint32_t)totalSize;
    header->fileCrc32 = entireFileCrc;
    header->reserved = 0;

    uint32_t seq = (startOffset / CHUNK_PAYLOAD_SIZE);
    uint32_t offset = startOffset;

    while (file.available() && _activeChan && _isStreaming) {
        size_t bytesRead = file.read(&packetBuffer[32], CHUNK_PAYLOAD_SIZE);
        if (bytesRead == 0) break;

        header->sequenceNum = seq++;
        header->byteOffset = offset;
        header->payloadLength = (uint16_t)bytesRead;
        header->chunkCrc32 = esp_rom_crc32_le(0, &packetBuffer[32], bytesRead);

        struct os_mbuf *om = ble_hs_mbuf_from_flat(packetBuffer, 32 + bytesRead);
        if (!om) {
            ESP_LOGE(TAG, "Failed to allocate mbuf for L2CAP packet");
            vTaskDelay(pdMS_TO_TICKS(5));
            continue;
        }

        int rc = ble_l2cap_send(_activeChan, om);
        int retryCount = 0;
        while (rc == BLE_HS_EAGAIN && _activeChan && retryCount < 100) {
            vTaskDelay(pdMS_TO_TICKS(5));
            rc = ble_l2cap_send(_activeChan, om);
            retryCount++;
        }

        if (rc != 0) {
            ESP_LOGE(TAG, "L2CAP send failed: rc = %d", rc);
            os_mbuf_free_chain(om);
            break;
        }

        offset += bytesRead;
        header->frameType = 0x01; // subsequent frames are DATA
    }

    // Send FIN frame upon completion
    if (_activeChan && _isStreaming && offset >= totalSize) {
        header->sequenceNum = seq;
        header->byteOffset = offset;
        header->payloadLength = 0;
        header->frameType = 0x05; // FIN frame
        header->chunkCrc32 = 0;

        struct os_mbuf *fin_om = ble_hs_mbuf_from_flat(packetBuffer, 32);
        if (fin_om) {
            ble_l2cap_send(_activeChan, fin_om);
        }
        ESP_LOGI(TAG, "L2CAP Audio stream finished (File ID: %lu, Total: %lu bytes)", fileId, totalSize);
    }

    file.close();
    _isStreaming = false;
    return true;
}
