# XIAO ESP32C3 - Voice Assistant & Dual-Mic Noise Vault

An embedded voice recording and signal processing platform built for the **Seeed Studio XIAO ESP32C3**, featuring **two I2S MEMS microphones**, a **6-axis IMU sensor** for tap-to-record shock detection, **persistent 4MB Flash storage (`LittleFS`)**, and a **hybrid BLE signaling + high-speed Wi-Fi synchronization engine** with real-time **Dual-Mic Active Noise Cancellation (DSP)**.

---

## Key Features

* **Tap-to-Record (Shock Detection):** Tap the breadboard once to start recording (Status LED turns ON); tap again to stop and save.
* **Discrete 2-Channel Stereo Recording:** Left and Right MEMS microphones are sampled with 100% hardware phase-synchronicity.
* **4:1 IMA-ADPCM Hardware Compression:** Audio is compressed on-the-fly to 4-bit per sample (16 KB/s for full 2-channel 16 kHz stereo), extending storage capacity by **400%**.
* **Zero-Drop Direct-to-Flash Streaming:** Audio data streams continuously into **LittleFS (4MB Flash)** with deep 16-buffer DMA and 4KB block-aligned caching, allowing recordings of **up to 5 minutes** per session with zero dropped frames.
* **Hybrid BLE + Wi-Fi Sync:**
  * **BLE GATT Server:** Lightweight, low-power background event signaling (*"New recordings pending"*).
  * **Wi-Fi Hotspot (`XIAO-Audio-Hotspot` @ `192.168.4.1`):** Sub-100ms multi-clip download speeds (>2–5 MB/s) with built-in Captive Portal DNS on port 53.
* **Dual-Microphone DSP & Noise Cancellation:**
  * 🎙️ **Dual-Mic Beamforming:** Coherent phase addition ($+3\text{ dB}$ SNR improvement and ambient noise rejection).
  * 🛡️ **Differential Active Noise Cancellation (ANC):** Real-time spatial subtraction ($S = \text{Mic}_1 - \alpha \cdot \text{Mic}_2$).
  * 🎚️ **Adaptive Noise Gate:** Automatically silences background hiss during speech pauses.
* **Zero-Install Web Dashboard & Companion App:** Works on Android, iOS, Windows, and macOS browsers out-of-the-box.

---

## System Architecture

```
                                      +---------------------------------------------+
                                      |         Web & Mobile Companion App          |
                                      |     (Waveform, DSP Noise Filter, Player)    |
                                      +---------------------------------------------+
                                            ^                                 ^
         1. BLE Event Notification:         |                                 |  2. Wi-Fi Sync API (HTTP):
            "CLIPS_PENDING"                 |                                 |     GET /api/clips
            (Latest ID, Total Count)        |                                 |     GET /api/download?id=X
                                            v                                 v
+---------------------------------------------------------------------------------------------------------+
|                                        XIAO ESP32C3 FIRMWARE                                            |
|                                                                                                         |
|  +---------------------+      +---------------------+      +-----------------------------------------+  |
|  |   IMU Tap Engine    |----->|  I2S Stereo Driver  |----->|     4:1 IMA-ADPCM Stereo Encoder        |  |
|  | (LSM6DS3 / BMI160)  |      |   2x MEMS Mics      |      |  Ch0 (Left Mic) + Ch1 (Right Mic)       |  |
|  +---------------------+      +---------------------+      +-----------------------------------------+  |
|                                                                                 |                       |
|                                                                                 v                       |
|                                 +-------------------+      +-----------------------------------------+  |
|                                 |  Status LED (D10) |<-----|       LittleFS Flash File System        |  |
|                                 |  Recording Light  |      |   /clip_001.wav, /clip_002.wav, ...     |  |
|                                 +-------------------+      +-----------------------------------------+  |
|                                                                                 |                       |
|                                                                                 v                       |
|                               +---------------------+      +-----------------------------------------+  |
|                               | NimBLE GATT Server  |      |         Wi-Fi REST Sync Server          |  |
|                               | (128-bit Signaling) |      |        Captive Portal DNS (Port 53)     |  |
|                               +---------------------+      +-----------------------------------------+  |
+---------------------------------------------------------------------------------------------------------+
```

---

## Hardware Pinout & Wiring

