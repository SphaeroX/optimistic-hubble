#pragma once
#include <Arduino.h>

// ============================================================================
// Hardware Pinout for Seeed Studio XIAO ESP32C3
// ============================================================================

// I2C Pins for 6-Axis IMU (LSM6DS3 / BMI160)
#define PIN_I2C_SDA             6   // XIAO D4 = GPIO 6
#define PIN_I2C_SCL             7   // XIAO D5 = GPIO 7
#define I2C_FREQUENCY           400000UL

// I2S Stereo Microphone Pins
#define PIN_I2S_SCK             2   // XIAO D0 = GPIO 2 (Bit Clock)
#define PIN_I2S_WS              3   // XIAO D1 = GPIO 3 (Word Select / LRCLK)
#define PIN_I2S_SD              4   // XIAO D2 = GPIO 4 (Serial Data In)
#define I2S_BUFFER_SAMPLES      256 // Number of stereo sample frames per read

// Optional External Status LED (Recommended on D10)
#define PIN_STATUS_LED          10  // XIAO D10 = GPIO 10

// Serial Baud Rate
#define SERIAL_BAUD_RATE        115200

// ============================================================================
// Audio Recording Parameters
// ============================================================================
#define AUDIO_SAMPLE_RATE       16000  // 16 kHz Voice sampling rate
#define AUDIO_MAX_SECONDS       5      // Maximum recording duration per clip (seconds)
#define AUDIO_BUFFER_BYTES      (AUDIO_SAMPLE_RATE * sizeof(int16_t) * AUDIO_MAX_SECONDS) // ~160 KB

// ============================================================================
// Tap & Shock Detection Parameters
// ============================================================================
#define TAP_JERK_THRESHOLD_G    1.4f   // Shock delta acceleration threshold in g
#define TAP_DEBOUNCE_MS         500    // Minimum time between tap triggers (ms)

// ============================================================================
// BLE GATT UUIDs (128-bit Custom Service)
// ============================================================================
#define BLE_DEVICE_NAME         "XIAO-Audio-Recorder"
#define BLE_SERVICE_UUID        "19b10000-e8f2-537e-4f6c-d104768a1214"
#define BLE_CHAR_STATE_UUID     "19b10001-e8f2-537e-4f6c-d104768a1214"
#define BLE_CHAR_AUDIO_UUID     "19b10002-e8f2-537e-4f6c-d104768a1214"
#define BLE_CHAR_TAP_UUID       "19b10003-e8f2-537e-4f6c-d104768a1214"

// Device Operational States
enum DeviceState : uint8_t {
    STATE_IDLE = 0,
    STATE_RECORDING = 1,
    STATE_TRANSFERRING = 2,
    STATE_DONE = 3
};
