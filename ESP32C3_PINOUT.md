# ESP32-C3-MINI-1-N4 — Pinout & Hardware-Spezifikation für Diktiergerät V2 (Production)

**Modul:** U1 · ESP32-C3-MINI-1-N4 (LCSC: **C2934560**, Espressif) · 53 SMD-Pads (13,2 mm × 16,6 mm × 2,4 mm)  
**Merkmale:** Integrierter 4 MB SPI-Flash, integrierter 40 MHz Quarz, integrierte PCB-Antenne (MIFA)  
**Quellen:** Espressif ESP32-C3-MINI-1 Datasheet v2.2 (Tab. 3-1, Tab. 4-1) · Schaltplan `SCHEMATIC_V2.png` · Stückliste `docs/hardware/BOM_V2_ESP32C3_MINI1.xlsx`

> [!IMPORTANT]
> **Vorteil gegenüber dem alten Bare-Die QFN-32 Design:**  
> Das Produktionsboard setzt auf das vollintegrierte **ESP32-C3-MINI-1-N4** Modul. Dadurch entfallen:
> 1. Der externe 40 MHz Quarz (Y1) sowie die Lastkondensatoren (C12, C13).
> 2. Die externe 2,4 GHz Chip-Antenne (A1, C293767).
> 3. Das diskrete HF-π-Matching-Netzwerk (C14, L1, C15).
> 
> Das Modul ist funkzertifiziert (CE / FCC / SRRC), garantiert optimale HF-Stabilität und reduziert die Bauteilanzahl und Bestückungsrisiken drastisch.

---

## 1. Vollständige 53-Pin Modul-Tabelle (ESP32-C3-MINI-1)

