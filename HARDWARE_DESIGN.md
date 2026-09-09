# Diktiergerät V2 — Production-Dokument (BOM + Verdrahtung)

**Stand:** 2026-09-09 (rev. nach Aktualisierung auf ESP32-C3-MINI-1-N4) · **Status:** 100 % abgeglichen mit der aktuellen Produktions-BOM (`docs/hardware/BOM_V2_ESP32C3_MINI1.xlsx`) und dem Produktions-Schaltplan (`docs/hardware/SCHEMATIC_V2.png`).  
**Fertigungsziel:** JLCPCB PCBA (SMT-Bestückung) · **Akku & Schalter:** fest verdrahtet über durchkontaktierte THT-Lötbohrungen (Holes).

---

## Wesentliche Architekturmerkmale (V2 Production)

1. **MCU-Modul:** **ESP32-C3-MINI-1-N4** (Espressif, LCSC C2934560, 53 Pins).
   - Enthält bereits den **internen 4 MB SPI-Flash**.
   - Enthält den **40 MHz Hauptquarz** intern $\rightarrow$ kein externer Quarz Y1 oder Lastkondensatoren (C12/C13) erforderlich.
   - Enthält eine **integrierte 2,4 GHz PCB-Antenne** $\rightarrow$ keine externe Chip-Antenne A1 und kein diskretes π-Matching-Netzwerk (C14/L1/C15) auf dem Mainboard nötig.
2. **Dedizierter Audio-Flash:** **W25Q128JVSIQ** (Winbond 16 MB SPI-Flash, SOIC-8) angebunden an **SPI2** für lückenlose Audiospeicherung:
   - `FLASH_CS` $\rightarrow$ GPIO 21 (Modul-Pin 28)
   - `FLASH_SCK` $\rightarrow$ GPIO 20 (Modul-Pin 27)
   - `FLASH_MOSI` $\rightarrow$ GPIO 1 (Modul-Pin 13)
   - `FLASH_MISO` $\rightarrow$ GPIO 0 (Modul-Pin 12)
   - `/WP` (Pin 3) und `/HOLD` (Pin 7) an 3V3 gelegt; C7 (100 nF) Entkopplung.
3. **High-Performance LDO:** **AP2112K-3.3TRG1** (Diodes Inc., SOT-25-5, LCSC C51118) mit bis zu 600 mA Dauerstrom und exzellenter Transientenregelung für Wi-Fi-Bursts.
4. **Li-Ion Ladecontroller:** **UMW TP4054** (TSOT-23-5, LCSC C668215) mit $R_9 = 2\,\text{k}\Omega$ für 500 mA Ladestrom.
5. **Stereo MEMS-Mikrofone:** 2× **TDK InvenSense ICS-43434** (LGA-6, LCSC C5656610) an gemeinsamem I2S-Bus (SCK = GPIO 2, WS = GPIO 3, SD = GPIO 4 mit 100 kΩ Pulldown $R_{10}$). U4 ist linker Kanal (L/R $\rightarrow$ GND), U5 ist rechter Kanal (L/R $\rightarrow$ 3V3).
6. **6-Achsen IMU:** **ST LSM6DSLTR** (LGA-14, LCSC C126672) an I2C (SDA = GPIO 6, SCL = GPIO 7 mit $4{,}7\,\text{k}\Omega$ Pull-ups) mit Hardware-Wakeup-Interrupt an GPIO 5.
7. **Dual Status-LEDs:** D1 (Rot, KT-0603R) an GPIO 10 und D2 (Grün, LTST-C190GKT) an GPIO 8 (beide mit $330\,\Omega$ Vorwiderständen).
8. **Kabel- & Testpad-Anbindung (THT Holes $d = 1{,}0\,\text{mm}$ / $D = 1{,}5\,\text{mm}$):**
   - `VDD+` / `BAT+`: Akku-Pluspol (Direktverlötung von Litzen, kein JST-Stecker)
   - `BAT-` / `GND`: Akku-Masse
   - `BOOT` / `BTN`: Externer Taster/Schalter an GPIO 9 gegen Masse
   - `RESET`: EN-Reset-Leitung
   - `PCHG_DETECT`: Lade-Status (CHRG-Pin)
   - `PCHG_PROG`: Ladestrom-Messpunkt

