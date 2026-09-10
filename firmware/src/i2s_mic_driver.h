#pragma once
#include <Arduino.h>
#include <driver/i2s.h>

struct StereoAudioMetrics {
    float leftRms;         // Root Mean Square amplitude (Left channel / Mic 1)
    float rightRms;        // Root Mean Square amplitude (Right channel / Mic 2)
    int32_t leftPeak;      // Peak-to-peak amplitude (Left)
    int32_t rightPeak;     // Peak-to-peak amplitude (Right)
    float leftDb;          // Relative dBFS level (0 to -96 dB)
    float rightDb;         // Relative dBFS level (0 to -96 dB)
    bool leftActive;       // True if audio detected above noise floor
    bool rightActive;      // True if audio detected above noise floor
};

class I2sMicDriver {
public:
    I2sMicDriver();

    bool begin(int sckPin, int wsPin, int sdPin, uint32_t sampleRate = 16000);
    bool readMetrics(StereoAudioMetrics& metrics);
    void stop();
    bool isInitialized() const { return _initialized; }
    uint32_t getSampleRate() const { return _sampleRate; }

    static void formatVuBar(char* buffer, size_t maxLen, float rmsValue, float maxScale = 50000.0f, size_t barWidth = 15);

private:
    bool _initialized;
    uint32_t _sampleRate;
    i2s_port_t _i2sPort;
    int32_t* _dmaBuffer;
    size_t _bufferSampleCount;
};
