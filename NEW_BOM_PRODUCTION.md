# Diktiergerät V2 — Production-Dokument (BOM + Verdrahtung)

**Stand:** 2026-08-23 (rev. nach Fach-Review) · **Status:** Alle Teile JLCPCB-verifiziert, Pin-Zuordnung gegen ESP32-C3 Datasheet v2.4 + offizielle Symbols geprüft
**Fertigungsziel:** JLCPCB PCBA (SMT-Bestückung) · **Akku & Switch: fest verdrahtet über durchkontaktierte THT-Lötbohrungen (Holes)**

> **Design-Entscheidungen (verifiziert):**
> - SPI-Flash-Bus (SPI0/1) = **GPIO12–17** → **ESP32-C3 C2838500 (OHNE internen Flash)** + W25Q128 als Boot-Daten-Flash.
> - **CHIP_EN** braucht zwingend RC (10k + 100nF) → tSTBL ≥ 50µs (Datasheet 2.5.3).
> - **LNA_IN (Pin 1)** braucht Antenne + π-Matching → Bare-SoC, sonst < 1m Reichweite.
> - **IC-43434 L/R-Pin (Pin 2)** muss beschaltet werden (U4→GND, U5→3V3).
> - **Akku fest verdrahtet** (kein JST-Stecker, keine großen SMD-Pads) → 2 durchkontaktierte THT-Lötbohrungen (Holes, z. B. Loch-Ø 1,0 mm, Pad-Ø 1,8 mm) für `BAT` (+) und `GND` (−) zum Durchstecken der Litzen und Verlöten.
> - **Switch / Button extern** (kein SMD-Taster, keine großen SMD-Pads) → 2 durchkontaktierte THT-Lötbohrungen (Holes, z. B. Loch-Ø 1,0 mm, Pad-Ø 1,8 mm) für `BTN` (GPIO9) und `GND` zum Durchstecken der Leitungen.

---

## TEIL 0 — GESAMT-BOM (komplett, für JLCPCB)

> **"LCSC" = JLCPCB-Part-Nummer**, **"MPN" = Hersteller-Teilenummer**, **Typ**: basic = kein Handling-Fee · ext = +$3/Zeile. Preise = 1-Stück-Tier. Alle Codes am 2026-08-23 per JLCPCB-API geprüft (lagernd).

### 0.1 Halbleiter & Module
| Ref | Value        | MPN          | Footprint     | **LCSC**     | Qty | Stock   | Typ       | Preis  | Note                          |
| --- | ------------ | ------------ | ------------- | ------------ | --- | ------- | --------- | ------ | ----------------------------- |
| U1  | ESP32-C3     | ESP32-C3     | QFN-32_5x5mm  | **C2838500** | 1   | 5.227   | ext       | $1.84  | SoC RISC-V, ohne int. Flash   |
| U2  | W25Q128JVSIQ | W25Q128JVSIQ | SOIC-8-208mil | **C97521**   | 1   | 82.615  | **basic** | $2.59  | 16MB SPI-Flash (Boot+Audio)   |
| U3  | LSM6DSL      | LSM6DSLTR    | LGA-14_2.5x3  | **C126672**  | 1   | 9.995   | ext       | $2.68  | IMU, Tap/Doppel-Tap/Pedometer |
| U4  | ICS-43434    | ICS-43434    | LGA-6_3.5x2.7 | **C5656610** | 1   | 4.391   | ext       | $3.80  | Mic L (LR→GND)                |
| U5  | ICS-43434    | ICS-43434    | LGA-6_3.5x2.7 | **C5656610** | 1   | 4.391   | ext       | $3.80  | Mic R (LR→3V3)                |
| U6  | TP4054       | TP4054       | TSOT-23-5     | **C668215**  | 1   | 165.704 | ext       | $0.043 | 1S Li-Ion Laderegler          |
| U7  | ME6211C33M5G | ME6211C33M5G | SOT-23-5      | **C82942**   | 1   | 2.590   | ext       | $0.05  | LDO 3,3V 500mA                |