---

## TEIL 0 — GESAMT-BOM (Abgestimmt auf `BOM_V2_ESP32C3_MINI1.xlsx`)

### 0.1 Halbleiter & Module (7 Bauteile)
| Ref | Bauteil / MPN | Gehäuse / Footprint | Hersteller | LCSC-Teilenummer | Qty | Funktion / Bemerkung |
| :--- | :--- | :--- | :--- | :--- | :---: | :--- |
| **U1** | ESP32-C3-MINI-1-N4 | WIFIM-SMD_ESP32-C3-MINI-1 | ESPRESSIF | **C2934560** (ESP32-C3-MINI-1-N4.1) | 1 | RISC-V MCU mit 4MB int. Flash, Quarz & PCB-Antenne |
| **U2** | W25Q128JVSIQ | SOIC-8_L5.3-W5.3-P1.27-LS8.0-BL | Winbond | **C97521** (W25Q128JVSIQTR.1) | 1 | 16 MB SPI-Flash für Audio-Aufnahmen an SPI2 |
| **U3** | LSM6DSLTR | LGA-14_L3.0-W2.5-P0.50-TL | STMicroelectronics | **C126672** (LSM6DSLTR.1) | 1 | 6-Achsen IMU, Tap/Doppel-Tap & Wakeup |
| **U4** | ICS-43434 | MIC-SMD_6P-L3.5-W2.7-P0.90-BL | TDK InvenSense | **C5656610** (ICS-43434_C5656610.1) | 1 | Stereo MEMS-Mic Links (L/R $\rightarrow$ GND) |
| **U5** | ICS-43434 | MIC-SMD_6P-L3.5-W2.7-P0.90-BL | TDK InvenSense | **C5656610** (ICS-43434_C5656610.1) | 1 | Stereo MEMS-Mic Rechts (L/R $\rightarrow$ 3V3) |
| **U6** | TP4054 | TSOT-23-5_L2.9-W1.6-P0.95-LS2.8-BR | UMW | **C668215** (TP4054_C668215.1) | 1 | 1S Li-Ion Linear-Laderegler (500 mA) |
| **U7** | AP2112K-3.3TRG1 | SOT-25-5_L2.9-W1.6-P0.95-LS2.8-BL | Diodes Inc. | **C51118** | 1 | Low-Dropout Regler 3,3 V, 600 mA Peak |

### 0.2 Anschlüsse & Optoelektronik (3 Bauteile)
| Ref | Bauteil / MPN | Gehäuse / Footprint | Hersteller | LCSC-Teilenummer | Qty | Funktion / Bemerkung |
| :--- | :--- | :--- | :--- | :--- | :---: | :--- |
| **J1** | GT-USB-7010ASV | USB-C-SMD_G-SWITCH_GT-USB-7010ASV | G-Switch | **C2988369** (GT-USB-7010ASV.1) | 1 | USB-C 16-Pin Buchse für 5V Laden & USB CDC |
| **D1** | KT-0603R | LED-SMD_L1.6-W0.8-R-RD (0603) | KENTO | **C2286** (KT-0603R.1) | 1 | Status-LED Rot an GPIO 10 (Recording) |
| **D2** | LTST-C190GKT | LED0603-RD (0603) | LITEON | **C125093** (LTST-C190GKT.1) | 1 | Status-LED Grün an GPIO 8 (System / Wi-Fi) |

