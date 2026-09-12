// ============================================================================
//  Audio-Vault Diktiergeraet  --  Armband-Gehaeuse (Garmin-Band 22,6 mm)
// ----------------------------------------------------------------------------
//  Basis: research/3D_PCB1_2026-09-08.stl  (EasyEDA-3D-Export der Baugruppe)
//  GEMESSENE HARDWARE (aus dem STL, nicht geschaetzt):
//    Board            22,626 x 36,975 x 1,6 mm
//    Board-Ecken      x -12.814 ..  9.811    y -11.079 .. 25.895   z 0 .. 1.6
//    hoechstes Teil   USB-C Buchse J1, Oberkante z = 4.760
//    ESP32-Modul      x -10.10 .. 3.10 , y -1.41 .. 15.19 , z 1.6 .. 4.10
//    Antennenflaeche  y -1.41 .. 4.2 (ungeschirmte Modulplatine, -Y Ende)
//    Mic U4 (links)   Pad bei ( 5.50, 23.83) , Schallloch 0,35 mm @ ( 5.50, 24.54)
//    Mic U5 (rechts)  Pad bei ( 5.50, -7.54) , Schallloch 0,35 mm @ ( 5.49, -6.83)
//    LEDs D1/D2       ( 7.19, 14.73) und ( 7.19, 16.73), leuchten nach oben
//    USB-C Muendung   x -11.96 .. -3.16 , z 1.66 .. 4.68  (Mitte -7.557 / 3.17)
//    THT-Loetloecher  ( 8.00, 22.97) ( 8.00, 24.64) ( 9.02, -0.89) (-11.94, 6.10)
//  WICHTIG: Die ICS-43434 sind BOTTOM-PORT-Mikrofone -> der Schall kommt durch
//  die 0,35-mm-Loecher in der PLATINENUNTERSEITE. Das Gehaeuse fuehrt den Schall
//  deshalb ueber zwei Schlitze in den Seitenwaenden in den Spalt zwischen
//  Platinenunterseite und Akku.
// ----------------------------------------------------------------------------
//  Druck: Tray auf dem Ruecken liegend (Clip unten, Oeffnung oben) -> keine
//         Stuetzen. Deckel siehe lid_print() (flach, Aussenseite unten).
//  Alle Koordinaten = STL-Koordinaten: Board-Unterseite = z 0.
// ============================================================================

$fn = 96;

// ============================== PARAMETER ==================================
// --- Board (gemessen, normalerweise nicht aendern) ---
bx0 = -12.814; bx1 =  9.811;
by0 = -11.079; by1 = 25.895;
board_t   = 1.6;
comp_zmax = 4.76;

// --- Gehaeuse ---
wall          = is_undef(wall) ? 1.6 : wall;              // Wandstaerke
clr_board     = is_undef(clr_board) ? 0.8 : clr_board;   // Luft Board-Kante -> Innenwand
clr_top       = is_undef(clr_top) ? 0.6 : clr_top;       // Luft ueber hoechstem Bauteil
lid_t         = is_undef(lid_t) ? 2.0 : lid_t;           // Deckelplatte
ant_recess    = is_undef(ant_recess) ? 0.8 : ant_recess; // Eindrehung ueber der Antenne
gap_under_pcb = is_undef(gap_under_pcb) ? 1.6 : gap_under_pcb;  // Akustikspalt
base_t        = is_undef(base_t) ? 1.6 : base_t;         // Bodenstaerke unter der Akkutasche
ledge_w       = is_undef(ledge_w) ? 1.0 : ledge_w;       // Auflageschulter fuer die Platine
rim_clr       = 0.15;   // Deckel-Rand -> Innenwand
rim_t         = is_undef(rim_t) ? 0.7 : rim_t;           // Deckel-Rand Dicke
rim_h         = 1.2;    // Deckel-Rand Hoehe
corner_ch     = is_undef(corner_ch) ? 1.8 : corner_ch;   // 45-Grad-Fase an den Senkrechtkanten