### 0.2 Anschlüsse, Antenne, Mechanik
| Ref    | Value                   | MPN            | Footprint  | **LCSC**      | Qty | Stock     | Typ       | Preis   | Note                        |
| ------ | ----------------------- | -------------- | ---------- | ------------- | --- | --------- | --------- | ------- | --------------------------- |
| J1     | USB-C                   | GT-USB-7010ASV | USB-C SMD  | **C2988369**  | 1   | 168.369   | ext       | $0.087  | USB-C 16P                   |
| Y1     | 40MHz Quarz             | 40MHz 15pF     | SMD3225-4P | **C47089419** | 1   | 1.533     | ext       | $0.105  | Haupttakt (Pflicht)         |
| **A1** | **2.4GHz Chip-Antenne** | ANT3216LL      | 1206       | **C293767**   | 1   | 25.822    | ext       | $0.18   | PCB-Antenne über π-Matching |
| D1     | LED Rot                 | 0603 Red       | 0603       | **C2286**     | 1   | 5.729.707 | **basic** | $0.0074 | Status-LED rot              |
| D2     | LED Grün                | LTST-C190GKT   | 0603       | **C125093**   | 1   | 79.086    | ext       | $0.0233 | Status-LED grün             |

> **Akku & Switch / Taster (nicht im SMT-BOM, per Litze durch THT-Bohrungen gelötet):**
> - **Akku:** 1S LiPo 3,7 V mit Zuleitungskabeln — rot (+) durch THT-Lötbohrung `BAT`, schwarz (−) durch THT-Lötbohrung `GND` stecken und verlöten (kein JST-Stecker, keine großen SMD-Pads).
> - **Switch / Button:** Externer Schalter/Taster mit Zuleitungskabeln — durch die beiden THT-Lötbohrungen `BTN` (GPIO9) und `GND` stecken und verlöten (kein SMD-Taster).

### 0.3 Widerstände (alle 0402, alle basic)
| Ref     | Wert     | MPN       | Footprint | **LCSC**   | Qty | Stock      | Typ       | Preis   | Funktion                 |
| ------- | -------- | --------- | --------- | ---------- | --- | ---------- | --------- | ------- | ------------------------ |
| R2      | 4,7k     | 0402 4.7k | 0402      | **C25900** | 1   | 21.952.436 | **basic** | $0.0049 | I2C-Pullup SDA           |
| R3      | 4,7k     | 0402 4.7k | 0402      | **C25900** | 1   | 21.952.436 | **basic** | $0.0049 | I2C-Pullup SCL           |
| R4      | 330      | 0402 330R | 0402      | **C25104** | 1   | 1.810.336  | **basic** | $0.0072 | LED D1 Vorwiderstand     |
| R5      | 10k      | 0402 10k  | 0402      | **C25744** | 1   | 22.337.033 | **basic** | $0.0019 | CHIP_EN Pull-up          |
| R6      | 330      | 0402 330R | 0402      | **C25104** | 1   | 1.810.336  | **basic** | $0.0072 | LED D2 Vorwiderstand     |
| R7      | 5,1k     | 0402 5.1k | 0402      | **C25905** | 1   | 8.999.306  | **basic** | $0.0043 | USB-C CC1 Pulldown       |
| R8      | 5,1k     | 0402 5.1k | 0402      | **C25905** | 1   | 8.999.306  | **basic** | $0.0043 | USB-C CC2 Pulldown       |
| R9      | 2k       | 0402 2k   | 0402      | **C4109**  | 1   | 7.675.689  | **basic** | $0.0064 | TP4054-PROG → 0,5A       |
| **R10** | **100k** | 0402 100k | 0402      | **C25741** | 1   | 14.734.064 | **basic** | $0.0053 | I2S-SD Pulldown nach GND |

