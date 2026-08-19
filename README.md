# XIAO ESP32C3 - Voice Assistant & Dual-Mic Noise Filter

An embedded voice recording and signal processing platform built for the **Seeed Studio XIAO ESP32C3**, featuring **two I2S MEMS microphones**, an **IMU sensor** for tap-to-record shock detection, **persistent 4MB Flash storage (`LittleFS`)**, and a **hybrid BLE signaling + high-speed Wi-Fi synchronization engine** with real-time **Dual-Mic Active Noise Filtering (DSP)** and **8 KB/s high-efficiency storage**.

---

## Key Features

* **Tap-to-Record (Shock Detection):** Tap the breadboard once to start recording (Status LED turns ON); tap again to stop and save.
* **Hardware Dual-Mic Noise Filtering (On-Chip DSP):** Both MEMS microphones are sampled with 100% hardware phase-synchronicity. The firmware combines both channels in real-time with coherent beamforming ($+6\text{ dB}$ voice boost and ambient noise cancellation), outputting a crystal-clear single-line mono stream.
* **4:1 IMA-ADPCM Hardware Compression (8 KB/s):** Audio is compressed on-the-fly to 4-bit per sample (8,000 bytes/sec @ 16 kHz Mono). Over **4 minutes** of audio fit into the 1.92 MB Flash partition!
* **+18 dB Digital Preamp Gain:** Integrated digital pre-amplifier with soft-limiting delivers loud, crisp, full-scale audio without clipping.
* **Universal Standard 16-Bit PCM WAV Export:** Downloads generate 100% standard Linear 16-Bit PCM WAV files (`Format Tag 1`) compatible with **Windows Media Player, VLC, QuickTime, Android, iOS, and Audacity**.
* **Zero-Drop Direct-to-Flash Streaming:** Continuous DMA queue draining and 4KB sector-aligned writes prevent buffer overruns and eliminate audio cracks or gaps.
* **Hybrid BLE + Wi-Fi Sync:**
  * **BLE GATT Server:** Lightweight, low-power background event signaling (*"New recordings pending"*).
  * **Wi-Fi Hotspot (`XIAO-Audio-Hotspot` @ `192.168.4.1`):** Sub-100ms multi-clip download speeds with built-in Captive Portal DNS on port 53.

---

## Hardware Pinout & Wiring

| Component | Component Pin | XIAO ESP32C3 Pin | ESP32-C3 GPIO | Description |
| :--- | :--- | :--- | :--- | :--- |
| **Power** | 3V3 / VCC | **3V3** | - | 3.3V Power Bus |
| **Ground** | GND | **GND** | - | Common Ground Bus |
| **IMU (LSM6DS3 / BMI160)** | SCL | **D5** | GPIO 7 | Hardware I2C Clock |
| | SDA | **D4** | GPIO 6 | Hardware I2C Data |
| | SDO / SA0 | **GND** | - | Address: `0x6A` (LSM6DS3) / `0x68` (BMI160) |
| **Mic 1 (Voice Mic / Left)**| SD / DOUT | **D2** | GPIO 4 | Shared I2S Serial Data In |
| | WS / LRCLK | **D1** | GPIO 3 | Shared I2S Word Select |
| | SCK / BCLK | **D0** | GPIO 2 | Shared I2S Bit Clock |
| | **L/R** | **GND** | - | **Tied to GND: Left Channel** |
| **Mic 2 (Noise Mic / Right)**| SD / DOUT | **D2** | GPIO 4 | Shared with Mic 1 SD |
| | WS / LRCLK | **D1** | GPIO 3 | Shared with Mic 1 WS |
| | SCK / BCLK | **D0** | GPIO 2 | Shared with Mic 1 SCK |
| | **L/R** | **3V3** | - | **Tied to 3.3V: Right Channel** |
| **Status LED (Recording Light)**| Anode (+) | **D10** | GPIO 10 | Long leg of LED to D10 |
| | Kathode (-) | **GND** (via Resistor) | - | Short leg via 220Ω–330Ω resistor to GND |

### Optional Storage Expansion: W25Q128 SPI-Flash (16 MB)

To extend the continuous recording time from ~4 minutes up to **~35 minutes**, an external 16 MB SPI-Flash chip (**Winbond W25Q128JV / W25Q128FV**) can be connected to the remaining free hardware pins:

