// Render-Ansichten fuer die Dokumentation
// Aufruf z.B.:
//   openscad -o bild.png -D 'mode="asm_iso"' --camera=0,0,0,55,0,25,0 \
//            --projection=o --autocenter --viewall --imgsize=1200,900 render.scad
use <audio_vault_case.scad>;

mode   = "asm_iso";
holder = "clip";      // "clip" (V1/V2) | "cassette" (V3, Band durchgefaedelt)
cutpos = 7.4;         // Schnittlage fuer die Schnittansichten
// ACHTUNG: "use <...>" importiert KEINE Variablen - Modellkonstanten hier lokal:
bat_cy = 7.408;       // = bat_cy in audio_vault_case.scad
show_pcb      = true;
show_battery  = true;
show_band     = true;
show_plug     = false;
show_lid      = true;

module slab_xz(y) { translate([-100, y - 0.35, -100]) cube([200, 0.7, 200]); }
module slab_yz(x) { translate([x - 0.35, -100, -100]) cube([0.7, 200, 200]); }

if (mode == "asm_iso")       assembly(holder);
if (mode == "tray_open")     { tray(holder);
                               if (show_pcb) pcb_assembly();
                               if (show_battery) battery_block();
                               if (show_band) color("grey") band_mock(140, holder); }
if (mode == "tray_only")     tray(holder);
if (mode == "lid_only")      lid();
if (mode == "section_xz")    intersection() { assembly(holder); slab_xz(cutpos); }
if (mode == "section_yz")    intersection() { assembly(holder); slab_yz(cutpos); }

// ---- V3: Kassette, Faltung, Boden -----------------------------------------
if (mode == "v3_section_fold")  intersection() {           // Schnitt quer durch die Faltung
    union() {
        color("SteelBlue") tray("cassette");
        color("grey")      band_mock(18, "cassette");      // nur kurzes Stueck Band
    }
    slab_xz(bat_cy);
}
if (mode == "v3_fold_cut")  band_cut_fold(18, 6, 40);      // sauberes Schnittprofil
if (mode == "v3_fold_zoom") band_cut_fold(4, 4, -11.4);    // Nahaufnahme der Faltung
if (mode == "v3_bottom")   {                               // Blick von unten auf die 2 Schlitze
    color("SteelBlue") tray("cassette");
    color("grey")      band_thread_mock();
}
if (mode == "v3_tray")     tray("cassette");
if (mode == "v3_asm")      assembly("cassette");
if (mode == "v3_open")     {                               // Deckel weg: Platine + Band
    color("SteelBlue") tray("cassette");
    color("darkgreen") pcb_assembly();
    color("grey")      band_thread_mock();
}
if (mode == "v3_print")    translate([1.5, -7.4, -12.7]) tray_thread_print();