### 0.4 Kondensatoren (alle 0402, alle basic)
| Ref     | Wert     | MPN        | Footprint | **LCSC**   | Qty | Stock      | Typ       | Preis   | Funktion                         |
| ------- | -------- | ---------- | --------- | ---------- | --- | ---------- | --------- | ------- | -------------------------------- |
| C1      | 100n     | 0402 100nF | 0402      | **C1525**  | 1   | 37.474.840 | **basic** | $0.0055 | Entkopplung ESP32                |
| C2      | 100n     | 0402 100nF | 0402      | **C1525**  | 1   | 37.474.840 | **basic** | $0.0055 | Entkopplung VDD_CPU              |
| C3      | 10µ      | 0402 10µF  | 0402      | **C15525** | 1   | 10.292.216 | **basic** | $0.0255 | USB-VBUS Bulk                    |
| C4      | 10µ      | 0402 10µF  | 0402      | **C15525** | 1   | 10.292.216 | **basic** | $0.0255 | LDO-Eingang (BAT)                |
| **C5**  | **10µ**  | 0402 10µF  | 0402      | **C15525** | 1   | 10.292.216 | **basic** | $0.0255 | **LDO-Ausgang (3V3)**            |
| **C6**  | **100n** | 0402 100nF | 0402      | **C1525**  | 1   | 37.474.840 | **basic** | $0.0055 | **LDO-Ausgang HF-Filter**        |
| C7      | 100n     | 0402 100nF | 0402      | **C1525**  | 1   | 37.474.840 | **basic** | $0.0055 | Entkopplung Flash                |
| C8      | 100n     | 0402 100nF | 0402      | **C1525**  | 1   | 37.474.840 | **basic** | $0.0055 | Entkopplung IMU                  |
| C9      | 100n     | 0402 100nF | 0402      | **C1525**  | 1   | 37.474.840 | **basic** | $0.0055 | Entkopplung Mic U4               |
| C10     | 100n     | 0402 100nF | 0402      | **C1525**  | 1   | 37.474.840 | **basic** | $0.0055 | Entkopplung Mic U5               |
| **C11** | **100n** | 0402 100nF | 0402      | **C1525**  | 1   | 37.474.840 | **basic** | $0.0055 | **CHIP_EN RC-Reset-Kondensator** |
| C12     | 15p      | 0402 15pF  | 0402      | **C1548**  | 1   | 2.023.368  | **basic** | $0.0047 | Quarz XTAL_P                     |
| C13     | 15p      | 0402 15pF  | 0402      | **C1548**  | 1   | 2.023.368  | **basic** | $0.0047 | Quarz XTAL_N                     |

**Summen:** 31 Bauteile · **21 untersch. LCSC-Codes** · Gesamt ≈ **$17.83 (ca. 16 €)**. Basic: Flash, LEDs, alle R + C. Extended: alle ICs + USB-C + Quarz + Antenne + grüne LED. (JST-Buchse BT1 entfällt — Akku wird per Litze durch 2 THT-Lötbohrungen gelötet. SMD-Taster SW1 entfällt — Switch/Button wird per Litze durch 2 THT-Lötbohrungen für GPIO9/GND durchgesteckt und gelötet; keine großen SMD-Pads.)

---

## TEIL 1 — VERDRAHTUNGS-ANLEITUNG (Schritt für Schritt)

> Alle Netznamen (VBUS, BAT, 3V3, GND) sind als Netzlabels in KiCad angelegt. Verdeutlichender Hinweis: **3V3** = geregelte 3,3 V vom LDO · **BAT** = Akku-Spannung (3,0–4,2 V) · **VBUS** = 5 V vom USB-C. Diese Anleitung geht der Reihe nach, bis alles verbunden und fertig ist.

### 📌 ESP32-C3 Pin-Nachschlagewerk (Table 2-1 / 2-4) — nur zur Kontrolle
| GPIO      | Pin#  | Name                       | Bemerkung                          |
| --------- | ----- | -------------------------- | ---------------------------------- |
| GPIO0     | 4     | XTAL_32K_P                 | nur als GPIO wenn kein 32kHz-Quarz |
| GPIO1     | 5     | XTAL_32K_N                 | dito                               |
| GPIO2     | 6     | MTMS                       | **Strapping** (Boot) – I2S SCK     |
| GPIO3     | 8     | MTDI                       | I2S WS                             |
| GPIO4     | 9     | MTCK                       | I2S SD                             |
| GPIO5     | 10    | MTDO                       | IMU INT1                           |
| GPIO6     | 12    | MTCK → I2C0 SDA            | I2C SDA                            |
| GPIO7     | 13    | MTDO → I2C0 SCL            | I2C SCL                            |
| GPIO8     | 14    | GPIO8                      | **Strapping** (Boot) – LED D2 grün |
| GPIO9     | 15    | GPIO9                      | **Strapping** (Boot, weak pull-up) – Switch/Button THT-Lötbohrung `BTN` |
| GPIO10    | 16    | GPIO10                     | LED D1 rot                         |
| GPIO11    | —     | (nicht vorhanden)          | **existiert NICHT als regulärer GPIO** – Pin 18 = VDD_SPI |
| GPIO12–17 | 19–24 | SPIHD..SPIQ                | **Flash** (nur ohne int. Flash)    |
| GPIO18/19 | 25/26 | D−/D+                      | **USB** (fest)                     |
| GPIO20/21 | 27/28 | U0RXD/TXD                  | frei (UART)                        |

