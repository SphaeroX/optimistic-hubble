# Dispatch for Explorer 2: Android 10-15 Networking & Background Execution
Path: .agents/teamwork_preview_explorer_2/DISPATCH.md

## 2026-08-20T13:38:40Z
You are Explorer 2 (Android OS Networking & Background Execution) for the Research & Architectural Study: Optimal IoT-to-Android Audio Sync (XIAO ESP32-C3).

Your working directory is: c:\Users\MGasc\Documents\antigravity\optimistic-hubble\.agents\teamwork_preview_explorer_2
The user requirements are in: c:\Users\MGasc\Documents\antigravity\optimistic-hubble\ORIGINAL_REQUEST.md

Conduct an exhaustive investigation on:
1. Android Programmatic Wi-Fi APIs (Android 10 through Android 15 / API 29 to 35+):
   - `WifiNetworkSpecifier.Builder`: SSID/BSSID pattern matching, WPA2 passphrase, `NetworkRequest`, `ConnectivityManager.requestNetwork` and `ConnectivityManager.NetworkCallback`.
   - UI/UX behavior: System dialog ("Connect to device?") on API 29-35, user approval persistence, how to make it 1-tap or seamless.
   - `CompanionDeviceManager` (CDM): Association flow (`AssociationRequest`, `WifiDeviceFilter` / `BluetoothDeviceFilter`), automatic pairing, bypassing user prompts on subsequent connects, exempting app from battery optimizations.
   - Teardown & cleanup: `ConnectivityManager.unregisterNetworkCallback()`, releasing Wi-Fi lock, restoring primary network.
2. Multi-Network Routing & Cellular Internet Preservation:
   - Modern Android dual-network behavior (Cellular default internet + local Wi-Fi IoT device without internet).
   - How Android marks IoT Wi-Fi as `NET_CAPABILITY_NOT_METERED` or `NET_CAPABILITY_CAPTIVE_PORTAL` / no internet.
   - How the Android app routes HTTP requests specifically to the ESP32-C3 (192.168.4.1) using `Network.bindSocket()`, `Network.openConnection()`, or custom OkHttpClient `SocketFactory` / `Dns` bound to the IoT `Network` object, WITHOUT calling `bindProcessToNetwork()` (which would break cellular internet for the whole app/system).
3. Android OS Background Restrictions & Permission Matrix (API 29 to 35+):
   - Runtime BLE permissions: Android 12+ (API 31+) `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT` with `neverForLocation` flag.
   - Android 14 & 15 (API 34/35+) Foreground Service restrictions: `foregroundServiceType="connectedDevice"` vs `"dataSync"`. Short service / 6-hour timeouts for `dataSync`, system notification requirements.
   - Background Execution mechanisms:
     * `WorkManager` (PeriodicWorkRequest, OneTimeWorkRequest with `setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)`).
     * BLE Opportunistic / Background Scanning with `PendingIntent` or `ScanFilter`.
     * Doze mode and App Standby Buckets behavior: Whitelisting via `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`.
4. Comprehensive Android Matrix: Compare API 29, 30, 31, 33, 34, 35 requirements, permissions, and behaviors.

Write your comprehensive findings to:
`c:\Users\MGasc\Documents\antigravity\optimistic-hubble\.agents\teamwork_preview_explorer_2\analysis.md`
And write your final summary to `handoff.md` in your working directory.
Communicate completion to parent via send_message.
