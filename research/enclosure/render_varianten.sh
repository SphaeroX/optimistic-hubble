#!/usr/bin/env bash
# Ansichten der drei V3-Varianten MIT durchgefaedeltem Band.
# Rendert direkt die geprueften Varianten-STLs (+ Band-Mock-STL) - so ist garantiert,
# dass im Bild die richtige Variante steht (-D greift bei "use/inlcude" nicht zuverlaessig).
#   bash render_varianten.sh
set -e
cd "$(dirname "$0")"
OS="${OPENSCAD:-C:/Program Files/OpenSCAD/openscad.exe}"
OPT="--imgsize=1500,1000 --projection=o --viewall --autocenter"

# Band-Mock einmal exportieren (Band ist in allen Varianten identisch)
if [ ! -f stl/band_mock.stl ] || [ audio_vault_case.scad -nt stl/band_mock.stl ]; then
    printf 'use <audio_vault_case.scad>;\nband_thread_mock();\n' > _bm.scad
    "$OS" -o stl/band_mock.stl _bm.scad >/dev/null 2>&1
    rm -f _bm.scad
    echo "  -> stl/band_mock.stl"
fi

ansicht() {   # ansicht <out.png> <tray.stl> <camera> [mit_band]
    local out=$1 stl=$2 cam=$3 band=${4:-ja}
    {
        printf 'color("SteelBlue") import("%s");\n' "$stl"
        [ "$band" = "ja" ] && printf 'color("grey") import("stl/band_mock.stl");\n'
    } > _tmp_var.scad
    "$OS" -o "$out" $OPT --camera="$cam" _tmp_var.scad >/dev/null 2>&1
    echo "  -> $out"
}

ansicht bild18_v3_A_slim_band.png     stl/v3_A_slim_tray.stl     0,0,0,-34,0,22,0
ansicht bild19_v3_B_standard_band.png stl/v3_B_standard_tray.stl 0,0,0,-34,0,22,0
ansicht bild20_v3_C_robust_band.png   stl/v3_C_robust_tray.stl   0,0,0,-34,0,22,0
ansicht bild21_v3_B_unten.png         stl/v3_B_standard_tray.stl 0,0,0,-88,0,0,0
ansicht bild22_v3_B_schraeg.png       stl/v3_B_standard_tray.stl 0,0,0,55,0,-35,0
rm -f _tmp_var.scad
md5sum bild18_v3_A_slim_band.png bild19_v3_B_standard_band.png bild20_v3_C_robust_band.png
