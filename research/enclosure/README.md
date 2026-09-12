# Gehäuse "Audio Vault" Diktiergerät — Armband-Ausführung

Parametrisches OpenSCAD-Gehäuse für die Platine `research/3D_PCB1_2026-09-08.stl`,
getragen an einem **Garmin-Armband (22,6 mm breit, 4,5 mm dick, Nylon)**.
Akku sitzt **hinter** der Platine (an der Armseite), Platine mit Bauteilen nach außen.

```
stl/tray_print.stl     V1  Tray, Band läuft LÄNGS der Platine (Y)   ~8,0 cm³
stl/tray90_print.stl   V2  Tray, Halterung 90° gedreht (Band in X) ~7,7 cm³
stl/lid_print.stl      Deckel – für BEIDE Versionen identisch       ~2,3 cm³

V3  Geschlossene Bandkassette, Band wird DURCHGEFÄDELT (2 Schlitze, Band quer zur
    Platinenlängsachse) – GESCHLOSSEN statt offener Kanal, in drei Dicken:
stl/v3_A_slim_tray_print.stl      A slim      Wand 1,2  Kassette 1,0  →  6,3 cm³
stl/v3_B_standard_tray_print.stl  B standard  Wand 1,6  Kassette 1,2  →  8,8 cm³
stl/v3_C_robust_tray_print.stl    C robust    Wand 2,0  Kassette 1,6  → 11,7 cm³
stl/v3_{A_slim,B_standard,C_robust}_lid_print.stl   passender Deckel je Variante
stl/v3_*_tray.stl / _lid.stl      Montagelage (nur für Prüfung/Render)
audio_vault_case.scad  Quelle (alle Maße als Parameter, Schalter band_rot90/holder_kind)
build_varianten.sh     baut alle drei V3-Varianten (+ Deckel) aus der Quelle
check_v3.py            maschinelle Prüfung der Varianten (USB-C, Mikrofone, LEDs, Band)
render_bilder.sh       rendert die Doku-Bilder (bild10 … bild17)
```

### Zwei Varianten — Bandlage um 90° gedreht

| | V1 (`band_rot90=false`) | V2 (`band_rot90=true`) |
| :--- | :--- | :--- |
| Bandkanal läuft | entlang **Y** (Längsachse der Platine) | entlang **X** (quer) |
| Kanalbreite quer | X, 23,4 mm (Wangen bündig mit dem Gehäuse) | Y, 23,4 mm (Wangen 2 mm, Rest ist Bodenrand) |
| Einlegefenster | 20 mm | 15 mm (automatisch gekappt) |
| Am Arm | Gerät liegt quer zur Bandlänge, langachse läuft um den Arm | **Längsachse liegt am Arm**, USB-C und Mikrofonseite zeigen zum Ellbogen bzw. zur Hand |
| Druckdatei | `stl/tray_print.stl` | `stl/tray90_print.stl` |

**V2 entspricht der ursprünglich gewünschten Orientierung:** USB-C zum Körper,
Mikrofon (U4) zur Hand — beides liegt dann auf der Armachse. Bei V1 zeigen diese
beiden Enden quer über den Arm.

---

## 1. Was aus dem STL gemessen wurde (nicht geschätzt)

| Merkmal | Wert |
| :--- | :--- |
| Platine | 22,626 × 36,975 × 1,6 mm (x −12,814…9,811 · y −11,079…25,895) |
| Höchstes Bauteil | USB-C-Buchse J1, Oberkante **z = 4,760** |
| ESP32-C3-MINI-1 | x −10,10…3,10 · y −1,41…15,19 · Oberkante 4,10 |
| Antennenfläche (ungeschirmt) | y ≈ −1,4 … 4,2 am **−Y-Ende** des Moduls |
| Mic U4 (links) | Pad (5,50 / 23,83), **Schallloch d = 0,35 mm @ (5,50 / 24,54)** |
| Mic U5 (rechts) | Pad (5,49 / −7,54), **Schallloch d = 0,35 mm @ (5,49 / −6,83)** |
| LEDs D1/D2 | (7,19 / 14,73) und (7,19 / 16,73), leuchten nach oben |
| USB-C-Mündung | x −11,96…−3,16 · z 1,66…4,68 (Mitte −7,557 / 3,17) |
| THT-Lötlöcher (d 0,85) | (8,00 / 22,97) (8,00 / 24,64) (9,02 / −0,89) (−11,94 / 6,10) |
| USB-C-Befestigungsschlitze | 4× im Bereich x −12,2…−3,0 / y −9,1…−3,4 |

