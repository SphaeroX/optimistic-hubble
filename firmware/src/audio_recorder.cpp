#include "audio_recorder.h"
#include <driver/i2s.h>

AudioRecorder::AudioRecorder(uint8_t ledPin)
    : _ledPin(ledPin), _recording(false), _currentClipId(0), 
      _quality(QUALITY_MEDIUM),
      _totalCompressedBytesWritten(0), _totalSamplesRecorded(0), 
      _recordStartTime(0),
      _hasPendingNibble(false), _pendingNibble(0),
      _lowQualitySkipToggle(false),
      _dcPrevXL(0.0f), _dcPrevYL(0.0f),
      _dcPrevXR(0.0f), _dcPrevYR(0.0f),
      _flashBufferIndex(0) {}

AudioRecorder::~AudioRecorder() {
    stopRecording();
}

bool AudioRecorder::begin() {
    if (_ledPin != 0xFF) {
        pinMode(_ledPin, OUTPUT);
        setLed(false);
    }
    _recording = false;
    _totalCompressedBytesWritten = 0;
    _totalSamplesRecorded = 0;
    _flashBufferIndex = 0;
    _hasPendingNibble = false;
    _lowQualitySkipToggle = false;
    _dcPrevXL = _dcPrevYL = 0.0f;
    _dcPrevXR = _dcPrevYR = 0.0f;
    return true;
}

void AudioRecorder::setLed(bool state) {
    if (_ledPin == 0xFF) return;
    // Active-LOW logic: LOW = ON, HIGH = OFF
    digitalWrite(_ledPin, state ? LED_LEVEL_ON : LED_LEVEL_OFF);
}

void AudioRecorder::blinkLed(uint8_t times, uint16_t delayMs) {
    for (uint8_t i = 0; i < times; ++i) {
        setLed(true);
        delay(delayMs);
        setLed(false);
        delay(delayMs);
    }
}

void AudioRecorder::writeWavHeader(File& file, size_t dataBytes, size_t totalSamples, uint32_t sampleRate, AudioQuality quality) {
    uint16_t numChannels = 1; // Single-Line Mono (Beamformed from Dual-Mics)

    if (quality == QUALITY_HIGH) {
        // Standard 44-byte Linear PCM Header (16-bit, 16 kHz mono = 32 KB/s)
        uint16_t bitsPerSample = 16;
        uint32_t byteRate = (sampleRate * numChannels * bitsPerSample) / 8; // 32000 B/s
        uint16_t blockAlign = (numChannels * bitsPerSample) / 8; // 2
        uint32_t chunkSize = 36 + dataBytes;

        uint8_t header[44];
        memset(header, 0, sizeof(header));

        header[0] = 'R'; header[1] = 'I'; header[2] = 'F'; header[3] = 'F';
        header[4] = (uint8_t)(chunkSize & 0xFF);
        header[5] = (uint8_t)((chunkSize >> 8) & 0xFF);
        header[6] = (uint8_t)((chunkSize >> 16) & 0xFF);
        header[7] = (uint8_t)((chunkSize >> 24) & 0xFF);
        header[8] = 'W'; header[9] = 'A'; header[10] = 'V'; header[11] = 'E';

        header[12] = 'f'; header[13] = 'm'; header[14] = 't'; header[15] = ' ';
        header[16] = 16; header[17] = 0; header[18] = 0; header[19] = 0; // fmt size: 16
        header[20] = 1; header[21] = 0; // Format 1: Linear PCM
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

        header[36] = 'd'; header[37] = 'a'; header[38] = 't'; header[39] = 'a';
        header[40] = (uint8_t)(dataBytes & 0xFF);
        header[41] = (uint8_t)((dataBytes >> 8) & 0xFF);
        header[42] = (uint8_t)((dataBytes >> 16) & 0xFF);
        header[43] = (uint8_t)((dataBytes >> 24) & 0xFF);

        file.write(header, 44);
    } else {
        // Standard 60-byte IMA-ADPCM Header (4-bit, 16 kHz or 8 kHz mono = 8 KB/s or 4 KB/s)
        uint16_t bitsPerSample = 4;
        uint32_t byteRate = (sampleRate * numChannels * bitsPerSample) / 8; // 8000 B/s or 4000 B/s
        uint16_t blockAlign = 1;
        uint32_t chunkSize = 36 + 14 + dataBytes;

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
        header[16] = 20; header[17] = 0; header[18] = 0; header[19] = 0; // fmt size: 20
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
        header[56] = (uint8_t)(dataBytes & 0xFF);
        header[57] = (uint8_t)((dataBytes >> 8) & 0xFF);
        header[58] = (uint8_t)((dataBytes >> 16) & 0xFF);
        header[59] = (uint8_t)((dataBytes >> 24) & 0xFF);

        file.write(header, 60);
    }
}

