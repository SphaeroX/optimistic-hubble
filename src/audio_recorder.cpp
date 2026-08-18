#include "audio_recorder.h"
#include <driver/i2s.h>

AudioRecorder::AudioRecorder(uint8_t ledPin)
    : _ledPin(ledPin), _recording(false), _currentClipId(0), 
      _totalPcmBytesWritten(0), _recordStartTime(0) {}

AudioRecorder::~AudioRecorder() {
    stopRecording();
}

bool AudioRecorder::begin() {
    pinMode(_ledPin, OUTPUT);
    setLed(false);
    _recording = false;
    _totalPcmBytesWritten = 0;
    return true;
}

void AudioRecorder::setLed(bool state) {
    digitalWrite(_ledPin, state ? HIGH : LOW);
}

void AudioRecorder::blinkLed(uint8_t times, uint16_t delayMs) {
    for (uint8_t i = 0; i < times; ++i) {
        setLed(true);
        delay(delayMs);
        setLed(false);
        delay(delayMs);
    }
}

void AudioRecorder::writeWavHeader(File& file, size_t pcmBytes, uint32_t sampleRate) {
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

bool AudioRecorder::startRecording(uint16_t clipId) {
    if (_recording) {
        stopRecording();
    }

    _currentClipId = clipId;
    _totalPcmBytesWritten = 0;

    char filename[32];
    snprintf(filename, sizeof(filename), "/clip_%03u.wav", _currentClipId);

    _activeFile = LittleFS.open(filename, FILE_WRITE);
    if (!_activeFile) {
        Serial.printf("[RECORDER] Error: Could not open %s for writing!\n", filename);
        return false;
    }

    // Reserve 44 bytes for WAV header (will be filled on stop)
    uint8_t dummyHeader[44] = {0};
    _activeFile.write(dummyHeader, 44);

    _recording = true;
    _recordStartTime = millis();
    setLed(true);

    Serial.printf("[RECORDER] Streaming real-time audio directly to %s...\n", filename);
    return true;
}

bool AudioRecorder::processRecording(I2sMicDriver& mic) {
    if (!_recording || !_activeFile) {
        return false;
    }

    // Read audio chunk from I2S (128 stereo samples)
    static int32_t rawChunk[128 * 2];
    size_t bytesRead = 0;
    esp_err_t err = i2s_read(I2S_NUM_0, rawChunk, sizeof(rawChunk), &bytesRead, pdMS_TO_TICKS(10));

    if (err == ESP_OK && bytesRead > 0) {
        size_t frameCount = bytesRead / (2 * sizeof(int32_t));
        int16_t pcmBuffer[128];

        for (size_t i = 0; i < frameCount; ++i) {
            int32_t leftSample = rawChunk[2 * i] >> 8;
            int32_t rightSample = rawChunk[2 * i + 1] >> 8;
            int32_t mixed = (leftSample + rightSample) / 2;
            pcmBuffer[i] = (int16_t)(mixed >> 8);
        }

        size_t bytesToWrite = frameCount * sizeof(int16_t);
        size_t written = _activeFile.write((const uint8_t*)pcmBuffer, bytesToWrite);
        _totalPcmBytesWritten += written;
    }

    // Stop if 5 minutes limit reached or if flash memory is getting full (less than 40 KB free)
    size_t freeFlash = LittleFS.totalBytes() - LittleFS.usedBytes();
    if (freeFlash < 40960 || (millis() - _recordStartTime >= 300000UL)) {
        Serial.println(F("[RECORDER] Storage limit or 5-minute timeout reached. Stopping."));
        stopRecording();
        return false;
    }

    return true;
}

void AudioRecorder::stopRecording() {
    if (!_recording) return;
    _recording = false;
    setLed(false);

    if (_activeFile) {
        // Seek to 0 and write the finalized WAV header with exact byte counts
        _activeFile.seek(0, SeekSet);
        writeWavHeader(_activeFile, _totalPcmBytesWritten, AUDIO_SAMPLE_RATE);
        _activeFile.flush();
        _activeFile.close();

        float dur = getDurationSeconds();
        Serial.printf("[RECORDER] Stream finalized: %u bytes PCM (%.2f s). Total WAV: %u bytes.\n",
                      _totalPcmBytesWritten, dur, 44 + _totalPcmBytesWritten);
    }
}
