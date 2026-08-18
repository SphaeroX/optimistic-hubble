#include "audio_recorder.h"
#include <driver/i2s.h>

AudioRecorder::AudioRecorder(uint8_t ledPin)
    : _ledPin(ledPin), _recording(false), _currentClipId(0), 
      _totalCompressedBytesWritten(0), _totalFramesRecorded(0), 
      _recordStartTime(0),
      _dcPrevXL(0.0f), _dcPrevYL(0.0f),
      _dcPrevXR(0.0f), _dcPrevYR(0.0f),
      _flashBufferIndex(0) {}

AudioRecorder::~AudioRecorder() {
    stopRecording();
}

bool AudioRecorder::begin() {
    pinMode(_ledPin, OUTPUT);
    setLed(false);
    _recording = false;
    _totalCompressedBytesWritten = 0;
    _totalFramesRecorded = 0;
    _flashBufferIndex = 0;
    _dcPrevXL = _dcPrevYL = 0.0f;
    _dcPrevXR = _dcPrevYR = 0.0f;
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

void AudioRecorder::writeWavHeader(File& file, size_t adpcmDataBytes, size_t totalFrames, uint32_t sampleRate) {
    uint16_t numChannels = 2;     // True Stereo (Left = Mic 1, Right = Mic 2)
    uint16_t bitsPerSample = 4;   // 4-Bit ADPCM per channel
    uint32_t byteRate = (sampleRate * numChannels * bitsPerSample) / 8; // 16000 B/s @ 16 kHz
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
    header[48] = (uint8_t)(totalFrames & 0xFF);
    header[49] = (uint8_t)((totalFrames >> 8) & 0xFF);
    header[50] = (uint8_t)((totalFrames >> 16) & 0xFF);
    header[51] = (uint8_t)((totalFrames >> 24) & 0xFF);

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
    _totalFramesRecorded = 0;
    _flashBufferIndex = 0;
    
    _dcPrevXL = _dcPrevYL = 0.0f;
    _dcPrevXR = _dcPrevYR = 0.0f;
    _encoderLeft.reset();
    _encoderRight.reset();

    char filename[32];
    snprintf(filename, sizeof(filename), "/clip_%03u.wav", _currentClipId);

    _activeFile = LittleFS.open(filename, FILE_WRITE);
    if (!_activeFile) {
        Serial.printf("[RECORDER] Error: Could not open %s for writing!\n", filename);
        return false;
    }

    // Reserve 60 bytes for Stereo IMA ADPCM WAV header
    uint8_t dummyHeader[60] = {0};
    _activeFile.write(dummyHeader, 60);

    _recording = true;
    _recordStartTime = millis();
    setLed(true);

    Serial.printf("[RECORDER] Recording True Stereo Dual-Mic Audio (16 KB/s) -> %s\n", filename);
    return true;
}

bool AudioRecorder::processRecording(I2sMicDriver& mic) {
    if (!_recording || !_activeFile) {
        return false;
    }

    // Drain I2S hardware queue completely
    static int32_t rawChunk[256 * 2];
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

            // Channel 1 (Left Mic) DC-blocking filter
            float xL = (float)sampleL16;
            float yL = xL - _dcPrevXL + (0.995f * _dcPrevYL);
            _dcPrevXL = xL;
            _dcPrevYL = yL;
            if (yL > 32767.0f) yL = 32767.0f;
            else if (yL < -32768.0f) yL = -32768.0f;
            int16_t cleanL = (int16_t)yL;

            // Channel 2 (Right Mic) DC-blocking filter
            float xR = (float)sampleR16;
            float yR = xR - _dcPrevXR + (0.995f * _dcPrevYR);
            _dcPrevXR = xR;
            _dcPrevYR = yR;
            if (yR > 32767.0f) yR = 32767.0f;
            else if (yR < -32768.0f) yR = -32768.0f;
            int16_t cleanR = (int16_t)yR;

            // Encode both channels independently with 4-bit IMA ADPCM
            uint8_t nibbleL = _encoderLeft.encodeSample(cleanL);
            uint8_t nibbleR = _encoderRight.encodeSample(cleanR);
            _totalFramesRecorded++;

            // Pack 1 Left nibble + 1 Right nibble into 1 byte per stereo frame
            uint8_t stereoByte = (nibbleL & 0x0F) | ((nibbleR & 0x0F) << 4);

            _flashWriteBuffer[_flashBufferIndex++] = stereoByte;
            if (_flashBufferIndex >= FLASH_WRITE_BUFFER_SIZE) {
                flushFlashBuffer();
            }
        }
    }

    // Safety checks: Flash limit or 5-minute timeout
    size_t freeFlash = LittleFS.totalBytes() - LittleFS.usedBytes();
    if (freeFlash < 20480 || (millis() - _recordStartTime >= 300000UL)) {
        Serial.println(F("[RECORDER] Storage limit reached. Stopping."));
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
        flushFlashBuffer();

        // Finalize 60-byte Stereo WAV header
        _activeFile.seek(0, SeekSet);
        writeWavHeader(_activeFile, _totalCompressedBytesWritten, _totalFramesRecorded, AUDIO_SAMPLE_RATE);
        _activeFile.flush();
        _activeFile.close();

        float dur = getDurationSeconds();
        Serial.printf("[RECORDER] Stereo Clip saved: %.2f s (%u frames) -> %u bytes WAV (16 KB/s).\n",
                      dur, _totalFramesRecorded, 60 + _totalCompressedBytesWritten);
    }
}