bool AudioRecorder::flushFlashBuffer() {
    if (_activeFile && _flashBufferIndex > 0) {
        size_t written = _activeFile.write(_flashWriteBuffer, _flashBufferIndex);
        _totalCompressedBytesWritten += written;
        bool ok = (written == _flashBufferIndex);
        _flashBufferIndex = 0;
        if (!ok) {
            Serial.println(F("[RECORDER] Flash write failed! Out of disk space."));
            return false;
        }
    }
    return true;
}

bool AudioRecorder::startRecording(uint16_t clipId, AudioQuality quality) {
    if (_recording) {
        stopRecording();
    }

    size_t total = LittleFS.totalBytes();
    size_t used = LittleFS.usedBytes();
    size_t freeFlash = (total > used) ? (total - used) : 0;
    if (freeFlash < MIN_FREE_STORAGE_BYTES) {
        Serial.printf("[RECORDER] Error: Flash full! Free: %u B < limit %u B\n", (unsigned int)freeFlash, (unsigned int)MIN_FREE_STORAGE_BYTES);
        blinkLed(4, 50);
        return false;
    }

    _currentClipId = clipId;
    _quality = quality;
    _totalCompressedBytesWritten = 0;
    _totalSamplesRecorded = 0;
    _flashBufferIndex = 0;
    _hasPendingNibble = false;
    _lowQualitySkipToggle = false;
    
    _dcPrevXL = _dcPrevYL = 0.0f;
    _dcPrevXR = _dcPrevYR = 0.0f;
    _encoder.reset();

    char filename[32];
    snprintf(filename, sizeof(filename), "/clip_%03u.wav", _currentClipId);

    _activeFile = LittleFS.open(filename, FILE_WRITE);
    if (!_activeFile) {
        Serial.printf("[RECORDER] Error: Could not open %s for writing!\n", filename);
        return false;
    }

    // Write initial valid header so file structure is immediately intact on disk
    writeWavHeader(_activeFile, 0, 0, getSampleRate(), _quality);

    _recording = true;
    _recordStartTime = millis();
    setLed(true);

    const char* qName = (_quality == QUALITY_HIGH) ? "High (16kHz PCM, 32 KB/s)" :
                        ((_quality == QUALITY_LOW) ? "Low (8kHz ADPCM, 4 KB/s)" : "Medium (16kHz ADPCM, 8 KB/s)");
    Serial.printf("[RECORDER] Starting recording -> %s | Quality: %s\n", filename, qName);
    return true;
}

