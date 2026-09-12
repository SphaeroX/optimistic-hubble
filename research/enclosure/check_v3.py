"""Pruefung der drei Dicken-Varianten der geschlossenen Bandkassette (V3).

Geprueft wird je Variante gegen das echte Tray-STL:
  1. STL sauber (wasserdicht, 1 Koerper, Aussenmasse wie berechnet)
  2. Platine / Akku liegen im Tray (0 Punkte im Material)
  3. USB-C-Stecker passt durch die Aussparung  -> USB-C ist ausgespart
  4. Schallwege beider Mikrofone frei          -> Mikrofone sind ausgespart
  5. LED-Sichtkanal im Deckel frei             -> LEDs sind ausgespart
  6. durchgefaedeltes Band (2,0 und 3,0 mm dick) stoesst nirgends an
  7. Kassette: nur die zwei Schlitze sind offen (Deckschicht dicht)

Aufruf:  python check_v3.py
"""
import os
import numpy as np
import trimesh

WD = r"C:\Users\MGasc\Documents\antigravity\optimistic-hubble\research\enclosure"
PCB = r"C:\Users\MGasc\Documents\antigravity\optimistic-hubble\research\3D_PCB1_2026-09-08.stl"

# --- gemeinsamer Unterbau (inside/box_pts/cyl_pts/mesh_points aus check_collision.py) ---
exec(open(os.path.join(WD, "check_collision.py")).read().split("results = []")[0])

# ---- unveraenderliche Hardware-Maße (aus dem PCB-STL gemessen) ----
BX0, BX1, BY0, BY1 = -12.814, 9.811, -11.079, 25.895
BOARD_T, COMP_ZMAX = 1.6, 4.76
BATT_T, BATT_W, BATT_L = 9.87, 20.0, 33.0
USB_X0, USB_X1, USB_Z0, USB_Z1 = -12.06, -3.06, 1.60, 4.78
USB_CX, USB_CZ = -7.557, 3.17
MIC_X, MICA_Y, MICB_Y = 5.495, 24.54, -6.83
SLOT_W, SLOT_Z0, SLOT_Z1 = 6.0, -1.55, -0.45
LED1, LED_WIN = (7.19, 14.73), (13.45, 18.00)
B3_W, B3_T, B3_VCLR = 24.75, 3.0, 0.40

# ---- Parametersaetze der drei Varianten (identisch zu build_varianten.sh) ----
VARIANTEN = {
    "A_slim": dict(wall=1.2, clr_board=0.6, clr_top=0.4, lid_t=1.5, ant_recess=0.6,
                   gap_under_pcb=1.2, base_t=1.2, ledge_w=0.8, rim_t=0.6, corner_ch=1.2,
                   batt_clr=0.5, b3_clr=0.25, b3_rail=1.4, b3_plate=1.0, b3_slot=8.0, b3_pitch=13.0),
    "B_standard": dict(wall=1.6, clr_board=0.8, clr_top=0.6, lid_t=2.0, ant_recess=0.8,
                       gap_under_pcb=1.6, base_t=1.6, ledge_w=1.0, rim_t=0.7, corner_ch=1.8,
                       batt_clr=0.8, b3_clr=0.30, b3_rail=1.8, b3_plate=1.2, b3_slot=7.0, b3_pitch=12.0),
    "C_robust": dict(wall=2.0, clr_board=1.0, clr_top=0.8, lid_t=2.4, ant_recess=1.0,
                     gap_under_pcb=2.0, base_t=2.0, ledge_w=1.2, rim_t=0.9, corner_ch=2.0,
                     batt_clr=1.2, b3_clr=0.40, b3_rail=2.2, b3_plate=1.6, b3_slot=7.0, b3_pitch=12.0),
}


