#pragma once
#include <Arduino.h>
#include <LittleFS.h>
#include <Preferences.h>
#include <vector>
#include "config.h"

class SpiFlashDriver;

struct ClipInfo {
    uint16_t id;
    char filename[32];
    size_t fileSize;
    float duration;
    uint32_t sampleRate;
    uint32_t ageSeconds;
};

class StorageManager {
public:
    StorageManager();

    bool begin(SpiFlashDriver* extFlash = nullptr, bool formatOnFail = true);
    bool saveWavClip(const uint8_t* pcmData, size_t pcmBytes, uint32_t sampleRate, uint16_t* clipIdOut = nullptr);
    
    std::vector<ClipInfo> listClips();
    File getClipFile(uint16_t id);
    bool deleteClip(uint16_t id);
    bool clearAll();

    void recordClipTimestamp(uint16_t id);
    uint32_t getClipAgeSeconds(uint16_t id);

    size_t getClipCount() const { return _clipCount; }
    uint16_t getNextClipId();
    void refresh() { scanExistingClips(); }
    size_t getUsedBytes() const { return _usedBytes; }
    size_t getTotalBytes() const { return _totalBytes; }
    bool isExternalFlash() const { return _isExternal; }

    void setQuality(AudioQuality quality);
    AudioQuality getQuality();

private:
    bool _initialized;
    bool _isExternal;
    uint16_t _nextClipId;
    size_t _clipCount;
    size_t _usedBytes;
    size_t _totalBytes;
    Preferences _prefs;

    void scanExistingClips();
    void writeWavHeader(File& file, size_t pcmBytes, uint32_t sampleRate);
};
