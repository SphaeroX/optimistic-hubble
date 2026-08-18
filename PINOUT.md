# Hardware Pinout & Wiring Guide
## Seeed Studio XIAO ESP32C3 with Stereo MEMS Microphones, IMU & Status LED

This document describes the complete breadboard wiring for connecting **two I2S MEMS Microphones**, an **IMU Sensor** (LSM6DS3 / BMI160), and an optional **Status LED** to the **Seeed Studio XIAO ESP32C3**.

---

## 1. Quick Pin Reference Table

| Device | Device Pin | XIAO ESP32C3 Pin | ESP32-C3 GPIO | Function / Notes |
| :--- | :--- | :--- | :--- | :--- |
| **Power Bus** | VCC / 3V3 | **3V3** | - | **3.3V Power Supply** (Do NOT use 5V for MEMS Mics!) |
| **Power Bus** | GND | **GND** | - | **Common Ground** |
| **IMU (LSM6DS3 / BMI160)** | VCC | **3V3** | - | Power Supply (3.3V) |
| | GND | **GND** | - | Ground |
| | SCL | **D5** | GPIO 7 | Hardware I2C Clock (SCL) |
| | SDA | **D4** | GPIO 6 | Hardware I2C Data (SDA) |
| | SDO / SA0 | **GND** | - | I2C Address: `0x6A` (LSM6DS3) / `0x68` (BMI160) |
| **Mic 1 (Left Channel)** | VDD / 3V3 | **3V3** | - | 3.3V Power |
| | GND | **GND** | - | Ground |
| | SD / DOUT | **D2** | GPIO 4 | Shared I2S Serial Data In |
| | WS / LRCLK | **D1** | GPIO 3 | Shared I2S Word Select (LRCLK) |
| | SCK / BCLK | **D0** | GPIO 2 | Shared I2S Bit Clock (BCLK) |
| | **L/R** | **GND** | - | **Configures Mic 1 as LEFT Channel** |
| **Mic 2 (Right Channel)**| VDD / 3V3 | **3V3** | - | 3.3V Power |
| | GND | **GND** | - | Ground |
| | SD / DOUT | **D2** | GPIO 4 | Connected to Mic 1 SD |
| | WS / LRCLK | **D1** | GPIO 3 | Connected to Mic 1 WS |
| | SCK / BCLK | **D0** | GPIO 2 | Connected to Mic 1 SCK |
| | **L/R** | **3V3** | - | **Configures Mic 2 as RIGHT Channel** |
| **Status LED (Optional)** | Anode (+) | **D10** | GPIO 10 | Connected via 220-470 Ohm resistor |
| | Kathode (-) | **GND** | - | Connect to GND rail |

---

## 2. Seeed Studio XIAO ESP32C3 Pinout Overview

```
                      +-------------------+
                      |   [USB-C Port]    |
       (GPIO 2)  D0  [ ]                 [ ]  5V       (USB 5V Out)
       (GPIO 3)  D1  [ ]                 [ ]  GND      (Ground)
       (GPIO 4)  D2  [ ]                 [ ]  3V3      (3.3V Out)
       (GPIO 5)  D3  [ ]                 [ ]  D10 / LED (GPIO 10)
 (SDA) (GPIO 6)  D4  [ ]                 [ ]  D9       (GPIO 21)
 (SCL) (GPIO 7)  D5  [ ]                 [ ]  D8       (GPIO 20)
       (GPIO 8)  D6  [ ]                 [ ]  D7       (GPIO 9 - Boot)
                      +-------------------+
```

---

## 3. How Tap-to-Record Works

1. **Idle State:** The device listens to the IMU accelerometer and advertises BLE.
2. **First Tap (Start Recording):** 
   - A physical tap on the breadboard triggers the accelerometer shock detector.
   - Status LED on D10 turns **ON**.
   - Audio is recorded directly from the MEMS microphones into fast internal SRAM.
3. **Second Tap (Stop & Transfer):**
   - Another tap stops recording.
   - Status LED turns **OFF** (or pulses during BLE transfer).
   - Audio is transmitted via BLE GATT Notifications to the Web Bluetooth Companion App.
4. **Playback:** The Companion App receives the voice clip, renders the waveform, and plays the recording.
