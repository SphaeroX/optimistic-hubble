# BRIEFING — 2026-08-20T13:40:45Z

## Mission
Investigate Android OS Networking & Background Execution (API 29-35+) for XIAO ESP32-C3 Audio Sync (Programmatic Wi-Fi, CompanionDeviceManager, Multi-Network Routing, Foreground Services, WorkManager, Permissions).

## 🔒 My Identity
- Archetype: explorer
- Roles: investigation, synthesis
- Working directory: c:\Users\MGasc\Documents\antigravity\optimistic-hubble\.agents\teamwork_preview_explorer_2
- Original parent: ff5b3206-dca0-46f5-be4f-e7353b2157c6
- Milestone: Explorer 2 Technical Deep Dive & Architectural Analysis

## 🔒 Key Constraints
- Read-only investigation — do NOT implement
- All code/comments in English, communication with user in German (if any), coordination via files/messages
- Target Android versions: Android 10 (API 29) to Android 15 (API 35+)
- Ensure high-precision API specifications, concrete Kotlin reference patterns, and comprehensive version matrix

## Current Parent
- Conversation ID: ff5b3206-dca0-46f5-be4f-e7353b2157c6
- Updated: 2026-08-20T13:40:45Z

## Investigation State
- **Explored paths**:
  - Android Programmatic Wi-Fi APIs (API 29–35+): `WifiNetworkSpecifier.Builder`, `NetworkRequest`, `ConnectivityManager.requestNetwork`, UI/UX prompt constraints, `CompanionDeviceManager` (CDM), and ephemeral connection cleanup.
  - Multi-Network Routing & Cellular Internet Preservation: Linux kernel routing, `SO_BINDTODEVICE`, `bindProcessToNetwork` anti-pattern vs. OkHttp `socketFactory` isolation.
  - Background Execution & Permissions (API 29–35+): BLE `neverForLocation` flag, Android 14/15 FGS mandates (`connectedDevice` vs `dataSync`), WorkManager expedited jobs, low-power BLE PendingIntent hardware scanning, Doze mode & battery exemptions.
- **Key findings**:
  - `WifiNetworkSpecifier` strictly requires foreground UI user confirmation on Android 10+ and cannot be executed silently in the background.
  - Dual networking is fully supported by binding only the IoT `OkHttpClient` to `network.socketFactory`, leaving general internet and cloud APIs routed over 5G/LTE Cellular.
  - Pure BLE 5.0 (L2CAP CoC / 2M PHY) is the only viable zero-click, silent background transfer channel (0.48 MB in ~4.8s).
  - Recommended hybrid architecture: Pure BLE 5.0 for silent background sync (< 2 MB) and 1-tap `WifiNetworkSpecifier` SoftAP HTTP sync for large recordings (> 2 MB, up to 16 MB in ~8s).
  - Foreground Service must use `foregroundServiceType="connectedDevice"` (Android 14/15 compliant).
- **Unexplored areas**: None. All requirements for Explorer 2 fully investigated and documented.

## Key Decisions Made
- Authored comprehensive technical analysis report at `.agents/teamwork_preview_explorer_2/analysis.md`
- Authored 5-component self-contained handoff report at `.agents/teamwork_preview_explorer_2/handoff.md`

## Artifact Index
- `.agents/teamwork_preview_explorer_2/analysis.md` — Full technical deep-dive report with architecture diagrams and production-ready Kotlin reference code.
- `.agents/teamwork_preview_explorer_2/handoff.md` — 5-component handoff report (Observation, Logic Chain, Caveats, Conclusion, Verification Method).
- `.agents/teamwork_preview_explorer_2/progress.md` — Liveness & task execution tracker.
- `.agents/teamwork_preview_explorer_2/DISPATCH.md` — Dispatch log.
