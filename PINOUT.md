# Hardware Pinout & Wiring Guide
## Seeed Studio XIAO ESP32C3 with Stereo MEMS Microphones & BMI160 IMU

This document describes the complete breadboard wiring for connecting **two I2S MEMS Microphones** (e.g., INMP441, MSM261S4030H0, ICS-43434) and a **Bosch BMI160 6-Axis IMU Sensor** to the **Seeed Studio XIAO ESP32C3** development board.

---

## 1. Quick Pin Reference Table

| Device | Device Pin | XIAO ESP32C3 Pin | ESP32-C3 GPIO | Function / Notes |
| :--- | :--- | :--- | :--- | :--- |
| **Power Bus** | VCC / 3V3 | **3V3** | - | **3.3V Power Supply** (Do NOT use 5V for MEMS Mics!) |
| **Power Bus** | GND | **GND** | - | **Common Ground** |
| **BMI160 (IMU)** | VCC | **3V3** | - | Power Supply (3.3V) |
| | GND | **GND** | - | Ground |
| | SCL | **D5** | GPIO 7 | I2C Clock Line (Hardware SCL) |
| | SDA | **D4** | GPIO 6 | I2C Data Line (Hardware SDA) |
| | SDO / SA0 | **GND** | - | I2C Address select: `0x68` (Connect to 3V3 for `0x69`) |
| | CS | **3V3** (or open) | - | Pull high for I2C mode (usually has onboard pullup) |
| **Mic 1 (Left Channel)** | VDD / 3V3 | **3V3** | - | 3.3V Power |
| | GND | **GND** | - | Ground |
| | SD / DOUT | **D2** | GPIO 4 | Shared I2S Serial Data In |
| | WS / LRCLK | **D1** | GPIO 3 | Shared I2S Word Select (LRCLK) |
| | SCK / BCLK | **D0** | GPIO 2 | Shared I2S Bit Clock (BCLK) |
| | **L/R** | **GND** | - | **Configures Mic 1 as LEFT Channel** |
| **Mic 2 (Right Channel)**| VDD / 3V3 | **3V3** | - | 3.3V Power |
| | GND | **GND** | - | Ground |
| | SD / DOUT | **D2** | GPIO 4 | Shared I2S Serial Data In (connected to Mic 1 SD) |
| | WS / LRCLK | **D1** | GPIO 3 | Shared I2S Word Select (connected to Mic 1 WS) |
| | SCK / BCLK | **D0** | GPIO 2 | Shared I2S Bit Clock (connected to Mic 1 SCK) |
| | **L/R** | **3V3** | - | **Configures Mic 2 as RIGHT Channel** |

---

## 2. Seeed Studio XIAO ESP32C3 Pinout Overview

```
                      +-------------------+
                      |   [USB-C Port]    |
       (GPIO 2)  D0  [ ]                 [ ]  5V       (USB 5V Out)
       (GPIO 3)  D1  [ ]                 [ ]  GND      (Ground)
       (GPIO 4)  D2  [ ]                 [ ]  3V3      (3.3V Out)
       (GPIO 5)  D3  [ ]                 [ ]  D10 / RX (GPIO 20)
 (SDA) (GPIO 6)  D4  [ ]                 [ ]  D9 / TX  (GPIO 21)
 (SCL) (GPIO 7)  D5  [ ]                 [ ]  D8       (GPIO 10)
 (SCK) (GPIO 8)  D6  [ ]                 [ ]  D7       (GPIO 9 - Boot)
                      +-------------------+
```

---

## 3. How the Stereo I2S Shared Bus Works

Standard digital I2S MEMS microphones (such as INMP441) are designed to share clock and data lines on a single bus:
1. **SCK (Bit Clock)** and **WS (Word Select)** are output by the ESP32-C3 to both microphones simultaneously.
2. When **WS is LOW**, Microphone 1 (L/R tied to GND) drives the **SD** line with 24-bit audio data, while Microphone 2 puts its SD pin into high-impedance (tri-state).
3. When **WS is HIGH**, Microphone 2 (L/R tied to 3.3V) drives the **SD** line, while Microphone 1 puts its SD pin into high-impedance.
4. This means **both microphones wire directly to the exact same pins (D0, D1, D2)** on the XIAO ESP32C3, and only their **L/R pin** is connected differently!

