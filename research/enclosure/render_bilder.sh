#!/usr/bin/env bash
# Doku-Bilder fuer das Gehaeuse rendern (OpenSCAD im PATH oder OPENSCAD setzen).
#   bash render_bilder.sh
set -e
cd "$(dirname "$0")"
OS="${OPENSCAD:-C:/Program Files/OpenSCAD/openscad.exe}"
OPT="--imgsize=1400,900 --projection=o --viewall --autocenter"

render() {   # render <out.png> <camera> <<< scad-code (ohne use-Zeile)
    local out=$1 cam=$2
    printf 'use <audio_vault_case.scad>;\n' > _tmp_render.scad
    cat >> _tmp_render.scad
    "$OS" -o "$out" $OPT --camera="$cam" _tmp_render.scad >/dev/null 2>&1
    echo "  -> $out"
}

echo "V3-Bilder:"
render bild10_v3_assembly.png 0,0,0,62,0,28,0 <<'EOF'
color("SteelBlue") assembly("cassette");
EOF

render bild11_v3_schnitt_faltung.png 0,0,0,72,0,22,0 <<'EOF'
band_cut_fold(18, 6, 40);
EOF

render bild12_v3_zoom_faltung.png 0,0,0,90,0,0,0 <<'EOF'
band_cut_fold(4, 4, -11.4);
EOF

render bild13_v3_ruecken.png 0,0,0,-65,0,20,0 <<'EOF'
color("SteelBlue") tray("cassette");
color("grey")      band_thread_mock();
EOF

render bild14_v3_druck.png 0,0,0,62,0,28,0 <<'EOF'
tray_thread_print();
EOF

echo "Varianten-Bilder (Druckdateien, Kassette unten):"
for V in A_slim B_standard C_robust; do
    N=$(echo "$V" | tr 'A-Z' 'a-z')
    printf 'import("stl/v3_%s_tray.stl");\n' "$V" > _tmp_render.scad
    "$OS" -o "bild${N}.png" $OPT --camera=0,0,0,-62,0,22,0 _tmp_render.scad >/dev/null 2>&1
    echo "  -> bild${N}.png"
done
rm -f _tmp_render.scad
