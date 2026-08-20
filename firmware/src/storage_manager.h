#pragma once
#include <Arduino.h>
#include <LittleFS.h>
#include <vector>

struct ClipInfo {
    uint16_t id;
    char filename[32];
    size_t fileSize;
    float duration;
    uint32_t sampleRate;
};

class StorageManager {
public:
    StorageManager();

    bool begin(bool formatOnFail = true);
    bool saveWavClip(const uint8_t* pcmData, size_t pcmBytes, uint32_t sampleRate, uint16_t* clipIdOut = nullptr);
    
    std::vector<ClipInfo> listClips();
    File getClipFile(uint16_t id);
    bool deleteClip(uint16_t id);
    bool clearAll();

    size_t getClipCount();
    uint16_t getNextClipId() const { return _nextClipId; }
    void refresh() { scanExistingClips(); }
    size_t getUsedBytes();
    size_t getTotalBytes();

private:
    bool _initialized;
    uint16_t _nextClipId;

    void scanExistingClips();
    void writeWavHeader(File& file, size_t pcmBytes, uint32_t sampleRate);
};
