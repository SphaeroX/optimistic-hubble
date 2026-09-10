#pragma once
#include <Arduino.h>
#include <LittleFS.h>
#include "i2s_mic_driver.h"
#include "adpcm.h"
#include "config.h"

class AudioRecorder {
public:
    AudioRecorder(uint8_t ledPin = 0xFF);
    ~AudioRecorder();

    bool begin();
    bool startRecording(uint16_t clipId, AudioQuality quality = QUALITY_MEDIUM);
    bool processRecording(I2sMicDriver& mic);
    void stopRecording();

    bool isRecording() const { return _recording; }
    size_t getRecordedBytes() const { return _totalCompressedBytesWritten; }
    size_t getRecordedSamples() const { return _totalSamplesRecorded; }
    AudioQuality getQuality() const { return _quality; }
    uint32_t getSampleRate() const {
        return (_quality == QUALITY_LOW) ? 8000 : 16000;
    }
    float getDurationSeconds() const {
        uint32_t sr = getSampleRate();
        return (sr > 0) ? ((float)_totalSamplesRecorded / (float)sr) : 0.0f;
    }
    uint16_t getCurrentClipId() const { return _currentClipId; }

    void setLed(bool state);
    void blinkLed(uint8_t times, uint16_t delayMs = 60);

private:
    uint8_t _ledPin;
    bool _recording;
    File _activeFile;
    uint16_t _currentClipId;
    AudioQuality _quality;
    size_t _totalCompressedBytesWritten;
    size_t _totalSamplesRecorded;
    unsigned long _recordStartTime;

    // Single-Line Mono ADPCM Encoder
    ImaAdpcm _encoder;
    bool _hasPendingNibble;
    uint8_t _pendingNibble;
    bool _lowQualitySkipToggle;

    // Dual-Mic DC-Blocking Filter States (Left & Right)
    float _dcPrevXL, _dcPrevYL;
    float _dcPrevXR, _dcPrevYR;

    static const size_t FLASH_WRITE_BUFFER_SIZE = 4096;
    uint8_t _flashWriteBuffer[FLASH_WRITE_BUFFER_SIZE];
    size_t _flashBufferIndex;

    bool flushFlashBuffer();
    void writeWavHeader(File& file, size_t dataBytes, size_t totalSamples, uint32_t sampleRate, AudioQuality quality);
};