// --- Akku (DICKE IST DIE VARIABLE) ---
batt_t   = 9.87;        // <<== AKKUDICKE in mm
batt_w   = 20.0;        // Akku-Breite (X)
batt_l   = 33.0;        // Akku-Laenge  (Y)
batt_clr = is_undef(batt_clr) ? 0.8 : batt_clr;          // Luft um den Akku

// --- Armband (Garmin, Nylon) ---
band_w      = 22.6;     // Bandbreite
band_t      = 4.5;      // Banddicke
band_clr_w  = 0.4;      // Luft je Seite im Kanal
band_squeeze= 0.2;      // leichte Klemmung
band_rot90  = true;     // <<< false = V1 (Band entlang Y) / true = V2 (90 Grad gedreht) (Kanalhoehe = Lippe + Band - squeeze)
rail_t      = 2.0;      // Dicke der Kanal-Seitenwangen
lip_w       = 3.0;      // Breite der Haltenasen
lip_t       = 1.2;      // Dicke der Haltenasen
lip_window  = 20;       // Fenster ohne Nasen zum Einlegen des Bandes (wird bei 90 Grad gekappt)
// false = Version 1: Band laeuft entlang Y (USB-Ende zuerst)
// true  = Version 2: Halterung um 90 Grad gedreht, Band laeuft entlang X

// --- V3: GESCHLOSSENE BANDKASSETTE (Band wird durchgefaedelt) --------------
// holder_kind = "cassette": statt des offenen Kanals (Lippen + Einlegefenster)
// sitzt unter dem Tray eine GESCHLOSSENE Kassette mit ZWEI Schlitzen. Das Band
// wird durchgefaedelt: hinein durch Schlitz 1, innerhalb der Kassette ueber den
// Steg (Faltung), hinaus durch Schlitz 2. Der Steg klemmt das Band wie eine
// Leiterschnalle (Doppelschlitz / "Ladder-Lock"): rutscht nicht, laesst sich
// aber bewusst verschieben. Bandlage wie V2 (Band laeuft entlang X).
holder_kind = "clip";   // "clip" = V1/V2 (offener Kanal) | "cassette" = V3
b3_w        = 24.75;    // <<< BANDBREITE  (Messwert: 24,70..24,75)
b3_t        = 3.0;      // <<< BANDDICKE   (2,0 .. 3,0; Falthoehe haengt daran)
b3_clr      = is_undef(b3_clr) ? 0.30 : b3_clr;     // Luft je Seite im Schacht
b3_vclr     = 0.40;     // Luft ueber dem Band im Faltraum
b3_rail     = is_undef(b3_rail) ? 1.80 : b3_rail;   // Wandstaerke der Kassette links/rechts
b3_plate    = is_undef(b3_plate) ? 1.20 : b3_plate; // Deckschicht (Boden unter dem Steg)
b3_slot     = is_undef(b3_slot) ? 7.00 : b3_slot;   // Schlitzlaenge in Bandrichtung (Faltrampe)
b3_pitch    = is_undef(b3_pitch) ? 12.00 : b3_pitch; // Mittenabstand der Schlitze (Steg = pitch - slot)
b3_cham     = 0.60;     // 45-Grad-Fase an den Kanten, ueber die das Band laeuft

// --- Anzeige (nur Preview) ---
show_pcb      = true;
show_battery  = true;
show_band     = true;
show_plug     = true;
show_lid      = true;

// ===================== VARIANTEN-PRESETS (A/B/C) ============================
// Die Maße unten sind per -D ueberschreibbar (Muster: is_undef(...)) - die drei
// Dicken-Varianten werden in build_varianten.sh als Parametersatz uebergeben:
//   A "slim"     : Wand 1,2 / Deckel 1,5 / Kassette 1,0
//   B "standard" : Wand 1,6 / Deckel 2,0 / Kassette 1,2 (wie bisher)
//   C "robust"   : Wand 2,0 / Deckel 2,4 / Kassette 1,6
profil = is_undef(profil) ? "standard" : profil;

// ============================ ABGELEITETE WERTE =============================
inn_x0 = bx0 - clr_board;  inn_x1 = bx1 + clr_board;
inn_y0 = by0 - clr_board;  inn_y1 = by1 + clr_board;
out_x0 = inn_x0 - wall;    out_x1 = inn_x1 + wall;
out_y0 = inn_y0 - wall;    out_y1 = inn_y1 + wall;

