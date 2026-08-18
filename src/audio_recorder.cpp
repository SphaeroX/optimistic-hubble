#include "audio_recorder.h"
#include <driver/i2s.h>

AudioRecorder::AudioRecorder(uint8_t ledPin)
    : _ledPin(ledPin), _recording(false), _currentClipId(0), 
      _totalCompressedBytesWritten(0), _totalSamplesRecorded(0), 
      _recordStartTime(0), _hasPendingNibble(false), _pendingNibble(0),
      _dcPrevX(0.0f), _dcPrevY(0.0f), _flashBufferIndex(0) {}

AudioRecorder::~AudioRecorder() {
    stopRecording();
}

bool AudioRecorder::begin() {
    pinMode(_ledPin, OUTPUT);
    setLed(false);
    _recording = false;
    _totalCompressedBytesWritten = 0;
    _totalSamplesRecorded = 0;
    _flashBufferIndex = 0;
    _hasPendingNibble = false;
    _dcPrevX = 0.0f;
    _dcPrevY = 0.0f;
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

void AudioRecorder::writeWavHeader(File& file, size_t adpcmDataBytes, size_t totalSamples, uint32_t sampleRate) {
    uint16_t numChannels = 1;     // Mono
    uint16_t bitsPerSample = 4;   // 4-Bit ADPCM
    uint32_t byteRate = (sampleRate * numChannels * bitsPerSample) / 8; // 8000 B/s @ 16 kHz
    uint16_t blockAlign = 1;
    uint32_t chunkSize = 36 + 14 + adpcmDataBytes;

    uint8_t header[60];
    memset(header, 0, sizeof(header));

    // RIFF Chunk
    header[0] = 'R'; header[1] = 'I'; header[2] = 'F'; header[3] = 'F';
    header[4] = (uint8_t)(chunkSize & 0xFF);
    header[5] = (uint8_t)((chunkSize >> 8) & 0xFF);
    header[6] = (uint8_t)((chunkSize >> 16) & 0xFF);
    header[7] = (uint8_t)((chunkSize >> 24) & 0xFF);
    header[8] = 'W'; header[9] = 'A'; header[10] = 'V'; header[11] = 'E';

    // fmt subchunk
    header[12] = 'f'; header[13] = 'm'; header[14] = 't'; header[15] = ' ';
    header[16] = 20; header[17] = 0; header[18] = 0; header[19] = 0;
    header[20] = 0x11; header[21] = 0x00; // Format 0x0011: IMA ADPCM
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
    header[36] = 2; header[37] = 0; // cbSize = 2
    header[38] = 1; header[39] = 0; // wSamplesPerBlock = 1

    // fact subchunk
    header[40] = 'f'; header[41] = 'a'; header[42] = 'c'; header[43] = 't';
    header[44] = 4; header[45] = 0; header[46] = 0; header[47] = 0;
    header[48] = (uint8_t)(totalSamples & 0xFF);
    header[49] = (uint8_t)((totalSamples >> 8) & 0xFF);
    header[50] = (uint8_t)((totalSamples >> 16) & 0xFF);
    header[51] = (uint8_t)((totalSamples >> 24) & 0xFF);

    // data subchunk
    header[52] = 'd'; header[53] = 'a'; header[54] = 't'; header[55] = 'a';
    header[56] = (uint8_t)(adpcmDataBytes & 0xFF);
    header[57] = (uint8_t)((adpcmDataBytes >> 8) & 0xFF);
    header[58] = (uint8_t)((adpcmDataBytes >> 16) & 0xFF);
    header[59] = (uint8_t)((adpcmDataBytes >> 24) & 0xFF);

    file.write(header, 60);
}

void AudioRecorder::flushFlashBuffer() {
    if (_activeFile && _flashBufferIndex > 0) {
        size_t written = _activeFile.write(_flashWriteBuffer, _flashBufferIndex);
        _totalCompressedBytesWritten += written;
        _flashBufferIndex = 0;
    }
}

bool AudioRecorder::startRecording(uint16_t clipId) {
    if (_recording) {
        stopRecording();
    }

    _currentClipId = clipId;
    _totalCompressedBytesWritten = 0;
    _totalSamplesRecorded = 0;
    _flashBufferIndex = 0;
    _hasPendingNibble = false;
    _dcPrevX = 0.0f;
    _dcPrevY = 0.0f;
    _encoder.reset();

    char filename[32];
    snprintf(filename, sizeof(filename), "/clip_%03u.wav", _currentClipId);

    _activeFile = LittleFS.open(filename, FILE_WRITE);
    if (!_activeFile) {
        Serial.printf("[RECORDER] Error: Could not open %s for writing!\n", filename);
        return false;
    }

    // Reserve 60 bytes for IMA ADPCM WAV header
    uint8_t dummyHeader[60] = {0};
    _activeFile.write(dummyHeader, 60);

    _recording = true;
    _recordStartTime = millis();
    setLed(true);

    Serial.printf("[RECORDER] Continuous clean stream recording started -> %s\n", filename);
    return true;
}

bool AudioRecorder::processRecording(I2sMicDriver& mic) {
    if (!_recording || !_activeFile) {
        return false;
    }

    // Completely drain all pending audio frames from I2S hardware queue
    // to guarantee 0% dropped frames, no cracks, and no temporal skipping!
    static int32_t rawChunk[256 * 2];
    while (true) {
        size_t bytesRead = 0;
        esp_err_t err = i2s_read(I2S_NUM_0, rawChunk, sizeof(rawChunk), &bytesRead, 0);

        if (err != ESP_OK || bytesRead == 0) {
            break;
        }

        size_t frameCount = bytesRead / (2 * sizeof(int32_t));

        for (size_t i = 0; i < frameCount; ++i) {
            // Dual-mic downmix
            int32_t leftSample = rawChunk[2 * i] >> 8;
            int32_t rightSample = rawChunk[2 * i + 1] >> 8;
            int32_t mixed = (leftSample + rightSample) / 2;
            int16_t raw16 = (int16_t)(mixed >> 8);

            // DC-blocking filter (fc ~ 15 Hz @ 16 kHz): y[n] = x[n] - x[n-1] + 0.995 * y[n-1]
            float x = (float)raw16;
            float y = x - _dcPrevX + (0.995f * _dcPrevY);
            _dcPrevX = x;
            _dcPrevY = y;

            if (y > 32767.0f) y = 32767.0f;
            else if (y < -32768.0f) y = -32768.0f;
            int16_t cleanSample16 = (int16_t)y;

            // Compress sample with 4-bit IMA ADPCM
            uint8_t nibble = _encoder.encodeSample(cleanSample16);
            _totalSamplesRecorded++;

            if (!_hasPendingNibble) {
                _pendingNibble = (nibble & 0x0F);
                _hasPendingNibble = true;
            } else {
                uint8_t packedByte = _pendingNibble | ((nibble & 0x0F) << 4);
                _hasPendingNibble = false;

                _flashWriteBuffer[_flashBufferIndex++] = packedByte;
                if (_flashBufferIndex >= FLASH_WRITE_BUFFER_SIZE) {
                    flushFlashBuffer();
                }
            }
        }
    }

    // Safety checks: Flash limit or 5-minute timeout
    size_t freeFlash = LittleFS.totalBytes() - LittleFS.usedBytes();
    if (freeFlash < 20480 || (millis() - _recordStartTime >= 300000UL)) {
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
        if (_hasPendingNibble) {
            _flashWriteBuffer[_flashBufferIndex++] = _pendingNibble;
            _hasPendingNibble = false;
        }

        flushFlashBuffer();

        // Finalize 60-byte WAV header
        _activeFile.seek(0, SeekSet);
        writeWavHeader(_activeFile, _totalCompressedBytesWritten, _totalSamplesRecorded, AUDIO_SAMPLE_RATE);
        _activeFile.flush();
        _activeFile.close();

        float dur = getDurationSeconds();
        Serial.printf("[RECORDER] Seamless audio saved: %.2f s (%u samples) -> %u bytes WAV (8 KB/s).\n",
                      dur, _totalSamplesRecorded, 60 + _totalCompressedBytesWritten);
    }
}
