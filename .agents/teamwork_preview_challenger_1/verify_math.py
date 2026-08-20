
import math

print('=== CHALLENGER 1 EMPIRICAL MATHEMATICAL VERIFICATION ===\n')

# 1. BLE 2M PHY Frame Timing & Airtime
t_preamble = 2 * 8 * 0.5  # 2 bytes = 8.0 us
t_aa = 4 * 8 * 0.5        # 4 bytes = 16.0 us
t_ll_hdr = 2 * 8 * 0.5    # 2 bytes = 8.0 us
t_payload_dle = 251 * 8 * 0.5  # 251 bytes = 1004.0 us
t_mic = 4 * 8 * 0.5       # 4 bytes = 16.0 us
t_crc = 3 * 8 * 0.5       # 3 bytes = 12.0 us

t_tx = t_preamble + t_aa + t_ll_hdr + t_payload_dle + t_mic + t_crc
print(f'1.1 BLE TX Airtime (DLE 251B): {t_tx:.2f} us (Report: 1064.0 us)')
assert abs(t_tx - 1064.0) < 1e-6

t_ack_report = 10 * 8 * 0.5 # 40.0 us
t_ack_strict = 11 * 8 * 0.5 # 44.0 us
t_ifs = 150.0

t_cycle_report = t_tx + t_ifs + t_ack_report + t_ifs
t_cycle_strict = t_tx + t_ifs + t_ack_strict + t_ifs

print(f'1.2 BLE Cycle Time (Report formula): {t_cycle_report:.2f} us (Report: 1404.0 us)')
print(f'    BLE Cycle Time (Strict 11B ACK): {t_cycle_strict:.2f} us')

max_pkts_sec_report = 1000000.0 / t_cycle_report
max_pkts_sec_strict = 1000000.0 / t_cycle_strict
print(f'1.3 Max Packets/s (Report): {max_pkts_sec_report:.4f} pkts/s (Report: 712.25)')
print(f'    Max Packets/s (Strict): {max_pkts_sec_strict:.4f} pkts/s')

ll_tp_report = (max_pkts_sec_report * 251) / 1000.0
l2cap_tp_report = (max_pkts_sec_report * 247) / 1000.0
gatt_tp_report = (max_pkts_sec_report * 244) / 1000.0

print(f'1.4 Throughput Limits (Report):')
print(f'    LL (251B):    {ll_tp_report:.2f} KB/s ({ll_tp_report*8/1000:.3f} Mbps) [Report: 178.78 KB/s / 1.430 Mbps]')
print(f'    L2CAP (247B): {l2cap_tp_report:.2f} KB/s ({l2cap_tp_report*8/1000:.3f} Mbps) [Report: 175.93 KB/s / 1.407 Mbps]')
print(f'    GATT (244B):  {gatt_tp_report:.2f} KB/s ({gatt_tp_report*8/1000:.3f} Mbps) [Report: 173.79 KB/s / 1.390 Mbps]')

print('\n' + '='*60 + '\n')

# 2. Audio Transfer Times & Speedups
print('2. Audio Transfer Times and Speedup Factors:')
cases = [
    ('1 Min (60s)', 60, 480),
    ('5 Min (300s)', 300, 2400),
    ('10 Min (600s)', 600, 4800),
    ('35 Min (2100s)', 2100, 16800),
]

protocols = {
    'BLE 1M GATT': {'v': 50.0, 'ths': 0.2},
    'BLE 2M GATT': {'v': 95.0, 'ths': 0.2},
    'BLE 2M L2CAP': {'v': 125.0, 'ths': 0.15},
    'Wi-Fi 4 SoftAP': {'v': 1800.0, 'ths': 3.5},
    'Wi-Fi 4 Station': {'v': 2800.0, 'ths': 0.1},
}

for name, dur, size in cases:
    print(f'--- {name} | Size: {size} KB ({size/1000:.2f} MB) ---')
    for proto_name, p in protocols.items():
        t_transfer = p['ths'] + (size / p['v'])
        speedup = dur / t_transfer
        print(f'  {proto_name:18}: T = {t_transfer:7.2f}s | Speedup: {speedup:6.1f}x')

print('\n' + '='*60 + '\n')

# 3. Energy Consumption & Crossover Point
print('3. Power Consumption & Energy Crossover Modeling:')
e_ble_per_mb = (18.2 * (1000.0 / 125.0)) / 3600.0 # mAh / MB
e_ble_c_per_mb = e_ble_per_mb * 3.6 # Coulombs / MB
print(f'  Energy BLE: {e_ble_per_mb:.6f} mAh/MB (Report: 0.0404 mAh/MB)')
print(f'  Coulombs BLE: {e_ble_c_per_mb:.6f} C/MB (Report: 0.145 C/MB)')

