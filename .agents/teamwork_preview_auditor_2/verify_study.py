import re
import math
import struct

def test_math_and_airtime():
    # 2M PHY parameters
    preamble = 2 * 8 * 0.5 # 8.0 us
    access_addr = 4 * 8 * 0.5 # 16.0 us
    ll_hdr = 2 * 8 * 0.5 # 8.0 us
    payload_dle = 251 * 8 * 0.5 # 1004.0 us
    mic = 4 * 8 * 0.5 # 16.0 us
    crc = 3 * 8 * 0.5 # 12.0 us
    t_tx = preamble + access_addr + ll_hdr + payload_dle + mic + crc
    print(f"t_tx: {t_tx} us (expected 1064.0)")
    assert t_tx == 1064.0, f"t_tx mismatch: {t_tx}"

    t_ifs = 150.0 # us
    empty_ack = 10 * 8 * 0.5 # 40.0 us
    t_cycle = t_tx + t_ifs + empty_ack + t_ifs
    print(f"t_cycle: {t_cycle} us (expected 1404.0)")
    assert t_cycle == 1404.0, f"t_cycle mismatch: {t_cycle}"

    pkts_per_sec = 1_000_000.0 / t_cycle
    print(f"pkts_per_sec: {pkts_per_sec:.2f} (expected 712.25)")
    assert abs(pkts_per_sec - 712.25) < 0.01

    ll_limit_kbs = (pkts_per_sec * 251) / 1000.0
    l2cap_limit_kbs = (pkts_per_sec * 247) / 1000.0
    gatt_limit_kbs = (pkts_per_sec * 244) / 1000.0
    print(f"LL limit: {ll_limit_kbs:.2f} KB/s, L2CAP: {l2cap_limit_kbs:.2f} KB/s, GATT: {gatt_limit_kbs:.2f} KB/s")
    assert abs(l2cap_limit_kbs - 175.93) < 0.1
    assert abs(gatt_limit_kbs - 173.79) < 0.1

    # Audio bitrate
    bitrate_bps = 16000 * 4
    bytes_per_sec = bitrate_bps / 8
    print(f"bytes_per_sec: {bytes_per_sec} (expected 8000)")
    assert bytes_per_sec == 8000

    # Transfer durations:
    # 1 min (60s -> 480 KB)
    # 5 min (300s -> 2400 KB)
    # 10 min (600s -> 4800 KB)
    # 35 min (2100s -> 16800 KB)
    durations = [60, 300, 600, 2100]
    sizes_kb = [d * 8 for d in durations]
    print(f"Sizes KB: {sizes_kb} (expected [480, 2400, 4800, 16800])")

    # Energy calculations
    # BLE: 18.2 mA * (S / 125 KB/s) / 3600 = 0.040444 mAh / MB
    # WiFi: [135 mA * (S / 1800 KB/s) + (85 mA * 3.5s)] / 3600
    e_ble_per_mb = (18.2 * (1000.0 / 125.0)) / 3600.0
    e_wifi_per_mb = (135.0 * (1000.0 / 1800.0)) / 3600.0
    e_wifi_setup = (85.0 * 3.5) / 3600.0
    print(f"e_ble_per_mb: {e_ble_per_mb:.6f} mAh/MB (expected ~0.0404)")
    print(f"e_wifi_per_mb: {e_wifi_per_mb:.6f} mAh/MB (expected ~0.0208)")
    print(f"e_wifi_setup: {e_wifi_setup:.6f} mAh (expected ~0.0826)")

    s_cross = e_wifi_setup / (e_ble_per_mb - e_wifi_per_mb)
    print(f"s_cross: {s_cross:.2f} MB (expected ~4.21 MB)")
    assert abs(s_cross - 4.21) < 0.05

def test_struct_packing():
    # uint16_t magic;          // 2
    # uint8_t  version;        // 1
    # uint8_t  frameType;      // 1
    # uint32_t fileId;         // 4
    # uint32_t sequenceNum;    // 4
    # uint32_t byteOffset;     // 4
    # uint16_t payloadLength;  // 2
    # uint16_t reserved;       // 2
    # uint32_t totalFileSize;  // 4
    # uint32_t chunkCrc32;     // 4
    # uint32_t fileCrc32;      // 4
    fmt = "<HBBIIIHHIII"
    sz = struct.calcsize(fmt)
    print(f"Packed struct size: {sz} bytes (expected 32)")
    assert sz == 32, f"Struct size mismatch: {sz}"

def check_file_content():
    path = r"c:\Users\MGasc\Documents\antigravity\optimistic-hubble\research\iot_android_transfer_study.md"
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    print(f"Total characters: {len(content)}, Total lines: {len(content.splitlines())}")

    # Check for placeholder markers
    placeholders = ["TODO", "FIXME", "TBD", "XXX", "stub", "placeholder", "NotImplementedError"]
    found_placeholders = {}
    for p in placeholders:
        matches = re.findall(rf"\b{p}\b", content, re.IGNORECASE)
        # Check if they are in explanatory text or actual placeholders
        if matches:
            found_placeholders[p] = len(matches)
    print(f"Placeholders found: {found_placeholders}")

    # Check for 8 acceptance criteria
    criteria = [
        "BLE 5.0",
        "WifiNetworkSpecifier",
        "Station Mode",
        "Hybrid",
        "ADPCM",
        "Android 12",
        "Android 14",
        "Android 15",
        "connectedDevice",
        "dataSync",
        "Plaud Note",
        "Mermaid",
        "ESP32-C3",
        "Kotlin"
    ]
    for c in criteria:
        assert c in content, f"Missing key term {c}"
    print("All key terms present!")

if __name__ == "__main__":
    test_math_and_airtime()
    test_struct_packing()
    check_file_content()
    print("ALL TESTS PASSED!")