| Modul-Pin | Signalname | ESP32-C3 GPIO / Funktion | Funktion im V2-Design | Verbunden mit | Typ / Bemerkung |
| :---: | :--- | :--- | :--- | :--- | :--- |
| **1** | GND | Masse | System-Masse | `GND` | Power |
| **2** | GND | Masse | System-Masse | `GND` | Power |
| **3** | 3V3 | VDD (3,0 V – 3,6 V) | 3,3V-Hauptversorgung | `3V3` (LDO U7 Ausgang) + C1 (100nF) | Power In |
| **4** | NC | — | Unbelegt | Nicht verbunden (NC) | Frei |
| **5** | IO2 | GPIO2 / ADC1_CH2 | I2S Bit Clock (SCK / BCLK) | U4 Pin 4 & U5 Pin 4 (Shared I2S) | ⚠️ **Strapping-Pin** (Pull-down im Boot) |
| **6** | IO3 | GPIO3 / ADC1_CH3 | I2S Word Select (WS / LRCLK) | U4 Pin 1 & U5 Pin 1 (Shared I2S) | I/O |
| **7** | NC | — | Unbelegt | Nicht verbunden (NC) | Frei |
| **8** | EN | CHIP_EN / RESET | Hardware-Reset & Enable | R5 (10k → `3V3`), C11 (100nF → `GND`), Testpad `RESET` | Aktiv-High / RC-Glied |
| **9** | NC | — | Unbelegt | Nicht verbunden (NC) | Frei |
| **10** | NC | — | Unbelegt | Nicht verbunden (NC) | Frei |
| **11** | GND | Masse | System-Masse | `GND` | Power |
| **12** | IO0 | GPIO0 / ADC1_CH0 | Flash MISO (DO / IO1) | U2 Pin 2 (W25Q128 DO) | SPI2 Daten-Eingang |
| **13** | IO1 | GPIO1 / ADC1_CH1 | Flash MOSI (DI / IO0) | U2 Pin 5 (W25Q128 DI) | SPI2 Daten-Ausgang |
| **14** | GND | Masse | System-Masse | `GND` | Power |
| **15** | NC | — | Unbelegt | Nicht verbunden (NC) | Frei |
| **16** | IO10 | GPIO10 / FSPICS0 | Status-LED Rot (D1) | D1 Kathode über R4 (330Ω) nach `3V3` | Aktiv-LOW (Aufnahme-Indikator) |
| **17** | IO4 | GPIO4 / ADC1_CH4 | I2S Serial Data (SD / DOUT) | U4 Pin 6 & U5 Pin 6 + R10 (100kΩ → `GND`) | Shared I2S Mikrofondaten |
| **18** | IO5 | GPIO5 / ADC2_CH0 | IMU Wakeup Interrupt (INT1) | U3 Pin 4 (LSM6DSL INT1) | RTC-GPIO / Deep-Sleep Wakeup |
| **19** | IO6 | GPIO6 | I2C Data (SDA) | U3 Pin 14 (LSM6DSL SDA) + R2 (4,7kΩ → `3V3`) | I2C-Bus (Hardware) |
| **20** | IO7 | GPIO7 | I2C Clock (SCL) | U3 Pin 13 (LSM6DSL SCL) + R3 (4,7kΩ → `3V3`) | I2C-Bus (Hardware) |
| **21** | IO8 | GPIO8 | Status-LED Grün (D2) | Kathode D2 über R6 (330Ω) nach `3V3` | ⚠️ **Strapping-Pin** (ROM-Log Print) |
| **22** | IO9 | GPIO9 | User-Button / Switch (`BTN`) | THT-Bohrung `BTN` → Taster → `GND` + Testpad `BOOT` | ⚠️ **Strapping-Pin** (interner Pull-up) |
| **23** | NC | — | Unbelegt | Nicht verbunden (NC) | Frei |
| **24** | NC | — | Unbelegt | Nicht verbunden (NC) | Frei |
| **25** | IO18 | GPIO18 / USB_D- | USB 2.0 Full-Speed D− | J1 USB-C Pin A7/B7 (USB_DN) | Nativer USB-Serial / JTAG |
| **26** | IO19 | GPIO19 / USB_D+ | USB 2.0 Full-Speed D+ | J1 USB-C Pin A6/B6 (USB_DP) | Nativer USB-Serial / JTAG |
| **27** | IO20 | GPIO20 / U0RXD | Flash SPI Clock (SCK) | U2 Pin 6 (W25Q128 CLK) | SPI2 Bus Clock |
| **28** | IO21 | GPIO21 / U0TXD | Flash Chip Select (/CS) | U2 Pin 1 (W25Q128 /CS) | SPI2 Chip Select |
| **29** | NC | — | Unbelegt | Nicht verbunden (NC) | Frei |
| **30** | NC | — | Unbelegt (optional UART RX) | Nicht verbunden (NC) | Frei |
| **31** | NC | — | Unbelegt (optional UART TX) | Nicht verbunden (NC) | Frei |
| **32** | NC | — | Unbelegt | Nicht verbunden (NC) | Frei |
| **33** | NC | — | Unbelegt | Nicht verbunden (NC) | Frei |
| **34** | NC | — | Unbelegt | Nicht verbunden (NC) | Frei |
| **35** | NC | — | Unbelegt | Nicht verbunden (NC) | Frei |
| **36–53** | GND | Center Thermal / Ground | Thermische Anbindung / Masse | `GND` (großflächige Massefläche mit Via-Matrix) | Ground & Wärmeableitung |

---

## 2. Kompakte GPIO-Funktionsmatrix (GPIO 0 bis 21)

