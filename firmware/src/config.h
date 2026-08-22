#pragma once
#include <Arduino.h>

// ============================================================================
// Hardware Pinout for Seeed Studio XIAO ESP32C3
// ============================================================================

// I2C Pins for 6-Axis IMU (LSM6DS3 / BMI160)
#define PIN_I2C_SDA 6 // XIAO D4 = GPIO 6
#define PIN_I2C_SCL 7 // XIAO D5 = GPIO 7
#define I2C_FREQUENCY 400000UL

// IMU Hardware Interrupt Wakeup Pin (RTC GPIO 5) & Boot Button (GPIO 9)
#define PIN_IMU_INT 5  // XIAO D3 = GPIO 5 (RTC IO, wakes ESP32-C3 from Deep Sleep)
#define PIN_BOOT_BTN 9 // XIAO D7 = GPIO 9 (Boot Button)

// I2S Stereo Microphone Pins
#define PIN_I2S_SCK 2          // XIAO D0 = GPIO 2 (Bit Clock)
#define PIN_I2S_WS 3           // XIAO D1 = GPIO 3 (Word Select / LRCLK)
#define PIN_I2S_SD 4           // XIAO D2 = GPIO 4 (Serial Data In)
#define I2S_BUFFER_SAMPLES 256 // Number of stereo sample frames per read

// External Status LED (Recording Indicator)
#define PIN_STATUS_LED 10 // XIAO D10 = GPIO 10

// Serial Baud Rate
#define SERIAL_BAUD_RATE 115200

// ============================================================================
// Ultra-Low-Power & Deep Sleep Parameters
// ============================================================================
#define INACTIVITY_SLEEP_TIMEOUT_MS 15000UL // 15 seconds of idle inactivity
#define WIFI_INACTIVITY_TIMEOUT_MS 120000UL // 2 minutes of idle Wi-Fi -> Stop SoftAP to save ~150 mA
#define IMU_WAKEUP_THRESHOLD_G 1.4f         // Hardware shock acceleration threshold
#define ENABLE_DEEP_SLEEP_AUTO false        // Deep Sleep disabled for active debugging

// ============================================================================
// Audio Recording & Preamp Parameters
// ============================================================================
#define AUDIO_SAMPLE_RATE 16000  // 16 kHz Voice sampling rate
#define MIC_GAIN_MULTIPLIER 8.0f // +18 dB Digital Preamp Gain (Crisp, loud & full-scale voice)

// ============================================================================
// Tap & Shock Detection Parameters
// ============================================================================
#define TAP_JERK_THRESHOLD_G 0.5f // Shock delta acceleration threshold in g
#define TAP_DEBOUNCE_MS 500       // Minimum time between tap triggers (ms)

// ============================================================================
// Wi-Fi High-Speed Audio Server Parameters
// ============================================================================
#define WIFI_AP_SSID "XIAO-Audio-Hotspot"
#define WIFI_AP_PASS "xiaoesp32c3" // WPA2 Passphrase (>= 8 chars)
#define HTTP_SERVER_PORT 80

// ============================================================================
// BLE GATT UUIDs (128-bit Custom Service)
// ============================================================================
#define BLE_DEVICE_NAME "XIAO-Audio-Recorder"
#define BLE_SERVICE_UUID "19b10000-e8f2-537e-4f6c-d104768a1214"
#define BLE_CHAR_STATE_UUID "19b10001-e8f2-537e-4f6c-d104768a1214"
#define BLE_CHAR_AUDIO_UUID "19b10002-e8f2-537e-4f6c-d104768a1214"
#define BLE_CHAR_TAP_UUID "19b10003-e8f2-537e-4f6c-d104768a1214"
#define BLE_CHAR_CMD_UUID "19b10004-e8f2-537e-4f6c-d104768a1214"

// SoftAP Watchdog Timing (Section 5.2.2)
#define SOFTAP_CONNECT_TIMEOUT_MS 60000UL // 60s timeout if no station connects
#define SOFTAP_IDLE_TIMEOUT_MS 30000UL    // 30s idle after transfer before powering off Wi-Fi

// BLE L2CAP CoC Parameters
#define BLE_L2CAP_AUDIO_PSM 0x0081

// Device Operational States
enum DeviceState : uint8_t
{
    STATE_IDLE = 0,
    STATE_RECORDING = 1,
    STATE_TRANSFERRING = 2,
    STATE_DONE = 3,
    STATE_WIFI_ACTIVE = 4,
    STATE_SLEEPING = 5
};

// Minimum free LittleFS Flash storage margin to prevent overflow (e.g., 24 KB)
#define MIN_FREE_STORAGE_BYTES 24576UL

// Remote Control Commands (via BLE)
enum BleCommand : uint8_t
{
    CMD_NONE = 0,
    CMD_START_WIFI = 1,
    CMD_STOP_WIFI = 2,
    CMD_ENTER_SLEEP = 3,
    CMD_START_RECORDING = 4,
    CMD_STOP_RECORDING = 5,
    CMD_CLEAR_STORAGE = 6,
    CMD_START_L2CAP_STREAM = 7,
    CMD_CONNECT_HOTSPOT = 8,
    CMD_DELETE_CLIP = 9
};

