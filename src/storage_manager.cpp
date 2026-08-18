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

    Serial.printf("[STORAGE] LittleFS mounted successfully. Total: %u KB, Used: %u KB, Existing Clips: %u\n",
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

void StorageManager::writeWavHeader(File& file, size_t pcmBytes, uint32_t sampleRate) {
    uint16_t numChannels = 1;     // Mono
    uint16_t bitsPerSample = 16;  // 16-Bit
    uint32_t byteRate = (sampleRate * numChannels * bitsPerSample) / 8;
    uint16_t blockAlign = (numChannels * bitsPerSample) / 8;
    uint32_t chunkSize = 36 + pcmBytes;

    uint8_t header[44];
    // RIFF Chunk
    header[0] = 'R'; header[1] = 'I'; header[2] = 'F'; header[3] = 'F';
    header[4] = (uint8_t)(chunkSize & 0xFF);
    header[5] = (uint8_t)((chunkSize >> 8) & 0xFF);
    header[6] = (uint8_t)((chunkSize >> 16) & 0xFF);
    header[7] = (uint8_t)((chunkSize >> 24) & 0xFF);
    header[8] = 'W'; header[9] = 'A'; header[10] = 'V'; header[11] = 'E';

    // fmt subchunk
    header[12] = 'f'; header[13] = 'm'; header[14] = 't'; header[15] = ' ';
    header[16] = 16; header[17] = 0; header[18] = 0; header[19] = 0;
    header[20] = 1;  header[21] = 0; // PCM
    header[22] = (uint8_t)(numChannels & 0xFF);
    header[23] = (uint8_t)((numChannels >> 8) & 0xFF);
    header[24] = (uint8_t)(sampleRate & 0xFF);
    header[25] = (uint8_t)((sampleRate >> 8) & 0xFF);
    header[26] = (uint8_t)((sampleRate >> 16) & 0xFF);
    header[27] = (uint8_t)((sampleRate >> 24) & 0xFF);
    header[28] = (uint8_t)(byteRate & 0xFF);
    header[29] = (uint8_t)((byteRate >> 8) & 0xFF);
    header[30] = (uint8_t)((byteRate >> 16) & 0xFF);
    header[31] = (uint8_t)((byteRate >> 24) & 0xFF);
    header[32] = (uint8_t)(blockAlign & 0xFF);
    header[33] = (uint8_t)((blockAlign >> 8) & 0xFF);
    header[34] = (uint8_t)(bitsPerSample & 0xFF);
    header[35] = (uint8_t)((bitsPerSample >> 8) & 0xFF);

    // data subchunk
    header[36] = 'd'; header[37] = 'a'; header[38] = 't'; header[39] = 'a';
    header[40] = (uint8_t)(pcmBytes & 0xFF);
    header[41] = (uint8_t)((pcmBytes >> 8) & 0xFF);
    header[42] = (uint8_t)((pcmBytes >> 16) & 0xFF);
    header[43] = (uint8_t)((pcmBytes >> 24) & 0xFF);

    file.write(header, 44);
}

bool StorageManager::saveWavClip(const uint8_t* pcmData, size_t pcmBytes, uint32_t sampleRate, uint16_t* clipIdOut) {
    if (!_initialized || pcmData == nullptr || pcmBytes == 0) {
        return false;
    }

    uint16_t clipId = _nextClipId++;
    char filename[32];
    snprintf(filename, sizeof(filename), "/clip_%03u.wav", clipId);

    File file = LittleFS.open(filename, FILE_WRITE);
    if (!file) {
        Serial.printf("[STORAGE] Failed to create file: %s\n", filename);
        return false;
    }

    // Write WAV header
    writeWavHeader(file, pcmBytes, sampleRate);

    // Write PCM data
    size_t written = file.write(pcmData, pcmBytes);
    file.close();

    if (written != pcmBytes) {
        Serial.printf("[STORAGE] Incomplete write for %s (%u / %u bytes)\n", filename, written, pcmBytes);
        return false;
    }

    if (clipIdOut) *clipIdOut = clipId;

    float duration = (float)pcmBytes / (float)(sampleRate * sizeof(int16_t));
    Serial.printf("[STORAGE] Saved %s (%u bytes, %.2f s) to Flash. Free: %u KB\n",
                  filename, 44 + pcmBytes, duration, (getTotalBytes() - getUsedBytes()) / 1024);

    return true;
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
            info.sampleRate = 16000; // Standard 16 kHz
            
            size_t pcmBytes = (info.fileSize > 44) ? (info.fileSize - 44) : 0;
            info.duration = (float)pcmBytes / (float)(info.sampleRate * sizeof(int16_t));

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