rim_z = board_t + comp_zmax + clr_top;         // 6.96 Tray-Oberkante

z_batt_top  = -gap_under_pcb;                  // -1.60
z_batt_bot  = z_batt_top - batt_t;             // -11.47
z_pocket_fl = z_batt_bot - batt_clr;           // -12.27
z_tray_bot  = z_pocket_fl - base_t;            // -13.87

pk_x0 = inn_x0 + ledge_w;  pk_x1 = inn_x1 - ledge_w;
pk_y0 = inn_y0 + ledge_w;  pk_y1 = inn_y1 - ledge_w;

bat_cx = (bx0 + bx1) / 2;  bat_cy = (by0 + by1) / 2;     // -1.5015 / 7.408

// Bandkanal: quer = X bei V1, quer = Y bei V2 (90 Grad gedreht)
ch_w   = band_w + 2 * band_clr_w;                        // 23.4 Kanalbreite
ch_c   = band_rot90 ? bat_cy : bat_cx;                   // Mitte quer zum Kanal
ch_lo  = ch_c - ch_w / 2;   ch_hi = ch_c + ch_w / 2;     // Kanalraender quer
ch_cw  = band_rot90 ? bat_cx : bat_cy;                   // Mitte in Kanalrichtung
ch_len = band_rot90 ? (out_x1 - out_x0) : (out_y1 - out_y0);
ch_h   = lip_t + band_t - band_squeeze;                  // 5.5
ch_z1  = z_tray_bot;        ch_z0 = ch_z1 - ch_h;        // -13.87 .. -19.37
win_len = min(lip_window, ch_len * 0.55);                // Einlegefenster (bei V2 gekappt)
// Wangen-Aussenkanten: buendig, wenn der Kanal fast so breit ist wie das Gehaeuse
wng_lo = band_rot90 ? max(out_y0, ch_lo - rail_t) : max(out_x0, ch_lo - rail_t);
wng_hi = band_rot90 ? min(out_y1, ch_hi + rail_t) : min(out_x1, ch_hi + rail_t);

// Bandkassette V3: lichte Breite, Faltraum, Schlitze, Steg
b3_chw  = b3_w + 2 * b3_clr;
b3_cx   = bat_cx;
b3_cy   = bat_cy;
b3_y0   = b3_cy - b3_chw / 2 - b3_rail;
b3_y1   = b3_cy + b3_chw / 2 + b3_rail;
b3_hv   = b3_t + b3_vclr;                       // Faltraumhoehe ueber dem Steg
b3_z0   = z_tray_bot - b3_hv - b3_plate;        // Unterseite der Kassette
b3_zbar = b3_z0 + b3_plate;                     // Oberkante Steg = Boden Faltraum
b3_s1x0 = bat_cx - b3_pitch/2 - b3_slot/2;      // Schlitz 1 (-X)
b3_s1x1 = bat_cx - b3_pitch/2 + b3_slot/2;
b3_s2x0 = bat_cx + b3_pitch/2 - b3_slot/2;      // Schlitz 2 (+X)
b3_s2x1 = bat_cx + b3_pitch/2 + b3_slot/2;
// Kassette X: mindestens die Gehaeusebreite, aber immer so breit, dass neben dem
// Bandschacht b3_rail Wand stehen bleibt (sonst 0,6-mm-Waende bei duennen Profilen)
b3_x0   = min(out_x0, b3_cx - b3_chw / 2 - b3_rail);
b3_x1   = max(out_x1, b3_cx + b3_chw / 2 + b3_rail);
b3_lead = b3_s1x0 - b3_x0;                      // Kassette bis zum ersten Schlitz

mic_x  = 5.495;            // beide Schallloecher liegen auf x = 5.49/5.50
micA_y = 24.54;            // +Y Wand
micB_y = -6.83;            // -Y Wand
slot_w = 6.0;              // Breite der Schallschlitze
slot_z0 = z_batt_top + 0.05;   // -1.55
slot_z1 = -0.45;               //  1,1 mm hoch

