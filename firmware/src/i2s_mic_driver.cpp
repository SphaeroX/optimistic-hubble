#include "i2s_mic_driver.h"
#include "config.h"
#include <math.h>

I2sMicDriver::I2sMicDriver()
    : _initialized(false), _i2sPort(I2S_NUM_0), _dmaBuffer(nullptr), _bufferSampleCount(256) {}

bool I2sMicDriver::begin(int sckPin, int wsPin, int sdPin, uint32_t sampleRate) {
    if (_initialized) {
        stop();
    }

    _bufferSampleCount = 256;
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
        .dma_buf_count = 16,            // 16 DMA buffers for deep hardware buffering
        .dma_buf_len = 256,              // 256 samples per buffer = 256ms total DMA reserve
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
    Serial.printf("[I2S Driver] Started at %u Hz (Stereo 32-bit DMA). Deep buffers: %u x %u\n", 
                  sampleRate, i2s_config.dma_buf_count, i2s_config.dma_buf_len);
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
    esp_err_t err = i2s_read(_i2sPort, _dmaBuffer, _bufferSampleCount * 2 * sizeof(int32_t), &bytesRead, 0);
    if (err != ESP_OK || bytesRead == 0) {
        return false;
    }

    size_t frameCount = bytesRead / (2 * sizeof(int32_t));
    if (frameCount == 0) return false;

    double leftSumSq = 0;
    double rightSumSq = 0;
    int32_t leftPeak = 0;
    int32_t rightPeak = 0;

    for (size_t i = 0; i < frameCount; ++i) {
        int32_t rawL = _dmaBuffer[2 * i] >> 8;
        int32_t rawR = _dmaBuffer[2 * i + 1] >> 8;

        int32_t absL = abs(rawL);
        int32_t absR = abs(rawR);

        if (absL > leftPeak) leftPeak = absL;
        if (absR > rightPeak) rightPeak = absR;

        leftSumSq += (double)rawL * (double)rawL;
        rightSumSq += (double)rawR * (double)rawR;
    }

    metrics.leftRms = (float)sqrt(leftSumSq / frameCount);
    metrics.rightRms = (float)sqrt(rightSumSq / frameCount);
    metrics.leftPeak = (float)leftPeak;
    metrics.rightPeak = (float)rightPeak;

    return true;
}

void I2sMicDriver::formatVuBar(char* outStr, size_t maxLen, float rmsValue, float maxScale, size_t barWidth) {
    if (maxLen == 0) return;
    if (maxScale <= 0) maxScale = 1.0f;

    float ratio = rmsValue / maxScale;
    if (ratio < 0.0f) ratio = 0.0f;
    if (ratio > 1.0f) ratio = 1.0f;

    size_t filled = (size_t)(ratio * barWidth);
    if (filled > barWidth) filled = barWidth;

    size_t idx = 0;
    outStr[idx++] = '[';
    for (size_t i = 0; i < barWidth && idx < maxLen - 2; ++i) {
        outStr[idx++] = (i < filled) ? '#' : '.';
    }
    outStr[idx++] = ']';
    outStr[idx] = '\0';
}