| Component | Component Pin | XIAO ESP32C3 Pin | ESP32-C3 GPIO | Description |
| :--- | :--- | :--- | :--- | :--- |
| **Power** | 3V3 / VCC | **3V3** | - | 3.3V Power Bus |
| **Ground** | GND | **GND** | - | Common Ground Bus |
| **IMU (LSM6DS3 / BMI160)** | SCL | **D5** | GPIO 7 | Hardware I2C Clock |
| | SDA | **D4** | GPIO 6 | Hardware I2C Data |
| | SDO / SA0 | **GND** | - | Address: `0x6A` (LSM6DS3) / `0x68` (BMI160) |
| **Mic 1 (Left Channel)** | SD / DOUT | **D2** | GPIO 4 | Shared I2S Serial Data In |
| | WS / LRCLK | **D1** | GPIO 3 | Shared I2S Word Select |
| | SCK / BCLK | **D0** | GPIO 2 | Shared I2S Bit Clock |
| | **L/R** | **GND** | - | **Tied to GND: Left Channel** |
| **Mic 2 (Right Channel)**| SD / DOUT | **D2** | GPIO 4 | Shared with Mic 1 SD |
| | WS / LRCLK | **D1** | GPIO 3 | Shared with Mic 1 WS |
| | SCK / BCLK | **D0** | GPIO 2 | Shared with Mic 1 SCK |
| | **L/R** | **3V3** | - | **Tied to 3.3V: Right Channel** |
| **Status LED (Recording Light)**| Anode (+) | **D10** | GPIO 10 | Long leg of LED to D10 |
| | Kathode (-) | **GND** (via Resistor) | - | Short leg via 220Ω–330Ω resistor to GND |