led1 = [7.19, 14.73];          // LED D1 (rot)
led2 = [7.19, 16.73];          // LED D2 (gruen)
led_hole_w = 1.9;              // Breite des Sichtfensters
led_win_y0 = 13.45;            // Fenster von y...
led_win_y1 = 18.00;            // ...bis y  (beide LEDs + 1 mm Rand)
led_csk    = 1.2;              // innen 45-Grad-Ansenkung (Lichtsammeltrichter)

usb_x0 = -12.06;  usb_x1 = -3.06;   // 9,0 mm breit (Muendung 8,8 + 0,1 Luft)
usb_z0 = 1.60;    usb_z1 = 4.78;

// ================================ MODULE ====================================
module pcb_assembly() {
    import("../3D_PCB1_2026-09-08.stl", convexity=10);
}

module battery_block() {
    translate([bat_cx - batt_w/2, bat_cy - batt_l/2, z_batt_bot])
        cube([batt_w, batt_l, batt_t]);
}

module band_mock(L = 140, holder = holder_kind) {   // Band liegt AUF den Haltenasen (V1/V2)
    if (holder == "cassette")
        band_thread_mock(b3_t, L);
    else if (!band_rot90)
        translate([bat_cx - band_w/2, bat_cy - L/2, ch_z0 + lip_t])
            cube([band_w, L, band_t]);
    else
        translate([bat_cx - L/2, bat_cy - band_w/2, ch_z0 + lip_t])
            cube([L, band_w, band_t]);
}

module band_thread_mock(t = b3_t, L = 55) {   // V3: durchgefaedeltes Band (Faltung ueber den Steg)
    zb = b3_zbar;
    translate([0, b3_cy + b3_w/2, 0]) rotate([90, 0, 0])
        linear_extrude(height = b3_w)
            polygon([
                [b3_s1x0 - L, b3_z0 - t], [b3_s1x0, b3_z0 - t],   // -X Lauf unten
                [b3_s1x1, zb],                                    // Rampe hoch
                [b3_s2x0, zb],                                    // ueber den Steg
                [b3_s2x1, b3_z0 - t],                             // Rampe runter
                [b3_s2x1 + L, b3_z0 - t], [b3_s2x1 + L, b3_z0],   // +X Lauf
                [b3_s2x1, b3_z0],                                 // zurueck ueber die Faltung
                [b3_s2x0, zb + t], [b3_s1x1, zb + t],
                [b3_s1x0, b3_z0], [b3_s1x0 - L, b3_z0]
            ]);
}

module band_cut_fold(L = 18, zpad = 6, ztop = 40) {
    // Schnittkoerper fuer die Dokumentation: Schnitt quer durch die Faltung
    intersection() {
        union() { tray("cassette"); band_thread_mock(b3_t, L); }
        translate([b3_s1x0 - L, b3_cy - 0.35, b3_z0 - zpad])
            cube([(b3_s2x1 - b3_s1x0) + 2 * L, 0.7, ztop - (b3_z0 - zpad)]);
    }
}

module usb_plug_mock() {
    // Metallzunge 8,34 x 2,56 mm, Mitte der Muendung z = 3.17
    translate([-7.557 - 8.34/2, -26, 3.17 - 2.56/2]) cube([8.34, 22, 2.56]);
    // Griff / Overmold
    translate([-7.557 - 6.0, -29.5, 3.17 - 3.25]) cube([12.0, 3.6, 6.5]);
}

// ---------------------------------------------------------------- TRAY -----
module tray_body() {
    translate([out_x0, out_y0, z_tray_bot])
        cube([out_x1-out_x0, out_y1-out_y0, rim_z - z_tray_bot]);
}

