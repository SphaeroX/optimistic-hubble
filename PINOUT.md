# Hardware Pinout & Verdrahtungs-Leitfaden (Wiring Guide)
## Prototyping (Seeed Studio XIAO ESP32C3) vs. Serie (Production PCB ESP32-C3-MINI-1-N4)

Dieses Dokument dient als zentrale Referenz für Entwickler und Hardware-Ingenieure. Es beschreibt:
1. Das **Breadboard-Prototyping-Setup** mit dem Entwicklungsboard **Seeed Studio XIAO ESP32C3**.
2. Die Übertragung und das Pinout auf das kundenspezifische **Serienboard (Production PCB V2)** mit dem **ESP32-C3-MINI-1-N4** Modul.

---

## 1. Umfassende Pin-Zuordnungs- und Vergleichstabelle

| Komponente | Komponenten-Pin | Prototyp XIAO Pin | Serie Modul-Pin | ESP32-C3 GPIO | Empf. Kabelfarbe | Funktion / Signalbeschreibung |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Power Rail** | 3.3V / VDD | **3V3** | **Pin 3** | - | 🔴 Rot | **3,3V-Hauptversorgung** (Niemals 5V an MEMS-Mikrofone anlegen!) |
| **Ground Rail** | GND / Masse | **GND** | **Pins 1, 2, 11, 14, 36–53** | - | ⚫ Schwarz | **Gemeinsame Systemmasse** (Common Ground Bus) |
| **6-Achsen IMU**<br>(LSM6DSL / LSM6DS3) | VDD / VDDIO | **3V3** | **Pin 3** | - | 🔴 Rot | 3,3V Versorgungsspannung (U3 Pin 5 & 8) + C8 (100nF) |
| | GND | **GND** | **GND** | - | ⚫ Schwarz | Masse (U3 Pins 6 & 7) |
| | SCL | **D5** | **Pin 20** | **GPIO 7** | 🟡 Gelb | I2C Clock (SCL) + R3 (4,7kΩ Pull-up nach 3V3) |
| | SDA | **D4** | **Pin 19** | **GPIO 6** | 🟢 Grün | I2C Data (SDA) + R2 (4,7kΩ Pull-up nach 3V3) |
| | SDO / SA0 | **GND** | **GND** | - | ⚫ Schwarz | Setzt I2C-Adresse fest auf **`0x6A`** |
| | CS | **3V3** | **3V3** | - | 🔴 Rot | I2C-Modus aktivieren (CS auf HIGH) |
| | **INT1 (Shock/Tap)** | **D3** | **Pin 18** | **GPIO 5** | ⚪ Weiß | **RTC-GPIO Interrupt:** Weckt ESP32-C3 aus Deep Sleep (< 10 µA)! |
| **Mikrofon 1**<br>(Links, ICS-43434) | VDD | **3V3** | **Pin 3** | - | 🔴 Rot | 3,3V Versorgungsspannung (U4 Pin 5) + C9 (100nF) |
| | GND | **GND** | **GND** | - | ⚫ Schwarz | Masse (U4 Pin 3) |
| | SCK / BCLK | **D0** | **Pin 5** | **GPIO 2** | 🟠 Orange | Shared I2S Bit Clock (BCLK) |
| | WS / LRCLK | **D1** | **Pin 6** | **GPIO 3** | 🔵 Blau | Shared I2S Word Select (Frame Clock) |
| | SD / DOUT | **D2** | **Pin 17** | **GPIO 4** | 🟣 Violett | Shared I2S Seriendaten + **R10 (100kΩ Pulldown)** |
| | **L/R** | **GND** | **GND** | - | ⚫ Schwarz | **Fest an GND: Konfiguriert Mikrofon 1 als LINKEN Kanal** |
| **Mikrofon 2**<br>(Rechts, ICS-43434) | VDD | **3V3** | **Pin 3** | - | 🔴 Rot | 3,3V Versorgungsspannung (U5 Pin 5) + C10 (100nF) |
| | GND | **GND** | **GND** | - | ⚫ Schwarz | Masse (U5 Pin 3) |
| | SCK / BCLK | **D0** | **Pin 5** | **GPIO 2** | 🟠 Orange | Parallel an Mic 1 SCK (Shared I2S Bus) |
| | WS / LRCLK | **D1** | **Pin 6** | **GPIO 3** | 🔵 Blau | Parallel an Mic 1 WS (Shared I2S Bus) |
| | SD / DOUT | **D2** | **Pin 17** | **GPIO 4** | 🟣 Violett | Parallel an Mic 1 SD (Shared I2S Bus) |
| | **L/R** | **3V3** | **3V3** | - | 🔴 Rot | **Fest an 3V3: Konfiguriert Mikrofon 2 als RECHTEN Kanal** |
| **Status-LED D1**<br>(Aufnahme-Indikator, Rot) | Anode (+) | **3V3** | **3V3** | - | 🔴 Rot | Anode fest an 3,3V |
| | Kathode (-) | **D10** (via 330Ω) | **Pin 16** (via R4) | **GPIO 10** | 🟤 Braun | Aktiv-LOW: GPIO 10 LOW schaltet D1 EIN |
| **Status-LED D2**<br>(System / WLAN, Grün) | Anode (+) | **3V3** | **3V3** | - | 🔴 Rot | Anode fest an 3,3V |
| | Kathode (-) | *(frei / ext)* | **Pin 21** (via R6) | **GPIO 8** | 🟢 Grün | Aktiv-LOW: GPIO 8 LOW schaltet D2 EIN |
| **User Switch / Button** | Taster Pin A | **D7** | **Pin 22** | **GPIO 9** | ⚪ Weiß | Verbunden mit THT-Lötbohrung `BTN` & Testpad `BOOT` |
| | Taster Pin B | **GND** | **GND** | - | ⚫ Schwarz | Taster schaltet GPIO 9 gegen Masse (interner Pull-up) |
| **Externer SPI-Flash**<br>(W25Q128 16MB Audio) | VCC | **3V3** | **Pin 3** | - | 🔴 Rot | 3,3V Stromversorgung + C7 (100nF) |
| | GND | **GND** | **GND** | - | ⚫ Schwarz | Masse (Pin 4) |
| | /CS (Chip Select) | **D3** *(oder ext)* | **Pin 28** | **GPIO 21** | ⚪ Weiß | SPI2 Chip Select (Aktiv-LOW) |
| | CLK / SCK | **D6** *(oder ext)* | **Pin 27** | **GPIO 20** | 🟤 Braun | SPI2 Bus-Takt |
| | DI / MOSI | **D9** | **Pin 13** | **GPIO 1** | 🟡 Gelb | SPI2 MOSI (Master Out -> Slave In) |
| | DO / MISO | **D8** | **Pin 12** | **GPIO 0** | 🟢 Grün | SPI2 MISO (Slave Out -> Master In) |
| | /HOLD & /WP | **3V3** | **3V3** | - | 🔴 Rot | Fest an 3V3 gebunden (Standard-SPI Modus) |
| **USB-C Schnittstelle** | D− (USB_DN) | *(USB Port)* | **Pin 25** | **GPIO 18** | ⚪ Weiß | Nativer USB-Serial / JTAG Controller |
| | D+ (USB_DP) | *(USB Port)* | **Pin 26** | **GPIO 19** | 🟢 Grün | Nativer USB-Serial / JTAG Controller |
| | CC1 / CC2 | *(intern)* | *(J1 Pins)* | - | - | Über R7 / R8 (5,1kΩ) nach GND terminiert |
| **Batterieladung & LDO** | TP4054 PROG | - | *(U6 Pin 5)* | - | - | R9 (2kΩ) nach GND -> 500mA Konstantstrom |
| | AP2112K LDO | - | *(U7)* | - | - | 600mA Low-Dropout Regler, Ausgang an `3V3` |
| | Akku-Lötbohrungen | *(BAT Pads)* | **THT Holes** | - | - | `BAT+` (VBAT) und `BAT-` (GND) für 1S LiPo-Litze |