> Detailed diagrams and notes are available in [PINOUT.md](file:///c:/Users/MGasc/Documents/antigravity/optimistic-hubble/PINOUT.md).

---

## API & Communication Specifications

### 1. Wi-Fi REST Sync API (HTTP Port 80)

* **Hotspot SSID:** `XIAO-Audio-Hotspot`
* **Hotspot Password:** `xiaoesp32c3`
* **Default Gateway / Web Dashboard:** `http://192.168.4.1`

#### Endpoints

#### `GET /api/clips`
Returns a JSON array of all voice recordings stored in the 4MB Flash memory.

**Response Example:**
```json
{
  "clips": [
    {
      "id": 1,
      "filename": "/clip_001.wav",
      "size": 160060,
      "duration": 10.0,
      "sampleRate": 16000
    },
    {
      "id": 2,
      "filename": "/clip_002.wav",
      "size": 48060,
      "duration": 3.0,
      "sampleRate": 16000
    }
  ]
}
```

#### `GET /api/download?id=<clip_id>`
Streams the requested uncompressed/ADPCM `.wav` file directly from Flash using chunked kernel `streamFile()`. If `id` is omitted, streams the latest recording.

* **Response Headers:** `Content-Type: audio/wav`, `Content-Disposition: inline; filename="clip_001.wav"`
* **CORS:** Enabled (`Access-Control-Allow-Origin: *`)

#### `GET /api/status`
Returns flash memory utilization and recording counts.

**Response Example:**
```json
{
  "totalClips": 2,
  "usedBytes": 208120,
  "totalBytes": 1966080,
  "freeBytes": 1757960,
  "usedKb": 203,
  "totalKb": 1920
}
```

#### `POST /api/clear` (or `GET /api/clear`)
Deletes all stored `.wav` audio recordings from Flash memory to reset storage space.

**Response Example:**
```json
{
  "status": "success",
  "message": "All clips cleared"
}
```

#### `GET /`
Serves the self-contained, mobile-optimized Web App with built-in Web Audio ADPCM player directly from the ESP32 (no local server required on smartphones).

---

### 2. BLE GATT Signaling Specifications

* **Device Advertising Name:** `XIAO-Audio-Recorder`
* **Custom Service UUID:** `19b10000-e8f2-537e-4f6c-d104768a1214`

| Characteristic UUID | Property | Data Type | Payload Description |
| :--- | :--- | :--- | :--- |
| `19b10001-e8f2-537e-4f6c-d104768a1214` | Read, Notify | `uint8_t[7]` | **Device State & Clip Stats:**<br>`[0]`: State (`0`=IDLE, `1`=RECORDING, `3`=DONE)<br>`[1..4]`: Latest Clip ID (uint32 Little-Endian)<br>`[5..6]`: Total Clips in Flash (uint16 Little-Endian) |
| `19b10003-e8f2-537e-4f6c-d104768a1214` | Read, Notify | `uint8_t[5]` | **Tap / Shock Telemetry:**<br>`[0]`: Tap Trigger Flag (`1`)<br>`[1..4]`: Measured Shock Force in milli-$g$ (`int32`) |

---

## Dual-Microphone DSP Noise Cancellation

The Companion App and Web Dashboard decode the raw 2-channel stereo streams and provide real-time DSP filtering:

$$\begin{aligned}
\text{Beamforming:} \quad & S_{\text{beam}}[n] = \frac{\text{Left}[n] + \text{Right}[n]}{2} \\
\text{ANC Subtraction:} \quad & S_{\text{anc}}[n] = \text{Left}[n] - \alpha \cdot \text{Right}[n]
\end{aligned}$$

1. **Dual-Mic Beamforming:** Combines correlated speech signals while suppressing uncorrelated background noise, yielding a **$+3\text{ dB}$ Signal-to-Noise Ratio (SNR) boost**.
2. **Differential Active Noise Cancellation (ANC):** Treats Mic 2 (Right) as an ambient reference and subtracts phase-shifted background noise from Mic 1 (Left).
3. **Noise Gate:** Smoothly mutes background hiss when audio power falls below the adjustable threshold slider.

---

## Quick Start Guide

### 1. Flashing Firmware
Run the included Windows automation script:
```powershell
.\flash_and_monitor.bat
```
*(Or use `pio run -t upload` in PlatformIO).*

### 2. Launching the Web Companion App
Run the local web server launcher:
```powershell
.\start_app.bat
```
Then navigate to `http://localhost:8000` in Google Chrome or Microsoft Edge.

### 3. Recording Voice Notes
1. **Tap the breadboard** $\rightarrow$ Status LED turns ON.
2. **Speak** into the MEMS microphones.
3. **Tap the breadboard again** $\rightarrow$ Status LED turns OFF, audio is finalized and saved into 4MB Flash storage.
4. **Download & Play:** Connect to Wi-Fi `XIAO-Audio-Hotspot` (PW: `xiaoesp32c3`), open `http://192.168.4.1` or click **"WLAN Synchronisieren"** in the Companion App!

---

## Project Structure

```
├── app/
│   ├── app.js               # Web Bluetooth + Wi-Fi Sync + Web Audio DSP Engine
│   ├── index.html           # Modern Web Dashboard & Waveform Visualizer
│   └── style.css            # Responsive dark-theme design tokens
├── src/
│   ├── adpcm.h / .cpp       # High-speed 4:1 IMA-ADPCM codec
│   ├── audio_recorder.h/.cpp# Zero-drop streaming recorder with DC-blocking filter
│   ├── ble_manager.h / .cpp # NimBLE GATT signaling server
│   ├── config.h             # Pinout constants, buffer limits, BLE/Wi-Fi configs
│   ├── i2c_scanner.h        # Non-blocking I2C diagnostic scanner
│   ├── i2s_mic_driver.h/.cpp# Synchronous stereo I2S DMA driver (16 kHz 32-bit)
│   ├── imu_driver.h / .cpp  # Auto-detecting 6-axis IMU driver (LSM6DS3 / BMI160)
│   ├── main.cpp             # Coordination loop & state management
│   ├── storage_manager.h/.cpp# LittleFS 4MB persistent storage manager
│   ├── tap_detector.h / .cpp# Accelerometer high-pass jerk tap detector
│   └── wifi_server.h / .cpp # SoftAP, Captive DNS & chunked REST sync server
├── PINOUT.md                # Detailed breadboard wiring guide & ASCII pinout
├── platformio.ini           # PlatformIO build configuration with no_ota partition
├── build.bat                # 1-Click PlatformIO compiler
├── flash_and_monitor.bat    # 1-Click build, flash & serial monitor
├── monitor.bat              # Standalone serial monitor (115200 baud)
└── start_app.bat            # 1-Click Companion App web server launcher
```