def ableiten(p):
    """Alle abgeleiteten Maße - dieselben Formeln wie im SCAD."""
    d = dict(p)
    d["inn_x0"], d["inn_x1"] = BX0 - p["clr_board"], BX1 + p["clr_board"]
    d["inn_y0"], d["inn_y1"] = BY0 - p["clr_board"], BY1 + p["clr_board"]
    d["out_x0"], d["out_x1"] = d["inn_x0"] - p["wall"], d["inn_x1"] + p["wall"]
    d["out_y0"], d["out_y1"] = d["inn_y0"] - p["wall"], d["inn_y1"] + p["wall"]
    d["rim_z"] = BOARD_T + COMP_ZMAX + p["clr_top"]
    d["z_batt_top"] = -p["gap_under_pcb"]
    d["z_batt_bot"] = d["z_batt_top"] - BATT_T
    d["z_pocket_fl"] = d["z_batt_bot"] - p["batt_clr"]
    d["z_tray_bot"] = d["z_pocket_fl"] - p["base_t"]
    d["bat_cx"], d["bat_cy"] = (BX0 + BX1) / 2, (BY0 + BY1) / 2
    d["b3_chw"] = B3_W + 2 * p["b3_clr"]
    d["b3_cy"] = d["bat_cy"]
    d["b3_hv"] = B3_T + B3_VCLR
    d["b3_z0"] = d["z_tray_bot"] - d["b3_hv"] - p["b3_plate"]
    d["b3_zbar"] = d["b3_z0"] + p["b3_plate"]
    d["s1x0"] = d["bat_cx"] - p["b3_pitch"] / 2 - p["b3_slot"] / 2
    d["s1x1"] = d["bat_cx"] - p["b3_pitch"] / 2 + p["b3_slot"] / 2
    d["s2x0"] = d["bat_cx"] + p["b3_pitch"] / 2 - p["b3_slot"] / 2
    d["s2x1"] = d["bat_cx"] + p["b3_pitch"] / 2 + p["b3_slot"] / 2
    d["b3_x0"] = min(d["out_x0"], d["bat_cx"] - d["b3_chw"] / 2 - p["b3_rail"])
    d["b3_x1"] = max(d["out_x1"], d["bat_cx"] + d["b3_chw"] / 2 + p["b3_rail"])
    d["b3_y0"] = d["b3_cy"] - d["b3_chw"] / 2 - p["b3_rail"]
    d["b3_y1"] = d["b3_cy"] + d["b3_chw"] / 2 + p["b3_rail"]
    return d


def band_punkte(d, t, L=30, res=0.25, rand=0.12):
    """Oberflaechenpunkte des durchgefaedelten Bandes (Profil in XZ, extrudiert ueber Y).

    rand: das Band wird um diesen Betrag eingezogen, damit Wandberuehrung durch
    Rundungsfehler nicht als Kollision zaehlt.
    """
    z0, zb = d["b3_z0"], d["b3_zbar"]
    s1x0, s1x1, s2x0, s2x1 = d["s1x0"], d["s1x1"], d["s2x0"], d["s2x1"]
    t = max(t - 2 * rand, 0.4)
    prof = [(s1x0 - L, z0 - t), (s1x0, z0 - t), (s1x1, zb), (s2x0, zb), (s2x1, z0 - t),
            (s2x1 + L, z0 - t), (s2x1 + L, z0), (s2x1, z0), (s2x0, zb + t), (s1x1, zb + t),
            (s1x0, z0), (s1x0 - L, z0)]
    ys = np.array([d["b3_cy"] - B3_W / 2 + rand, d["b3_cy"], d["b3_cy"] + B3_W / 2 - rand])
    pts = []
    for i in range(len(prof)):
        a, b = np.array(prof[i]), np.array(prof[(i + 1) % len(prof)])
        n = max(2, int(np.linalg.norm(b - a) / res))
        for s in np.linspace(0, 1, n):
            x, z = a + s * (b - a)
            for y in ys:
                pts.append((x, y, z))
    return np.asarray(pts, float)


