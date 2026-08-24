# ESP32-C3 (C2838500) — Pinout für Diktiergerät V2 (Production)

**IC:** U1 · ESP32-C3 (C2838500, JLCPCB) · QFN-32 5×5 mm · 33 Pins (32 QFN + EPAD)
**Gehäuse-Top-Markierung:** Pin 1 = **LNA_IN** (oben links, im Gegenuhrzeigersinn).
**Quellen:** ESP32-C3 Datasheet v2.4 (Tab. 2-1/2-4/2-12) · Design aus `NEW_BOM_PRODUCTION.md` · KiCad-Symbol C2838500.

> **Nets:** `3V3` = geregelte 3,3 V vom LDO (U7) · `BAT` = Akku 3,0–4,2 V (U6, LDO-VIN) · `VBUS` = 5 V von USB-C (J1) · `GND` = Masse.
> **Grundversorgung (Pins 2,3,11,17,18,31,32) alle an `3V3`**, EPAD(33) + GND-Pins an `GND`.

---

## 1. Vollständige Pin-Tabelle (QFN-32)

| Pin# | Name          | Funktion im Design                           | Verbunden mit                                        | Typ / Bemerkung |
| ---: | ------------- | -------------------------------------------- | --------------------------------------------------- | --------------- |
| 1    | LNA_IN        | RF-Antenneneingang (2,4 GHz)                  | π-Matching → **A1** (C293767)                        | **RF, kritisch** |
| 2    | VDD3P3        | Digitale Spannungsversorgung                  | `3V3`                                               | Power           |
| 3    | VDD3P3        | Digitale Spannungsversorgung                  | `3V3`                                               | Power           |
| 4    | GPIO0 / XTAL_32K_P | **unbenutzt** (kein 32 kHz-Quarz)        | NC                                                  | frei            |
| 5    | GPIO1 / XTAL_32K_N | **unbenutzt**                                | NC                                                  | frei            |
| 6    | GPIO2 / MTMS   | I2S Bit-Clock (SCK/BCLK) — gemeinsames Signal | beide **U4+U5** Pin 4, **GPIO2**                    | ⚠️ **Strapping (Boot)** |
| 7    | CHIP_EN        | Reset/Enable                                 | R5(10k →`3V3`) **+** C11(100n →`GND`)               | **RC-Pflicht** |
| 8    | GPIO3 / MTDI   | I2S Word-Select (WS/LRCLK) — gemeinsames      | beide **U4+U5** Pin 1                                | frei            |
| 9    | GPIO4 / MTCK   | I2S Serial-Daten (SD) — gemeinsames           | beide **U4+U5** Pin 6 + **R10**(100k →`GND`)         | Mikrofon-Daten  |
| 10   | GPIO5 / MTDO   | IMU Interrupt (Tap/Wakeup)                    | **U3 INT1 (Pin 4)**                                  | Interrupt       |
| 11   | VDD3P3_RTC     | RTC-Spannung                                  | `3V3`                                               | Power           |
| 12   | GPIO6 / MTCK   | I2C **SDA** (IMU)                             | **U3 SDA (Pin 13)** + R2(4,7k →`3V3`)                | I2C             |
| 13   | GPIO7 / MTDO   | I2C **SCL** (IMU)                             | **U3 SCL (Pin 14)** + R3(4,7k →`3V3`)                | I2C             |
| 14   | GPIO8          | **unbenutzt**                                 | NC                                                  | ⚠️ **Strapping (Boot)** |
| 15   | GPIO9          | **Switch / Button** (THT-Lötbohrung `BTN`)    | THT-Hole BTN → Taster/Switch → `GND` (interner weak Pull-up) | ⚠️ **Strapping (Boot)** |
| 16   | GPIO10         | **LED rot (D1)**                              | Kathode D1 über R4(330) → `3V3`                      | LED-Ausgang     |
| 17   | VDD3P3_CPU     | CPU-Spannung                                  | `3V3` + C2(100n →`GND`)                              | Power + Entkopplung |
| 18   | VDD_SPI        | SPI-Flash-Spannung                            | `3V3`                                               | Power (Lib-Bug: `power_out`→`power_in` patchen) |
| 19   | GPIO12 / SPIQ  | Flash **IO3 / /HOLD**                         | **U2 Pin 7** (W25Q128)                               | Flash QIO       |
| 20   | GPIO13 / SPIHD | Flash **IO2 / /WP**                           | **U2 Pin 3** (W25Q128)                               | Flash QIO       |
| 21   | GPIO14 / SPICS0| Flash **/CS**                                 | **U2 Pin 1** (W25Q128)                               | Flash-CS        |
| 22   | GPIO15 / SPICLK| Flash **CLK**                                 | **U2 Pin 6** (W25Q128)                               | Flash-CLK       |
| 23   | GPIO16 / SPID  | Flash **IO0 / DI**                            | **U2 Pin 5** (W25Q128)                               | Flash QIO       |
| 24   | GPIO17 / SPIQ  | Flash **IO1 / DO**                            | **U2 Pin 2** (W25Q128)                               | Flash QIO       |
| 25   | GPIO18 / D−    | **USB D−** (fest)                             | **J1 D−**                                            | USB (fest)      |
| 26   | GPIO19 / D+    | **USB D+** (fest)                             | **J1 D+**                                            | USB (fest)      |
| 27   | GPIO20 / U0RXD | **unbenutzt**                                 | NC                                                  | frei/UART       |
| 28   | GPIO21 / U0TXD | **unbenutzt**                                 | NC                                                  | frei/UART       |
| 29   | XTAL_N         | Quarz (N)                                     | **Y1** + C13(15p →`GND`)                              | Haupttakt 40 MHz |
| 30   | XTAL_P         | Quarz (P)                                     | **Y1** + C12(15p →`GND`)                              | Haupttakt 40 MHz |
| 31   | VDDA           | Analog-Versorgung                             | `3V3`                                               | Power           |
| 32   | VDDA           | Analog-Versorgung                             | `3V3`                                               | Power           |
| 33   | EPAD (Thermal) | Masse / thermisch                             | `GND` (**3×3 Via-Matrix** unter IC)                  | GND             |