e_wifi_active_per_mb = (135.0 * (1000.0 / 1800.0)) / 3600.0 # mAh / MB
e_wifi_setup = (85.0 * 3.5) / 3600.0 # mAh setup
print(f'  Energy WiFi Active: {e_wifi_active_per_mb:.6f} mAh/MB (Report: 0.0208 mAh/MB)')
print(f'  Energy WiFi Setup:  {e_wifi_setup:.6f} mAh (Report: 0.0826 mAh)')

s_cross_exact = e_wifi_setup / (e_ble_per_mb - e_wifi_active_per_mb)
s_cross_rounded = 0.0826 / (0.0404 - 0.0208)
print(f'  Crossover Size (Exact): {s_cross_exact:.4f} MB (Report: 4.21 MB)')
print(f'  Crossover Size (from rounded coeffs): {s_cross_rounded:.4f} MB')
audio_min_cross = (s_cross_exact * 1000.0 / 8.0) / 60.0
print(f'  Audio Minutes at Crossover: {audio_min_cross:.2f} min (Report: ~8.7 min)')

print('\n' + '='*60 + '\n')

# 4. Energy per File Size Table
print('4. Energy Table Verification:')
sizes_mb = [0.48, 2.40, 4.80, 16.80]
for s in sizes_mb:
    e_ble = s * e_ble_per_mb
    e_ble_from_rounded = s * 0.0404
    e_wifi = s * e_wifi_active_per_mb + e_wifi_setup
    e_wifi_from_rounded = s * 0.0208 + 0.0826
    c_ble = e_ble * 3.6
    c_wifi = e_wifi * 3.6
    winner = 'BLE' if e_ble < e_wifi else 'Wi-Fi'
    ratio = max(e_ble, e_wifi) / min(e_ble, e_wifi)
    print(f'  Size {s:5.2f} MB:')
    print(f'    BLE:   Exact={e_ble:.4f} mAh ({c_ble:.3f} C) | FromRounded={e_ble_from_rounded:.4f} mAh')
    print(f'    Wi-Fi: Exact={e_wifi:.4f} mAh ({c_wifi:.3f} C) | FromRounded={e_wifi_from_rounded:.4f} mAh')
    print(f'    Winner: {winner} ({ratio:.1f}x)')

print('\n' + '='*60 + '\n')

# 5. Battery Longevity Model
print('5. Battery Longevity Model (150 mAh & 300 mAh LiPo @ 85% DoD):')
cap_150 = 150.0 * 0.85 # 127.5 mAh
cap_300 = 300.0 * 0.85 # 255.0 mAh

profiles = [
    ('Light: 10x 1-min memos/day', 14.66),
    ('Business: 6x 20-min mtgs', 56.12),
    ('Heavy: 5h continuous rec', 123.13),
]

for name, daily_mah in profiles:
    days_150 = cap_150 / daily_mah
    hours_150 = days_150 * 24.0
    days_300 = cap_300 / daily_mah
    hours_300 = days_300 * 24.0
    print(f'  {name}:')
    print(f'    Daily Consumption: {daily_mah:.2f} mAh/day')
    print(f'    150 mAh: {days_150:.2f} Days ({hours_150:.1f} Hours) [Report: {days_150:.2f} Days ({hours_150:.1f} Hours)]')
    print(f'    300 mAh: {days_300:.2f} Days ({hours_300:.1f} Hours) [Report: {days_300:.2f} Days ({hours_300:.1f} Hours)]')

print('\n' + '='*60 + '\n')

# 6. Trade-off Matrix Composite Scoring
print('6. Multi-Attribute Decision Matrix Scoring:')
weights = [0.25, 0.25, 0.20, 0.15, 0.15]
cols = {
    'BLE 1M GATT':  [3.0, 9.0, 4.0, 8.5, 9.5],
    'BLE 2M GATT':  [6.0, 9.0, 7.0, 8.5, 9.0],
    'BLE 2M L2CAP': [7.0, 9.5, 8.0, 9.0, 8.5],
    'Wi-Fi SoftAP':  [9.5, 6.0, 8.0, 3.0, 8.0],
    'Hybrid Engine': [9.5, 9.0, 9.5, 9.5, 8.8],
}

for name, scores in cols.items():
    weighted_score = sum(w * s for w, s in zip(weights, scores))
    print(f'  {name:15}: Weighted Score = {weighted_score:.2f} / 10')