def deckel_dicht(lid, d, res=0.3):
    """Deckschicht-Mittenebene: nur das LED-Langloch darf offen sein."""
    z = d["rim_z"] + d["lid_t"] / 2
    xs = np.arange(d["out_x0"] + 0.2, d["out_x1"] - 0.2, res)
    ys = np.arange(d["out_y0"] + 0.2, d["out_y1"] - 0.2, res)
    X, Y = np.meshgrid(xs, ys)
    pts = np.c_[X.ravel(), Y.ravel(), np.full(X.size, z)]
    ins = inside(lid, pts)
    offen = pts[~ins]
    if len(offen) == 0:
        return True, "keine Oeffnung"
    # gewollt: LED-Langloch (1,9 mm) + innenliegender 45°-Lichtsammler bis 4,3 mm
    x_ok = np.abs(offen[:, 0] - LED1[0]) < 3.5
    y_ok = (offen[:, 1] > LED_WIN[0] - 2.4) & (offen[:, 1] < LED_WIN[1] + 2.4)
    fremd = offen[~(x_ok & y_ok)]
    return len(fremd) == 0, (f"LED-Fenster offen ({int((x_ok & y_ok).sum())} Punkte)"
                             + ("" if len(fremd) == 0 else f" + {len(fremd)} ungewollte Punkte"))


def kassette_dicht(tray, d, res=0.3):
    """Deckschicht der Kassette (Mittenebene): nur die zwei Schlitze duerfen offen sein."""
    z = d["b3_z0"] + d["b3_plate"] / 2
    xs = np.arange(d["b3_x0"] + 0.2, d["b3_x1"] - 0.2, res)
    ys = np.arange(d["b3_y0"] + 0.2, d["b3_y1"] - 0.2, res)
    X, Y = np.meshgrid(xs, ys)
    pts = np.c_[X.ravel(), Y.ravel(), np.full(X.size, z)]
    ins = inside(tray, pts)
    offen = pts[~ins]
    if len(offen) == 0:
        return False, "Kassette hat gar keine Schlitze"
    in_slot = np.zeros(len(offen), bool)
    for (a, b) in ((d["s1x0"], d["s1x1"]), (d["s2x0"], d["s2x1"])):
        in_slot |= (offen[:, 0] > a - 0.6) & (offen[:, 0] < b + 0.6)
    fremd = offen[~in_slot]
    ok = len(fremd) == 0
    return ok, (f"{len(offen)} Punkte offen, davon {len(fremd)} ausserhalb der Schlitze")


pcb = trimesh.load(PCB, process=True)
P_pcb = mesh_points(pcb, 120000)
gesamt = []