> **Statistik:** 17 GPIO belegt (2,3,4,5,6,7,9,10,11,12,13,14,15,16,17,18,19) · 5 GPIO frei (0,1,8,20,21) · 7 Spannungs-/Analog-Pins (2,3,11,17,18,31,32) + EPAD(33).

---

## 2. GPIO-Funktionsübersicht (kompakt)

| GPIO | Pin# | Peripherie (ESPRESSIF) | Design-Funktion           | Ziel-Pin/Ziel       |
| ---: | ---: | ---------------------- | ------------------------- | ------------------- |
| GPIO2 | 6   | MTMS (jTAG)           | I2S BCLK / SCK            | U4/U5 Pin 4         |
| GPIO3 | 8   | MTDI (jTAG)           | I2S LRCLK / WS            | U4/U5 Pin 1         |
| GPIO4 | 9   | MTCK (jTAG)           | I2S SD (Mic-Daten)        | U4/U5 Pin 6 + R10   |
| GPIO5 | 10  | MTDO (jTAG)           | IMU INT1 (Wakeup)         | U3 Pin 4            |
| GPIO6 | 12  | MTCK → I2C0 SDA       | I2C **SDA**                | U3 Pin 13 + R2      |
| GPIO7 | 13  | MTDO → I2C0 SCL       | I2C **SCL**                | U3 Pin 14 + R3      |
| GPIO9 | 15  | —                     | Switch/Button `BTN` (GND)  | THT-Lötbohrung BTN  |
| GPIO10| 16  | —                     | LED **D1 rot**             | D1 Kathode via R4   |
| GPIO11| 18  | —                     | LED **D2 grün**            | D2 Kathode via R6   |
| GPIO12| 19  | SPIQ                  | Flash **IO3/HOLD**         | U2 Pin 7            |
| GPIO13| 20  | SPIHD                 | Flash **IO2/WP**           | U2 Pin 3            |
| GPIO14| 21  | SPICS0                | Flash **/CS**              | U2 Pin 1            |
| GPIO15| 22  | SPICLK                | Flash **CLK**              | U2 Pin 6            |
| GPIO16| 23  | SPID                  | Flash **IO0/DI**           | U2 Pin 5            |
| GPIO17| 24  | SPIQ                  | Flash **IO1/DO**           | U2 Pin 2            |
| GPIO18| 25  | USB_D−                | USB **D−**                 | J1                  |
| GPIO19| 26  | USB_D+                | USB **D+**                 | J1                  |