module clip() {   // Seitenwangen + Haltenasen unter dem Ruecken (Kanalrichtung je Version)
    for (s = [0, 1]) {
        a0 = s == 0 ? wng_lo : ch_hi;          // Aussenkante der Wange
        a1 = s == 0 ? ch_lo  : wng_hi;
        if (!band_rot90) {
            // Kanal laeuft in Y: Wangen an den X-Seiten
            translate([a0, out_y0, ch_z0])
                cube([a1 - a0, out_y1 - out_y0, ch_h + 0.5]);            // Wange (0,5 in den Koerper)
            translate([s == 0 ? ch_lo : ch_hi - lip_w, out_y0, ch_z0])
                cube([lip_w, out_y1 - out_y0, lip_t]);                   // Nase
        } else {
            // Kanal laeuft in X: Wangen an den Y-Seiten
            translate([out_x0, a0, ch_z0])
                cube([out_x1 - out_x0, a1 - a0, ch_h + 0.5]);
            translate([out_x0, s == 0 ? ch_lo : ch_hi - lip_w, ch_z0])
                cube([out_x1 - out_x0, lip_w, lip_t]);
        }
    }
}

module tray_cuts(holder = holder_kind) {
    // Akkutasche + Platinenfach (Schulter = ledge_w rundum, Hoehe bis z=0)
    translate([pk_x0, pk_y0, z_pocket_fl])
        cube([pk_x1-pk_x0, pk_y1-pk_y0, -z_pocket_fl + 0.05]);
    translate([inn_x0, inn_y0, -0.05])
        cube([inn_x1-inn_x0, inn_y1-inn_y0, rim_z + 1.05]);

    // USB-C Aussparung in der -Y Wand
    translate([usb_x0, out_y0 - 1, usb_z0])
        cube([usb_x1-usb_x0, (inn_y0 + 1) - (out_y0 - 1), usb_z1-usb_z0]);

    // Schallschlitze fuer die Bottom-Port-Mikrofone (Ebene des Spalts)
    translate([mic_x - slot_w/2, pk_y1 - 2.5, slot_z0])
        cube([slot_w, (out_y1 + 1) - (pk_y1 - 2.5), slot_z1 - slot_z0]);     // Mic U4
    translate([mic_x - slot_w/2, out_y0 - 1, slot_z0])
        cube([slot_w, (pk_y0 + 2.5) - (out_y0 - 1), slot_z1 - slot_z0]);     // Mic U5

    // Kabelfenster in den Schultern (an den THT-Loetloechern)
    translate([pk_x1 - 1.5, 21.9, z_pocket_fl]) cube([ledge_w + 2, 2.8, -z_pocket_fl + 0.05]); // (8.0,22.97)/(8.0,24.64)
    translate([pk_x1 - 1.5, -2.3, z_pocket_fl]) cube([ledge_w + 2, 2.8, -z_pocket_fl + 0.05]); // (9.02,-0.89)
    translate([pk_x0 - 0.5, 4.7, z_pocket_fl])  cube([ledge_w + 2, 2.8, -z_pocket_fl + 0.05]); // (-11.94,6.10)

    // Fenster ohne Haltenasen (Band von unten einlegen) -- nur beim offenen Kanal
    if (holder == "clip") {
        if (!band_rot90)
            for (lx = [ch_lo, ch_hi - lip_w])
                translate([lx - 1, ch_cw - win_len/2, ch_z0 - 0.5])
                    cube([lip_w + 2, win_len, lip_t + 0.6]);
        else
            for (ly = [ch_lo, ch_hi - lip_w])
                translate([ch_cw - win_len/2, ly - 1, ch_z0 - 0.5])
                    cube([win_len, lip_w + 2, lip_t + 0.6]);
    }

    // Fasen an den 4 Senkrechtkanten (Schenkellaenge corner_ch, darf die Wand nicht durchtrennen)
    for (px = [out_x0, out_x1]) for (py = [out_y0, out_y1])
        translate([px, py, (z_tray_bot + rim_z) / 2])
            rotate([0, 0, 45])
                cube([corner_ch*sqrt(2), corner_ch*sqrt(2), (rim_z - z_tray_bot) + 4], center=true);

    // Nut fuer die Deckel-Rastnocken (0,3 mm tief, rundum in der oberen Innenwand)
    gz = rim_z - rim_h + 0.35;
    translate([inn_x0 - 0.30, inn_y0, gz]) cube([0.70, inn_y1-inn_y0, 0.60]);
    translate([inn_x1 - 0.40, inn_y0, gz]) cube([0.70, inn_y1-inn_y0, 0.60]);
    translate([inn_x0+0.40, inn_y1 - 0.30, gz]) cube([inn_x1-inn_x0-0.80, 0.70, 0.60]);
    translate([inn_x0+0.40, inn_y0 - 0.40, gz]) cube([inn_x1-inn_x0-0.80, 0.70, 0.60]);
}