print("=" * 104)
for name, params in VARIANTEN.items():
    d = ableiten(params)
    fallen = []
    tray = trimesh.load(os.path.join(WD, "stl", f"v3_{name}_tray.stl"), process=True)
    lid = trimesh.load(os.path.join(WD, "stl", f"v3_{name}_lid.stl"), process=True)
    print(f"\n### Variante {name}   (Wand {params['wall']} / Deckel {params['lid_t']} / Kassette {params['b3_plate']})")

    # 1. STL + Aussenmasse
    ist = np.round(tray.extents, 2)
    soll = np.round([d["b3_x1"] - d["b3_x0"], d["out_y1"] - d["out_y0"], d["rim_z"] - d["b3_z0"]], 2)
    ok = (tray.is_watertight and tray.body_count == 1 and np.allclose(ist[:2], soll[:2], atol=0.05))
    print(f"{'OK ' if ok else 'FEHLER'} | Tray STL / Aussenmaße        | {'dicht, 1 Koerper' if tray.is_watertight else 'UNDICHT'}"
          f", Volumen {tray.volume/1000:.2f} cm3, X×Y = {ist[0]}×{ist[1]} (soll {soll[0]}×{soll[1]})")
    fallen.append(ok)
    ok = lid.is_watertight and lid.body_count == 1
    print(f"{'OK ' if ok else 'FEHLER'} | Deckel STL                    | {'dicht, 1 Koerper' if ok else 'Problem'}, Volumen {lid.volume/1000:.2f} cm3")
    fallen.append(ok)

    # 2. Platine / Akku
    for nm, mesh, pts in (("Platine <-> Tray", tray, P_pcb),
                          ("Akku 20x33x9.87 <-> Tray", tray,
                           box_pts([d["bat_cx"] - BATT_W/2, d["bat_cy"] - BATT_L/2, d["z_batt_bot"]],
                                   [d["bat_cx"] + BATT_W/2, d["bat_cy"] + BATT_L/2, d["z_batt_top"]], 0.3))):
        ins = inside(mesh, pts)
        k = int(ins.sum())
        tief = 0.0
        if k:
            _, dist, _ = trimesh.proximity.closest_point(mesh, pts[ins])
            tief = float(dist.max())
        ok = k == 0
        print(f"{'OK ' if ok else 'FEHLER'} | {nm:29s} | {k:6d} Punkte im Material"
              + (f" (tiefste {tief:.3f} mm)" if k else ""))
        fallen.append(ok)

    # 3. USB-C-Stecker durch die Aussparung
    plug = np.vstack([box_pts([USB_CX - 8.34/2, -26.0, USB_CZ - 1.28], [USB_CX + 8.34/2, -4.0, USB_CZ + 1.28], 0.3),
                      box_pts([USB_CX - 6.0, -29.5, USB_CZ - 3.25], [USB_CX + 6.0, -26.0, USB_CZ + 3.25], 0.5)])
    ins = inside(tray, plug)
    k = int(ins.sum())
    print(f"{'OK ' if k == 0 else 'FEHLER'} | USB-C-Stecker <-> Tray        | {k:6d} Punkte im Material "
          f"(Aussparung {USB_X1-USB_X0:.1f} x {USB_Z1-USB_Z0:.2f} mm @ Wand -Y)")
    fallen.append(k == 0)

    # 4. Schallwege beider Mikrofone (Schlitzhoehe haengt am Akustikspalt der Variante)
    sz0, sz1 = d["z_batt_top"] + 0.05, -0.45
    for nm, my in (("Mic U4 (+Y)", MICA_Y), ("Mic U5 (-Y)", MICB_Y)):
        lo_y, hi_y = (my, d["out_y1"] + 3) if my > 0 else (d["out_y0"] - 3, my)
        pts = box_pts([MIC_X - 2.5, lo_y, sz0 + 0.15], [MIC_X + 2.5, hi_y, sz1 - 0.05], 0.2)
        k = int(inside(tray, pts).sum())
        print(f"{'OK ' if k == 0 else 'FEHLER'} | Schallweg {nm:20s} | {k:6d} Punkte im Material "
              f"(Schlitz {SLOT_W:.0f} x {sz1-sz0:.2f} mm)")
        fallen.append(k == 0)

    # 5. LED-Sichtkanal (durch Deckelplatte + Trichter bis ueber die Deckeloberseite)
    pts = cyl_pts(LED1[0], LED1[1], 2.55, d["rim_z"] + d["lid_t"] + 1.0, 1.7, 0.2)
    k = int(inside(lid, pts).sum())
    print(f"{'OK ' if k == 0 else 'FEHLER'} | LED-Sichtkanal d=1,7 mm        | {k:6d} Punkte im Material (Deckel)")
    fallen.append(k == 0)

    # 6. Band durchgefaedelt (2,0 und 3,0 mm dick); Beruehrung der Wand ist erlaubt
    for t in (2.0, 3.0):
        pts = band_punkte(d, t)
        ins = inside(tray, pts)
        k = int(ins.sum())
        tief = 0.0
        if k:
            _, dist, _ = trimesh.proximity.closest_point(tray, pts[ins])
            tief = float(dist.max())
        ok = tief <= 0.05
        print(f"{'OK ' if ok else 'FEHLER'} | Band {t:.1f} mm durchgefaedelt      | "
              + ("kein Kontakt" if k == 0 else f"{k:6d} Beruehrpunkte, tiefste {tief:.3f} mm")
              + f"  (Faltraum {d['b3_hv']-t:.2f} mm Luft ueber dem Steg)")
        fallen.append(ok)

    # 7. Kassette dicht bis auf die zwei Schlitze + Deckel dicht bis aufs LED-Fenster
    ok, info = kassette_dicht(tray, d)
    print(f"{'OK ' if ok else 'FEHLER'} | Kassette: nur 2 Schlitze offen | {info}")
    fallen.append(ok)
    ok, info = deckel_dicht(lid, d)
    print(f"{'OK ' if ok else 'FEHLER'} | Deckel: nur LED-Fenster offen  | {info}")
    fallen.append(ok)

    gesamt.append((name, sum(fallen), len(fallen)))

print("\n" + "=" * 104)
for name, gut, n in gesamt:
    print(f"{'BESTANDEN' if gut == n else 'FEHLER    '} | {name:12s} | {gut}/{n} Checks")
print("=" * 104)