| GPIO | Modul-Pin | Primäre Peripherie | Funktion im Design | Ziel-Komponente & Pins | Pegel / Besonderheit |
| :---: | :---: | :--- | :--- | :--- | :--- |
| **GPIO 0** | Pin 12 | SPI2 MISO | Flash Data Out (DO) | U2 Pin 2 (W25Q128 DO / IO1) | Digital In |
| **GPIO 1** | Pin 13 | SPI2 MOSI | Flash Data In (DI) | U2 Pin 5 (W25Q128 DI / IO0) | Digital Out |
| **GPIO 2** | Pin 5 | I2S SCK | Microphone Bit Clock (BCLK) | U4 Pin 4 & U5 Pin 4 | ⚠️ **Strapping-Pin** (Default: Low) |
| **GPIO 3** | Pin 6 | I2S WS | Microphone Frame Clock (LRCLK)| U4 Pin 1 & U5 Pin 1 | Digital Out |
| **GPIO 4** | Pin 17 | I2S SD | Microphone Data Line (DIN) | U4 Pin 6 & U5 Pin 6 + R10 (100kΩ) | Digital In (Shared Bus) |
| **GPIO 5** | Pin 18 | RTC GPIO5 | IMU Hardware Shock/Tap Wakeup | U3 Pin 4 (LSM6DSL INT1) | RTC Interrupt / Deep-Sleep Wake |
| **GPIO 6** | Pin 19 | I2C0 SDA | Sensor Bus Datenleitung | U3 Pin 14 + R2 (4,7kΩ Pull-up) | Open-Drain / I2C Fast Mode (400 kHz) |
| **GPIO 7** | Pin 20 | I2C0 SCL | Sensor Bus Taktleitung | U3 Pin 13 + R3 (4,7kΩ Pull-up) | Open-Drain / I2C Fast Mode (400 kHz) |
| **GPIO 8** | Pin 21 | GPIO8 | Status-LED Grün (D2) | Kathode D2 über R6 (330Ω) nach 3V3 | ⚠️ **Strapping-Pin** (Aktiv-LOW) |
| **GPIO 9** | Pin 22 | GPIO9 / BOOT | User-Button / Switch (`BTN`) | THT `BTN` gegen GND / Pad `BOOT` | ⚠️ **Strapping-Pin** (interner Pull-up) |
| **GPIO 10**| Pin 16 | GPIO10 | Status-LED Rot (D1) | Kathode D1 über R4 (330Ω) nach 3V3 | Aktiv-LOW (Aufnahme aktiv) |
| **GPIO 11**| — | *Nicht als externer GPIO herausgeführt (intern für Modul-Flash reserviert)* | — | — | — |
| **GPIO 12–17**| — | *Intern für integrierten 4 MB SPI-Flash im Modul verdrahtet* | — | — | — |
| **GPIO 18**| Pin 25 | USB D- | USB Full-Speed Daten (D−) | J1 Pin A7/B7 (GT-USB-7010ASV) | USB PHY direkt integriert |
| **GPIO 19**| Pin 26 | USB D+ | USB Full-Speed Daten (D+) | J1 Pin A6/B6 (GT-USB-7010ASV) | USB PHY direkt integriert |
| **GPIO 20**| Pin 27 | SPI2 SCK | Flash SPI Clock (CLK) | U2 Pin 6 (W25Q128 CLK) | Digital Out |
| **GPIO 21**| Pin 28 | SPI2 CS | Flash Chip Select (/CS) | U2 Pin 1 (W25Q128 /CS) | Digital Out (Aktiv-LOW) |

---

## 3. Strapping-Pins & Boot-Konfiguration

Der ESP32-C3 besitzt drei Strapping-Pins, deren logischer Pegel während des Kaltstarts / Resets abgefragt wird (tSTBL-Phase):

| Strapping-Pin | Modul-Pin | Interner Pull | Boot-Funktion | Verhalten im Design |
| :--- | :---: | :---: | :--- | :--- |
| **GPIO 2** | Pin 5 | Pull-down | Boot-Modus-Selektion | Verbunden mit I2S SCK. Die ICS-43434 Mikrofone ziehen den SCK-Pin im Ruhezustand nicht nach High; der Pin bleibt beim Reset LOW. |
| **GPIO 8** | Pin 21 | Pull-up | ROM-Log Printing Steuerung (1 = Ausgabe aktiv, 0 = stumm) | Verbunden über R6 (330Ω) und grüne LED D2 an 3V3. Zieht den Pin sanft nach High $\rightarrow$ Standard-Bootmeldungen auf USB-CDC/UART bleiben erhalten. |
| **GPIO 9** | Pin 22 | Pull-up | **Boot-Modus: 1 = SPI Boot (Normal), 0 = Download Boot (Flashen)** | Taster an THT `BTN` schaltet gegen Masse. Bei Normalstart unbetätigt (High durch internen Pull-up $\rightarrow$ bootet aus Flash). Wird der Taster beim Einschalten gedrückt gehalten (Low $\rightarrow$ Download Boot), startet der ROM-Bootloader für Firmware-Recovery/Flashen über USB. |

---

## 4. Detaillierte Peripherie-Beschaltung

### 4.1 Externer Audio-Speicher: W25Q128JVSIQ (U2, 16 MB NOR Flash)
* **Bus:** Dedizierter SPI2-Bus (vollständig unabhängig vom internen 4 MB Programmcode-Flash des ESP32-C3-MINI-1).
* **Pin 1 (/CS):** An **GPIO 21** (Modul-Pin 28).
* **Pin 2 (DO / IO1):** An **GPIO 0** (Modul-Pin 12) als MISO.
* **Pin 3 (/WP / IO2):** Fest an `3V3` gebunden (Standard-SPI Modus).
* **Pin 4 (GND):** An `GND`.
* **Pin 5 (DI / IO0):** An **GPIO 1** (Modul-Pin 13) als MOSI.
* **Pin 6 (CLK):** An **GPIO 20** (Modul-Pin 27) als SPI-Takt.
* **Pin 7 (/HOLD / IO3):** Fest an `3V3` gebunden.
* **Pin 8 (VCC):** An `3V3` mit Pufferkondensator **C7 (100 nF, 0402)** direkt am Pin gegen `GND`.

