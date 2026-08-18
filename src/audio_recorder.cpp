#include "audio_recorder.h"
#include <driver/i2s.h>

AudioRecorder::AudioRecorder(uint8_t ledPin)
    : _ledPin(ledPin), _recording(false), _pcmBuffer(nullptr), 
      _maxSamples(AUDIO_SAMPLE_RATE * AUDIO_MAX_SECONDS), _recordedSamples(0), _recordStartTime(0) {}

AudioRecorder::~AudioRecorder() {
    if (_pcmBuffer != nullptr) {
        free(_pcmBuffer);
        _pcmBuffer = nullptr;
    }
}

bool AudioRecorder::begin() {
    pinMode(_ledPin, OUTPUT);
    setLed(false);

    if (_pcmBuffer == nullptr) {
        // Try allocating buffer; if heap is tight, scale down to fit safely
        size_t targetSamples = _maxSamples;
        _pcmBuffer = (int16_t*)malloc(targetSamples * sizeof(int16_t));
        
        while (_pcmBuffer == nullptr && targetSamples >= (AUDIO_SAMPLE_RATE * 3)) {
            targetSamples -= AUDIO_SAMPLE_RATE; // Reduce by 1 second
            _pcmBuffer = (int16_t*)malloc(targetSamples * sizeof(int16_t));
        }

        if (_pcmBuffer == nullptr) {
            return false;
        }
        _maxSamples = targetSamples;
    }

    _recordedSamples = 0;
    _recording = false;
    return true;
}

void AudioRecorder::setLed(bool state) {
    // Active-HIGH standard output
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

bool AudioRecorder::startRecording() {
    if (_pcmBuffer == nullptr) {
        if (!begin()) return false;
    }

    _recordedSamples = 0;
    _recording = true;
    _recordStartTime = millis();
    setLed(true); // Light up LED
    return true;
}

bool AudioRecorder::processRecording(I2sMicDriver& mic) {
    if (!_recording || _pcmBuffer == nullptr) {
        return false;
    }

    // Read audio chunk from I2S
    static int32_t rawChunk[256 * 2]; // 256 stereo frames
    size_t bytesRead = 0;
    esp_err_t err = i2s_read(I2S_NUM_0, rawChunk, sizeof(rawChunk), &bytesRead, pdMS_TO_TICKS(10));

    if (err == ESP_OK && bytesRead > 0) {
        size_t frameCount = bytesRead / (2 * sizeof(int32_t));

        for (size_t i = 0; i < frameCount; ++i) {
            if (_recordedSamples >= _maxSamples) {
                // Buffer full, auto stop
                stopRecording();
                return false;
            }

            // Extract Left & Right 24-bit samples
            int32_t leftSample = rawChunk[2 * i] >> 8;
            int32_t rightSample = rawChunk[2 * i + 1] >> 8;

            // Downsample / Mix to 16-bit mono
            int32_t mixed = (leftSample + rightSample) / 2;
            
            // Scale 24-bit (-8388608..8388607) down to 16-bit (-32768..32767)
            int16_t sample16 = (int16_t)(mixed >> 8);

            _pcmBuffer[_recordedSamples++] = sample16;
        }
    }

    // Check maximum time limit
    if (millis() - _recordStartTime >= (AUDIO_MAX_SECONDS * 1000UL)) {
        stopRecording();
        return false;
    }

    return true;
}

void AudioRecorder::stopRecording() {
    _recording = false;
    setLed(false); // Turn off LED
}
