// Querschnitt quer durch die Bandfaltung (Farben bleiben erhalten)
difference() {
    union() {
        color("SteelBlue") tray("cassette");
        color("grey")      band_thread_mock(b3_t, 18);
    }
    translate([b3_s1x0 - 25, b3_cy, b3_z0 - 15]) cube([60, 60, 60]);
}
