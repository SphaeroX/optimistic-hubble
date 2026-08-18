#include "storage_manager.h"

StorageManager::StorageManager()
    : _initialized(false), _nextClipId(1) {}

bool StorageManager::begin(bool formatOnFail) {
    if (!LittleFS.begin(formatOnFail)) {
        Serial.println(F("[STORAGE] LittleFS mount failed!"));
        return false;
    }

    _initialized = true;
    scanExistingClips();

    Serial.printf("[STORAGE] LittleFS mounted. Total: %u KB, Used: %u KB, Clips: %u\n",
                  getTotalBytes() / 1024, getUsedBytes() / 1024, getClipCount());
    return true;
}

void StorageManager::scanExistingClips() {
    _nextClipId = 1;
    File root = LittleFS.open("/");
    if (!root || !root.isDirectory()) return;

    File file = root.openNextFile();
    while (file) {
        String name = file.name();
        if (name.startsWith("clip_") && name.endsWith(".wav")) {
            int id = name.substring(5, name.indexOf('.')).toInt();
            if (id >= _nextClipId) {
                _nextClipId = id + 1;
            }
        }
        file = root.openNextFile();
    }
}

std::vector<ClipInfo> StorageManager::listClips() {
    std::vector<ClipInfo> clips;
    if (!_initialized) return clips;

    File root = LittleFS.open("/");
    if (!root || !root.isDirectory()) return clips;

    File file = root.openNextFile();
    while (file) {
        String name = file.name();
        if (name.startsWith("clip_") && name.endsWith(".wav")) {
            ClipInfo info;
            int id = name.substring(5, name.indexOf('.')).toInt();
            info.id = (uint16_t)id;
            snprintf(info.filename, sizeof(info.filename), "%s", name.c_str());
            info.fileSize = file.size();
            info.sampleRate = 16000;
            
            // 4-bit Mono IMA-ADPCM at 16 kHz = 8,000 bytes per second
            size_t dataBytes = (info.fileSize > 60) ? (info.fileSize - 60) : ((info.fileSize > 44) ? (info.fileSize - 44) : 0);
            info.duration = (float)dataBytes / 8000.0f;

            clips.push_back(info);
        }
        file = root.openNextFile();
    }
    return clips;
}

File StorageManager::getClipFile(uint16_t id) {
    if (!_initialized) return File();

    char filename[32];
    snprintf(filename, sizeof(filename), "/clip_%03u.wav", id);

    if (!LittleFS.exists(filename)) {
        return File();
    }

    return LittleFS.open(filename, FILE_READ);
}

bool StorageManager::deleteClip(uint16_t id) {
    if (!_initialized) return false;

    char filename[32];
    snprintf(filename, sizeof(filename), "/clip_%03u.wav", id);

    if (LittleFS.exists(filename)) {
        return LittleFS.remove(filename);
    }
    return false;
}

bool StorageManager::clearAll() {
    if (!_initialized) return false;

    File root = LittleFS.open("/");
    if (!root || !root.isDirectory()) return false;

    std::vector<String> filesToDelete;
    File file = root.openNextFile();
    while (file) {
        String name = file.name();
        if (name.startsWith("clip_") && name.endsWith(".wav")) {
            filesToDelete.push_back("/" + name);
        }
        file = root.openNextFile();
    }

    for (const auto& path : filesToDelete) {
        LittleFS.remove(path);
    }

    _nextClipId = 1;
    Serial.println(F("[STORAGE] Cleared all audio clips from Flash."));
    return true;
}

size_t StorageManager::getClipCount() {
    return listClips().size();
}

size_t StorageManager::getUsedBytes() {
    if (!_initialized) return 0;
    return LittleFS.usedBytes();
}

size_t StorageManager::getTotalBytes() {
    if (!_initialized) return 0;
    return LittleFS.totalBytes();
}