### 4.2 Stereo MEMS-Mikrofone: 2x ICS-43434 (U4 links, U5 rechts)
* **Bus:** Gemeinsamer (shared) digitaler I2S-Bus.
* **SCK (Pin 4):** Beide Mikrofone an **GPIO 2** (Modul-Pin 5).
* **WS (Pin 1):** Beide Mikrofone an **GPIO 3** (Modul-Pin 6).
* **SD (Pin 6):** Beide Mikrofone an **GPIO 4** (Modul-Pin 17).
* **Bus-Terminierung:** **R10 (100 kΩ, 0402)** als Pulldown von SD (GPIO 4) nach `GND`. Verhindert Floating der Datenleitung in den Tri-State-Austastlücken zwischen linkem und rechtem Kanal.
* **Kanalzuweisung (L/R-Pin 2):**
  * **U4 (Linker Kanal):** Pin 2 fest an `GND` verdrahtet.
  * **U5 (Rechter Kanal):** Pin 2 fest an `3V3` verdrahtet.
* **Entkopplung:** C9 (100 nF) an U4 Pin 5 (VDD); C10 (100 nF) an U5 Pin 5 (VDD) direkt am Gehäuse gegen `GND`.
* **Akustikport:** Bohrung (0,6–0,8 mm) in der Leiterplatte unter dem Gehäuse für Schalleintritt von unten.

### 4.3 6-Achsen IMU: LSM6DSLTR (U3, STMicroelectronics)
* **Bus:** Hardware-I2C, Adresse `0x6A`.
* **SDA (Pin 14):** An **GPIO 6** (Modul-Pin 19) mit Pull-up-Widerstand **R2 (4,7 kΩ, 0402)** an `3V3`.
* **SCL (Pin 13):** An **GPIO 7** (Modul-Pin 20) mit Pull-up-Widerstand **R3 (4,7 kΩ, 0402)** an `3V3`.
* **INT1 (Pin 4):** An **GPIO 5** (Modul-Pin 18). Dient als Hardware-Interrupt (Double-Tap / Shock / Bewegung), um den ESP32-C3 über den RTC-GPIO aus dem Deep Sleep aufzuwecken.
* **Konfiguration:** CS (Pin 12) an `3V3` (aktiviert I2C-Modus), SDO/SA0 (Pin 1) an `GND` (setzt I2C-Adresse 0x6A).
* **Versorgung:** VDD (Pin 8) und VDDIO (Pin 5) an `3V3`, Pins 6 & 7 an `GND`. Entkopplung über **C8 (100 nF, 0402)**.

### 4.4 Status-LEDs (D1 rot, D2 grün)
* **D1 (Rot, KT-0603R, C2286):** Anode an `3V3`, Kathode über Vorwiderstand **R4 (330 Ω, 0402)** an **GPIO 10** (Modul-Pin 16). Signalisiert aktive Sprachaufnahme.
* **D2 (Grün, LTST-C190GKT, C125093):** Anode an `3V3`, Kathode über Vorwiderstand **R6 (330 Ω, 0402)** an **GPIO 8** (Modul-Pin 21). Signalisiert Systemstatus, WLAN-Transfer oder Akkuladung.
* **Schaltungslogik:** Aktiv-LOW (GPIO auf LOW schaltet LED ein, GPIO auf HIGH bzw. Tri-State schaltet LED aus).

### 4.5 USB-C Schnittstelle (J1, GT-USB-7010ASV)
* **Natives USB:** GPIO 18 (Modul-Pin 25) an D− und GPIO 19 (Modul-Pin 26) an D+. Bietet integrierten USB-CDC (virtuelle serielle Konsole) und JTAG-Debugging ohne externen USB-UART-Chip (wie CP2102/CH340).
* **CC-Leitungen:** CC1 und CC2 sind jeweils über **R7 und R8 (5,1 kΩ, 0402)** nach `GND` gezogen. Ermöglicht ordnungsgemäße Erkennung an Standard-USB-C-Netzteilen und Host-Computern (Standard 5V/3A bzw. 5V/1.5A).
* **VBUS:** 5 V Einspeisung mit Pufferkondensator **C3 (10 µF, 0402)** gegen Masse.