| W25Q128 Pin | Function | XIAO ESP32C3 Pin | ESP32-C3 GPIO | Description |
| :--- | :--- | :--- | :--- | :--- |
| **VCC** | 3.3V Power | **3V3** | - | 3.3V Power Rail |
| **GND** | Ground | **GND** | - | Common Ground Rail |
| **CS / /CS** | Chip Select | **D3** | GPIO 5 | SPI Slave Select |
| **CLK / SCK** | SPI Clock | **D6** | GPIO 8 | Hardware SPI Clock |
| **DO / MISO** | Data Out (MISO) | **D8** | GPIO 20 | Hardware SPI MISO |
| **DI / MOSI** | Data In (MOSI) | **D9** | GPIO 21 | Hardware SPI MOSI |
| **/HOLD & /WP** | Hold & Write Protect | **3V3** | - | Tied to 3.3V (or via 10k pull-up) |

#### Storage Capacity & Recording Time Comparison

| Storage Medium | Usable Capacity | Audio Format & Bitrate | Max. Recording Time | Capacity Gain |
| :--- | :--- | :--- | :--- | :--- |
| **Internal Flash (Default)** | ~1.92 MB (LittleFS) | 16 kHz Mono ADPCM (8 KB/s) | **~4.1 minutes** (~245 s) | 1× (Baseline) |
| **W25Q128 SPI-Flash (Expanded)** | **16 MB** (~15.5–16 MB net) | 16 kHz Mono ADPCM (8 KB/s) | **~35.0 minutes** (~2,097 s) | **8.5× Increase** |
| *W25Q128 (Uncompressed)* | 16 MB | 16 kHz 16-Bit PCM (32 KB/s) | **~8.5 minutes** (~524 s) | 2.1× |
| *W25Q128 (Telephony)* | 16 MB | 8 kHz Mono ADPCM (4 KB/s) | **~70.0 minutes** (~4,194 s) | 17× (> 1 hour) |
| *W25Q256 (32 MB Optional)* | 32 MB | 16 kHz Mono ADPCM (8 KB/s) | **~70.0 minutes** (~4,194 s) | 17× |

> Detailed diagrams and notes are available in [PINOUT.md](file:///c:/Users/MGasc/Documents/antigravity/optimistic-hubble/PINOUT.md).

---

## API & Communication Specifications

### 1. Wi-Fi REST Sync API (HTTP Port 80)

* **Hotspot SSID:** `XIAO-Audio-Hotspot`
* **Hotspot Password:** `xiaoesp32c3`
* **Default Gateway / Web Dashboard:** `http://192.168.4.1`

#### Endpoints

* **`GET /api/clips`**: Returns JSON list of all recordings in Flash (`id`, `filename`, `size`, `duration`, `sampleRate`).
* **`GET /api/download?id=<clip_id>`**: Streams the requested `.wav` file directly from Flash storage.
* **`GET /api/status`**: Returns Flash memory utilization and clip counts.
* **`POST /api/clear`**: Deletes all stored recordings from Flash.
* **`GET /`**: Serves the mobile-optimized Web App with built-in Web Audio player and universal WAV exporter.

### 2. BLE GATT Signaling Specifications

* **Device Advertising Name:** `XIAO-Audio-Recorder`
* **Custom Service UUID:** `19b10000-e8f2-537e-4f6c-d104768a1214`
* **State Characteristic (`19b10001-...`):** `[state, latestClipId, totalClips]`
* **Tap Characteristic (`19b10003-...`):** `[tapFlag, shockMilliG]`

---

## Quick Start Guide

### 1. Flashing Firmware
```powershell
.\flash_and_monitor.bat
```

### 2. Launching the Web Companion App
```powershell
.\start_app.bat
```
Navigate to `http://localhost:8000`.

### 3. Recording Voice Notes
1. **Tap the breadboard** $\rightarrow$ Status LED turns ON.
2. **Speak** into the MEMS microphones (real-time noise filtering active).
3. **Tap again** $\rightarrow$ Status LED turns OFF, audio is saved to 4MB Flash in 8 KB/s ADPCM format.
4. **Download & Play:** Connect to `XIAO-Audio-Hotspot` and click **"WLAN Synchronisieren"** in the Companion App!