### 0.3 Widerstände (alle 0402 1%, 9 Bauteile)
| Ref | Wert | MPN | Gehäuse | LCSC-Teilenummer | Qty | Funktion / Netz |
| :--- | :--- | :--- | :--- | :--- | :---: | :--- |
| **R2** | $4{,}7\,\text{k}\Omega$ | 0402WGF4701TCE | 0402 | **C25900** (0402WGF4701TCE.1) | 1 | I2C SDA Pull-up nach 3V3 |
| **R3** | $4{,}7\,\text{k}\Omega$ | 0402WGF4701TCE | 0402 | **C25900** (0402WGF4701TCE.1) | 1 | I2C SCL Pull-up nach 3V3 |
| **R4** | $330\,\Omega$ | 0402WGF3300TCE | 0402 | **C25104** (0402WGF3300TCE.1) | 1 | Vorwiderstand LED D1 (Rot) |
| **R5** | $10\,\text{k}\Omega$ | 0402WGF1002TCE | 0402 | **C25744** (0402WGF1002TCE.1) | 1 | EN / CHIP_EN Pull-up nach 3V3 |
| **R6** | $330\,\Omega$ | 0402WGF3300TCE | 0402 | **C25104** (0402WGF3300TCE.1) | 1 | Vorwiderstand LED D2 (Grün) |
| **R7** | $5{,}1\,\text{k}\Omega$ | 0402WGF5101TCE | 0402 | **C25905** (0402WGF5101TCE.1) | 1 | USB-C CC1 Pulldown nach GND |
| **R8** | $5{,}1\,\text{k}\Omega$ | 0402WGF5101TCE | 0402 | **C25905** (0402WGF5101TCE.1) | 1 | USB-C CC2 Pulldown nach GND |
| **R9** | $2\,\text{k}\Omega$ | 0402WGF2001TCE | 0402 | **C4109** (0402WGF2001TCE.1) | 1 | TP4054 PROG-Widerstand $\rightarrow$ 500 mA Ladestrom |
| **R10** | $100\,\text{k}\Omega$ | 0402WGF1003TCE | 0402 | **C25741** (0402WGF1003TCE.1) | 1 | I2S Serial Data (SD) Pulldown nach GND |

### 0.4 Kondensatoren (alle 0402, 10 Bauteile)
| Ref | Wert | MPN | Gehäuse | LCSC-Teilenummer | Qty | Funktion / Netz |
| :--- | :--- | :--- | :--- | :--- | :---: | :--- |
| **C1** | $100\,\text{nF}$ | CL05B104KO5NNNC | 0402 | **C1525** (CL05B104KO5NNNC.1) | 1 | Entkopplung ESP32-C3-MINI-1 3V3 VDD |
| **C3** | $10\,\mu\text{F}$ | CL05A106MQ5NUNC | 0402 | **C15525** (CL05A106MQ5NUNC.1) | 1 | USB-C VBUS Bulk-Filter |
| **C4** | $10\,\mu\text{F}$ | CL05A106MQ5NUNC | 0402 | **C15525** (CL05A106MQ5NUNC.1) | 1 | LDO-Eingang (BAT / VIN) Puffer |
| **C5** | $10\,\mu\text{F}$ | CL05A106MQ5NUNC | 0402 | **C15525** (CL05A106MQ5NUNC.1) | 1 | LDO-Ausgang (3V3 / VOUT) Stabilität |
| **C6** | $100\,\text{nF}$ | CL05B104KO5NNNC | 0402 | **C1525** (CL05B104KO5NNNC.1) | 1 | LDO-Ausgang HF-Entkopplung |
| **C7** | $100\,\text{nF}$ | CL05B104KO5NNNC | 0402 | **C1525** (CL05B104KO5NNNC.1) | 1 | Entkopplung SPI-Flash U2 (W25Q128) |
| **C8** | $100\,\text{nF}$ | CL05B104KO5NNNC | 0402 | **C1525** (CL05B104KO5NNNC.1) | 1 | Entkopplung IMU U3 (LSM6DSL) |
| **C9** | $100\,\text{nF}$ | CL05B104KO5NNNC | 0402 | **C1525** (CL05B104KO5NNNC.1) | 1 | Entkopplung Mic U4 (Links) |
| **C10** | $100\,\text{nF}$ | CL05B104KO5NNNC | 0402 | **C1525** (CL05B104KO5NNNC.1) | 1 | Entkopplung Mic U5 (Rechts) |
| **C11** | $100\,\text{nF}$ | CL05B104KO5NNNC | 0402 | **C1525** (CL05B104KO5NNNC.1) | 1 | EN / CHIP_EN RC-Reset-Filter mit R5 |