---

## 3. Design-kritische Pins

1. **CHIP_EN (Pin 7) — unbedingt RC:** R5(10k →`3V3`) + C11(100n →`GND`) parallel. Ohne C11 keine garantierte Reset-Rampe (tSTBL ≥ 50 µs, Datasheet 2.5.3).
2. **LNA_IN (Pin 1) — Antenne + π-Matching:** Bare-SoC. Direkt auf LNA_IN ohne Matching → Reichweite < 1 m. π-Netz (C-Serie-Parallel / L) zwischen **A1 (C293767)** und Pin 1; EPAD-RF-Bereich sauber halten.
3. **Flash Quad-SPI (GPIO12–17):** /WP→GPIO13, /HOLD→GPIO12 (nicht fest an 3V3!) → volle QIO-Datenrate. Wichtig, da `C2838500` **keinen internen Flash** hat.
4. **Strapping-Pins (Boot-Phase):** GPIO2 (Pin 6), GPIO8 (Pin 14), GPIO9 (Pin 15). Beim Boot Zustand beachten: GPIO9 hat internen **weak Pull-up** → eignet sich für einen GND-Taster (kein externer Pull-up nötig). GPIO2 wird als I2S-BCLK benutzt — sicherstellen, dass der Boot-Zustand nicht kollidiert.
5. **USB GPIO18/19 (Pins 25/26):** fest verdrahtet; direkt an J1 D−/D+ (kein externes Pull-up nötig).
6. **VDD_SPI (Pin 18):** im offiziellen KiCad-Symbol als `power_out` deklariert → auf `power_in` patchen (sonst ERC-Fehler).

---

## 4. Unbenutzte / freie Pins

| GPIO | Pin# | Hinweis                                  |
| ---: | ---: | ---------------------------------------- |
| GPIO0 | 4   | XTAL_32K_P — frei, kein 32 kHz-Kristall  |
| GPIO1 | 5   | XTAL_32K_N — frei, kein 32 kHz-Kristall  |
| GPIO8 | 14  | Strapping — frei (nicht beschaltet)      |
| GPIO20| 27  | U0RXD — frei (UART, falls Debug nötig)   |
| GPIO21| 28  | U0TXD — frei (UART, falls Debug nötig)   |

> Für Debug: GPIO20/21 an RX/TX des USB-UART-Adapters legen (3,3 V!) — interne UART.

---

## 5. Referenz — ESP32-C3 Pin# ↔ GPIO (Datasheet v2.4)

| Pin# | GPIO | Pin# | GPIO | Pin# | Name  | Pin# | Name  |
| ---: | :--- | ---: | :--- | ---: | :---- | ---: | :---- |
| 4    | GPIO0| 14   | GPIO8| 11   | VDD3P3_RTC | 25 | GPIO18 (D−) |
| 5    | GPIO1| 15   | GPIO9| 17   | VDD3P3_CPU | 26 | GPIO19 (D+) |
| 6    | GPIO2| 16   | GPIO10| 18  | VDD_SPI | 27 | GPIO20 (U0RXD) |
| 8    | GPIO3| 18   | GPIO11| 19   | GPIO12 (SPIQ) | 28 | GPIO21 (U0TXD) |
| 9    | GPIO4| 19–24 | GPIO12–17 | — | — | 29 | XTAL_N |
| 10   | GPIO5| 20   | GPIO13| 21   | GPIO14 (SPICS0) | 30 | XTAL_P |
| 12   | GPIO6| 21   | GPIO14| 22   | GPIO15 (SPICLK) | 31/32 | VDDA |
| 13   | GPIO7| 22   | GPIO15| 23   | GPIO16 (SPID) | 33 | EPAD |
|      |     | 23   | GPIO16| 24   | GPIO17 (SPIQ) | 2/3 | VDD3P3 |

---
*Pin-Zuordnung gegen ESP32-C3 Datasheet v2.4 (Tab. 2-1/2-4) verifiziert. Design-Abhängigkeiten gemäß `NEW_BOM_PRODUCTION.md`.*