```
                       XIAO ESP32C3
                       +-----------+
    D0 (GPIO 2) ------>| SCK       |---------------------+
    D1 (GPIO 3) ------>| WS        |---------+           |
    D2 (GPIO 4) <------| SD (Data) |---+     |           |
                       +-----------+   |     |           |
                                       |     |           |
             +-------------------------+     |           |
             |   +---------------------------+           |
             |   |   +-----------------------------------+
             |   |   |
             v   v   v
       +---------------+                     +---------------+
       | SD  WS  SCK   |                     | SD  WS  SCK   |
       |               |                     |               |
       |  MIC 1 (LEFT) |                     | MIC 2 (RIGHT) |
       |               |                     |               |
       | VDD  GND  L/R |                     | VDD  GND  L/R |
       +---------------+                     +---------------+
          |    |    |                           |    |    |
         3V3  GND  GND (Left)                  3V3  GND  3V3 (Right)
```

---

## 4. BMI160 I2C Connection

The BMI160 communicates over the standard I2C bus:
- **XIAO D4 (GPIO 6)** connects to **BMI160 SDA**
- **XIAO D5 (GPIO 7)** connects to **BMI160 SCL**
- **XIAO 3V3** connects to **BMI160 VCC** (and CS if needed)
- **XIAO GND** connects to **BMI160 GND** and **SDO / SA0** (sets address to `0x68`)

```
 XIAO ESP32C3                          BMI160 IMU Breakout
 +----------+                          +-------------------+
 |      3V3 |------------------------->| VCC / VIN         |
 |      GND |-------------------+----->| GND               |
 |          |                   |  +-->| SDO / SA0  (0x68) |
 |          |                   |  |   |                   |
 | D4 (SDA) |-------------------|--|-->| SDA               |
 | D5 (SCL) |-------------------|--|-->| SCL               |
 +----------+                   |  |   +-------------------+
                                +--+ (Tie SDO to GND for 0x68)
```

---

## 5. Step-by-Step Breadboard Assembly Instructions

1. **Power Rails**:
   - Connect **3V3** of the XIAO ESP32C3 to the **Red (+) rail** of your breadboard.
   - Connect **GND** of the XIAO ESP32C3 to the **Blue (-) rail** of your breadboard.

2. **BMI160 Sensor**:
   - `VCC` -> Breadboard Red Rail (`+3.3V`)
   - `GND` -> Breadboard Blue Rail (`GND`)
   - `SDA` -> XIAO `D4` (GPIO 6)
   - `SCL` -> XIAO `D5` (GPIO 7)
   - `SDO / SA0` -> Breadboard Blue Rail (`GND`)
   - `CS` -> Leave disconnected or connect to Red Rail (`+3.3V`)

3. **MEMS Mic 1 (Left Channel)**:
   - `VDD` -> Breadboard Red Rail (`+3.3V`)
   - `GND` -> Breadboard Blue Rail (`GND`)
   - `SCK` -> XIAO `D0` (GPIO 2)
   - `WS`  -> XIAO `D1` (GPIO 3)
   - `SD`  -> XIAO `D2` (GPIO 4)
   - `L/R` -> Breadboard Blue Rail (`GND`)

4. **MEMS Mic 2 (Right Channel)**:
   - `VDD` -> Breadboard Red Rail (`+3.3V`)
   - `GND` -> Breadboard Blue Rail (`GND`)
   - `SCK` -> Same breadboard row as Mic 1 SCK (XIAO `D0`)
   - `WS`  -> Same breadboard row as Mic 1 WS (XIAO `D1`)
   - `SD`  -> Same breadboard row as Mic 1 SD (XIAO `D2`)
   - `L/R` -> Breadboard Red Rail (`+3.3V`)

---

## 6. Hardware Checklist & Troubleshooting

| Symptom | Probable Cause | Solution |
| :--- | :--- | :--- |
| **I2C Scanner shows "No I2C devices found"** | SDA / SCL reversed or loose power wire | Swap D4 (SDA) and D5 (SCL). Check VCC & GND. |
| **BMI160 Chip ID != 0xD8 (e.g. 0x00 or 0xFF)** | Wrong I2C address or poor contact | Check if SDO is tied to GND (`0x68`) or 3V3 (`0x69`). Check solder joints on pin headers. |
| **Microphones output flat 0 or static** | `L/R` pin floating or SCK/WS/SD disconnected | Ensure Mic 1 L/R is firmly connected to GND and Mic 2 L/R is firmly connected to 3.3V. |
| **Both microphones show identical sound level** | Both `L/R` pins connected to same rail | Verify one mic has L/R to GND (Left) and the other has L/R to 3.3V (Right). |
| **ESP32-C3 fails to flash / boot** | Floating boot pins or power sag | Use a stable USB-C data cable and ensure 3.3V is not overloaded. |