// ------------------------------------------------- V3 BANDKASSETTE ---------
module cham_xz(xe, ze, s, qx, qz) {
    // 45-Grad-Fase in der XZ-Ebene (Band laeuft in X), ueber die ganze Bandbreite
    translate([xe, b3_cy + b3_chw/2 + 0.2, ze]) rotate([90, 0, 0])
        linear_extrude(height = b3_chw + 0.4)
            polygon([[0, 0], [qx * s, 0], [0, qz * s]]);
}

module cassette_body() {
    translate([b3_x0, b3_y0, b3_z0])
        cube([b3_x1 - b3_x0, b3_y1 - b3_y0, (z_tray_bot + 0.5) - b3_z0]);   // 0.5 in den Tray
}

module cassette_cuts() {
    // Faltraum: hier laeuft das Band ueber den Steg, Decke = Trayboden
    translate([b3_s1x0, b3_cy - b3_chw/2, b3_zbar])
        cube([b3_s2x1 - b3_s1x0, b3_chw, z_tray_bot - b3_zbar]);
    // die beiden Schlitze: durch die Deckschicht bis in den Faltraum
    for (sx = [b3_s1x0, b3_s2x0])
        translate([sx, b3_cy - b3_chw/2, b3_z0 - 1])
            cube([b3_slot, b3_chw, b3_plate + 1]);
    // Fasen an den 4 Kanten, ueber die das Band laeuft (Einfädeln und Biegen)
    cham_xz(b3_s1x0, b3_z0,   b3_cham, -1, +1);   // Einlauf, aussen
    cham_xz(b3_s2x1, b3_z0,   b3_cham, +1, +1);   // Auslauf, aussen
    cham_xz(b3_s1x1, b3_zbar, b3_cham, +1, -1);   // Steg, Band kommt hoch
    cham_xz(b3_s2x0, b3_zbar, b3_cham, -1, -1);   // Steg, Band geht runter
}

module cassette() {
    difference() {
        cassette_body();
        cassette_cuts();
    }
}

module tray_thread_print() {   // Drucklage der Kassette (Unterseite auf dem Bett)
    translate([0, 0, -b3_z0]) tray("cassette");
}

module tray(holder = holder_kind) {
    difference() {
        union() {
            tray_body();
            if (holder == "cassette") cassette(); else clip();
        }
        tray_cuts(holder);
    }
}

// ---------------------------------------------------------------- DECKEL ---
module lid() {
    difference() {
        union() {
            translate([out_x0, out_y0, rim_z])
                cube([out_x1-out_x0, out_y1-out_y0, lid_t]);
            // Rand (3 Seiten, -Y bleibt frei wegen USB-C)
            translate([inn_x1 - rim_clr - rim_t, inn_y0, rim_z - rim_h])
                cube([rim_t, inn_y1 - inn_y0, rim_h + 0.5]);
            translate([inn_x0 + rim_clr, inn_y0, rim_z - rim_h])
                cube([rim_t, inn_y1 - inn_y0, rim_h + 0.5]);
            translate([inn_x0 + rim_clr + rim_t, inn_y1 - rim_clr - rim_t, rim_z - rim_h])
                cube([(inn_x1 - rim_clr - rim_t) - (inn_x0 + rim_clr + rim_t), rim_t, rim_h + 0.5]);
            // Rastnocken (0,25 mm ueber den Rand hinaus)
            for (py = [inn_y0 + 8, inn_y1 - 8]) {
                translate([inn_x1 - rim_clr - 0.25, py - 1.5, rim_z - 0.75]) rotate([-90,0,0]) cylinder(r=0.5, h=3);
                translate([inn_x0 + rim_clr + 0.25, py - 1.5, rim_z - 0.75]) rotate([-90,0,0]) cylinder(r=0.5, h=3);
            }
            // Niederhalter-Stifte bis auf die Platinenoberseite (3 Ecken ohne Bauteile)
            for (p = [[8.6, 24.9], [8.6, -10.3], [-12.2, 24.9]])
                translate([p[0]-0.8, p[1]-0.8, board_t + 0.1])
                    cube([1.6, 1.6, rim_z - board_t + 0.4]);
        }
        // LED-Sichtfenster (ein Langloch ueber beide LEDs) + innen 45-Grad-Trichter
        hull() {
            for (yy = [led_win_y0, led_win_y1])
                translate([led1[0], yy, rim_z])
                    cylinder(d = led_hole_w + 2 * led_csk, h = 0.02);
            for (yy = [led_win_y0, led_win_y1])
                translate([led1[0], yy, rim_z + led_csk])
                    cylinder(d = led_hole_w, h = 0.02);
        }
        hull() for (yy = [led_win_y0, led_win_y1])
            translate([led1[0], yy, rim_z - 1])
                cylinder(d = led_hole_w, h = lid_t + 2);
        // Eindrehung ueber der Antenne
        translate([-10.5, -2.5, rim_z + lid_t - ant_recess])
            cube([14.0, 7.5, ant_recess + 1]);
    }
}

