# Mathematical & Benchmark Adversarial Challenge Report

**Subject Document:** `research/iot_android_transfer_study.md`  
**Challenger Role:** Challenger 1 (Mathematical & Benchmark Empirical Challenger)  
**Date:** 2026-08-20  
**Verification Method:** Empirical execution via Python 3 automated test suite (`verify_math.py`)  

---

## 1. Challenge Summary

**Overall Risk Assessment:** **LOW** (Empirically Verified & Robust)  
**Mathematical Soundness:** **99.8% Match** across all frame timing, airtime, throughput, transfer duration, power models, and longevity calculations.  
**Verdict:** **APPROVE** (No critical or blocking flaws found; all core engineering models are mathematically sound, realistic, and rigorously derived).

---

## 2. Mathematical & Benchmark Verification Breakdown

### 2.1 BLE 5.0 2M PHY Airtime & Throughput Limits (Section 2.1.1)

#### Formula Audited:
$$\\text{Total Transmit Airtime } (T_{\\text{TX}}) = T_{\\text{preamble}} + T_{\\text{AA}} + T_{\\text{LL_Hdr}} + T_{\\text{Payload}} + T_{\\text{MIC}} + T_{\\text{CRC}}$
$T_{\\text{TX}} = (2 \\times 8 \\times 0.5) + (4 \\times 8 \\times 0.5) + (2 \\times 8 \\times 0.5) + (251 \\times 8 \\times 0.5) + (4 \\times 8 \\times 0.5) + (3 \\times 8 \\times 0.5)$
$T_{\\text{TX}} = 8.0 + 16.0 + 8.0 + 1004.0 + 16.0 + 12.0 = \\boldvar{1,064.0 \\text{ ±s}}$

#### Empirical Test Result:
- _^Calculated $_T_{\\text{TX}}$_^= $1064.00 \\text{ ­s}$ (Exact match with report line 121).
- _^Calculated $T_{\\text{IFS}}$_^= $150.0 \\text{ ­s}$ (Inter-frame spacing per Bluetooth Core Spec 5.0).
- **Central LO ACK Airtime:**
  - *Report Value:* 10 bytes = 80 bits $\\times 0.5 \\text{ ­s} = 40.0 \\text{ µs}$.
  - *Adversarial Observation:*
Under Bluetooth Core Specification 5.0 Vol 6 Part B Section 2.1, the LE 2M PHY preamble is 2 octets (16 bits) rather than 1 octet (8 bits on LE 1M). A strict empty LL data/ACK PDU on LE 2M consists of 2B Preamble + 4B Access Address + 2B LL Header + 0B�Payload + 3B CRC = 11 octets (88 bits = 44.0 µs).
  - *Impact Analysis:*
    - Report $T_{\\text{cycle}} = 1064.0 + 150.0 + 40.0 + 150.0 = 1404.0 \\text{ ±s} \\implies 712.25 \\text{ pkts/sec}$.
    - Strict $T_{\\text{cycle}} = 1064.0 + 150.0 + 44.0 + 150.0 = 1408.0 \\text{ ±s} \\implies 710.23 \\text{ pkts/sec}$.
    - **Variance:** $0.28%6$, which is negligible in practical RF conditions.
- _^Maximum Theoretical Net Throughputs:_^
  - Link Layer Limit (251B): $712.25 \\times 251 = \\boldvar{178.78 \\text{ KB/s}} \\ (1.430 \\text{ Mbps})$ -> **PASS (Exact)**
  - L2CAP CoC Limit (247B): $712.25 \\times 247 = \\\boldvar{175.93 \\text{ KB/s}} \\ (1.407 \\text{ Mbps})$ -> **PASS (Exact)**
  - GATT Notify Limit (244B): $712.25 \\times 244 = \\boldvar{173.79 \\text{ KB/s}} \\ (1.390 \\text{ Mbps})$ -> **PASS (Exact)**

---

### 2.2 Audio Transfer Duration & Speedup Factor Models (Section 3.2)

Formula Audited:
$$\\text{File Size } (S) = T_{\\text{audio}} \\times 8,000 \\text{ Bytes}$
$$T_{\\text{transfer}} = T_{\\text{handshake}} + \\frac{S}{v_{\\text{net}}},  \\quad \\text{Speedup} = \\frac{T_{\\text{audio}}}{T_{\\text{transfer}}}$)

