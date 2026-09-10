#pragma once
#include <Arduino.h>
#include <LittleFS.h>
#include <Preferences.h>
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

    size_t getClipCount() const { return _clipCount; }
    uint16_t getNextClipId();
    void refresh() { scanExistingClips(); }
    size_t getUsedBytes() const { return _usedBytes; }
    size_t getTotalBytes() const { return _totalBytes; }

private:
    bool _initialized;
    uint16_t _nextClipId;
    size_t _clipCount;
    size_t _usedBytes;
    size_t _totalBytes;
    Preferences _prefs;

    void scanExistingClips();
    void writeWavHeader(File& file, size_t pcmBytes, uint32_t sampleRate);
};