**BOM-Summen:** Exakt **29 SMT-Bauteile** auf **17 Positionen**. Alle Teile sind basic bzw. standardmäßig bei JLCPCB/LCSC geführt.

---

## TEIL 1 — VERDRAHTUNGS-ANLEITUNG & SCHALTUNGS-DETAILS

### 1.1 Stromversorgung & Laden (USB $\rightarrow$ TP4054 $\rightarrow$ LiPo $\rightarrow$ AP2112K $\rightarrow$ 3V3)
1. **USB-C Buchse (J1):**
   - `VBUS` verbindet mit Ladecontroller U6 Pin 4 und C3 ($10\,\mu\text{F}$) gegen GND.
   - `CC1` über R7 ($5{,}1\,\text{k}\Omega$) nach GND.
   - `CC2` über R8 ($5{,}1\,\text{k}\Omega$) nach GND.
   - `D-` an GPIO 18 (Modul-Pin 25).
   - `D+` an GPIO 19 (Modul-Pin 26).
   - `GND` und Shield an Ground.
2. **Laderegler TP4054 (U6):**
   - Pin 1 (`CHRG`): optional an Testpunkt `PCHG_DETECT`.
   - Pin 2 (`GND`): GND.
   - Pin 3 (`BAT`): Netz `BAT` (LiPo-Pluspol) und LDO-Eingang C4 ($10\,\mu\text{F}$).
   - Pin 4 (`VCC`): Netz `VBUS`.
   - Pin 5 (`PROG`): R9 ($2\,\text{k}\Omega$) nach GND $\rightarrow$ Ladestrom $I = 1000\,\text{V} / 2000\,\Omega = 500\,\text{mA}$.
3. **LDO AP2112K-3.3 (U7):**
   - Pin 1 (`VIN`): Netz `BAT` mit C4 ($10\,\mu\text{F}$).
   - Pin 2 (`GND`): GND.
   - Pin 3 (`EN`): Netz `BAT` (Dauerhaft aktiv, Ultra-Low Quiescent Current).
   - Pin 4 (`NC`): Nicht verbunden.
   - Pin 5 (`VOUT`): Netz `3V3` mit C5 ($10\,\mu\text{F}$) und C6 ($100\,\text{nF}$).

### 1.2 Mikrocontroller ESP32-C3-MINI-1-N4 (U1)
4. **Spannungsversorgung & Reset:**
   - Pin 3 (`3V3`): An `3V3` mit C1 ($100\,\text{nF}$) direkt am Pin gegen GND.
   - Pin 8 (`EN`): RC-Reset mit R5 ($10\,\text{k}\Omega$) nach `3V3` und C11 ($100\,\text{nF}$) nach GND. Testpunkt `RESET`.
   - Pins 1, 2, 11, 14, 33–53: An `GND`. Unter dem Modul massive GND-Plane mit Stitching-Vias.
5. **USB-Schnittstelle:**
   - Pin 25 (`IO18`): `USB_DN` $\rightarrow$ J1 Pin D-.
   - Pin 26 (`IO19`): `USB_DP` $\rightarrow$ J1 Pin D+.
6. **Schalter / Taster (`BTN`):**
   - Pin 22 (`IO9`): Verbunden mit THT-Lötbohrung `BTN`. Taster schaltet gegen GND (interner schwacher Pull-up). Dient im Boot-Modus zugleich als Strapping-Pin.

