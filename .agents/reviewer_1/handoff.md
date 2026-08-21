# Reviewer 1 Handoff Report

> [!WARNING] **Skepticism Disclaimer**
> Code verified through full automated unit tests, static Dart analysis, and native Android Gradle builds; physical SoftAP and captive portal behavior on physical OEM devices (Samsung OneUI, Xiaomi MIUI) remain subject to real-hardware testing.

## 1. What the prior attempt got wrong
1. **NetworkCallback Leak in Android ConnectivityManager on Network Drop / Timeout**:
   - *Input*: Wi-Fi SoftAP drops connection (`onLost`) or user dismisses connection prompt / 30s timeout occurs (`onUnavailable`).
   - *Expected*: `IotWifiManager` unregisters the `NetworkCallback` with `connectivityManager.unregisterNetworkCallback(this)` to free the OS handle and prevent hitting Android's maximum registered callbacks limit.
   - *Actual*: `onLost` and `onUnavailable` nulled out `activeCallback` in memory without unregistering it with `ConnectivityManager`. Subsequent `connect()` calls registered new callbacks, causing callback handle leaks and risk of `TooManyRequestsException`.
   - *Root Cause*: Missing `try { connectivityManager.unregisterNetworkCallback(this) } catch (_: Exception) {}` in `onLost` and `onUnavailable`.

2. **Dangling Connection Dialog on Coroutine Cancellation**:
   - *Input*: Coroutine awaiting `IotWifiManager.connect()` cancelled by user or parent scope.
   - *Expected*: Wi-Fi request is cancelled and callback unregistered immediately.
   - *Actual*: `deferred.await()` threw `CancellationException` without cleaning up the pending `requestNetwork` registration, leaving the OS Wi-Fi prompt active in system UI.
   - *Root Cause*: `connect()` did not catch `CancellationException` to trigger `disconnect()`.

3. **Redundant 1.5s BLE Hotspot Command Delay per Clip in Batch Sync**:
   - *Input*: "Adaptive Sync All" batch sync executing over 5+ clips.
   - *Expected*: Wi-Fi hotspot is started once at the batch level without re-triggering BLE commands and delays on every clip.
   - *Actual*: `downloadClip()` checked `bleService.telemetry.state != DeviceState.wifiActive`, which caused redundant `BleCommand.startWifi` and 1500ms delay for clips before BLE telemetry caught up.
   - *Root Cause*: `downloadClip()` did not gate `needStartWifi` with `!keepWifiAlive`.

4. **Destination Storage Directory Discrepancy**:
   - *Input*: Downloading audio clips via Android native `startWifiSoftApSync`.
   - *Expected*: Synced WAV files are stored in the Flutter app's canonical recordings directory (`LocalStorageManager.getRecordingsDirectory()`) so `loadSavedLocalRecordings()` sees them on next app launch.
   - *Actual*: Native layer wrote directly to `context.filesDir`, potentially separating native downloads from HTTP-downloaded recordings depending on platform paths.
   - *Root Cause*: `startWifiSoftApSync` hardcoded `File(filesDir, ...)` without accepting a custom `destinationPath`.

5. **Glob Pattern Matching Edge Cases for SoftAP SSID**:
   - *Input*: SSID pattern `XIAO-Audio-.*` or custom prefix `XIAO-Audio-*`.
   - *Expected*: Properly formatted for Android's `PatternMatcher.PATTERN_SIMPLE_GLOB`.
   - *Actual*: Hardcoded replacement of `.*` with `"XIAO-Audio-Hotspot"` broke wildcard matching for devices with custom SSID suffixes (e.g., `XIAO-Audio-Hotspot-01`).
   - *Root Cause*: Exact string substitution instead of sanitizing regex `.*` to glob wildcard `*`.

## 2. What I changed
- **`apps/companion_app/android/app/src/main/kotlin/com/sphaerox/companion_app/network/IotWifiManager.kt`**:
  - Added explicit `unregisterNetworkCallback(this)` in `onLost` and `onUnavailable` to prevent Android OS callback leaks.
  - Added `CancellationException` handling in `connect()` to cleanly invoke `disconnect()` if the calling coroutine is cancelled.
  - Improved SSID pattern sanitization from `.*` to `*` with support for optional WPA2 passphrase.
- **`apps/companion_app/android/app/src/main/kotlin/com/sphaerox/companion_app/MainActivity.kt`**:
  - Added `getWifiManager()` singleton helper to ensure consistent instance reuse across all MethodChannel calls.
  - Added `destinationPath` parameter support in `startWifiSoftApSync` and `startBleL2capSync`.
  - Added resilient fallback copy-on-rename for temporary `.part` files.
- **`apps/companion_app/android/app/src/main/kotlin/com/sphaerox/companion_app/service/AudioSyncForegroundService.kt`**:
  - Removed unused imports (`WifiConnectionState`, `flow.first`).
- **`apps/companion_app/lib/core/services/native_audio_sync_bridge.dart`**:
  - Added `destinationPath` parameter to `startWifiSoftApSync` and `startBleL2capSync`.
  - Applied Dart null-aware map elements (`'destinationPath': ?destinationPath`).
- **`apps/companion_app/lib/features/recordings/services/recording_sync_manager.dart`**:
  - Gated single-clip Wi-Fi start in `downloadClip` with `!keepWifiAlive` to eliminate redundant 1.5s delays during batch sync.
  - Passed canonical recording path (`LocalStorageManager.getRecordingsDirectory()`) to `startWifiSoftApSync`.
- **`apps/companion_app/test/hybrid_sync_test.dart`**:
  - Added unit test assertions for `startWifiSoftApSync` and `startBleL2capSync` with `destinationPath` and `keepConnected`.

## 3. Verification Record
- **Deep Verification (ran actual tests):**
  - `flutter analyze` in `apps/companion_app` (0 issues, clean).
  - `flutter test` in `apps/companion_app` (8/8 tests passed).
  - `.\gradlew.bat assembleDebug` in `apps/companion_app/android` with JDK 21 (BUILD SUCCESSFUL in 20s).
- **Shallow Verification (manual only):**
  - Code review and verification of thread safety, state locks, and coroutine scopes.
- **Unverified aspects:**
  - Physical interaction with physical XIAO ESP32-C3 hardware running SoftAP firmware.
  - OEM-specific Android aggressive captive-portal disconnections (e.g. MIUI/OneUI specific auto-reconnect prompts).

## 4. Known Issues
- `Minor Robustness Risk`: On custom OEM Android skins (e.g. MIUI, ColorOS), connecting to a Wi-Fi network without internet may trigger an OS dialog "This network has no internet. Stay connected?". If rejected by the user, Android OS terminates the connection.

## 5. Remaining risk & next step
- The implementation is complete, robust, and verified against the compiler and test suites.
- Next step: Live bench testing with physical hardware to validate end-to-end throughput and packet verification.
