#!/usr/bin/env bash
# Rendert die drei V3-Dicken-Varianten (A slim / B standard / C robust) fuer den
# Telegram-Vergleich. Parameter per -D; die Szene wird an eine Kopie der
# Modelldatei angehaengt, damit alle Modellkonstanten (b3_*, out_*) gueltig sind.
set -e
cd "$(dirname "$0")"
OS="C:/Program Files/OpenSCAD/openscad.exe"
SRC=audio_vault_case.scad
OPT="--imgsize=1200,900 --projection=o --render"
DIST=${DIST:-120}
ROT=${ROT:-55,0,25}

P_A="wall=1.2 clr_board=0.6 clr_top=0.4 lid_t=1.5 ant_recess=0.6 gap_under_pcb=1.2 base_t=1.2 ledge_w=0.8 rim_t=0.6 corner_ch=1.2 batt_clr=0.5"
P_B="wall=1.6 clr_board=0.8 clr_top=0.6 lid_t=2.0 ant_recess=0.8 gap_under_pcb=1.6 base_t=1.6 ledge_w=1.0 rim_t=0.7 corner_ch=1.8 batt_clr=0.8"
P_C="wall=2.0 clr_board=1.0 clr_top=0.8 lid_t=2.4 ant_recess=1.0 gap_under_pcb=2.0 base_t=2.0 ledge_w=1.2 rim_t=0.9 corner_ch=2.0 batt_clr=1.2"

render() {  # render <out.png> <params> <scene-file>
    local out=$1 params=$2 scene=$3
    local D=""
    for kv in $params; do D="$D -D $kv"; done
    cp -f "$SRC" _v3_tmp.scad
    cat "$scene" >> _v3_tmp.scad
    "$OS" -o "$out" $OPT -D 'part="none"' $D --autocenter \
          --camera="0,0,0,$ROT,$DIST" _v3_tmp.scad >/dev/null 2>&1 || echo "  !! Fehler bei $out"
    echo "  -> $out"
}

case "${1:-all}" in
  closed)
    render v3r_A_closed.png "$P_A" _scene_closed.scad
    render v3r_B_closed.png "$P_B" _scene_closed.scad
    render v3r_C_closed.png "$P_C" _scene_closed.scad
    ;;
  open)
    render v3r_A_open.png "$P_A" _scene_open.scad
    render v3r_B_open.png "$P_B" _scene_open.scad
    render v3r_C_open.png "$P_C" _scene_open.scad
    ;;
  fold)
    render v3r_B_fold.png "$P_B" _scene_fold.scad
    ;;
  *)
    render v3r_A_closed.png "$P_A" _scene_closed.scad
    render v3r_B_closed.png "$P_B" _scene_closed.scad
    render v3r_C_closed.png "$P_C" _scene_closed.scad
    render v3r_A_open.png   "$P_A" _scene_open.scad
    render v3r_B_open.png   "$P_B" _scene_open.scad
    render v3r_C_open.png   "$P_C" _scene_open.scad
    render v3r_B_fold.png   "$P_B" _scene_fold.scad
    ;;
esac
rm -f _v3_tmp.scad
echo "fertig"
