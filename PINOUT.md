# Hardware Pinout & Verdrahtungs-Leitfaden (Wiring Guide)
## Custom Production PCB V2 (ESP32-C3-MINI-1-N4)

Dieses Dokument dient als zentrale Referenz für Entwickler und Hardware-Ingenieure für das kundenspezifische **Serienboard (Production PCB V2)** mit dem **ESP32-C3-MINI-1-N4** Modul.

---

## 1. Vollständige Pin-Zuordnungs-Tabelle (Custom PCB V2)

| Komponente | Komponenten-Pin | ESP32-C3 Modul-Pin | ESP32-C3 GPIO | Funktion / Signalbeschreibung |
| :--- | :--- | :--- | :--- | :--- |
| **Power Rail** | 3.3V / VDD | **Pin 3** | - | **3,3V-Hauptversorgung** aus AP2112K LDO (U7) |
| **Ground Rail** | GND / Masse | **Pins 1, 2, 11, 14, 36–53** | - | **Gemeinsame Systemmasse** (Common Ground Bus) |
| **6-Achsen IMU**<br>(ST LSM6DSLTR, U3) | VDD / VDDIO | **Pin 3** | - | 3,3V Versorgungsspannung (U3 Pin 5 & 8) + C8 (100nF) |
| | GND | **GND** | - | Masse (U3 Pins 6 & 7) |
| | SCL | **Pin 20** | **GPIO 7** | I2C Clock (SCL) + R3 (4,7kΩ Pull-up nach 3V3) |
| | SDA | **Pin 19** | **GPIO 6** | I2C Data (SDA) + R2 (4,7kΩ Pull-up nach 3V3) |
| | SDO / SA0 | **GND** | - | Setzt I2C-Adresse fest auf **`0x6A`** |
| | CS | **3V3** | - | I2C-Modus aktivieren (CS auf HIGH) |
| | **INT1 (Shock/Tap)** | **Pin 18** | **GPIO 5** | **RTC-GPIO Interrupt:** Weckt ESP32-C3 aus Deep Sleep (< 10 µA)! |
| **Mikrofon 1**<br>(Links, ICS-43434, U4) | VDD | **Pin 3** | - | 3,3V Versorgungsspannung (U4 Pin 5) + C9 (100nF) |
| | GND | **GND** | - | Masse (U4 Pin 3) |
| | SCK / BCLK | **Pin 5** | **GPIO 2** | Shared I2S Bit Clock (BCLK) |
| | WS / LRCLK | **Pin 6** | **GPIO 3** | Shared I2S Word Select (Frame Clock) |
| | SD / DOUT | **Pin 17** | **GPIO 4** | Shared I2S Seriendaten + **R10 (100kΩ Pulldown)** |
| | **L/R** | **GND** | - | **Fest an GND: Konfiguriert Mikrofon 1 als LINKEN Kanal** |
| **Mikrofon 2**<br>(Rechts, ICS-43434, U5) | VDD | **Pin 3** | - | 3,3V Versorgungsspannung (U5 Pin 5) + C10 (100nF) |
| | GND | **GND** | - | Masse (U5 Pin 3) |
| | SCK / BCLK | **Pin 5** | **GPIO 2** | Parallel an Mic 1 SCK (Shared I2S Bus) |
| | WS / LRCLK | **Pin 6** | **GPIO 3** | Parallel an Mic 1 WS (Shared I2S Bus) |
| | SD / DOUT | **Pin 17** | **GPIO 4** | Parallel an Mic 1 SD (Shared I2S Bus) |
| | **L/R** | **3V3** | - | **Fest an 3V3: Konfiguriert Mikrofon 2 als RECHTEN Kanal** |
| **Status-LED D1**<br>(Aufnahme-Indikator, Rot) | Anode (+) | **3V3** | - | Anode fest an 3,3V |
| | Kathode (-) | **Pin 16** (via R4: 330Ω) | **GPIO 10** | Aktiv-LOW: GPIO 10 LOW schaltet D1 EIN |
| **Status-LED D2**<br>(System / WLAN, Grün) | Anode (+) | **3V3** | - | Anode fest an 3,3V |
| | Kathode (-) | **Pin 21** (via R6: 330Ω) | **GPIO 8** | Aktiv-LOW: GPIO 8 LOW schaltet D2 EIN |
| **User Switch / Button** | Taster Pin A | **Pin 22** | **GPIO 9** | Verbunden mit THT-Lötbohrung `BTN` & Testpad `BOOT` |
| | Taster Pin B | **GND** | - | Taster schaltet GPIO 9 gegen Masse (interner Pull-up) |
| **Externer SPI-Flash**<br>(Winbond W25Q128, U2) | VCC | **Pin 3** | - | 3,3V Stromversorgung + C7 (100nF) |
| | GND | **GND** | - | Masse (Pin 4) |
| | /CS (Chip Select) | **Pin 28** | **GPIO 21** | SPI2 Chip Select (Aktiv-LOW) |
| | CLK / SCK | **Pin 27** | **GPIO 20** | SPI2 Bus-Takt |
| | DI / MOSI | **Pin 13** | **GPIO 1** | SPI2 MOSI (Master Out -> Slave In) |
| | DO / MISO | **Pin 12** | **GPIO 0** | SPI2 MISO (Slave Out -> Master In) |
| | /HOLD & /WP | **3V3** | - | Fest an 3V3 gebunden (Standard-SPI Modus) |
| **USB-C Schnittstelle**<br>(GT-USB-7010ASV, J1) | D− (USB_DN) | **Pin 25** | **GPIO 18** | Nativer USB-Serial / JTAG Controller |
| | D+ (USB_DP) | **Pin 26** | **GPIO 19** | Nativer USB-Serial / JTAG Controller |
| | CC1 / CC2 | *(J1 Pins)* | - | Über R7 / R8 (5,1kΩ) nach GND terminiert |
| **Batterieladung & LDO** | TP4054 PROG | *(U6 Pin 5)* | - | R9 (2kΩ) nach GND -> 500mA Konstantstrom |
| | AP2112K LDO | *(U7)* | - | 600mA Low-Dropout Regler, Ausgang an `3V3` |
| | Akku-Lötbohrungen | **THT Holes** | - | `BAT+` (VBAT) und `BAT-` (GND) für 1S LiPo-Litze |
| | Testpunkte | **THT Pads** | - | `VDD+`, `BAT-`, `PCHG_DETECT`, `PCHG_PROG`, `BOOT`, `RESET` |

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

## 3. Software-Konfigurations-Auszug (`firmware/src/config.h`)

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