**Wichtigster Befund:** Die ICS-43434 sind **Bottom-Port-Mikrofone**. Der Schall
kommt durch die 0,35-mm-Löcher in der **Platinenunterseite** — also ausgerechnet
von der Akkuseite. Das Gehäuse führt den Schall deshalb über zwei **Schallschlitze
in den Seitenwänden** in den 1,6-mm-Spalt zwischen Platinenunterseite und Akku.
Würde man das Gehäuse an dieser Stelle dicht machen, wären beide Mikrofone taub.

---

## 2. Aufbau (von der Armseite nach außen)

```
        Band 4,5 mm  ── im Clip-Kanal, 23,4 × 5,5 mm, Lippen halten es
   ┌──────────────────────────────┐
   │ Clip: 2 Wangen + Innenlippen │  5,5 mm + 1,2 mm Lippe
   ├──────────────────────────────┤  Tray-Boden 1,6 mm
   │ Akkutasche  22,2 × 36,6 × 11,3│  Akku (Vorgabe 20 × 33 × 9,87)
   ├──────────────────────────────┤  +0,8 mm Luft
   │ Akustikspalt  1,6 mm         │  ← Schallschlitze münden hier
   ├──────────────────────────────┤  Platine 1,6 mm (liegt auf 1 mm Schulter)
   │ Bauteile bis 4,76 mm         │  +0,6 mm Luft
   ├──────────────────────────────┤  Deckelplatte 2,0 mm
   └──────────────────────────────┘
```

Außenmaße: **27,4 × 41,8 × 28,3 mm** (inkl. Deckel und Clip), Volumen 10,1 cm³
→ ca. 12 g PLA massiv, mit 25 % Infill ~7 g.

| Loch / Öffnung | Lage | Größe |
| :--- | :--- | :--- |
| USB-C-Aussparung | Wand −Y | 9,0 × 3,18 mm (x −12,06…−3,06 · z 1,60…4,78) |
| Schallschlitz Mic U4 | Wand **+Y** | 6,0 × 1,05 mm (x 2,5…8,5 · z −1,55…−0,45) |
| Schallschlitz Mic U5 | Wand **−Y** | 6,0 × 1,05 mm, gleiche Höhe |
| LED-Sichtfenster | Deckel | Langloch 1,9 × 6,45 mm + 45°-Trichter innen (Lichtsammler) |
| Antennenfeld | Deckel außen | 14 × 7,5 mm, 0,8 mm tief → nur noch 1,2 mm Wand |
| Rastnut | Innenwand rundum | 0,3 mm tief, Deckel rastet mit 4 Nocken ein |
| Kabeldurchführungen | Schulter | an den 3 THT-Lochgruppen |
| Bandkanal | Rückseite | 23,4 × 5,5 mm, Lippen 3 × 1,2 mm, Einlegefenster 20 mm (V1) / 15 mm (V2) |

---

## 3. Parameter (oben in `audio_vault_case.scad`)

```scad
batt_t   = 9.87;   // <<< AKKUDICKE - hier anpassen
batt_w   = 20.0;   // Akku-Breite  (X)   <- bitte prüfen
batt_l   = 33.0;   // Akku-Länge   (Y)   <- bitte prüfen
band_w   = 22.6;   // Armbandbreite
band_t   = 4.5;    // Armbanddicke
gap_under_pcb = 1.6;  // Akustikspalt (kleiner = weniger Hohlraumklang)
wall     = 1.6;    // Wandstärke (0,4 mm weniger = 0,8 mm flacheres Gerät)
```
`band_rot90 = true/false` schaltet zwischen V1 und V2 um (der Deckel ist in
beiden Fällen identisch, weil der Clip nichts mit dem Deckel zu tun hat).

Nach Änderungen neu exportieren:
```bash
openscad -o stl/tray_print.stl   -D 'part="tray_print"' -D 'band_rot90=false' audio_vault_case.scad
openscad -o stl/tray90_print.stl -D 'part="tray_print"' -D 'band_rot90=true'  audio_vault_case.scad
openscad -o stl/lid_print.stl    -D 'part="lid_print"'                        audio_vault_case.scad
```

---

## 4. Drucken

* **Tray**: `stl/tray_print.stl` — liegt schon richtig (Clip auf dem Bett,
  Öffnung oben). **Keine Stützen.** Die Decke des Bandkanals wird als 23 mm
  Brücke gedruckt; wenn dein Drucker das schlecht kann: Stützen nur dort.