// ============================== ZUSAMMENBAU =================================
module assembly(holder = holder_kind) {
    if (show_pcb)     color("darkgreen") pcb_assembly();
    if (show_battery) color("orange")    battery_block();
    if (show_band)    color("grey")      band_mock(140, holder);
    if (show_plug)    color("silver")    usb_plug_mock();
    color("SteelBlue") tray(holder);
    if (show_lid)     color("SkyBlue")   lid();
}

// ============================ EXPORT-SCHALTER ===============================
// Export:  openscad -o teil.stl -D 'part="tray_print"' audio_vault_case.scad
part = is_undef(part) ? "assembly" : part;   // "assembly" | "tray" | "lid" | "tray_print" | "lid_print" | "tray_thread" | "tray_thread_print"

if (part == "assembly")  assembly();
if (part == "tray")      tray();
if (part == "lid")       lid();
// Drucklage: Tray liegt schon richtig (Clip unten, Oeffnung oben), nur nach z>0 schieben
if (part == "tray_print") translate([0, 0, -(ch_z0)]) tray();
// Deckel um 180 Grad um X kippen -> Aussenseite liegt auf dem Bett, Rand/Stifte stehen hoch
if (part == "lid_print") translate([0, out_y0 + out_y1, rim_z + lid_t + 1]) rotate([180, 0, 0]) lid();

// --- V3: Tray mit geschlossener Bandkassette (Band wird durchgefaedelt) -----
//   openscad -o stl/tray90_thread.stl       -D 'part="tray_thread"'       audio_vault_case.scad
//   openscad -o stl/tray90_thread_print.stl -D 'part="tray_thread_print"' audio_vault_case.scad
// (holder_kind ist in tray_thread* fest auf "cassette" gesetzt)
if (part == "tray_thread")       tray("cassette");
if (part == "tray_thread_print") tray_thread_print();

// --- Masse ausgeben (fuer Doku/Pruefskripte): -D 'part="info"' --------------
if (part == "info") {
    echo(str("PROFIL ", profil,
             " | Wand ", wall, " | Deckel ", lid_t,
             " | Aussen X ", out_x1 - out_x0, " Y ", out_y1 - out_y0,
             " | Bauhoehe Tray+Deckel ", rim_z + lid_t - z_tray_bot,
             " | mit Kassette ", rim_z + lid_t - b3_z0));
    echo(str("  Kassette X ", b3_x1 - b3_x0, " Y ", b3_y1 - b3_y0,
             " Unterkante z ", b3_z0, " | Schacht ", b3_chw, " breit, Faltraum ", b3_hv,
             " | Schlitze ", b3_slot, " breit, Steg ", b3_pitch - b3_slot,
             " | Band ", b3_w, " x ", b3_t));
    echo(str("  Oeffnungen: USB-C ", usb_x1 - usb_x0, " x ", usb_z1 - usb_z0,
             " in -Y-Wand | Schallschlitze ", slot_w, " x ", slot_z1 - slot_z0,
             " in +/-Y | LED-Sichtfenster ", led_hole_w, " breit im Deckel"));
}
