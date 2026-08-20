# XIAO ESP32C3 - Ultra-Low-Power Voice Assistant & Companion Monorepo

An embedded voice recording, signal processing, and companion application monorepo built for the **Seeed Studio XIAO ESP32C3**, featuring **two I2S MEMS microphones**, an **IMU sensor** with **Ultra-Low-Power Deep Sleep (< 10 µA)** & **Hardware Shock Wakeup**, **persistent Flash storage (`LittleFS`)**, and a **Flutter Multiplatform Companion App** supporting **Android, iOS, and Windows Desktop**.

---

## Monorepo Architecture

```
optimistic-hubble/
├── apps/
│   ├── companion_app/           # Flutter Multiplatform App (Android, iOS, Windows, macOS, Web)
│   │   ├── lib/                 # Clean, modular Dart architecture (Theme, BLE, Wi-Fi sync, Telemetry)
│   │   ├── android/             # Android project & permissions
│   │   ├── ios/                 # iOS project & Info.plist permissions
│   │   └── windows/             # Windows desktop runner & Win32 window config
│   └── web_prototype/           # Legacy Web Bluetooth prototype
├── firmware/                    # PlatformIO ESP32-C3 Firmware
│   ├── src/                     # Audio recorder, BLE service, Wi-Fi SoftAP server, IMU drivers
│   ├── platformio.ini           # Board definitions, partition tables & compiler flags
│   └── xiao_esp32c3_hw_test.ino # Hardware test & validation sketch
├── hardware/                    # KiCad & EasyEDA schematic generators, symbols, outputs
├── research/                    # IoT transfer studies, BLE/Wi-Fi benchmarks & protocol docs
├── build.bat                    # Compiles ESP32-C3 firmware
├── flash_and_monitor.bat        # Builds, flashes and monitors XIAO ESP32-C3
├── monitor.bat                  # Starts serial monitor (115200 baud)
├── run_flutter_windows.bat      # Launches Flutter companion app on Windows desktop
└── start_app.bat                # Starts legacy web prototype
```

---

## Quick Start Guide

### 1. Running the Flutter Companion App
* **Windows Desktop (Testing on PC):**
  ```powershell
  .\run_flutter_windows.bat
  # Or:
  cd apps\companion_app
  flutter run -d windows
  ```
* **Android:**
  ```powershell
  cd apps\companion_app
  flutter run -d android
  ```
* **iOS:**
  ```powershell
  cd apps\companion_app
  flutter run -d ios
  ```

### 2. Building and Flashing Firmware
* **Build Firmware:** Double-click `build.bat` or run `cd firmware; pio run`
* **Flash & Monitor:** Double-click `flash_and_monitor.bat` or run `cd firmware; pio run -t upload; pio device monitor`

---

## Key Features

* **Ultra-Low-Power Deep Sleep (< 10 µA):** ESP32-C3 drops to ~8 µA in sleep mode, extending battery life from ~2 hours to **over 3 months** on a compact 300 mAh LiPo!
* **Hardware Shock / Tap Wake-Up:** LSM6DS3 / BMI160 / MPU-6050 configured in low-power interrupt mode automatically wakes the MCU upon shock/tap (> 1.4g) and instantly begins recording.
* **On-Demand Wi-Fi Hotspot:** High-power Wi-Fi SoftAP (~150 mA) and I2S DMA (~5 mA) are dynamically powered down during idle and activated only on-demand via BLE command or Boot button (D7).
* **Hardware Dual-Mic Noise Filtering (On-Chip DSP):** Both MEMS microphones are sampled with 100% hardware phase-synchronicity. The firmware combines both channels in real-time with coherent beamforming ($+6\text{ dB}$ voice boost and ambient noise cancellation), outputting a crystal-clear single-line mono stream.
* **4:1 IMA-ADPCM Hardware Compression (8 KB/s):** Audio is compressed on-the-fly to 4-bit per sample (8,000 bytes/sec @ 16 kHz Mono). Over **4 minutes** of audio fit into the 1.92 MB Flash partition!
* **+18 dB Digital Preamp Gain:** Integrated digital pre-amplifier with soft-limiting delivers loud, crisp, full-scale audio without clipping.
* **Universal Standard 16-Bit PCM WAV Export:** Downloads generate 100% standard Linear 16-Bit PCM WAV files (`Format Tag 1`) compatible with **Windows Media Player, VLC, QuickTime, Android, iOS, and Audacity**.
* **Zero-Drop Direct-to-Flash Streaming:** Continuous DMA queue draining and 4KB sector-aligned writes prevent buffer overruns and eliminate audio cracks or gaps.

---

## Power Consumption & Battery Life

| State | Previous Firmware | Optimized Firmware | 300 mAh Battery Runtime |
| :--- | :--- | :--- | :--- |
| **Standby / Idle** | ~180 mA (Wi-Fi AP always on) | **~8–10 µA** (Deep Sleep + IMU LP Mode) | **~2,500+ Hours (~3.5 Months)** |
| **Active Recording** | ~40 mA | **~28 mA** (Wi-Fi OFF, I2S active) | **~10.5 Hours** continuous audio |
| **Wi-Fi Sync (Burst)** | ~180 mA (Permanent) | ~150 mA (Burst only when syncing) | Auto-timeout after 2 min |

---

## Hardware Pinout & Wiring

| Component | Component Pin | XIAO ESP32C3 Pin | ESP32-C3 GPIO | Description |
| :--- | :--- | :--- | :--- | :--- |
| **Power** | 3V3 / VCC | **3V3** | - | 3.3V Power Bus |
| **Ground** | GND | **GND** | - | Common Ground Bus |
| **IMU (LSM6DS3 / BMI160)** | SCL | **D5** | GPIO 7 | Hardware I2C Clock |
| | SDA | **D4** | GPIO 6 | Hardware I2C Data |
| | SDO / SA0 | **GND** | - | Address: `0x6A` (LSM6DS3) / `0x68` (BMI160) |
| | **INT1 (Shock Interrupt)**| **D3** | **GPIO 5** | **RTC GPIO: Deep Sleep Shock Wakeup (< 10 µA)!** |
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
| **Manual Wi-Fi Toggle** | Boot Button / Switch | **D7** | GPIO 9 | Press to toggle Wi-Fi ON/OFF manually |

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
