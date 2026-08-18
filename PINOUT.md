# Hardware Pinout & Wiring Guide
## Seeed Studio XIAO ESP32C3 with Stereo MEMS Microphones, IMU & Status LED

This document describes the complete breadboard wiring for connecting **two I2S MEMS Microphones**, an **IMU Sensor** (LSM6DS3 / BMI160), and a **Status LED** to the **Seeed Studio XIAO ESP32C3**.

---

## 1. Complete Pin Assignment Table

| Component | Component Pin | XIAO ESP32C3 Pin | ESP32-C3 GPIO | Wire Color (Rec.) | Function / Description |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Power Rail** | VCC / 3V3 | **3V3** | - | 🔴 Red | **3.3V Power Bus** (Do NOT use 5V for MEMS Mics!) |
| **Ground Rail** | GND | **GND** | - | ⚫ Black | **Common Ground Bus** |
| **IMU (LSM6DS3 / BMI160)** | VCC | **3V3** | - | 🔴 Red | 3.3V Power Supply |
| | GND | **GND** | - | ⚫ Black | Ground |
| | SCL | **D5** | GPIO 7 | 🟡 Yellow | Hardware I2C Clock (SCL) |
| | SDA | **D4** | GPIO 6 | 🟢 Green | Hardware I2C Data (SDA) |
| | SDO / SA0 | **GND** | - | ⚫ Black | Sets I2C Address: `0x6A` (LSM6DS3) / `0x68` (BMI160) |
| **Mic 1 (Left Channel)** | VDD / 3V3 | **3V3** | - | 🔴 Red | 3.3V Power |
| | GND | **GND** | - | ⚫ Black | Ground |
| | SD / DOUT | **D2** | GPIO 4 | 🟣 Purple | Shared I2S Serial Data In |
| | WS / LRCLK | **D1** | GPIO 3 | 🔵 Blue | Shared I2S Word Select (LRCLK) |
| | SCK / BCLK | **D0** | GPIO 2 | 🟠 Orange | Shared I2S Bit Clock (BCLK) |
| | **L/R** | **GND** | - | ⚫ Black | **Tied to GND: Configures Mic 1 as LEFT Channel** |
| **Mic 2 (Right Channel)**| VDD / 3V3 | **3V3** | - | 🔴 Red | 3.3V Power |
| | GND | **GND** | - | ⚫ Black | Ground |
| | SD / DOUT | **D2** | GPIO 4 | 🟣 Purple | Connected to Mic 1 SD (Shared bus) |
| | WS / LRCLK | **D1** | GPIO 3 | 🔵 Blue | Connected to Mic 1 WS (Shared bus) |
| | SCK / BCLK | **D0** | GPIO 2 | 🟠 Orange | Connected to Mic 1 SCK (Shared bus) |
| | **L/R** | **3V3** | - | 🔴 Red | **Tied to 3.3V: Configures Mic 2 as RIGHT Channel** |
| **Status LED (Recording Indicator)** | Anode (+) | **D10** | GPIO 10 | 🔴 Red | Long leg of LED connected to D10 |
| | Kathode (-) | **GND** (via Resistor) | - | ⚫ Black | Short leg connected via 220Ω–330Ω resistor to GND |

---

## 2. Status LED Wiring Detail

> [!IMPORTANT]
> **Why an External LED on D10?**  
> The onboard red LED on the Seeed Studio XIAO ESP32C3 is hardwired to the lithium battery charging IC (ETA6003) and is permanently lit when USB power is attached. It cannot be controlled via software.  
> Therefore, an external **Status LED on Pin D10 (GPIO 10)** is used as the active recording indicator.

```
       XIAO D10 (GPIO 10)
              |
              |
            +---+
            |   |  LED Anode (+) [Long Leg]
            |   |
            +---+  LED Kathode (-) [Short Leg / Flat Side]
              |
              |
           [ 220Ω - 330Ω Resistor ]
              |
              |
             GND Rail
```

* **LED Behavior:**
  * **Boot:** Blinks 3 times quickly to signal system readiness.
  * **Recording:** Turns **ON** (solid) during voice recording.
  * **Standby / Stop:** Turns **OFF** immediately when recording stops.

---

## 3. XIAO ESP32C3 Pinout Diagram

```
                       +-------------------+
                       |   [USB-C Port]    |
        (GPIO 2)  D0  [ ]                 [ ]  5V       (USB 5V Out)
        (GPIO 3)  D1  [ ]                 [ ]  GND      (Ground Bus)
        (GPIO 4)  D2  [ ]                 [ ]  3V3      (3.3V Power Bus)
        (GPIO 5)  D3  [ ]                 [ ]  D10 / LED (GPIO 10 -> Status LED)
  (SDA) (GPIO 6)  D4  [ ]                 [ ]  D9       (GPIO 21)
  (SCL) (GPIO 7)  D5  [ ]                 [ ]  D8       (GPIO 20)
        (GPIO 8)  D6  [ ]                 [ ]  D7       (GPIO 9 - Boot)
                       +-------------------+
```

---

## 4. Shared Stereo I2S Bus Explained

Both I2S MEMS microphones (e.g. INMP441 / ICS-43434 / MSM261S) share the exact same 3 data lines:
* **`D0 (SCK)`** $\rightarrow$ Provides the synchronous Bit Clock to both microphones.
* **`D1 (WS)`** $\rightarrow$ Provides the Word Select / Frame Clock (Left = Low, Right = High).
* **`D2 (SD)`** $\rightarrow$ Both microphones output their data onto this single line during their respective time slot.

Because **Mic 1 has L/R = GND** and **Mic 2 has L/R = 3.3V**, they automatically multiplex onto the single data pin without any collision, giving **100% sample-synchronous 2-channel stereo audio**.
