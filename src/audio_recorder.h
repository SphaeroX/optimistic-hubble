#pragma once
#include <Arduino.h>
#include "i2s_mic_driver.h"
#include "config.h"

class AudioRecorder {
public:
    AudioRecorder(uint8_t ledPin = PIN_STATUS_LED);
    ~AudioRecorder();

    bool begin();
    bool startRecording();
    bool processRecording(I2sMicDriver& mic);
    void stopRecording();

    bool isRecording() const { return _recording; }
    const uint8_t* getBuffer() const { return (const uint8_t*)_pcmBuffer; }
    size_t getRecordedBytes() const { return _recordedSamples * sizeof(int16_t); }
    size_t getRecordedSamples() const { return _recordedSamples; }
    uint32_t getSampleRate() const { return AUDIO_SAMPLE_RATE; }
    float getDurationSeconds() const { return (float)_recordedSamples / (float)AUDIO_SAMPLE_RATE; }

    void setLed(bool state);
    void blinkLed(uint8_t times, uint16_t delayMs = 60);

private:
    uint8_t _ledPin;
    bool _recording;
    int16_t* _pcmBuffer;
    size_t _maxSamples;
    size_t _recordedSamples;
    unsigned long _recordStartTime;
};