---

## 2. Detaillierte Schaltbilder & Bus-Konzepte

### 2.1 Gemeinsamer Stereo I2S-Bus (ICS-43434 Multiplexing)

Beide I2S-MEMS-Mikrofone (U4 & U5) teilen sich dieselben drei Signalleitungen am ESP32-C3:

```
        ESP32-C3 GPIO 2 (SCK)  -------------------+-------------------+
        ESP32-C3 GPIO 3 (WS)   --------------+    |                   |
        ESP32-C3 GPIO 4 (SD)   ---------+    |    |                   |
                                        |    |    |                   |
                                      +-------------+       +-------------+
                                      | U4 (Links)  |       | U5 (Rechts) |
                                      | ICS-43434   |       | ICS-43434   |
                                      +-------------+       +-------------+
                                      | 4: SCK      |       | 4: SCK      |
                                      | 1: WS       |       | 1: WS       |
                                      | 6: SD       |       | 6: SD       |
                                      | 2: L/R      |       | 2: L/R      |
                                      | 5: VDD(3V3) |       | 5: VDD(3V3) |
                                      | 3: GND      |       | 3: GND      |
                                      +-------------+       +-------------+
                                             |                     |
                                            GND                   3V3
                                       (Linker Kanal)        (Rechter Kanal)
```

