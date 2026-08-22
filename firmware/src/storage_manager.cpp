#include "storage_manager.h"

StorageManager::StorageManager()
    : _initialized(false), _nextClipId(1), _clipCount(0), _usedBytes(0), _totalBytes(0) {}

bool StorageManager::begin(bool formatOnFail) {
    if (!LittleFS.begin(formatOnFail)) {
        Serial.println(F("[STORAGE] LittleFS mount failed!"));
        return false;
    }

    _initialized = true;
    _totalBytes = LittleFS.totalBytes();
    scanExistingClips();

    Serial.printf("[STORAGE] LittleFS mounted. Total: %u KB, Used: %u KB, Clips: %u\n",
                  getTotalBytes() / 1024, getUsedBytes() / 1024, getClipCount());
    return true;
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
    _nextClipId = 1;
    _clipCount = 0;
    if (!_initialized) return;

    File root = LittleFS.open("/");
    if (!root || !root.isDirectory()) return;

    File file = root.openNextFile();
    while (file) {
        String name = file.name();
        if (name.indexOf("clip_") != -1 && name.endsWith(".wav")) {
            _clipCount++;
            int id = extractClipIdFromFilename(name);
            if (id >= _nextClipId) {
                _nextClipId = id + 1;
            }
        }
        file = root.openNextFile();
    }
    _usedBytes = LittleFS.usedBytes();
    _totalBytes = LittleFS.totalBytes();
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
                info.sampleRate = 16000;
                
                // 4-bit Mono IMA-ADPCM at 16 kHz = 8,000 bytes per second
                size_t dataBytes = (info.fileSize > 60) ? (info.fileSize - 60) : ((info.fileSize > 44) ? (info.fileSize - 44) : 0);
                info.duration = (float)dataBytes / 8000.0f;

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

    _nextClipId = 1;
    _clipCount = 0;
    _usedBytes = LittleFS.usedBytes();
    Serial.println(F("[STORAGE] Cleared all audio clips from Flash."));
    return true;
}