bool AudioRecorder::processRecording(I2sMicDriver& mic) {
    if (!_recording || !_activeFile) {
        return false;
    }

    static int32_t rawChunk[256 * 2];
    bool writeFailed = false;

    while (true) {
        size_t bytesRead = 0;
        esp_err_t err = i2s_read(I2S_NUM_0, rawChunk, sizeof(rawChunk), &bytesRead, 0);

        if (err != ESP_OK || bytesRead == 0) {
            break;
        }

        size_t frameCount = bytesRead / (2 * sizeof(int32_t));

        for (size_t i = 0; i < frameCount; ++i) {
            // Raw 24-bit samples from Left (Mic 1) and Right (Mic 2)
            int32_t rawL = rawChunk[2 * i] >> 8;
            int32_t rawR = rawChunk[2 * i + 1] >> 8;

            int16_t sampleL16 = (int16_t)(rawL >> 8);
            int16_t sampleR16 = (int16_t)(rawR >> 8);

            // Channel 1 (Mic 1) Preamp Gain (+18 dB) + DC Filter
            float xL = (float)sampleL16 * MIC_GAIN_MULTIPLIER;
            float yL = xL - _dcPrevXL + (0.995f * _dcPrevYL);
            _dcPrevXL = xL;
            _dcPrevYL = yL;

            // Channel 2 (Mic 2) Preamp Gain (+18 dB) + DC Filter
            float xR = (float)sampleR16 * MIC_GAIN_MULTIPLIER;
            float yR = xR - _dcPrevXR + (0.995f * _dcPrevYR);
            _dcPrevXR = xR;
            _dcPrevYR = yR;

            // Real-Time Dual-Mic Coherent Beamforming: clean mono
            float mixed = (yL + yR) / 2.0f;
            if (mixed > 32767.0f) mixed = 32767.0f;
            else if (mixed < -32768.0f) mixed = -32768.0f;
            int16_t cleanSample16 = (int16_t)mixed;

            if (_quality == QUALITY_HIGH) {
                // 16-bit Linear PCM (32 KB/s)
                _totalSamplesRecorded++;
                _flashWriteBuffer[_flashBufferIndex++] = (uint8_t)(cleanSample16 & 0xFF);
                _flashWriteBuffer[_flashBufferIndex++] = (uint8_t)((cleanSample16 >> 8) & 0xFF);

                if (_flashBufferIndex >= FLASH_WRITE_BUFFER_SIZE) {
                    if (!flushFlashBuffer()) {
                        writeFailed = true;
                        break;
                    }
                }
            } else if (_quality == QUALITY_LOW) {
                // Decimate 16 kHz to 8 kHz (every 2nd sample)
                _lowQualitySkipToggle = !_lowQualitySkipToggle;
                if (_lowQualitySkipToggle) continue;

                _totalSamplesRecorded++;
                uint8_t nibble = _encoder.encodeSample(cleanSample16);
                if (!_hasPendingNibble) {
                    _pendingNibble = (nibble & 0x0F);
                    _hasPendingNibble = true;
                } else {
                    uint8_t packedByte = _pendingNibble | ((nibble & 0x0F) << 4);
                    _hasPendingNibble = false;
                    _flashWriteBuffer[_flashBufferIndex++] = packedByte;
                    if (_flashBufferIndex >= FLASH_WRITE_BUFFER_SIZE) {
                        if (!flushFlashBuffer()) {
                            writeFailed = true;
                            break;
                        }
                    }
                }
            } else {
                // QUALITY_MEDIUM: 16 kHz IMA-ADPCM (8 KB/s)
                _totalSamplesRecorded++;
                uint8_t nibble = _encoder.encodeSample(cleanSample16);
                if (!_hasPendingNibble) {
                    _pendingNibble = (nibble & 0x0F);
                    _hasPendingNibble = true;
                } else {
                    uint8_t packedByte = _pendingNibble | ((nibble & 0x0F) << 4);
                    _hasPendingNibble = false;
                    _flashWriteBuffer[_flashBufferIndex++] = packedByte;
                    if (_flashBufferIndex >= FLASH_WRITE_BUFFER_SIZE) {
                        if (!flushFlashBuffer()) {
                            writeFailed = true;
                            break;
                        }
                    }
                }
            }
        }
        if (writeFailed) break;
    }

    if (writeFailed) {
        Serial.println(F("[RECORDER] Stopping due to write error."));
        stopRecording();
        return false;
    }

    // Safety checks: Flash headroom limit or 10-minute timeout
    size_t total = LittleFS.totalBytes();
    size_t used = LittleFS.usedBytes();
    size_t freeFlash = (total > used) ? (total - used) : 0;
    if (freeFlash < MIN_FREE_STORAGE_BYTES || (millis() - _recordStartTime >= 600000UL)) {
        Serial.printf("[RECORDER] Storage limit reached (Free: %u B < %u B). Stopping safely.\n",
                      (unsigned int)freeFlash, (unsigned int)MIN_FREE_STORAGE_BYTES);
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

        // Finalize WAV header with actual recorded data length and sample count
        _activeFile.seek(0, SeekSet);
        writeWavHeader(_activeFile, _totalCompressedBytesWritten, _totalSamplesRecorded, getSampleRate(), _quality);
        _activeFile.flush();
        _activeFile.close();

        float dur = getDurationSeconds();
        Serial.printf("[RECORDER] Clean Clip saved: %.2f s (%u samples) -> %u bytes WAV.\n",
                      dur, (unsigned int)_totalSamplesRecorded,
                      (unsigned int)(((_quality == QUALITY_HIGH) ? 44 : 60) + _totalCompressedBytesWritten));
    }
}
