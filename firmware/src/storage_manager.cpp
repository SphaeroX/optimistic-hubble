#include "storage_manager.h"
#include "spi_flash_driver.h"
extern "C" {
#include "esp_littlefs.h"
}

StorageManager::StorageManager()
    : _initialized(false), _isExternal(false), _nextClipId(1), _clipCount(0), _usedBytes(0), _totalBytes(0) {}

bool StorageManager::begin(SpiFlashDriver* extFlash, bool formatOnFail) {
    bool mounted = false;

    // Ensure any previously mounted LittleFS instance is cleanly closed
    LittleFS.end();

    if (extFlash != nullptr && extFlash->isPartitionRegistered()) {
        Serial.println(F("[STORAGE] Attempting to mount LittleFS on External 16 MB Flash (\"ext_flash\")..."));
        mounted = LittleFS.begin(formatOnFail, "/littlefs", 10, extFlash->getPartitionLabel());
        if (mounted) {
            _isExternal = true;
            Serial.printf("[STORAGE] SUCCESS: LittleFS mounted on External 16 MB SPI Flash! Capacity: %u KB\n",
                          (unsigned int)(LittleFS.totalBytes() / 1024));
        } else {
            Serial.println(F("[STORAGE] Warning: External flash mount failed. Falling back to internal flash."));
        }
    }

    if (!mounted) {
        Serial.println(F("[STORAGE] Mounting LittleFS on internal flash partition..."));
        LittleFS.end();
        mounted = LittleFS.begin(formatOnFail);
        _isExternal = false;
        if (!mounted) {
            Serial.println(F("[STORAGE] LittleFS internal mount failed!"));
            return false;
        }
    }

    _prefs.begin("dictula_store", false);
    _initialized = true;
    _totalBytes = LittleFS.totalBytes();
    if (_isExternal && (_totalBytes == 0 || _totalBytes < 10000000) && extFlash != nullptr) {
        _totalBytes = extFlash->getCapacityBytes();
    }
    _usedBytes = LittleFS.usedBytes();
    scanExistingClips();

    Serial.printf("[STORAGE] LittleFS ready (%s). Total: %u KB, Used: %u KB, Clips: %u, NextClipId: %u\n",
                  _isExternal ? "External 16MB" : "Internal 1.9MB",
                  (unsigned int)(getTotalBytes() / 1024), (unsigned int)(getUsedBytes() / 1024),
                  (unsigned int)getClipCount(), (unsigned int)_nextClipId);
    return true;
}

void StorageManager::setQuality(AudioQuality quality) {
    _prefs.putUChar("quality", (uint8_t)quality);
}

AudioQuality StorageManager::getQuality() {
    return (AudioQuality)_prefs.getUChar("quality", (uint8_t)QUALITY_MEDIUM);
}

static int extractClipIdFromFilename(const String& rawName) {
    int idx = rawName.indexOf("clip_");
    if (idx == -1) return -1;
    int dotIdx = rawName.indexOf('.', idx);
    if (dotIdx == -1) return -1;
    String numStr = rawName.substring(idx + 5, dotIdx);
    return numStr.toInt();
}

void StorageManager::scanExistingClips() {
    _clipCount = 0;
    uint16_t maxOnDisk = 0;

    if (_initialized) {
        File root = LittleFS.open("/");
        if (root && root.isDirectory()) {
            File file = root.openNextFile();
            while (file) {
                String name = file.name();
                if (name.indexOf("clip_") != -1 && name.endsWith(".wav")) {
                    _clipCount++;
                    int id = extractClipIdFromFilename(name);
                    if (id > (int)maxOnDisk) {
                        maxOnDisk = (uint16_t)id;
                    }
                }
                file = root.openNextFile();
            }
        }
        _usedBytes = LittleFS.usedBytes();
        _totalBytes = LittleFS.totalBytes();
    }

    uint16_t lastSavedId = _prefs.getUShort("last_id", 0);
    uint16_t baseId = (maxOnDisk > lastSavedId) ? maxOnDisk : lastSavedId;
    _nextClipId = baseId + 1;
    if (_nextClipId == 0) _nextClipId = 1;
}

uint16_t StorageManager::getNextClipId() {
    uint16_t id = _nextClipId;
    _prefs.putUShort("last_id", id);
    _nextClipId++;
    if (_nextClipId == 0) _nextClipId = 1;
    return id;
}