* **Deckel**: `stl/lid_print.stl` — Außenseite liegt auf dem Bett, Rand und
  die 3 Niederhalter-Stifte stehen nach oben. Keine Stützen.
* 0,15–0,2 mm Schichthöhe, 3 Perimeter, 25 % Infill (Gyroid).
* **PLA oder PETG, auf keinen Fall Metall-/Carbon-Filament** — das Antennenfeld
  (1,2 mm Wand über dem ESP-Modul) muss HF-durchlässig bleiben.

## 5. Montage

1. Akku- und Tasterlitzen **vor** dem Einlegen an die THT-Löcher löten
   (Positionen siehe Tabelle; Kabelwege sind als Fenster in der Schulter frei).
2. Platine in den Tray legen — sie liegt auf der umlaufenden 1-mm-Schulter,
   Bauteile nach oben. Kabel neben der Platine durch die Fenster führen.
3. Akku in die Tasche, Litzen am Platinenrand nach oben.
4. *(Empfehlung)* dünnes Moosgummi-/Filz-Ringchen (Ø ~6 mm) um jedes
   Mikrofon-Schallloch auf die Platinenunterseite kleben: verkleinert das
   Frontvolumen von ~1,3 cm³ auf wenige mm³ → deutlich klarerer Klang.
5. Optional Klarsichtband/Klebertropfen über das LED-Fenster (Staubschutz).
6. Deckel aufsetzen und einrasten (4 Nocken in der Nut); die 3 Stifte drücken
   die Platine auf die Schulter.
7. Armband: entweder längs durch den Kanal schieben oder im Fenster ohne Lippen
   (mittig) von unten eindrücken und dann zentrieren.
   Das 4,5-mm-Band wird mit 0,2 mm Übermaß geklemmt — es sitzt stramm.
   V2 liegt dabei quer auf dem Arm, d. h. der Kanal läuft über die Bandbreite
   (23,4 mm Kanal für 22,6 mm Band, 15 mm Einlegefenster).

## 6. Orientierung am Arm

Das −Y-Ende des Gehäuses ist die **USB-C-Buchse**, das +Y-Ende die
**Mikrofonseite** (Mic U4 sitzt dort). Beide Gehäuse sind in dieser Achse
symmetrisch — ein Umdrehen um 180° auf dem Band genügt, um zu tauschen,
welches Ende zum Ellbogen zeigt.

* **V2** (empfohlen für „USB zu mir / Mikrofon zur Hand“): Längsachse liegt
  auf der Armachse, USB-C zeigt zum Körper, Mikrofon zur Hand.
* **V1**: Band läuft längs der Platine, die Enden zeigen quer über den Arm
  (USB-C nach innen oder außen).

---

## 7. Prüfergebnisse (automatisiert, nicht per Auge)

`check_collision.py` (Punkt-in-Körper, Ray-Parity mit 3 Richtungen, Mehrheits-
entscheid; die PCB-Baugruppe wird mit bis zu 200 000 Oberflächenpunkten geprüft)
und `check_shell.py` (Scan der Wand-Mittenflächen auf ungewollte Öffnungen):

```
V1: 11/11 Kollisionschecks bestanden
V2: 11/11 Kollisionschecks bestanden
    PCB <-> Tray                  0 Punkte im Material
    PCB <-> Deckel                0 Punkte im Material
    Akku 20x33x9.87 <-> Tray      0 Punkte im Material
    USB-Stecker <-> Tray/Deckel   0 Punkte (Mündung 9,0 x 3,18 mm passt)
    Band 4,29 mm                  läuft frei
    Band 4,50 mm                  klemmt mit genau 0,200 mm (gewollt)
    LED 1/2 Sichtkanal d=1,7 mm   0 Punkte (Lichtweg frei)
    Schallweg Mic U4 / U5         0 Punkte (Weg außen -> unter das Schalloch frei)
WAND-INTEGRITAET: ALLES OK
    einzige Öffnungen: USB-Aussparung, 2 Schallschlitze, LED-Fenster, Eckfasen
```

Beide Teile sind **wasserdicht und einteilig** (`trimesh`: watertight=True, 1 Körper,
Tray 8,03 cm³ / Tray90 7,67 cm³ / Deckel 2,30 cm³).