### 1.3 Externer Audio-Flash W25Q128 (U2 an SPI2)
7. **SPI2 Bus-Verdrahtung:**
   - Pin 1 (`/CS`): An GPIO 21 (U1 Pin 28) $\rightarrow$ Netz `FLASH_CS`.
   - Pin 2 (`DO/IO1`): An GPIO 0 (U1 Pin 12) $\rightarrow$ Netz `FLASH_MISO`.
   - Pin 3 (`/WP/IO2`): An `3V3` (Schreibschutz inaktiv).
   - Pin 4 (`GND`): GND.
   - Pin 5 (`DI/IO0`): An GPIO 1 (U1 Pin 13) $\rightarrow$ Netz `FLASH_MOSI`.
   - Pin 6 (`CLK`): An GPIO 20 (U1 Pin 27) $\rightarrow$ Netz `FLASH_SCK`.
   - Pin 7 (`/HOLD/IO3`): An `3V3`.
   - Pin 8 (`VCC`): An `3V3` mit C7 ($100\,\text{nF}$) gegen GND.

### 1.4 Beschleunigungssensor LSM6DSL (U3 an I2C)
8. **I2C Bus & Interrupt:**
   - Pin 1 (`SDO/SA0`): An GND $\rightarrow$ I2C-Adresse fest auf `0x6A`.
   - Pin 4 (`INT1`): An GPIO 5 (U1 Pin 18) $\rightarrow$ Hardware-Interrupt (Tap/Shake Wakeup).
   - Pin 5 (`VDDIO`): An `3V3`.
   - Pins 6, 7 (`GND`): GND.
   - Pin 8 (`VDD`): An `3V3` mit C8 ($100\,\text{nF}$) gegen GND.
   - Pin 12 (`CS`): An `3V3` (I2C-Modus erzwungen).
   - Pin 13 (`SCL`): An GPIO 7 (U1 Pin 20) mit R3 ($4{,}7\,\text{k}\Omega$) nach `3V3`.
   - Pin 14 (`SDA`): An GPIO 6 (U1 Pin 19) mit R2 ($4{,}7\,\text{k}\Omega$) nach `3V3`.

### 1.5 Stereo I2S MEMS-Mikrofone ICS-43434 (U4 & U5)
9. **Gemeinsamer I2S-Bus:**
   - `SCK / BCLK`: GPIO 2 (U1 Pin 5) an Pin 4 beider Mikrofone.
   - `WS / LRCLK`: GPIO 3 (U1 Pin 6) an Pin 1 beider Mikrofone.
   - `SD / DOUT`: GPIO 4 (U1 Pin 17) an Pin 6 beider Mikrofone. Pulldown R10 ($100\,\text{k}\Omega$) von SD nach GND.
10. **Kanal-Konfiguration:**
    - **U4 (Links):** Pin 2 (`LR`) an GND; Pin 5 (`VDD`) an `3V3` mit C9 ($100\,\text{nF}$); Pin 3 (`GND`) an GND.
    - **U5 (Rechts):** Pin 2 (`LR`) an `3V3`; Pin 5 (`VDD`) an `3V3` mit C10 ($100\,\text{nF}$); Pin 3 (`GND`) an GND.

### 1.6 Status-LEDs (D1 & D2)
11. **D1 (Rot):** Anode an `3V3`, Kathode über R4 ($330\,\Omega$) an GPIO 10 (U1 Pin 16).
12. **D2 (Grün):** Anode an `3V3`, Kathode über R6 ($330\,\Omega$) an GPIO 8 (U1 Pin 21).

---

## TEIL 2 — PIN-BELEGUNGSTABELLE (ESP32-C3-MINI-1-N4)

