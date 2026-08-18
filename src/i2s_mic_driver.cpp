#include "i2s_mic_driver.h"
#include "config.h"
#include <math.h>

I2sMicDriver::I2sMicDriver()
    : _initialized(false), _i2sPort(I2S_NUM_0), _dmaBuffer(nullptr), _bufferSampleCount(I2S_BUFFER_SAMPLES) {}

bool I2sMicDriver::begin(int sckPin, int wsPin, int sdPin, uint32_t sampleRate) {
    if (_initialized) {
        stop();
    }

    _bufferSampleCount = I2S_BUFFER_SAMPLES;
    if (_dmaBuffer == nullptr) {
        _dmaBuffer = (int32_t*)malloc(_bufferSampleCount * 2 * sizeof(int32_t)); // 2 channels (Stereo)
        if (_dmaBuffer == nullptr) {
            return false;
        }
    }

    i2s_config_t i2s_config = {
        .mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_RX),
        .sample_rate = sampleRate,
        .bits_per_sample = I2S_BITS_PER_SAMPLE_32BIT,
        .channel_format = I2S_CHANNEL_FMT_RIGHT_LEFT, // Stereo: Left (GND) + Right (3.3V)
        .communication_format = I2S_COMM_FORMAT_STAND_I2S,
        .intr_alloc_flags = ESP_INTR_FLAG_LEVEL1,
        .dma_buf_count = 4,
        .dma_buf_len = (int)_bufferSampleCount,
        .use_apll = false,
        .tx_desc_auto_clear = false,
        .fixed_mclk = 0
    };

    i2s_pin_config_t pin_config = {
        .bck_io_num = sckPin,
        .ws_io_num = wsPin,
        .data_out_num = I2S_PIN_NO_CHANGE,
        .data_in_num = sdPin
    };

    esp_err_t err = i2s_driver_install(_i2sPort, &i2s_config, 0, NULL);
    if (err != ESP_OK) {
        return false;
    }

    err = i2s_set_pin(_i2sPort, &pin_config);
    if (err != ESP_OK) {
        i2s_driver_uninstall(_i2sPort);
        return false;
    }

    i2s_start(_i2sPort);

    // Warm-up discard to let MEMS mic clocks settle
    delay(100);
    size_t bytesRead = 0;
    i2s_read(_i2sPort, _dmaBuffer, _bufferSampleCount * 2 * sizeof(int32_t), &bytesRead, pdMS_TO_TICKS(100));

    _initialized = true;
    return true;
}

void I2sMicDriver::stop() {
    if (_initialized) {
        i2s_stop(_i2sPort);
        i2s_driver_uninstall(_i2sPort);
        _initialized = false;
    }
    if (_dmaBuffer != nullptr) {
        free(_dmaBuffer);
        _dmaBuffer = nullptr;
    }
}

bool I2sMicDriver::readMetrics(StereoAudioMetrics& metrics) {
    if (!_initialized || _dmaBuffer == nullptr) {
        return false;
    }

    size_t bytesRead = 0;
    size_t bytesToRead = _bufferSampleCount * 2 * sizeof(int32_t);
    esp_err_t err = i2s_read(_i2sPort, _dmaBuffer, bytesToRead, &bytesRead, pdMS_TO_TICKS(100));

    if (err != ESP_OK || bytesRead == 0) {
        return false;
    }

    size_t sampleCount = bytesRead / (2 * sizeof(int32_t));
    if (sampleCount == 0) {
        return false;
    }

    double sumSqLeft = 0.0;
    double sumSqRight = 0.0;
    int32_t minL = INT32_MAX, maxL = INT32_MIN;
    int32_t minR = INT32_MAX, maxR = INT32_MIN;

    for (size_t i = 0; i < sampleCount; ++i) {
        // INMP441 is 24-bit data MSB-aligned in 32-bit slot
        // Shift right by 8 to normalize to signed 24-bit integer
        int32_t rawLeft = _dmaBuffer[2 * i] >> 8;
        int32_t rawRight = _dmaBuffer[2 * i + 1] >> 8;

        // Peak tracking
        if (rawLeft < minL) minL = rawLeft;
        if (rawLeft > maxL) maxL = rawLeft;

        if (rawRight < minR) minR = rawRight;
        if (rawRight > maxR) maxR = rawRight;

        // Sum of squares for RMS calculation
        sumSqLeft += ((double)rawLeft * (double)rawLeft);
        sumSqRight += ((double)rawRight * (double)rawRight);
    }

    metrics.leftRms = sqrt(sumSqLeft / (double)sampleCount);
    metrics.rightRms = sqrt(sumSqRight / (double)sampleCount);

    metrics.leftPeak = (maxL > minL) ? (maxL - minL) : 0;
    metrics.rightPeak = (maxR > minR) ? (maxR - minR) : 0;

    // Relative dBFS calculation (reference 24-bit full scale 8388607)
    const float fullScale24Bit = 8388607.0f;
    metrics.leftDb = (metrics.leftRms > 1.0f) ? (20.0f * log10f(metrics.leftRms / fullScale24Bit)) : -96.0f;
    metrics.rightDb = (metrics.rightRms > 1.0f) ? (20.0f * log10f(metrics.rightRms / fullScale24Bit)) : -96.0f;

    // Active detection: RMS > threshold
    const float ACTIVITY_THRESHOLD = 1500.0f;
    metrics.leftActive = (metrics.leftRms > ACTIVITY_THRESHOLD);
    metrics.rightActive = (metrics.rightRms > ACTIVITY_THRESHOLD);

    return true;
}

void I2sMicDriver::formatVuBar(char* buffer, size_t maxLen, float rmsValue, float maxScale, size_t barWidth) {
    if (buffer == nullptr || maxLen < barWidth + 3) {
        return;
    }

    float ratio = rmsValue / maxScale;
    if (ratio < 0.0f) ratio = 0.0f;
    if (ratio > 1.0f) ratio = 1.0f;

    size_t activeChars = (size_t)(ratio * (float)barWidth);
    if (rmsValue > 500.0f && activeChars == 0) {
        activeChars = 1; // Show at least 1 tick if above baseline noise
    }

    buffer[0] = '[';
    for (size_t i = 0; i < barWidth; ++i) {
        buffer[i + 1] = (i < activeChars) ? '#' : '.';
    }
    buffer[barWidth + 1] = ']';
    buffer[barWidth + 2] = '\0';
}
