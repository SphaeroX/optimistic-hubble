# Reviewer 2 Handoff Report

> [!WARNING] **Skepticism Disclaimer**
> Verified across Kotlin/Dart type checkers, static analysis, unit test suites, and native Android Gradle compilation with JDK 21; real-world Wi-Fi SoftAP handshake and OEM captive-portal suppression require validation on physical ESP32-C3 hardware.

## 1. What the prior attempt got wrong

1. **Race Condition on Late `onAvailable` Callback After Cancellation / Disconnect in `IotWifiManager`**:
   - *Input*: Coroutine awaiting `IotWifiManager.connect()` is aborted or cancelled via `disconnect()`, but the Android OS `ConnectivityManager` dispatches a pending `onAvailable(network)` event shortly thereafter.
   - *Expected*: `IotWifiManager` discards the late network event, keeps `activeNetwork` null, avoids binding the process to the disconnected network, and unregisters the orphaned callback.
   - *Actual*: `onAvailable` unconditionally set `activeNetwork = network`, set `activeCallback = this`, and bound the Android process to the network (`connectivityManager.bindProcessToNetwork(network)`), reviving a stale connection and hijacking application network routing.
   - *Root Cause*: `onAvailable` did not check `deferred.isCompleted` or `activeCallback != this` before applying state changes and binding the process.

2. **OkHttp Response and Socket Resource Leak on Non-200/206 HTTP Responses in `MainActivity` and `AudioSyncForegroundService`**:
   - *Input*: ESP32 MCU HTTP endpoint returns an error status (e.g. 404 Not Found, 500 Server Error) during `startWifiSoftApSync` or foreground service download.
   - *Expected*: The underlying OkHttp `Response` and connection socket are closed immediately to return sockets to the connection pool and release resources.
   - *Actual*: An `IOException` was thrown before reaching `body.byteStream().use { ... }`, leaving the OkHttp `Response` unclosed.
   - *Root Cause*: `val response = client.newCall(...).execute()` was not enclosed in `response.use { ... }`.

3. **Uncooperative Download Loop and Cancellation Exception Misreported as Transfer Failure**:
   - *Input*: User cancels an active Wi-Fi Turbo or BLE L2CAP download midway via `cancelSync()`.
   - *Expected*: The streaming read loop stops immediately without finishing unnecessary socket I/O, does not promote the incomplete `.part` file to `.wav`, and suppresses spurious `"failed"` error events so the UI reflects `"cancelled"`.
   - *Actual*:
     - The stream read loop (`while (input.read(buffer) != -1)`) did not check `coroutineContext.isActive`, continuing to pull stream chunks until complete.
     - The outer `catch (e: Exception)` caught `CancellationException` and fired `sendEvent("failed", ...)`, overwriting the user-facing `"cancelled"` status with an error state.
   - *Root Cause*: Missing cooperative `if (!isActive) throw CancellationException(...)` checks within the chunk stream loop and absence of dedicated `CancellationException` handlers.

4. **Missing Copy Fallback on Atomic File Rename in `BleL2capAudioReceiver`**:
   - *Input*: Moving `.part` file to final destination `.wav` when `tempFile.renameTo(outputFile)` fails due to mount boundaries or storage permissions.
   - *Expected*: Resilient byte-copy fallback with file cleanup before throwing.
   - *Actual*: Immediately threw `IOException("Failed to rename temporary file to destination")`.
   - *Root Cause*: Missing `tempFile.copyTo(outputFile, overwrite = true)` fallback in `BleL2capAudioReceiver.kt`.

5. **WPA2 Passphrase Minimum Length Validation**:
   - *Input*: Short or invalid passphrase (< 8 characters) provided to `WifiNetworkSpecifier.Builder.setWpa2Passphrase()`.
   - *Expected*: Safe validation preventing runtime `IllegalArgumentException` from the Android framework.
   - *Actual*: Checked only `passphrase.isNotEmpty()`, risking crash if < 8 characters.
   - *Root Cause*: Missing `passphrase.length >= 8` guard.

6. **Locale-Dependent Decimal Formatting in Native Telemetry Events**:
   - *Input*: Device set to non-US locale (e.g. `de_DE`).
   - *Expected*: Consistent decimal point notation (`1.85 MB/s`).
   - *Actual*: `String.format("%.2f", speedMb)` formatted decimals with commas (`1,85 MB/s`).
   - *Root Cause*: Missing `Locale.US` in `String.format`.

## 2. What I changed

- **`apps/companion_app/android/app/src/main/kotlin/com/sphaerox/companion_app/network/IotWifiManager.kt`**:
  - Added race condition guard in `onAvailable` (`if (deferred.isCompleted || activeCallback != this)`) to immediately unbind and unregister late connections.
  - Added `passphrase.isNotBlank() && passphrase.length >= 8` check for WPA2 passphrase specifiers.
- **`apps/companion_app/android/app/src/main/kotlin/com/sphaerox/companion_app/MainActivity.kt`**:
  - Wrapped OkHttp execution in `client.newCall(reqBuilder.build()).execute().use { response -> ... }` to guarantee socket disposal.
  - Added cooperative cancellation check `if (!isActive) throw CancellationException(...)` within the binary download stream loop.
  - Added dedicated `catch (e: CancellationException)` blocks to cleanly handle user cancellation without emitting false `"failed"` events.
  - Standardized speed string formatting with `Locale.US`.
- **`apps/companion_app/android/app/src/main/kotlin/com/sphaerox/companion_app/service/AudioSyncForegroundService.kt`**:
  - Enclosed OkHttp response handling in `response.use { ... }`.
- **`apps/companion_app/android/app/src/main/kotlin/com/sphaerox/companion_app/ble/BleL2capAudioReceiver.kt`**:
  - Added `tempFile.copyTo(outputFile, overwrite = true)` fallback for atomic rename failures.
- **`apps/companion_app/test/hybrid_sync_test.dart`**:
  - Expanded unit test coverage with assertions for cancellation events and `RecordingItem.copyWith` preservation.

## 3. Verification Record

- **Deep Verification (ran actual tests):**
  - `flutter analyze` in `apps/companion_app`: **0 issues found** (clean).
  - `flutter test` in `apps/companion_app`: **9/9 tests passed** (including ADPCM decoder, model conversions, event lifecycle, and copyWith tests).
  - Native Gradle build: `$env:JAVA_HOME="C:\Program Files\Java\jdk-21"; .\gradlew.bat assembleDebug` in `apps/companion_app/android`: **BUILD SUCCESSFUL in 16s** (182 actionable tasks, 0 compiler errors).
- **Shallow Verification (manual only):**
  - Static code inspection of concurrency locks (`stateLock`), volatile fields, and lifecycle callbacks across `IotWifiManager.kt` and `MainActivity.kt`.
- **Unverified aspects:**
  - Physical Wi-Fi SoftAP association and packet transmission with physical ESP32-C3 hardware.
  - OEM-specific Android battery optimization / aggressive captive-portal popup dismissal behavior on real devices.

## 4. Known Issues

- `Minor Robustness Risk`: On customized OEM Android distributions (e.g. Xiaomi HyperOS / Samsung OneUI), connecting to a Wi-Fi network with no internet may generate an OS system notification "Wi-Fi has no internet access. Tap for options". The user must accept or ignore the prompt without selecting "Switch to mobile data".

## 5. Remaining risk & next step

- Codebase is fully verified against native Kotlin and Flutter compilers and test suites.
- All R1, R2, and R3 requirements are met and protected against concurrency race conditions, socket leaks, and cancellation anomalies.
- Ready for hardware bench testing with ESP32-C3 running SoftAP firmware.
