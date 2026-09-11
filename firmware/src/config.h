#pragma once
#include <Arduino.h>

// ============================================================================
// Hardware Pinout for ESP32-C3-MINI-1-N4 (V2 Production Design)
// ============================================================================

// I2C Pins for 6-Axis IMU (ST LSM6DSLTR, U3)
#define PIN_I2C_SDA 6 // GPIO 6 (Module Pin 19) + 4.7k Pull-up to 3V3
#define PIN_I2C_SCL 7 // GPIO 7 (Module Pin 20) + 4.7k Pull-up to 3V3
#define I2C_FREQUENCY 400000UL

// IMU Hardware Interrupt Wakeup Pin (RTC GPIO 5) & Push Button (GPIO 9)
#define PIN_IMU_INT 5  // GPIO 5 (Module Pin 18, RTC IO5, Deep Sleep Wakeup from INT1)
#define PIN_BOOT_BTN 9 // GPIO 9 (Module Pin 22, THT BTN Switch against GND)

// I2S Stereo Microphone Pins (TDK InvenSense ICS-43434, U4 & U5)
#define PIN_I2S_SCK 2          // GPIO 2 (Module Pin 5, Bit Clock)
#define PIN_I2S_WS 3           // GPIO 3 (Module Pin 6, Word Select / LRCLK)
#define PIN_I2S_SD 4           // GPIO 4 (Module Pin 17, Serial Data In + 100k Pulldown)
#define I2S_BUFFER_SAMPLES 256 // Number of stereo sample frames per read

// External Status LEDs (D1 Red, D2 Green - Active LOW: Anode to 3V3, Cathode to GPIO via 330R)
#define PIN_STATUS_LED 10 // GPIO 10 (Module Pin 16) = Red Status LED (D1, Recording)
#define PIN_LED_GREEN 8   // GPIO 8  (Module Pin 21) = Green Status LED (D2, System/Wi-Fi)
#define LED_LEVEL_ON  LOW
#define LED_LEVEL_OFF HIGH

// External SPI Flash Pins (Winbond W25Q128JVSIQ 16MB Audio Storage on SPI2 / FSPI)
// Empirically verified on PCB V2 hardware routing:
// CS=GPIO 21, SCK=GPIO 0, MOSI=GPIO 20, MISO=GPIO 1
#define PIN_FLASH_CS 21   // GPIO 21 (Module Pin 28) = /CS (Chip Select)
#define PIN_FLASH_SCK 0   // GPIO 0  (Module Pin 12) = CLK (Clock)
#define PIN_FLASH_MOSI 20 // GPIO 20 (Module Pin 27) = DI (Serial Data In)
#define PIN_FLASH_MISO 1  // GPIO 1  (Module Pin 13) = DO (Serial Data Out)

// Serial Baud Rate
#define SERIAL_BAUD_RATE 115200

// ============================================================================
// Ultra-Low-Power & Deep Sleep Parameters
// ============================================================================
#define INACTIVITY_SLEEP_TIMEOUT_MS 15000UL // 15 seconds of idle inactivity before Deep Sleep
#define WIFI_INACTIVITY_TIMEOUT_MS 120000UL // 2 minutes of idle Wi-Fi -> Stop SoftAP to save ~150 mA
#define IMU_WAKEUP_THRESHOLD_G 1.4f         // Hardware shock acceleration threshold
#define ENABLE_DEEP_SLEEP_AUTO true         // Deep Sleep enabled for battery saving

// ============================================================================
// Audio Recording & Preamp Parameters
// ============================================================================
#define AUDIO_SAMPLE_RATE 16000  // 16 kHz Voice sampling rate
#define MIC_GAIN_MULTIPLIER 8.0f // +18 dB Digital Preamp Gain (Crisp, loud & full-scale voice)

// ============================================================================
// Tap & Double-Tap Detection Parameters
// ============================================================================
#define TAP_JERK_THRESHOLD_G 0.55f    // Shock delta acceleration threshold in g
#define TAP_DEBOUNCE_MS 120           // Minimum time between raw tap triggers (ms)
#define DOUBLE_TAP_WINDOW_MIN_MS 120  // Minimum interval between 1st and 2nd tap (debounce)
#define DOUBLE_TAP_WINDOW_MAX_MS 650  // Maximum interval between 1st and 2nd tap for valid double tap

// ============================================================================
// Shake Gesture Parameters (for Recording Start/Stop)
// ============================================================================
#define SHAKE_THRESHOLD_G 1.60f        // Dynamic acceleration threshold in g
#define SHAKE_WINDOW_MS 650            // Time window for shake reversals (ms)
#define SHAKE_REVERSALS_REQUIRED 2     // Minimum direction reversals to qualify as shake
#define SHAKE_COOLDOWN_MS 1200         // Cooldown after trigger before next shake (ms)

// Orientation Threshold: Y-axis points downwards (-1g Earth gravity) when arm is raised
// Arm raised: accelY_g <= -0.50g
#define IMU_ARM_UP_Y_THRESHOLD_G -0.50f

// ============================================================================
// Wi-Fi High-Speed Audio Server Parameters
// ============================================================================
#define WIFI_AP_SSID "Audio-Vault-Hotspot"
#define WIFI_AP_PASS "audiovault2026" // WPA2 Passphrase (>= 8 chars)
#define HTTP_SERVER_PORT 80

// ============================================================================
// BLE GATT UUIDs (128-bit Custom Service)
// ============================================================================
#define BLE_DEVICE_NAME "Audio-Vault"
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

// Minimum free LittleFS Flash storage margin to prevent overflow (256 KB safe headroom for COW blocks & header updates)
#define MIN_FREE_STORAGE_BYTES 262144UL

// Audio Recording Quality Modes
enum AudioQuality : uint8_t
{
    QUALITY_HIGH = 0,   // 16 kHz, 16-bit Linear PCM Mono (32 KB/s, uncompressed studio quality)
    QUALITY_MEDIUM = 1, // 16 kHz, 4-bit IMA-ADPCM Mono (8 KB/s, balanced speech, default)
    QUALITY_LOW = 2     // 8 kHz,  4-bit IMA-ADPCM Mono (4 KB/s, long-play mode)
};

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
    CMD_DELETE_CLIP = 9,
    CMD_SET_QUALITY = 10
};

