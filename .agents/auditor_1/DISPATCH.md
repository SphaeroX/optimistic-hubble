## 2026-08-21T18:08:45Z

You are the Independent Victory Auditor.
Your working directory for metadata and reports is: c:\Users\MGasc\Documents\antigravity\optimistic-hubble\.agents\auditor_1
The project root is: c:\Users\MGasc\Documents\antigravity\optimistic-hubble

<original_task>
This is a single self-contained fix; keep it small and focused.

Fix the Android Wi-Fi connection lifecycle, socket binding, and recording synchronization issue between the Flutter companion app and the ESP32 MCU SoftAP.

Working directory: c:\Users\MGasc\Documents\antigravity\optimistic-hubble
Integrity mode: development

## Requirements

### R1. Wi-Fi SoftAP Connection Lifecycle & Callback Retention
Fix the native Android IotWifiManager.kt and MainActivity.kt network callback lifecycle. Currently, consuming connectToEsp32SoftAp via Kotlin Flow .first() immediately triggers awaitClose { disconnect() }, which unregisters the network callback and causes Android to tear down the Wi-Fi connection within milliseconds and fall back to cellular. The network callback and process/socket binding must remain active throughout the active transfer session and only disconnect when the sync operation is genuinely complete or cancelled.

### R2. Network Socket Routing & No-Internet SoftAP Handling
Ensure that all HTTP requests (downloading clips from http://192.168.4.1/api/download) are strictly routed through the dedicated IoT Wi-Fi network socket via IotHttpClientFactory / Network.socketFactory or bindProcessToNetwork, preventing Android's cellular data fallback or captive-portal validation from interfering with local MCU communication.

### R3. Batch & Single Clip Sync Flow Optimization
Refactor the Flutter sync logic in recording_sync_manager.dart and NativeAudioSyncBridge so that during batch synchronization ("Adaptive Sync All"), the Wi-Fi hotspot and connection are kept alive across all files rather than redundantly starting and stopping the Wi-Fi hotspot and network specifier for every individual clip.

## Acceptance Criteria

### Connection & Lifecycle Integrity
- [ ] IotWifiManager does not prematurely unregister its NetworkCallback or unbind the network while data transfer is pending or in progress.
- [ ] The app successfully connects to XIAO-Audio-Hotspot on Android 10+ using WifiNetworkSpecifier and maintains connection without looping or switching back to 4G/5G during transfer.
- [ ] Syncing multiple recordings in "Adaptive Sync All" reuses the active Wi-Fi session and gracefully shuts down the SoftAP connection only when the entire batch is completed or cancelled.

### Build & Code Quality
- [ ] Flutter app and native Android project compile cleanly (./gradlew assembleDebug / flutter analyze).
- [ ] All code comments and identifiers adhere to the project's English language standards.
</original_task>

Conduct a 3-phase victory audit (timeline verification, cheating detection, independent test execution) against the codebase and git history.
Write your audit report and final verdict (CONFIRMED / REJECTED) to c:\Users\MGasc\Documents\antigravity\optimistic-hubble\.agents\auditor_1\handoff.md and report back your verdict.