Prüfbefehle für beide Varianten (OpenSCAD rendert vorher `stl/tray.stl` bzw.
`stl/tray90.stl` und `stl/lid.stl` mit `part="tray"/"lid"`):
```bash
python check_collision.py                                        # V1
BAND90=1 TRAY_STL=stl/tray90.stl python check_collision.py       # V2
python check_shell.py                                            # V1
BAND90=1 TRAY_STL=stl/tray90.stl python check_shell.py           # V2
```

## 8. Offene Punkte

* **Akku-Fußabdruck** ist mit 20 × 33 mm angenommen (nur die Dicke 9,87 mm war
  bekannt). Größer geht bis 22,2 × 36,6 mm — dann `batt_w/batt_l` anpassen.
* **Taster**: die vier THT-Lötpunkte sind über die Schulter-Fenster erreichbar,
  ein Taster braucht aber noch eine Deckelöffnung (im Modell nicht enthalten).
* **Akustik**: der Spalt unter der Platine ist ein ~1,3-cm³-Hohlraum; ohne das
  Moosgummi aus Schritt 4 klingt es bauchig (Resonanz grob bei 200 Hz).
* **WLAN**: Antenne zeigt nach außen, Deckel dort nur 1,2 mm — der Akku liegt
  allerdings hinter der Platine und schirmt mit. Falls der Durchsatz klemmt,
  Akku kürzer wählen und die Antennenzone freihalten.
* Passung Deckel/Tray: `rim_clr = 0.15`, Nocken 0,25 mm über den Rand. Bei
  zu strammem/zu lockerem Sitz diese Werte in 0,1-mm-Schritten anpassen.

---

# V3 — geschlossene Bandkassette: Band wird durchgefädelt

Wunsch: Halterung **nicht offen** (kein Kanal mit Lippen und Einlegefenster),
sondern ein Gehäuse, durch das das Armband **gefädelt** wird – mit **Doppelschlitz**,
damit es nicht am Band rutscht. Band quer zur Platinenlängsachse (wie V2), Bandmaß
des Nutzers: **24,70 … 24,75 mm breit, 2–3 mm dick**.

## 9.1 Prinzip: Leiterschnalle statt Kanal

