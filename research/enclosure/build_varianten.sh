#!/usr/bin/env bash
# Baut die drei Dicken-Varianten (A slim / B standard / C robust) der
# geschlossenen Bandkassette: Tray (Montagelage), Tray (Drucklage), Deckel.
#   bash build_varianten.sh
set -e
cd "$(dirname "$0")"
OS="${OPENSCAD:-C:/Program Files/OpenSCAD/openscad.exe}"
SRC=audio_vault_case.scad

# Parametersatz je Variante (nur die abweichenden Werte; Rest = Standard)
P_A="wall=1.2 clr_board=0.6 clr_top=0.4 lid_t=1.5 ant_recess=0.6 gap_under_pcb=1.2 \
base_t=1.2 ledge_w=0.8 rim_t=0.6 corner_ch=1.2 batt_clr=0.5 \
b3_w=24.75 b3_t=3.0 b3_clr=0.25 b3_rail=1.4 b3_plate=1.0 b3_slot=8.0 b3_pitch=13.0"
P_B="wall=1.6 clr_board=0.8 clr_top=0.6 lid_t=2.0 ant_recess=0.8 gap_under_pcb=1.6 \
base_t=1.6 ledge_w=1.0 rim_t=0.7 corner_ch=1.8 batt_clr=0.8 \
b3_w=24.75 b3_t=3.0 b3_clr=0.30 b3_rail=1.8 b3_plate=1.2 b3_slot=7.0 b3_pitch=12.0"
P_C="wall=2.0 clr_board=1.0 clr_top=0.8 lid_t=2.4 ant_recess=1.0 gap_under_pcb=2.0 \
base_t=2.0 ledge_w=1.2 rim_t=0.9 corner_ch=2.0 batt_clr=1.2 \
b3_w=24.75 b3_t=3.0 b3_clr=0.40 b3_rail=2.2 b3_plate=1.6 b3_slot=7.0 b3_pitch=12.0"

build() {   # build <Buchstabe> <name> <params>
    local L=$1 NAME=$2 PARAMS=$3
    local D=""
    for kv in $PARAMS; do D="$D -D $kv"; done
    echo "== Variante $L ($NAME)"
    eval "\"$OS\" -o stl/v3_${L}_${NAME}_tray.stl -D 'part=\"tray_thread\"' $D $SRC" 2>/dev/null || echo "   (Fehler bei tray)"
    eval "\"$OS\" -o stl/v3_${L}_${NAME}_tray_print.stl -D 'part=\"tray_thread_print\"' $D $SRC" 2>/dev/null || echo "   (Fehler bei tray_print)"
    eval "\"$OS\" -o stl/v3_${L}_${NAME}_lid.stl -D 'part=\"lid\"' $D $SRC" 2>/dev/null || echo "   (Fehler bei lid)"
    eval "\"$OS\" -o stl/v3_${L}_${NAME}_lid_print.stl -D 'part=\"lid_print\"' $D $SRC" 2>/dev/null || echo "   (Fehler bei lid_print)"
    eval "\"$OS\" -o stl/_info.stl -D 'part=\"info\"' $D $SRC" 2>&1 | grep -a '^ECHO' | sed 's/^/   /'
    rm -f stl/_info.stl
}

build A slim   "$P_A"
build B standard "$P_B"
build C robust "$P_C"
echo "fertig: stl/v3_{A_slim,B_standard,C_robust}_{tray,tray_print,lid_print}.stl"