| Modul-Pin | Signal / GPIO | Netzname | Angeschlossenes Ziel | Funktion |
| :---: | :--- | :--- | :--- | :--- |
| **1, 2** | GND | `GND` | Ground Plane | Masse |
| **3** | 3V3 | `3V3` | LDO VOUT + C1 | 3,3 V Hauptversorgung |
| **4** | NC | - | - | Unbelegt |
| **5** | GPIO 2 | `I2S_SCK` | U4.4, U5.4 | I2S Bit Clock (BCLK) |
| **6** | GPIO 3 | `I2S_WS` | U4.1, U5.1 | I2S Word Select (LRCLK) |
| **7** | NC | - | - | Unbelegt |
| **8** | EN / CHIP_EN | `EN` | R5 (10k) + C11 (100n) | Reset / Enable (RC-Timing) |
| **9, 10** | NC | - | - | Unbelegt |
| **11** | GND | `GND` | Ground Plane | Masse |
| **12** | GPIO 0 | `FLASH_MISO` | U2.2 (DO) | SPI2 Serial Data Out (Audio-Flash) |
| **13** | GPIO 1 | `FLASH_MOSI` | U2.5 (DI) | SPI2 Serial Data In (Audio-Flash) |
| **14** | GND | `GND` | Ground Plane | Masse |
| **15** | NC | - | - | Unbelegt |
| **16** | GPIO 10 | `LED_R` | D1 (Rot) via R4 (330) | Aufnahme-Status (Rot) |
| **17** | GPIO 4 | `I2S_SD` | U4.6, U5.6 + R10 (100k) | I2S Mikrofondaten |
| **18** | GPIO 5 | `IMU_INT` | U3.4 (INT1) | IMU Wakeup-Interrupt |
| **19** | GPIO 6 | `I2C_SDA` | U3.14 (SDA) + R2 (4.7k) | I2C Daten |
| **20** | GPIO 7 | `I2C_SCL` | U3.13 (SCL) + R3 (4.7k) | I2C Takt |
| **21** | GPIO 8 | `LED_G` | D2 (Grün) via R6 (330) | System-/Wi-Fi-Status (Grün) |
| **22** | GPIO 9 | `BTN` | THT-Hole BTN $\rightarrow$ Schalter | Funktionstaste / Boot / Wakeup |
| **23, 24** | NC | - | - | Unbelegt |
| **25** | GPIO 18 | `USB_DN` | J1 (D-) | USB CDC Daten (-) |
| **26** | GPIO 19 | `USB_DP` | J1 (D+) | USB CDC Daten (+) |
| **27** | GPIO 20 | `FLASH_SCK` | U2.6 (CLK) | SPI2 Takt (Audio-Flash) |
| **28** | GPIO 21 | `FLASH_CS` | U2.1 (/CS) | SPI2 Chip Select (Audio-Flash) |
| **29–32** | NC | - | - | Unbelegt |
| **33–53** | GND / EPAD | `GND` | Thermal GND Plane | Masse & thermische Anbindung |

---

## TEIL 3 — PRODUCTION-CHECKLISTE FÜR JLCPCB

- [x] **ESP32-C3-MINI-1-N4 (C2934560)** als SMD-Modul verwendet (interner Flash + Quarz + Antenne vorhanden).
- [x] **Kein diskretes π-Matching und kein Quarz mehr nötig** (Fehlerquelle im alten Bare-Die Layout behoben).
- [x] **Audio-Flash W25Q128 (C97521)** korrekt an SPI2 angebunden (GPIO 0, 1, 20, 21).
- [x] **RC-Reset-Netzwerk** R5 ($10\,\text{k}\Omega$) + C11 ($100\,\text{nF}$) an EN garantiert $t_{\text{STBL}} \ge 50\,\mu\text{s}$.
- [x] **LDO AP2112K-3.3 (C51118)** mit C4 ($10\,\mu\text{F}$ Eingang) und C5 ($10\,\mu\text{F}$) + C6 ($100\,\text{nF}$) am Ausgang bestückt.
- [x] **I2S ICS-43434:** L/R-Pins fest an Masse (U4) bzw. 3,3 V (U5); R10 ($100\,\text{k}\Omega$) Pulldown auf SD vorhanden.
- [x] **LSM6DSLTR:** I2C-Pullups R2/R3 ($4{,}7\,\text{k}\Omega$) auf 3,3 V; CS an 3,3 V; SDO an GND.
- [x] **Akku & Taster:** Durchkontaktierte THT-Löcher ($d = 1{,}0\,\text{mm}$ / $D = 1{,}5\,\text{mm}$) für zuverlässige Litzenverlötung ohne SMD-Abrissrisiko.
- [x] **PCB-Keepout:** Unter der Antennenspitze des ESP32-C3-MINI-1 (Überhang bzw. Antennenbereich) dürfen auf keinem Layer Kupferflächen, Leiterbahnen oder Bauteile liegen.