* **Funktionsweise des Multiplexings:**
  * **Word Select (`WS` = LOW):** Mikrofon U4 aktiviert seinen Tri-State-Ausgang und sendet 24-Bit Audiodaten des **linken Kanals** über `SD`. Mikrofon U5 befindet sich im hochohmigen Zustand (Hi-Z).
  * **Word Select (`WS` = HIGH):** Mikrofon U5 aktiviert seinen Ausgang und sendet die Daten des **rechten Kanals** über `SD`. Mikrofon U4 ist im Hi-Z-Zustand.
  * **R10 (100 kΩ Pulldown an SD):** Zieht die Datenleitung in den Umschaltphasen definiert gegen Masse und verhindert kapazitives Rauschen.

---

### 2.2 Status-LEDs (D1 Rot, D2 Grün)

```
        3.3V Rail
           |
           +--------------------+
           |                    |
        +-----+              +-----+
        | D1  | LED Rot      | D2  | LED Grün
        | (A) | (Aufnahme)   | (A) | (System)
        +-----+              +-----+
        | (K) |              | (K) |
        +-----+              +-----+
           |                    |
       [ R4: 330Ω ]         [ R6: 330Ω ]
           |                    |
      GPIO 10 (Pin 16)      GPIO 8 (Pin 21)
       (Aktiv-LOW)          (Aktiv-LOW)
```

* **Software-Steuerung:**
  * LED Einschalten: `digitalWrite(PIN, LOW);` (Strom fließt von 3V3 über Vorwiderstand in den GPIO).
  * LED Ausschalten: `digitalWrite(PIN, HIGH);` oder Pin auf `INPUT` (Tri-State).

---

### 2.3 Prototyping XIAO ESP32C3 Pinout-Diagramm

Für das Breadboard-Setup mit dem Seeed Studio XIAO ESP32C3:

```
                              +-------------------+
                              |   [USB-C Port]    |
        (I2S SCK) (GPIO 2) D0 [ ]                 [ ] 5V       (USB 5V Out)
        (I2S WS)  (GPIO 3) D1 [ ]                 [ ] GND      (Masse-Schiene)
        (I2S SD)  (GPIO 4) D2 [ ]                 [ ] 3V3      (3,3V Power-Rail)
  (IMU INT / CS)  (GPIO 5) D3 [ ]                 [ ] D10 / LED(GPIO 10 -> D1 Rot)
  (I2C SDA)       (GPIO 6) D4 [ ]                 [ ] D9       (GPIO 1  -> SPI MOSI)
  (I2C SCL)       (GPIO 7) D5 [ ]                 [ ] D8       (GPIO 0  -> SPI MISO)
  (SPI SCK)       (GPIO 8) D6 [ ]                 [ ] D7       (GPIO 9  -> Boot / BTN)
                              +-------------------+
```

