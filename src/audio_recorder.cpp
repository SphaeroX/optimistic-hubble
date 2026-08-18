#include "audio_recorder.h"
#include <driver/i2s.h>
#include <esp_heap_caps.h>

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
        // Find largest available contiguous heap block
        size_t maxAlloc = heap_caps_get_largest_free_block(MALLOC_CAP_8BIT);
        
        // Target 4 seconds = 128,000 bytes. Leave at least 50 KB for Wi-Fi & BLE stacks
        size_t desiredBytes = AUDIO_SAMPLE_RATE * sizeof(int16_t) * AUDIO_MAX_SECONDS;
        if (desiredBytes > maxAlloc - 50000) {
            desiredBytes = (maxAlloc > 70000) ? (maxAlloc - 50000) : 48000;
        }

        _maxSamples = desiredBytes / sizeof(int16_t);
        _pcmBuffer = (int16_t*)malloc(_maxSamples * sizeof(int16_t));

        if (_pcmBuffer == nullptr) {
            Serial.println(F("[RECORDER] Error: Out of memory for audio buffer!"));
            return false;
        }

        Serial.printf("[RECORDER] Allocated %u samples (%.2f s, %u bytes). Free heap: %u\n", 
                      _maxSamples, (float)_maxSamples / AUDIO_SAMPLE_RATE, 
                      _maxSamples * sizeof(int16_t), ESP.getFreeHeap());
    }

    _recordedSamples = 0;
    _recording = false;
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

bool AudioRecorder::startRecording() {
    if (_pcmBuffer == nullptr) {
        if (!begin()) return false;
    }

    _recordedSamples = 0;
    _recording = true;
    _recordStartTime = millis();
    setLed(true);
    return true;
}

bool AudioRecorder::processRecording(I2sMicDriver& mic) {
    if (!_recording || _pcmBuffer == nullptr) {
        return false;
    }

    static int32_t rawChunk[128 * 2]; // 128 stereo frames
    size_t bytesRead = 0;
    esp_err_t err = i2s_read(I2S_NUM_0, rawChunk, sizeof(rawChunk), &bytesRead, pdMS_TO_TICKS(10));

    if (err == ESP_OK && bytesRead > 0) {
        size_t frameCount = bytesRead / (2 * sizeof(int32_t));

        for (size_t i = 0; i < frameCount; ++i) {
            if (_recordedSamples >= _maxSamples) {
                stopRecording();
                return false;
            }

            int32_t leftSample = rawChunk[2 * i] >> 8;
            int32_t rightSample = rawChunk[2 * i + 1] >> 8;
            int32_t mixed = (leftSample + rightSample) / 2;
            int16_t sample16 = (int16_t)(mixed >> 8);

            _pcmBuffer[_recordedSamples++] = sample16;
        }
    }

    if (millis() - _recordStartTime >= (AUDIO_MAX_SECONDS * 1000UL)) {
        stopRecording();
        return false;
    }

    return true;
}

void AudioRecorder::stopRecording() {
    _recording = false;
    setLed(false);
}
