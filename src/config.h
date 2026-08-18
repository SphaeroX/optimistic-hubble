#pragma once
#include <Arduino.h>

// ============================================================================
// Pin Configuration for Seeed Studio XIAO ESP32C3
// ============================================================================

// I2C Pins for BMI160 Sensor
// XIAO D4 = GPIO 6 (SDA), XIAO D5 = GPIO 7 (SCL)
#define PIN_I2C_SDA         6
#define PIN_I2C_SCL         7
#define I2C_FREQUENCY       400000UL // 400 kHz Fast-Mode I2C

// BMI160 I2C Default Address
// 0x68 when SDO pin is tied to GND, 0x69 when SDO pin is tied to 3.3V
#define BMI160_DEFAULT_ADDR 0x68
#define BMI160_ALT_ADDR     0x69
#define BMI160_CHIP_ID      0xD8

// I2S Stereo Microphone Pins
// XIAO D0 = GPIO 2 (SCK), XIAO D1 = GPIO 3 (WS), XIAO D2 = GPIO 4 (SD)
#define PIN_I2S_SCK         2  // Bit Clock (BCLK)
#define PIN_I2S_WS          3  // Word Select / LRCLK
#define PIN_I2S_SD          4  // Serial Data In (DOUT from Mics)

// Audio Acquisition Parameters
#define I2S_SAMPLE_RATE     16000  // 16 kHz sampling rate
#define I2S_BUFFER_SAMPLES  256    // Number of stereo sample frames per read
#define SERIAL_BAUD_RATE    115200 // Serial monitor baud rate
