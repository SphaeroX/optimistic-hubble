# Audio Vault ESP32-C3 - Ultra-Low-Power Voice Assistant & Companion Monorepo

An embedded voice recording, signal processing, and companion application monorepo built for the **ESP32-C3**, featuring **two I2S MEMS microphones**, an **IMU sensor** with **Ultra-Low-Power Deep Sleep (< 10 µA)** & **Hardware Shock Wakeup**, **persistent Flash storage (`LittleFS`)**, and a **Flutter Multiplatform Companion App** supporting **Android, iOS, and Windows Desktop**.

---

## Monorepo Architecture

```
optimistic-hubble/
├── apps/
│   └── companion_app/           # Flutter Multiplatform App (Android, iOS, Windows, macOS, Web)
│       ├── lib/                 # Clean, modular Dart architecture (Theme, BLE, Wi-Fi sync, Telemetry)
│       ├── android/             # Android project & permissions
│       ├── ios/                 # iOS project & Info.plist permissions
│       └── windows/             # Windows desktop runner & Win32 window config
├── firmware/                    # PlatformIO ESP32-C3 Firmware
│   ├── src/                     # Audio recorder, BLE service, Wi-Fi SoftAP server, IMU drivers
│   ├── platformio.ini           # Board definitions, partition tables & compiler flags
│   └── esp32c3_hw_test.ino      # Hardware test & validation sketch
├── research/                    # IoT transfer studies, BLE/Wi-Fi benchmarks & protocol docs
├── 01_flash_mcu.bat             # Builds, flashes and monitors ESP32-C3
├── 02_run_flutter_device.bat    # Launches Flutter companion app on connected device
├── 03_build_apk.bat             # Builds Flutter Android Release APK
├── 03_flash_and_build_apk.bat   # Flashes ESP32-C3 firmware and builds Android APK
├── 04_monitor.bat               # Starts serial monitor (115200 baud)
├── 05_run_flutter_windows.bat   # Launches Flutter companion app on Windows desktop
└── 06_erase_flash.bat           # Completely wipes ESP32 Flash memory and resets LittleFS
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

### 2. Building, Flashing & Packaging
* **Flash MCU & Build Android APK (All-in-One):** Double-click `flash_and_build_apk.bat`
* **Build Android APK Only:** Double-click `build_apk.bat`
* **Flash MCU & Monitor:** Double-click `flash_mcu.bat`
* **Full Flash Erase & Reset:** Double-click `erase_flash.bat`

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

## Hardware Architectures & Pinout

The project supports two target hardware setups:
1. **Custom Production Board V2:** Built around the **ESP32-C3-MINI-1-N4** module (integrated 4MB Flash, 40MHz crystal & PCB antenna), an **AP2112K-3.3TRG1 LDO (600mA)**, an external **Winbond W25Q128JVSIQ (16MB)** SPI Flash on **SPI2**, dual status LEDs, and direct THT through-hole soldering for LiPo battery and tactile switch.
2. **Breadboard Prototype:** Built using an ESP32-C3 breakout board.

### Production Board V2 (ESP32-C3-MINI-1-N4) Pin Assignment

| Component | Part / IC | Module Pin | ESP32-C3 GPIO | Function / Net |
| :--- | :--- | :---: | :--- | :--- |
| **Power (3.3V)** | AP2112K-3.3 (U7) | Pin 3 | `3V3` | Regulated 3.3V power rail (600mA peak) |
| **Ground** | System GND Plane | Pins 1, 2, 11, 14, 33–53 | `GND` | Common ground rail & thermal ground |
| **I2S Stereo Mic (L)** | ICS-43434 (U4) | Pin 5, 6, 17 | GPIO 2 (SCK), 3 (WS), 4 (SD) | Left Channel (L/R $\rightarrow$ GND) |
| **I2S Stereo Mic (R)** | ICS-43434 (U5) | Pin 5, 6, 17 | GPIO 2 (SCK), 3 (WS), 4 (SD) | Right Channel (L/R $\rightarrow$ 3V3) + R10 (100k pulldown) |
| **6-Axis IMU** | LSM6DSLTR (U3) | Pin 19, 20 | GPIO 6 (SDA), GPIO 7 (SCL) | I2C Bus (`0x6A`) + R2/R3 ($4.7\text{k}\Omega$ pullups) |
| **IMU Wakeup** | LSM6DSLTR (U3) | Pin 18 | GPIO 5 (INT1) | Hardware shock/tap wakeup interrupt |
| **Status LED (Red)**| KT-0603R (D1) | Pin 16 | GPIO 10 | Recording indicator via R4 ($330\Omega$) |
| **Status LED (Grn)**| LTST-C190GKT (D2) | Pin 21 | GPIO 8 | System/Wi-Fi status via R6 ($330\Omega$) |
| **User Button** | External Switch | Pin 22 | GPIO 9 (`BTN`) | THT hole to GND (weak pull-up, boot strap) |
| **USB-C Data** | GT-USB-7010ASV (J1)| Pin 25, 26 | GPIO 18 (D-), GPIO 19 (D+) | USB CDC / JTAG serial interface |
| **Audio Flash (16MB)**| W25Q128 (U2) | Pin 28 | GPIO 21 | `FLASH_CS` (/CS on SPI2) |
| | W25Q128 (U2) | Pin 27 | GPIO 20 | `FLASH_SCK` (CLK on SPI2) |
| | W25Q128 (U2) | Pin 13 | GPIO 1 | `FLASH_MOSI` (DI on SPI2) |
| | W25Q128 (U2) | Pin 12 | GPIO 0 | `FLASH_MISO` (DO on SPI2) |
| **Battery Charger** | TP4054 (U6) | - | - | 1S Li-Ion charger via USB-C (500mA, R9 = $2\text{k}\Omega$) |

> Complete hardware design, schematics, and JLCPCB manufacturing BOM are available in [HARDWARE_DESIGN.md](file:///c:/Users/MGasc/Documents/antigravity/optimistic-hubble/HARDWARE_DESIGN.md) and [ESP32C3_PINOUT.md](file:///c:/Users/MGasc/Documents/antigravity/optimistic-hubble/ESP32C3_PINOUT.md).

---

### Prototype Wiring (ESP32-C3)

| Component | Component Pin | ESP32-C3 Pin | ESP32-C3 GPIO | Description |
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

#### Storage Capacity & Recording Time Comparison

| Storage Medium | Usable Capacity | Audio Format & Bitrate | Max. Recording Time | Capacity Gain |
| :--- | :--- | :--- | :--- | :--- |
| **Internal Flash (Default)** | ~1.92 MB (LittleFS) | 16 kHz Mono ADPCM (8 KB/s) | **~4.1 minutes** (~245 s) | 1× (Baseline) |
| **W25Q128 SPI-Flash (Expanded)** | **16 MB** (~15.5–16 MB net) | 16 kHz Mono ADPCM (8 KB/s) | **~35.0 minutes** (~2,097 s) | **8.5× Increase** |
| *W25Q128 (Uncompressed)* | 16 MB | 16 kHz 16-Bit PCM (32 KB/s) | **~8.5 minutes** (~524 s) | 2.1× |
| *W25Q128 (Telephony)* | 16 MB | 8 kHz Mono ADPCM (4 KB/s) | **~70.0 minutes** (~4,194 s) | 17× (> 1 hour) |
| *W25Q256 (32 MB Optional)* | 32 MB | 16 kHz Mono ADPCM (8 KB/s) | **~70.0 minutes** (~4,194 s) | 17× |

> Detailed diagrams and breadboard guides are available in [PINOUT.md](file:///c:/Users/MGasc/Documents/antigravity/optimistic-hubble/PINOUT.md).

---

## API & Communication Specifications

### 1. Wi-Fi REST Sync API (HTTP Port 80)

* **Hotspot SSID:** `Audio-Vault-Hotspot`
* **Hotspot Password:** `audiovault2026`
* **Default Gateway / Web Dashboard:** `http://192.168.4.1`

