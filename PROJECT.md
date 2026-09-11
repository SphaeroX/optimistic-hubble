# Project: Optimal IoT-to-Android Audio Sync (ESP32-C3)

## Architecture
- Dual-Mode Hybrid Architecture: BLE 5.0 Low-Energy Signaling/Short-Sync + Programmatic Wi-Fi SoftAP / Station High-Speed Sync.
- Target Hardware: Custom Production Board V2 (ESP32-C3-MINI-1-N4 with 4MB internal Flash, Winbond W25Q128 16MB SPI2 Flash, AP2112K-3.3 LDO) & ESP32-C3 Dev Boards.
- Target Mobile Platform: Android 10 to Android 15 (API levels 29 to 35+).
- Target Audio Stream: 16 kHz Mono IMA-ADPCM (4 bits/sample = 8 KB/s).

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | R1.1 BLE 5.0 High-Throughput | 2M PHY, DLE (251 bytes), ATT MTU, L2CAP CoC vs GATT Notify analysis & benchmarks | M1 | ORIGINAL_REQUEST.md §R1 |
| 2 | R1.2 Android Programmatic Wi-Fi | `WifiNetworkSpecifier`, `CompanionDeviceManager`, cellular data preservation, auto-disconnect | M1 | ORIGINAL_REQUEST.md §R1 |
| 3 | R1.3 Local Wi-Fi STA / mDNS | Home Wi-Fi BLE provisioning, local mDNS discovery, LAN HTTP sync | M1 | ORIGINAL_REQUEST.md §R1 |
| 4 | R1.4 Market Reference Analysis | Plaud Note AI, Senstone, Mobvoi, Wearables sync architecture reverse-engineering | M1 | ORIGINAL_REQUEST.md §R1 |
| 5 | R2.1 Benchmark Matrix | Quantitative speeds, transfer times (0.5MB, 2MB, 5MB, 16MB), power consumption, battery life | M2 | ORIGINAL_REQUEST.md §R2 |
| 6 | R2.2 Android Restrictions Matrix | API 29-35+ permissions, ForegroundService types (`connectedDevice`, `dataSync`), Doze Mode | M2 | ORIGINAL_REQUEST.md §R2 |
| 7 | R2.3 UX Friction & Trade-off Scoring | Zero-click vs 1-tap vs manual, comprehensive multi-attribute decision matrix | M2 | ORIGINAL_REQUEST.md §R2 |
| 8 | R3.1 Primary & Hybrid Strategy | Zero-friction primary protocol, smart threshold-based dynamic switching (BLE vs Wi-Fi) | M3 | ORIGINAL_REQUEST.md §R3 |
| 9 | R3.2 Background & Foreground Modes | WorkManager periodic sync, BLE-triggered wakeup, Foreground fast sync | M3 | ORIGINAL_REQUEST.md §R3 |
| 10 | R3.3 Resilient Packet/Recovery Protocol | Chunk-based streaming, CRC32 hashing, partial transfer offset resume | M3 | ORIGINAL_REQUEST.md §R3 |
| 11 | R4.1 Sequence Diagrams (Mermaid) | Foreground On-Open Sync and Silent Background Sync complete sequence flows | M4 | ORIGINAL_REQUEST.md §R4 |
| 12 | R4.2 ESP32-C3 Firmware Blueprint | NimBLE/ESP-IDF BLE service, L2CAP CoC / GATT high MTU, Wi-Fi SoftAP state machine | M4 | ORIGINAL_REQUEST.md §R4 |
| 13 | R4.3 Android Kotlin Reference Code | Production Kotlin reference: BLE 2M/L2CAP, WifiNetworkSpecifier socket binding, WorkManager worker | M4 | ORIGINAL_REQUEST.md §R4 |
| 14 | Final Deliverable Compilation | Comprehensive report in `research/iot_android_transfer_study.md` | M5 | ORIGINAL_REQUEST.md §Acceptance Criteria |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Protocol Deep-Dive & Survey | R1: BLE 5.0, Android Wi-Fi APIs, STA/mDNS, Plaud Note analysis | none | DONE |
| M2 | Benchmarks & Trade-Off Matrix | R2: Quantitative transfer times, power, UX, API 29-35+ constraints | M1 | DONE |
| M3 | Architecture & Recovery Protocol | R3: Optimal hybrid strategy, sync modes, CRC32 chunk recovery | M1, M2 | DONE |
| M4 | Sequence Diagrams & Reference Code | R4: Mermaid diagrams, ESP32-C3 firmware architecture, Kotlin reference code | M3 | DONE |
| M5 | Synthesis & Final Review Gate | Assemble `research/iot_android_transfer_study.md`, multi-reviewer & auditor verification | M1, M2, M3, M4 | DONE |

## Code Layout
- Deliverable: `research/iot_android_transfer_study.md` (2,034 lines, 106.8 KB)
- Metadata: `.agents/teamwork_preview_orchestrator_1/`