Unter dem Tray sitzt eine **geschlossene Kassette** (Bandschacht 25,25–25,55 ×
3,2–3,6 mm im Querschnitt) mit **zwei Schlitzen** in der Deckschicht. Das Band wird
gefädelt: **rein durch Schlitz 1 → innerhalb der Kassette über den Steg → raus durch
Schlitz 2.** Der Steg zwingt das Band in eine Faltung (wie eine Leiterschnalle /
„ladder lock"), dadurch:

* das Gehäuse kann nicht vom Band rutschen (die Faltung hält es),
* Zug am Band klemmt die Faltung fest,
* bewusst verschieben geht trotzdem (Band entlasten, schieben),
* das Band ist im Bereich des Gehäuses **vollständig verdeckt** – nichts ist offen,
* die zwei Schlitze liegen 12–13 mm auseinander, das Gehäuse kann nicht kippeln.

## 9.2 Die drei Dicken-Varianten

| | A **slim** | B **standard** | C **robust** |
| :--- | :--- | :--- | :--- |
| Wandstärke | 1,2 mm | 1,6 mm | 2,0 mm |
| Deckelplatte | 1,5 mm | 2,0 mm | 2,4 mm |
| Akkuluft / Boden | 0,5 / 1,2 mm | 0,8 / 1,6 mm | 1,2 / 2,0 mm |
| Akustikspalt | 1,2 mm | 1,6 mm | 2,0 mm |
| Kassettendeckschicht | 1,0 mm | 1,2 mm | 1,6 mm |
| Schlitz / Steg | 8 / 5 mm | 7 / 5 mm | 7 / 5 mm |
| **Außenmaß (X × Y)** | **26,2 × 40,6 mm** | 27,4 × 41,8 mm | 29,0 × 43,0 mm |
| **Bauhöhe Tray+Deckel** | **21,0 mm** | 22,8 mm | 24,6 mm |
| **Bauhöhe mit Kassette** | **25,4 mm** | 27,4 mm | 29,6 mm |
| Tray-Volumen | 6,25 cm³ | 8,82 cm³ | 11,65 cm³ |
| Deckel-Volumen | 1,61 cm³ | 2,30 cm³ | 2,96 cm³ |
| Schallschlitz-Höhe | 0,7 mm | 1,1 mm | 1,5 mm |
| Charakter | dünnstes, leichtestes Gehäuse; 1,2-mm-Wände und 0,7-mm-Schallschlitz sind die Untergrenze für FDM | Alltagsvariante, gute Reserve | dick, steif, großzügige Toleranzen; Kassette 1,6 mm trägt mehr Bandzug |

Alle drei Varianten haben dieselben **Aussparungen** – maschinell geprüft (9.4):

| Öffnung | Lage | Größe | wofür |
| :--- | :--- | :--- | :--- |
| USB-C-Aussparung | Wand −Y | **9,0 × 3,18 mm** | Stecker passt durch (Mock 8,34 × 2,56 mm) |
| Schallschlitz Mic U4 | Wand +Y | **6,0 × 0,7–1,5 mm** | Bottom-Port-Mikrofon hört in den Akustikspalt |
| Schallschlitz Mic U5 | Wand −Y | 6,0 × 0,7–1,5 mm | zweites Mikrofon |
| LED-Sichtfenster | Deckel | Langloch 1,9 × (13,45…18,00) + 45°-Trichter | beide LEDs |

Mit dieser Öffnungsliste wird auch bestätigt, dass die Kassette selbst **nur** die
zwei Bandschlitze als Öffnung hat (Deckschicht sonst dicht).

## 9.3 Einfädeln

1. Bandende durch **Schlitz 1** von unten in die Kassette schieben (die Kanten sind
   45° gefast).
2. Ende innerhalb der Kassette über den **Steg** führen (der Faltraum ist 0,4 mm
   höher als das Band) und durch **Schlitz 2** wieder herausziehen.
3. Band durchziehen, bis das Gehäuse an der gewünschten Stelle sitzt; Band spannen –
   die Faltung klemmt.
4. Banddicke anpassen: `b3_t` in `audio_vault_case.scad` (bzw. `b3_t=…` in
   `build_varianten.sh`) – 2,0 mm und 3,0 mm sind beide geprüft. Bei 2,0 mm Band
   bleibt mehr Luft im Faltraum, der Halt kommt aus der Faltung, nicht aus Klemmung.

## 9.4 Prüfungen (maschinell, `python check_v3.py`)

```
Variante A_slim: 12/12 · B_standard: 12/12 · C_robust: 12/12
  Tray/Deckel: wasserdicht, je 1 Körper, Außenmaße = berechnete Maße (±0,05 mm)
  Platine / Akku 20×33×9,87     0 Punkte im Material
  USB-C-Stecker 8,34×2,56       0 Punkte  (Aussparung 9,0 × 3,18 mm)
  Schallweg Mic U4 / U5         0 Punkte  (Schlitz 6 × 0,7 … 1,5 mm)
  LED-Sichtkanal d=1,7 mm       0 Punkte  (Deckel)
  Band 2,0 mm und 3,0 mm durchgefädelt: kein Eindringen (nur Wandberührung, 0,000 mm)
  Kassette: nur die 2 Schlitze offen (0 Punkte außerhalb)
  Deckel-Mittenebene: nur LED-Fenster offen
```

## 9.5 Drucken

* **Tray**: `stl/v3_<X>_tray_print.stl` – liegt richtig (Kassette unten auf dem Bett,
  Öffnung oben). Die Decke über dem Bandschacht ist eine **25 mm breite Brücke**;
  wenn der Drucker das schlecht kann: Stützen nur dort, sonst keine.
* **Deckel**: `stl/v3_<X>_lid_print.stl` – Außenseite liegt auf dem Bett.
* 0,15–0,2 mm Schicht, 3 Perimeter, 25 % Infill. **Kein Metall-/Carbon-Filament**
  (Antennenfeld).
* Variante C wiegt ~1,5 × Variante A – bei gleichem Material ist A die leichte,
  C die steife Ausführung.

## 9.6 Neu bauen

```bash
bash build_varianten.sh                       # alle drei Varianten + Deckel
python check_v3.py                            # 12 Prüfungen je Variante
bash render_bilder.sh                         # Doku-Bilder bild10 … bild17
# Einzelvariante mit abweichenden Maßen:
openscad -o test.stl -D 'part="tray_thread"' -D 'wall=1.4' -D 'b3_plate=1.1' \
         -D 'lid_t=1.8' audio_vault_case.scad
```

Bilder: `bild10_v3_assembly.png` (Baugruppe mit gefädeltem Band),
`bild11_v3_schnitt_faltung.png` + `bild12_v3_zoom_faltung.png` (Schnitt/Detail der
Faltung über den Steg), `bild13_v3_ruecken.png` (von unten),
`bild14_v3_druck.png` (Drucklage), `bild15/16/17_v3_{slim,standard,robust}.png`
(die drei Varianten im Vergleich).