#### Endpoints

* **`GET /api/clips`**: Returns JSON list of all recordings in Flash (`id`, `filename`, `size`, `duration`, `sampleRate`).
* **`GET /api/download?id=<clip_id>`**: Streams the requested `.wav` file directly from Flash storage.
* **`GET /api/status`**: Returns Flash memory utilization and clip counts.
* **`POST /api/clear`**: Deletes all stored recordings from Flash.
* **`GET /`**: Serves the mobile-optimized Web App with built-in Web Audio player and universal WAV exporter.

### 2. BLE GATT Signaling Specifications

* **Device Advertising Name:** `Audio-Vault`
* **Custom Service UUID:** `19b10000-e8f2-537e-4f6c-d104768a1214`
* **State Characteristic (`19b10001-...`):** `[state, latestClipId, totalClips]`
* **Tap Characteristic (`19b10003-...`):** `[tapFlag, shockMilliG]`

---

## Workflow: Recording & Syncing Voice Notes

1. **Tap the breadboard** $\rightarrow$ Status LED turns ON.
2. **Speak** into the MEMS microphones (real-time noise filtering active).
3. **Tap again** $\rightarrow$ Status LED turns OFF, audio is saved to Flash in 8 KB/s ADPCM format.
4. **Download & Play:** Launch the Flutter Companion App (via `02_run_flutter_device.bat` or `05_run_flutter_windows.bat`) and click **"WLAN Synchronisieren"** or BLE sync!