### 4.6 Spannungsversorgung & Ladekreis
* **Li-Ion Laderegler (U6, TP4054):**
  * Eingang: VBUS (5 V) von USB-C.
  * Ausgang: Netz `BAT` zum 1S LiPo-Akku (3,7 V Nennspannung, 4,2 V Ladeschlussspannung).
  * **R9 (2 kΩ, 0402)** an Pin 5 (PROG) nach `GND` stellt den Ladestrom exakt auf **500 mA** ein ($I_{CHG} = 1000\,	ext{V} / 2000\,\Omega$).
* **Spannungsregler (U7, AP2112K-3.3TRG1):**
  * Typ: Ultra-Low-Dropout CMOS LDO (SOT-25-5), bis zu 600 mA Dauerstrom, extrem geringer Dropout (~250 mV bei Vollast).
  * Eingang (Pin 1 VIN): Verbunden mit `BAT`, gestützt durch **C4 (10 µF, 0402)**.
  * Enable (Pin 3 EN): Verbunden mit `BAT` (dauerhaft aktiv).
  * Ausgang (Pin 5 VOUT): Regelt auf stabile 3,3 V (`3V3`), stabilisiert durch **C5 (10 µF, 0402)** und HF-Filter **C6 (100 nF, 0402)**.

### 4.7 THT-Bohrungen & Testpads
* **Akku-Anschluss:** 2 durchkontaktierte Lötbohrungen `BAT+` (VBAT) und `BAT-` / `GND` (Loch-Ø 1,0 mm, Pad-Ø 1,8 mm) zum direkten Durchstecken und Verlöten der Litzen des 1S LiPo-Akkus (kein fehleranfälliger JST-Stecker nötig).
* **User-Button:** 2 durchkontaktierte Lötbohrungen `BTN` (GPIO 9) und `GND` zum Anschluss des Gehäuseschalters/Tasters.
* **Testpads (1x1 P2.54 THT / Testpunkte, OD=1,5 mm, ID=1,0 mm):**
  1. `VDD+`: Batteriespannung (VBAT)
  2. `BAT-`: Akku-Masse (GND)
  3. `PCHG_DETECT`: Batteriestatus-Erkennung
  4. `PCHG_PROG`: Ladestrom-/Status-Messpunkt
  5. `BOOT`: Manuelles Triggern des Bootloader-Modus (GPIO 9 nach GND)
  6. `RESET`: Manueller Hardware-Reset (CHIP_EN nach GND)

---

## 5. Layout- & Fertigungshinweise

1. **Antennen-Keepout:** Der Antennenbereich des ESP32-C3-MINI-1 (Kopfseite mit Meander-Leiterbahn) muss zwingend über die Kante des Träger-PCBs hinausragen oder als Keepout definiert sein: **Kein Kupfer, keine Leiterbahnen, keine Masseflächen auf allen Layern unter der Antenne!**
2. **Masse-Vias (EPAD):** Die zentralen Masse-Pads (Pins 36 bis 53) müssen über eine dichte 3×3- bzw. 4×4-Via-Matrix direkt mit dem durchgehenden Ground-Plane auf Bottom/Innenlagen thermisch und niederohmig verbunden werden.
3. **Mikrofon-Schallführung:** Unter den beiden ICS-43434 Mikrofonen (U4, U5) muss sich jeweils eine saubere Durchkontaktierungsbohrung (0,6–0,8 mm ohne Kupferring am Schalleintritt) im Board befinden, damit der Schall ungehindert von der Gehäuseaußenseite zum MEMS-Sensor gelangt.
4. **CHIP_EN RC-Reset:** Der 10 kΩ Pull-up (R5) und der 100 nF Kondensator (C11) müssen zwingend nahe an Pin 8 platziert werden, um die minimale Anstiegszeit $t_{STBL} \ge 50\,\mu	ext{s}$ zuverlässig einzuhalten.

---
*Dokumentation aktualisiert für Produktionsstand V2 mit ESP32-C3-MINI-1-N4. Vollständig geprüft gegen Schaltplan `SCHEMATIC_V2.png`, BOM und Espressif Hardware Guidelines.*
