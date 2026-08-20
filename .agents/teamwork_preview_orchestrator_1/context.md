# Context: Research & Architectural Study — Optimal IoT-to-Android Audio Sync (XIAO ESP32-C3)

## System Overview
- **Hardware Target**: Seeed Studio XIAO ESP32-C3 (Single-core 32-bit RISC-V @ 160MHz, 400KB SRAM, 4MB Flash, Wi-Fi 4 802.11 b/g/n, BLE 5.0). Optional SPI Flash W25Q128 (16MB).
- **Audio Profile**: 16 kHz Mono IMA-ADPCM @ 4 bits/sample = 8,000 bytes/second (8 KB/s).
- **Typical File Sizes**:
  - 1 min: 480 KB (~0.5 MB)
  - 5 min: 2.4 MB (~2.4 MB)
  - 10 min: 4.8 MB (~5 MB)
  - 35 min (max capacity): 16.8 MB (~16 MB)
- **Target Mobile Platform**: Android 10 to Android 15 (API level 29 to 35+).
- **Key UX Goal**: Seamless, zero-manual-Wi-Fi-switching audio synchronization.

## Core Problem Statement
How to transfer 0.5 MB to 16 MB audio files from the ESP32-C3 to an Android smartphone with maximum speed, minimal battery consumption, zero user friction (no manual Wi-Fi switching in Android OS Settings), and robust background and foreground sync capabilities despite strict modern Android OS background and networking restrictions.