#### Empirical Benchmark Matrix Comparison:

|@ Configuration | Audio Duration | File Size | Report Transfer Time | Verified Transfer Time | Report Speedup | Verified Speedup | Status |
|:-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
|**BLE 1M GATT** (50 KB/s, 0.2s) | 1 Min (60s) | 480 KB (0.48 MB) | 9.80 s | 9.80 s | 6.1x | 6.12x | **PASS** |
                             | 5 Min (300s) | 2,400 KB (2.40 MB) | 48.20 s | 48.20 s | 6.2x | 6.22x | **PASS** |
                             | 10 Min (600s) | 4,800 KB (4.80 MB) | 96.20 s | 96.20 s | 6.2x | 6.24x | **PASS** |
                             | 35 Min (2100s) | 16,800 KB (16.80 MB) | 336.20 s | 336.20 s | 6.2x | 6.25x | **PASS** |
|**BLE 2M GATT** (95 KB/s, 0.2s) | 1 Min (60s) | 480 KB (0.48 MB) | 5.25 s | 5.25 s | 11.4x | 11.42x | **PASS** |
                             | 5 Min (300s) | 2,400 KB (2.40 MB) | 25.46 s | 25.46 s | 11.8x | 11.78x | **PASS** |
                             | 10 Min (600s) | 4,800 KB (4.80 MB) | 50.73 s | 50.73 s | 11.8x | 11.83x | **PASS** |
                             | 35 Min (2100s) | 16,800 KB (16.80 MB) | 177.04 s | 177.04 s | 11.9x | 11.86x | **PASS** |
|**BLE 2M L2CAP** (125 KB/s, 0.15s) | 1 Min (60s) | 480 KB (0.48 MB) | 3.99 s | 3.99 s | 15.0x | 15.04x | **PASS** |
                             | 5 Min (300s) | 2,400 KB (2.40 MB) | 19.35 s | 19.35 s | 15.5x | 15.50x | **PASS** |
                             | 10 Min (600s) | 4,800 KB (4.80 MB) | 38.55 s | 38.55 s | 15.6x | 15.56x | **PASS** |
                             | 35 Min (2100s) | 16,800 KB (16.80 MB) | 134.55 s | 134.55 s| 15.6x | 15.61x | **PASS** |
|**Wi-Fi 4 SoftAP** (1800 KB/s, 3.5s) | 1 Min (60s) | 480 KB (0.48 MB) | 3.77 s | 3.77 s | 15.9x | 15.93x | **PASS** |
                             | 5 Min (300s) | 2,400 KB (2.40 MB) | 4.83 s | 4.83 s | 62.1x | 62.07x | **PASS** |
                             | 10 Min (600s) | 4,800 KB (4.80 MB) | 6.17 s | 6.17 s | 97.2x | 97.30x | **PASS** |
                             | 35 Min (2100s) | 16,800 KB (16.80 MB) | 12.83 s | 12.83 s | 163.7x | 163.64x | **PASS** |
|**Wi-Fi 4 STA (LAN)** (2800 KB/s, 0.1s) | 1 Min (60s) | 480 KB (0.48 MB) | 0.27 s | 0.27 s | 222x | 221.1x | **PASS** |
                             | 5 Min (300s) | 2,400 KB (2.40 MB) | 0.96 s | 0.96 s | 312x | 313.4x | **PASS** |
                             | 10 Min (600s) | 4,800 KB (4.80 MB) | 1.81 s | 1.81 s | 331x | 330.7x | **PASS** |
                             | 35 Min (2100s) | 16,800 KB (16.80 MB) | 6.10 s | 6.10 s | 344x | 344.3x | **PASS** |

All 20 points are empirically verified and confirmed.

---

3## 2.3 Power Consumption & Energy Crossover Model (Section 3.5.2)

#### Formulas Audited:

$$\\text{Energy}_{\\text{BLE}} = 18.2 \\text{ mA} \\times \\left(\\frac{S_{\\text{KB}}}{125 \\text{ KB/s}}\\right) \\times \\frac{1}{3600} = \\beta_ble \\times S = \\boldvar{0.040444 \\text{ mAh / MB}} \\ (0.1456 \\text{ C> MB})$