std::vector<ClipInfo> StorageManager::listClips() {
    std::vector<ClipInfo> clips;
    if (!_initialized) return clips;

    File root = LittleFS.open("/");
    if (!root || !root.isDirectory()) return clips;

    File file = root.openNextFile();
    while (file) {
        String name = file.name();
        if (name.indexOf("clip_") != -1 && name.endsWith(".wav")) {
            int id = extractClipIdFromFilename(name);
            if (id > 0) {
                ClipInfo info;
                info.id = (uint16_t)id;
                snprintf(info.filename, sizeof(info.filename), "%s", name.c_str());
                info.fileSize = file.size();

                // Read WAV header to determine sample rate & byte rate
                uint32_t sampleRate = 16000;
                uint32_t byteRate = 8000;
                if (info.fileSize >= 44) {
                    uint8_t hdr[44];
                    file.seek(0);
                    if (file.read(hdr, 44) == 44) {
                        sampleRate = hdr[24] | (hdr[25] << 8) | (hdr[26] << 16) | (hdr[27] << 24);
                        byteRate = hdr[28] | (hdr[29] << 8) | (hdr[30] << 16) | (hdr[31] << 24);
                    }
                }
                if (byteRate == 0) byteRate = (sampleRate == 8000) ? 4000 : 8000;

                size_t headerSize = (info.fileSize > 60) ? 60 : 44;
                size_t dataBytes = (info.fileSize > headerSize) ? (info.fileSize - headerSize) : 0;
                info.sampleRate = sampleRate;
                info.duration = (float)dataBytes / (float)byteRate;

                clips.push_back(info);
            }
        }
        file = root.openNextFile();
    }
    return clips;
}

File StorageManager::getClipFile(uint16_t id) {
    if (!_initialized) return File();

    char filename[32];
    snprintf(filename, sizeof(filename), "/clip_%03u.wav", id);
    if (LittleFS.exists(filename)) {
        return LittleFS.open(filename, FILE_READ);
    }

    snprintf(filename, sizeof(filename), "/clip_%u.wav", id);
    if (LittleFS.exists(filename)) {
        return LittleFS.open(filename, FILE_READ);
    }

    // Fallback search in root directory
    File root = LittleFS.open("/");
    if (root && root.isDirectory()) {
        File file = root.openNextFile();
        while (file) {
            String name = file.name();
            if (name.endsWith(".wav") && extractClipIdFromFilename(name) == (int)id) {
                String fullPath = name.startsWith("/") ? name : ("/" + name);
                return LittleFS.open(fullPath, FILE_READ);
            }
            file = root.openNextFile();
        }
    }

    return File();
}

bool StorageManager::deleteClip(uint16_t id) {
    if (!_initialized) return false;

    char filename[32];
    snprintf(filename, sizeof(filename), "/clip_%03u.wav", id);
    if (LittleFS.exists(filename)) {
        bool ok = LittleFS.remove(filename);
        if (ok) scanExistingClips();
        return ok;
    }

    snprintf(filename, sizeof(filename), "/clip_%u.wav", id);
    if (LittleFS.exists(filename)) {
        bool ok = LittleFS.remove(filename);
        if (ok) scanExistingClips();
        return ok;
    }

    bool removed = false;
    // Fallback scan in root directory
    File root = LittleFS.open("/");
    if (root && root.isDirectory()) {
        File file = root.openNextFile();
        while (file) {
            String name = file.name();
            if (name.endsWith(".wav") && extractClipIdFromFilename(name) == (int)id) {
                String fullPath = name.startsWith("/") ? name : ("/" + name);
                removed = LittleFS.remove(fullPath);
                break;
            }
            file = root.openNextFile();
        }
    }

    if (removed) {
        scanExistingClips();
    }
    return removed;
}

bool StorageManager::clearAll() {
    if (!_initialized) return false;

    File root = LittleFS.open("/");
    if (!root || !root.isDirectory()) return false;

    std::vector<String> filesToDelete;
    File file = root.openNextFile();
    while (file) {
        String name = file.name();
        if (name.endsWith(".wav") || name.indexOf("clip_") != -1) {
            String fullPath = name.startsWith("/") ? name : ("/" + name);
            filesToDelete.push_back(fullPath);
        }
        file = root.openNextFile();
    }

    for (const auto& path : filesToDelete) {
        LittleFS.remove(path);
    }

    _prefs.putUShort("last_id", 0);
    _nextClipId = 1;
    _clipCount = 0;
    _usedBytes = LittleFS.usedBytes();
    Serial.println(F("[STORAGE] Cleared all audio clips from Flash and reset clip ID."));
    return true;
}