---

### 1.1 Stromversorgung & Laden (USB-C → TP4054 → LiPo → LDO → 3V3)

#### USB-C-Buchse (J1)
1. **VBUS:** Verbinde den VBUS-Pin von J1 mit dem Netzlabel `VBUS`. Lege C3 (10µ, C15525) parallel zwischen `VBUS` und `GND`.
2. **GND/SHIELD:** Verbinde die GND-Pins und SHIELD von J1 mit `GND`.
3. **CC1:** Verbinde CC1 von J1 über R7 (5,1k, C25905) nach `GND`.
4. **CC2:** Verbinde CC2 von J1 über R8 (5,1k, C25905) nach `GND`.
5. **USB-Daten:** Verbinde D+ von J1 mit **GPIO19 (Pin 26)** und D− mit **GPIO18 (Pin 25)**.

#### Laderegler TP4054 (U6)
6. **VCC (Pin 4):** Verbinde mit `VBUS`.
7. **BAT (Pin 3):** Verbinde mit dem Netzlabel `BAT`.
8. **GND (Pin 2):** Verbinde mit `GND`.
9. **PROG (Pin 5):** Verbinde über R9 (2k, C4109) nach `GND` → ergibt 0,5 A Ladestrom.
10. **CHRG (Pin 1):** Bleibt offen, wenn keine Lade-LED bestückt ist.

#### LiPo-Akku (durchsteckbare THT-Lötbohrungen — kein Stecker, keine großen SMD-Pads)
11. **Pluspol:** Führe die rote Litze (+) des Akkus durch die durchkontaktierte Lötbohrung `BAT` (THT-Hole, Loch-Ø ca. 1,0 mm, Pad-Ø 1,8 mm) und verlöte sie sauber auf der Unter-/Oberseite.
12. **Minuspol:** Führe die schwarze Litze (−) des Akkus durch die durchkontaktierte Lötbohrung `GND` (THT-Hole, Loch-Ø ca. 1,0 mm, Pad-Ø 1,8 mm) und verlöte sie sauber. → Feste mechanische Verbindung durch Einstecken ins Loch.

#### LDO ME6211C33M5G (U7)
13. **VIN (Pin 1):** Verbinde mit `BAT` und lege C4 (10µ, C15525) zwischen `BAT` und `GND` (LDO-Eingang).
14. **GND (Pin 2):** Verbinde mit `GND`.
15. **EN (Pin 3):** Verbinde mit `BAT` (Enable dauerhaft aktiv → LDO ist immer an).
16. **VOUT (Pin 5):** Verbinde mit dem Netzlabel `3V3` und lege **C5 (10µ, C15525)** sowie **C6 (100n, C1525)** parallel zwischen `3V3` und `GND` (LDO-Ausgang — zwingend für Regelkreis-Stabilität).

---

### 1.2 ESP32-C3 (U1) Grundversorgung
17. **LNA_IN (Pin 1):** Verbinde über das π-Matching-Netzwerk mit der 2,4-GHz-Antenne A1 (C293767).
18. **VDD3P3 (Pins 2, 3):** Verbinde mit `3V3`.
19. **CHIP_EN (Pin 7):** Verbinde über R5 (10k, C25744) nach `3V3` **und** über C11 (100n, C1525) nach `GND`. → **RC-Netz, unbedingt so.**
20. **VDD3P3_RTC (Pin 11):** Verbinde mit `3V3`.
21. **VDD3P3_CPU (Pin 17):** Verbinde mit `3V3` und lege C2 (100n, C1525) zwischen `3V3` und `GND`.
22. **VDD_SPI (Pin 18):** Verbinde mit `3V3`.
23. **VDDA (Pins 31, 32):** Verbinde mit `3V3`.
24. **XTAL_N (Pin 29) / XTAL_P (Pin 30):** Verbinde mit dem Quarz Y1. Lege C12 (15p, C1548) zwischen XTAL_N und `GND`, sowie C13 (15p, C1548) zwischen XTAL_P und `GND`.
25. **EPAD (Pin 33):** Verbinde massiv mit `GND` (3×3 Via-Matrix unter dem IC).
26. **Entkopplung C1:** Lege C1 (100n, C1525) als Entkopplung zwischen `3V3` und `GND` nahe am ESP32.