---

## 3. Unterschiede Prototyp (XIAO) vs. Serie (Production PCB)

| Aspekt | Breadboard Prototyp (XIAO ESP32C3) | Serie (Custom Production PCB V2) |
| :--- | :--- | :--- |
| **MCU Formfaktor** | Fertiges Entwicklungsboard (XIAO) | **ESP32-C3-MINI-1-N4 Modul (53 SMD-Pins)** |
| **Abmessungen** | 21 mm × 17,5 mm (nur MCU Board) | **Ganze Platine: extrem kompakt (ca. 20 mm × 37 mm)** |
| **Programm-Flash** | 4 MB extern auf XIAO integriert | **4 MB im ESP32-C3-MINI-1 Modul integriert** |
| **Audio-Flash (W25Q128)** | Externes SPI-Flash Breakout-Modul | **Onboard W25Q128JVSIQ (SOIC-8) an SPI2 (GPIO 0, 1, 20, 21)** |
| **Mikrofone** | Breakout-Boards mit Stiftleisten | **2x ICS-43434 SMD auf Board mit akustischen Durchgangslöchern** |
| **IMU** | LSM6DS3 / BMI160 I2C Breakout | **LSM6DSLTR (LGA-14) direkt auf I2C (GPIO 6, 7) + INT an GPIO 5** |
| **Stromversorgung** | USB-C vom XIAO / ETA6003 Charger | **TP4054 (500mA Charger) + AP2112K-3.3 (600mA Low-Dropout LDO)** |
| **Akku-Anschluss** | 2 kleine Lötpads auf XIAO-Unterseite | **Robuste durchkontaktierte THT-Lötbohrungen `BAT+` / `BAT-`** |
| **Bedienung** | Reset / Boot-Taster auf XIAO | **THT-Lötbohrungen `BTN` / `GND` für externen Gehäusetaster** |
| **Statusanzeige** | 1x externe LED auf D10 | **D1 Rot (GPIO 10) + D2 Grün (GPIO 8)** |
| **Testpunkte** | Keine genormten Testpads | **6x dedizierte THT-Testpunkte: VDD+, BAT-, PCHG_DETECT, PCHG_PROG, BOOT, RESET** |

---

## 4. Software-Konfigurations-Auszug (`firmware/src/config.h`)

Die Firmware-Pindefinitionen stimmen exakt mit dem Produktionsschaltplan überein:

```cpp
// I2C Pins für 6-Achsen IMU (LSM6DSL)
#define PIN_I2C_SDA      6   // GPIO 6 (Modul-Pin 19)
#define PIN_I2C_SCL      7   // GPIO 7 (Modul-Pin 20)
#define PIN_IMU_INT      5   // GPIO 5 (Modul-Pin 18) - RTC Wakeup Interrupt
#define PIN_BOOT_BTN     9   // GPIO 9 (Modul-Pin 22) - THT BTN / Boot Button

// I2S Stereo Mikrofon Pins (ICS-43434)
#define PIN_I2S_SCK      2   // GPIO 2 (Modul-Pin 5)  - Bit Clock
#define PIN_I2S_WS       3   // GPIO 3 (Modul-Pin 6)  - Word Select / LRCLK
#define PIN_I2S_SD       4   // GPIO 4 (Modul-Pin 17) - Serial Data

// Status LEDs
#define PIN_STATUS_LED  10   // GPIO 10 (Modul-Pin 16) - D1 Rot (Aufnahme)
#define PIN_LED_GREEN    8   // GPIO 8  (Modul-Pin 21) - D2 Grün (Status / WLAN)

// Externer Audio SPI-Flash (W25Q128 auf SPI2)
#define PIN_FLASH_CS    21   // GPIO 21 (Modul-Pin 28) - /CS
#define PIN_FLASH_SCK   20   // GPIO 20 (Modul-Pin 27) - CLK
#define PIN_FLASH_MOSI   1   // GPIO 1  (Modul-Pin 13) - DI
#define PIN_FLASH_MISO   0   // GPIO 0  (Modul-Pin 12) - DO
```
