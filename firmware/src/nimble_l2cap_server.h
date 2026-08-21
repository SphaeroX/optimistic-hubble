#pragma once
#include <Arduino.h>
#include <NimBLEDevice.h>
#include <LittleFS.h>
#include <esp_rom_crc.h>

#define L2CAP_AUDIO_PSM       0x0081 // Simplified Protocol/Service Multiplexer
#define L2CAP_COC_MTU         512    // L2CAP Maximum Transmission Unit

#pragma pack(push, 1)
struct SyncChunkHeader {
    uint16_t magic;          // 0xAA55 (2 bytes)
    uint8_t  version;        // 0x01 (1 byte)
    uint8_t  frameType;      // 0x01=DATA, 0x02=ACK, 0x03=NACK, 0x04=RESUME, 0x05=FIN (1 byte)
    uint32_t fileId;         // Unique File Identifier (4 bytes)
    uint32_t sequenceNum;    // Monotonically increasing chunk index (4 bytes)
    uint32_t byteOffset;     // Exact byte offset in file (4 bytes)
    uint16_t payloadLength;  // Size of binary payload in this chunk (2 bytes)
    uint16_t reserved;       // 0x0000 (Alignment) (2 bytes)
    uint32_t totalFileSize;  // Total size of complete audio file (4 bytes)
    uint32_t chunkCrc32;     // Hardware-accelerated CRC32 of payload bytes (4 bytes)
    uint32_t fileCrc32;      // Complete file CRC32 checksum (4 bytes)
};
#pragma pack(pop)

static_assert(sizeof(SyncChunkHeader) == 32, "SyncChunkHeader must be exactly 32 bytes");

class NimBleL2CapServer {
public:
    static NimBleL2CapServer& getInstance();

    bool begin(uint16_t psm = L2CAP_AUDIO_PSM, uint16_t mtu = L2CAP_COC_MTU);
    bool isConnected() const;
    
    bool streamAudioFile(const char* filePath, uint32_t fileId, uint32_t startOffset = 0);
    void closeChannel();

    // Internal NimBLE event callback handler
    static int onL2capEvent(struct ble_l2cap_event *event, void *arg);

private:
    NimBleL2CapServer();
    ~NimBleL2CapServer();

    uint16_t _psm;
    uint16_t _mtu;
    bool _initialized;
    struct ble_l2cap_chan* _activeChan;
    volatile bool _isStreaming;
};