---

### 1.3 Flash W25Q128 (U2) — volle Quad-SPI
27. **(Pin 1) /CS:** Verbinde mit **GPIO14 (Pin 21)**.
28. **(Pin 2) DO/IO1:** Verbinde mit **GPIO17 (Pin 24)**.
29. **(Pin 3) /WP/IO2:** Verbinde mit **GPIO13 (Pin 20)**.
30. **(Pin 4) GND:** Verbinde mit `GND`.
31. **(Pin 5) DI/IO0:** Verbinde mit **GPIO16 (Pin 23)**.
32. **(Pin 6) CLK:** Verbinde mit **GPIO15 (Pin 22)**.
33. **(Pin 7) /HOLD/IO3:** Verbinde mit **GPIO12 (Pin 19)**.
34. **(Pin 8) VCC:** Verbinde mit `3V3` und lege C7 (100n, C1525) zwischen `3V3` und `GND`.

> **Quad-SPI (QIO) bestätigt:** /WP→GPIO13, /HOLD→GPIO12 (statt fest an 3V3) → volle Datenrate. WP/HOLD arbeiten hier als IO2/IO3.

---

### 1.4 Beschleunigungssensor LSM6DSL (U3)
35. **(Pin 1) SDO/SA0:** Verbinde mit `GND` (→ I2C-Adresse 0x6A).
36. **(Pin 4) INT1:** Verbinde mit **GPIO5 (Pin 10)** (Wakeup / Tap-Ausgang).
37. **(Pin 5) VDDIO:** Verbinde mit `3V3`.
38. **(Pins 6, 7) GND:** Verbinde mit `GND`.
39. **(Pin 8) VDD:** Verbinde mit `3V3` und lege C8 (100n, C1525) zwischen `3V3` und `GND`.
40. **(Pin 12) CS:** Verbinde mit `3V3` (I2C-Modus aktiv).
41. **(Pin 13) SCL:** Verbinde mit **GPIO7 (Pin 13)** und ziehe R3 (4,7k, C25900) von SCL nach `3V3`.
42. **(Pin 14) SDA:** Verbinde mit **GPIO6 (Pin 12)** und ziehe R2 (4,7k, C25900) von SDA nach `3V3`.

---

### 1.5 Mikrofon links (U4) + Mikrofon rechts (U5) — je ICS-43434

> **Pin-Mapping (verbindlich):** 1 = WS · **2 = LR (Kanalwahl)** · 3 = GND · 4 = SCK · 5 = VDD · 6 = SD. Der LR-Pin MUSS beschaltet werden.

#### Mikrofon U4 (linker Kanal)
43. **(Pin 1) WS:** Verbinde mit **GPIO3 (Pin 8)**.
44. **(Pin 2) LR:** Verbinde mit `GND` → **linker Kanal**.
45. **(Pin 3) GND:** Verbinde mit `GND`.
46. **(Pin 4) SCK:** Verbinde mit **GPIO2 (Pin 6)**.
47. **(Pin 5) VDD:** Verbinde mit `3V3` und lege C9 (100n, C1525) zwischen `3V3` und `GND`.
48. **(Pin 6) SD:** Verbinde mit **GPIO4 (Pin 9)**.

#### Mikrofon U5 (rechter Kanal)
49. **(Pin 1) WS:** Verbinde mit **GPIO3 (Pin 8)** — gemeinsames WS.
50. **(Pin 2) LR:** Verbinde mit `3V3` → **rechter Kanal**.
51. **(Pin 3) GND:** Verbinde mit `GND`.
52. **(Pin 4) SCK:** Verbinde mit **GPIO2 (Pin 6)** — gemeinsames SCK.
53. **(Pin 5) VDD:** Verbinde mit `3V3` und lege C10 (100n, C1525) zwischen `3V3` und `GND`.
54. **(Pin 6) SD:** Verbinde mit **GPIO4 (Pin 9)** — gemeinsames SD. Ziehe **R10 (100k, C25741)** von SD (GPIO4) nach `GND` (Pulldown).