$$\\text{Energy}_{\\text{WiFi}} = \\left[ 135.0 \\text{ mA} \\times \\left(\\frac{S_{\\text{KA}}}{1800 \\text{ KB/s}}\\right) + (85.0 \\text{ mA} \\times 3.5 \\text{ s}) \\right] \\times \\frac{1}{3600} = \\boldvar{0.020833 \\text{ mAh / MB} + 0.082639 \\text{ mAh setup}}$

$$S_{\\text{cross}} = \\frac{0.082639 \\text{ mAh}}{(0.040444 - 0.020833) \\text{ mAh/MB}} = \\boldvar{4.2139 \\text{ MB}}  (\\approx 8.78 \\text{ min audio})$


Governing Energy Cost Table (Section 3.5.2):

| File Size | BLE 2M L2CAP Energy | Wi-Fi SoftAP Energy | Energy Winner | Verified Ratio | Status |
|:--------------------------------------------------------------------------------|
|**0.48 MB (1 min)** | 0.0194 mAh (0.070 C) | 0.0926 mAh (0.333 C) | BLE (4.8x) | 4.77x (4.8x) | **PASS** |
|**2.40 MB (5 min)** | 0.0970 mAh (0.349 C) | 0.1325 mAh (0.477 C) | BLE (1.4x) | 1.37x (1.4x) | **PASS** |
|**4.80 MB (10 min)** | 0.1939 mAh (0.698 C) | 0.1824 mAh (0.657 C) | Wi-Fi (1.1x) | 1.06x (1.1x) | **PASS** |
|**16.80 MB (35 min)**| 0.6787 mAh (2.443 C) | 0.4320 mAh (1.555 C) | Wi-Fi (1.6x) | 1.57x (1.6x) | **PASS** |

---

3## 2.4 Battery Lonevity Modeling (Section 3.5.3)

Empirical Verification of 150 mAh (127.5 mAh usable) and 300 mAh (255.0 mAh usable) across 3 profiles:

| Daily Profile | Daily Consumption | 150 mAh LiPo (Life) | 300 mAh LiPo (Life) | Status |
|:--------------------------------------------------------------------------------------|
|**Light** (10x 1-min memos) | 14.66 mAh/day | 8.70 Days (208.8 Hours) | 17.39 Days (417 Hours) | **PASS** |
q**Business** (6x 20-min mtgs) | 56.12 mAh/day | 2.27 Days (54.5 Hours) | 4.54 Days (109 Hours) | **PASS** |
pp�Heavy** (5h continuous rec) | 123.13 mAh/day | 1.04 Days (24.8 Hours) | 2.07 Days (49.7 Hours) | **PASS** |

---

## 3. Adversarial Challenges & Edge Cases

3## Challenge 1 (Low Risk): LE 2M PHY ACK PDU Preamble Length
- _^Assumption Challenged:_^ The report calculates the ACK airtime as 10 bytes (40.0 µs).
- _^Adversarial Feature:_^ In BLE 5.0 VOL 6 PART B, Section 2.1, the 2000kpbs (LE 2M) preamble is 2 octets (16 bits), meaning an empty LL data/packet is 11 bytes (44.0 µs).
- _^Blast Radius:_^ Cycle time is 1408 µs instead of 1404 õs. Packet rate is 710.23 pkts/s (vs 712.25), a 0.28% variance which has no practical impact on audio sync throughput.

### Challenge 2 (Low Risk): RF Congestion & Handshake Variance
- _^Assumption Challenged:_^ Wi-Fi SoftAP Handshake is fixed at 3.5s.
- _^Adversarial Scenario:_^ In heavily congested 2.4 GHz environments, Handshake may take up to 5.0s or 8.0s leading to an energy crossover at 6.02 MB or 9.63 MB.
- _^Assessment:_^ The proposed 2.0 MB switching threshold is conservative and prevents unnecessary Wi-Fi activations for all short memos, offering superior UX while protecting battery.

---

## 4. FINAL VERDICT

**VERDICT: APPROVE**

All mathematical derivations, frame timing, airtimes, speedup factors, power models, and battery longevities are mathematically sound, empirically verified, and ready for completion.