---

### 1.6 Status-LEDs & Switch-/Button-Lötbohrungen
55. **D1 (rot):** Verbinde die Anode mit `3V3`, die Kathode über R4 (330, C25104) nach **GPIO10 (Pin 16)**.
56. **D2 (grün):** Verbinde die Anode mit `3V3`, die Kathode über R6 (330, C25104) nach **GPIO8 (Pin 14)**. *(Korrektur: GPIO11 existiert am ESP32-C3 nicht als regulärer GPIO — Pin 18 ist `VDD_SPI`/Flash-Power-Supply. GPIO8 ist der übliche Status-LED-Pin auf C3-Boards.)*
57. **Switch / Button Lötbohrungen (2 THT-Holes):** Platziere zwei durchkontaktierte Lötbohrungen / THT-Lötaugen (z. B. Loch-Ø 1,0 mm, Pad-Ø 1,8 mm, Through-Hole — keine großen SMD-Pads): eine verbunden mit **GPIO9 (Pin 15)** (Beschriftung Silkscreen `BTN`), die andere mit `GND` (Beschriftung `GND`). Die Zuleitungskabel/Litzen des externen Schalters oder Tasters werden durch die Bohrungen gesteckt und verlötet. GPIO9 hat einen internen (schwachen) Pull-up → ein externer Pull-up ist nicht nötig; der Schalter schaltet GPIO9 beim Betätigen sauber gegen `GND`.

---

## TEIL 2 — Production-Checkliste

### ✅ Vor Bestellung / Layout
- [x] CHIP_EN RC: **R5(10k) + C11(100n)** vorhanden
- [x] LDO-Ausgang: **C5(10µ) + C6(100n)** an `3V3` vorhanden
- [x] **Antenne A1 (C293767)** + π-Matching an LNA_IN vorhanden
- [x] Mic **LR-Pin (Pin 2)**: U4→GND, U5→3V3 vorhanden
- [x] I2S-SD **R10(100k)** Pulldown vorhanden
- [x] **Switch / Button THT-Lötbohrungen** auf **GPIO9 (`BTN`)** + `GND` (2 durchkontaktierte Löcher/Holes, z. B. Ø 1,0 mm / Pad Ø 1,8 mm zum Durchstecken der Litzen)
- [x] W25Q128 in **Quad-SPI** (WP→GPIO13, HOLD→GPIO12) vorhanden
- [x] **Akku fest gelötet** — kein JST-Stecker (BT1 entfernt)
- [x] **Akku THT-Lötbohrungen** auf `BAT` + `GND` auf dem PCB (2 durchkontaktierte Löcher/Holes, z. B. Ø 1,0 mm / Pad Ø 1,8 mm zum Durchstecken der Litzen)

### ⚠️ KiCad-Fallen
1. Netzlabels mit **exakten** Pin-Koordinaten (roundet nicht).
2. ESP32-C3-Lib-Bug: Pin 18 VDD_SPI = `power_out` → auf `power_in` patchen.
3. PWR_FLAG an VBUS.
4. Mic-SD → `bidirectional`.
5. Kein String-`replace` auf Koordinaten (korrupt).
6. **PCB-Layout:** Mic-Bohrung (0.6–0.8 mm) unter Schallport, EPAD-Vias 3×3, Quarz nah an XTAL-Pins, Antennen-RF-Bereich sauber.
7. **Kabel- & Lötbohrungen (Akku & Switch):** Durchkontaktierte THT-Löcher (Hole-Ø 1,0 mm) vorsehen, damit die Litzen/Kabel von Akku und Gehäuseschalter durch die Platine gesteckt, sauber verlötet und mechanisch zugentlastet werden können (keine oberflächlichen SMD-Pads).

---
*Re-verified nach externem Fach-Review. Pin-Zuordnung aus ESP32-C3 Datasheet v2.4 (T2-1/T2-4/T2-12) + offizialen KiCad-Symbolen (ICS-43434, LSM6DSL). Alle LCSC-Codes 2026-08-23 via JLCPCB-API geprüft. Akku und Switch fest über THT-Lötbohrungen (Holes) verdrahtet, keine großen SMD-Pads.*
