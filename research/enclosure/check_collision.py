"""Kollisionspruefung v2 - eigener, robuster Point-in-Solid-Test (Ray-Parity, 3 Richtungen,
Mehrheitsentscheid). Kein Vertrauen in trimesh.contains.
"""
import os, sys
import numpy as np
import trimesh

import os
WD  = r"C:\Users\MGasc\Documents\antigravity\optimistic-hubble\research\enclosure"
PCB = r"C:\Users\MGasc\Documents\antigravity\optimistic-hubble\research\3D_PCB1_2026-09-08.stl"
# BAND90=1 prueft die 90-Grad-Version (Band laeuft entlang X), TRAY_STL waehlt die Datei
band_rot90 = os.environ.get("BAND90") == "1"
tray_name  = os.environ.get("TRAY_STL", "tray.stl")
rng = np.random.default_rng(11)

# ---- Parameter (identisch zum SCAD) ----
bx0, bx1, by0, by1 = -12.814, 9.811, -11.079, 25.895
board_t, comp_zmax, clr_top = 1.6, 4.76, 0.6
wall, clr_board = 1.6, 0.8
gap_under_pcb, batt_t, batt_clr, base_t, ledge_w = 1.6, 9.87, 0.8, 1.6, 1.0
batt_w, batt_l = 20.0, 33.0
band_w, band_t, band_squeeze, band_clr_w = 22.6, 4.5, 0.2, 0.4
rail_t, lip_w, lip_t = 2.0, 3.0, 1.2
inn_x0, inn_x1 = bx0 - clr_board, bx1 + clr_board
inn_y0, inn_y1 = by0 - clr_board, by1 + clr_board
out_x0, out_x1 = inn_x0 - wall, inn_x1 + wall
out_y0, out_y1 = inn_y0 - wall, inn_y1 + wall
rim_z = board_t + comp_zmax + clr_top
z_batt_top, z_batt_bot = -gap_under_pcb, -gap_under_pcb - batt_t
z_pocket_fl, z_tray_bot = z_batt_bot - batt_clr, z_batt_bot - batt_clr - base_t
bat_cx, bat_cy = (bx0 + bx1) / 2, (by0 + by1) / 2
ch_w = band_w + 2 * band_clr_w
ch_c = bat_cy if band_rot90 else bat_cx          # Mitte quer zum Kanal
ch_lo, ch_hi = ch_c - ch_w / 2, ch_c + ch_w / 2
ch_cw = bat_cx if band_rot90 else bat_cy         # Mitte in Kanalrichtung
ch_h = lip_t + band_t - band_squeeze
ch_z1, ch_z0 = z_tray_bot, z_tray_bot - ch_h
mic_x, micA_y, micB_y = 5.495, 24.54, -6.83
lid_t, rim_h, rim_clr, ant_recess = 2.0, 1.2, 0.15, 0.8
led_win_y0, led_win_y1 = 13.45, 18.00
corner_ch = 1.8
led1, led2 = (7.19, 14.73), (7.19, 16.73)
usb_cx, usb_cz = -7.557, 3.17

DIRS = np.array([[0.311, 0.927, 0.207], [-0.577, 0.577, 0.577], [0.123, -0.456, 0.881]])
DIRS /= np.linalg.norm(DIRS, axis=1, keepdims=True)


def inside(T, pts, chunk=1500, dirs=DIRS):
    """T = Dreiecksarray (F,3,3) oder trimesh; pts (N,3) -> bool 'im Material'."""
    if hasattr(T, "faces"):
        T = np.asarray(T.vertices, dtype=np.float64)[np.asarray(T.faces, dtype=np.int64)]
    T = np.asarray(T, dtype=np.float64)
    p0, e1, e2 = T[:, 0], T[:, 1] - T[:, 0], T[:, 2] - T[:, 0]
    N = len(pts)
    votes = np.zeros((N, len(dirs)), bool)
    for k, d in enumerate(dirs):
        h = np.cross(d, e2)
        a = np.einsum("ij,ij->i", e1, h)
        ok = np.abs(a) > 1e-12
        f = np.where(ok, 1.0 / np.where(ok, a, 1.0), 0.0)
        for i in range(0, N, chunk):
            P = pts[i:i + chunk]
            s = P[:, None, :] - p0[None, :, :]
            u = f[None, :] * (s * h[None, :, :]).sum(2)
            q = np.cross(s, e1[None, :, :])
            v = f[None, :] * (q * d[None, None, :]).sum(2)
            t = f[None, :] * (q * e2[None, :, :]).sum(2)
            hit = ok[None, :] & (u >= -1e-9) & (v >= -1e-9) & (u + v <= 1 + 1e-9) & (t > 1e-6)
            votes[i:i + chunk, k] = (hit.sum(1) % 2) == 1
    return votes.sum(1) >= 2


def box_pts(lo, hi, res=0.3):
    xs = np.arange(lo[0], hi[0] + 1e-9, res); ys = np.arange(lo[1], hi[1] + 1e-9, res)
    zs = np.arange(lo[2], hi[2] + 1e-9, res)
    X, Y = np.meshgrid(xs, ys); X2, Z2 = np.meshgrid(xs, zs); Y3, Z3 = np.meshgrid(ys, zs)
    return np.vstack([
        np.c_[X.ravel(), Y.ravel(), np.full(X.size, lo[2])],
        np.c_[X.ravel(), Y.ravel(), np.full(X.size, hi[2])],
        np.c_[X2.ravel(), np.full(X2.size, lo[1]), Z2.ravel()],
        np.c_[X2.ravel(), np.full(X2.size, hi[1]), Z2.ravel()],
        np.c_[np.full(Y3.size, lo[0]), Y3.ravel(), Z3.ravel()],
        np.c_[np.full(Y3.size, hi[0]), Y3.ravel(), Z3.ravel()]])


def cyl_pts(cx, cy, z0, z1, d, res=0.25):
    r = d / 2
    th = np.linspace(0, 2 * np.pi, max(12, int(np.pi * d / res)), endpoint=False)
    zs = np.arange(z0, z1 + 1e-9, res)
    TH, Z = np.meshgrid(th, zs)
    rr = np.arange(0, r + 1e-9, res)
    TH2, RR = np.meshgrid(th, rr)
    side = np.c_[cx + r * np.cos(TH.ravel()), cy + r * np.sin(TH.ravel()), Z.ravel()]
    caps = [np.c_[cx + RR.ravel() * np.cos(TH2.ravel()), cy + RR.ravel() * np.sin(TH2.ravel()),
                  np.full(TH2.size, z)] for z in (z0, z1)]
    return np.vstack([side] + caps)


def mesh_points(m, target=150000):
    T = np.asarray(m.vertices, float)[np.asarray(m.faces, np.int64)]
    mid = np.concatenate([(T[:, 0] + T[:, 1]) / 2, (T[:, 1] + T[:, 2]) / 2, (T[:, 2] + T[:, 0]) / 2])
    P = np.vstack([m.vertices, T.mean(1), mid])
    if len(P) > target:
        P = P[rng.choice(len(P), target, replace=False)]
    return np.ascontiguousarray(P, dtype=np.float64)


results = []


def check(name, mesh, pts, expect_inside=0, tolerance=0):
    ins = inside(mesh, pts)
    k = int(ins.sum())
    ok = abs(k - expect_inside) <= tolerance
    info = f"{k:6d} Punkte im Material"
    if k:
        P = pts[ins]
        _, dist, _ = trimesh.proximity.closest_point(mesh, P)
        info += f" | tiefster {dist.max():.3f} mm | bbox-Ausdehnung {np.round(P.max(0)-P.min(0),2).tolist()}"
        if k and expect_inside == 0:
            info += f" | z.B. {np.round(P[np.argsort(-dist)[0]],2).tolist()}"
    results.append((ok, name, info))
    print(f"{'OK ' if ok else 'FEHLER'} | {name:38s} | {info}")


pcb  = trimesh.load(PCB, process=True)
tray = trimesh.load(os.path.join(WD, tray_name), process=True)
lid  = trimesh.load(os.path.join(WD, "lid.stl"), process=True)

# Selbsttest des inside()-Tests an bekannten Punkten
sanity = np.array([[-15.0, 0.0, -5.0], [-1.5, 7.4, -6.0], [0.0, 0.0, 60.0], [-1.5, 7.4, -17.0], [9.9, 0.0, -0.5]])
exp = [True, False, False, False, False]
got = inside(tray, sanity)
print("Selbsttest inside(tray):", list(zip(exp, got.tolist())), "->", "OK" if all(a == b for a, b in zip(exp, got)) else "TEST KAPUTT")
print("=" * 118)

P_pcb = mesh_points(pcb, 150000)
check("PCB <-> Tray", tray, P_pcb)
check("PCB <-> Deckel", lid, P_pcb)

check(f"Akku {batt_w}x{batt_l}x{batt_t}", tray,
      box_pts([bat_cx - batt_w/2, bat_cy - batt_l/2, z_batt_bot],
              [bat_cx + batt_w/2, bat_cy + batt_l/2, z_batt_top], 0.25))

plug = np.vstack([box_pts([usb_cx - 8.34/2, -26.0, usb_cz - 1.28], [usb_cx + 8.34/2, -5.0, usb_cz + 1.28], 0.25),
                  box_pts([usb_cx - 6.0, -29.5, usb_cz - 3.25], [usb_cx + 6.0, -26.0, usb_cz + 3.25], 0.5)])
check("USB-Stecker <-> Tray", tray, plug)
check("USB-Stecker <-> Deckel", lid, plug)

# Band liegt AUF den Nasen: Unterkante = ch_z0 + lip_t
def band_box(t):
    z0, z1 = ch_z0 + lip_t, ch_z0 + lip_t + t
    if not band_rot90:
        return [bat_cx - band_w/2, bat_cy - 60, z0], [bat_cx + band_w/2, bat_cy + 60, z1]
    return [bat_cx - 60, bat_cy - band_w/2, z0], [bat_cx + 60, bat_cy + band_w/2, z1]

for t, expect in ((4.29, 0), (band_t, None)):
    lo, hi = band_box(t)
    b = box_pts(lo, hi, 0.4)
    if expect is None:
        ins = inside(tray, b)
        k = int(ins.sum())
        if k:
            P = b[ins]
            _, d, _ = trimesh.proximity.closest_point(tray, P)
            print(f"OK  | Band {t} mm klemmt wie gewollt        | {k:6d} Punkte | max. Eindringtiefe {d.max():.3f} mm")
            results.append((d.max() < 0.35, f"Band {t} Klemmung", f"{d.max():.3f} mm"))
        else:
            print(f"OK  | Band {t} mm                       | kein Kontakt (Klemmung zu lose)")
            results.append((False, "Band Klemmung", "kein Kontakt"))
    else:
        check(f"Band {t} mm laeuft frei", tray, b, expect_inside=0)

for i, p in enumerate((led1, led2), 1):
    check(f"LED {i} Sichtkanal d=1,7 mm", lid, cyl_pts(p[0], p[1], 2.55, rim_z + 2.0, 1.7, 0.2))

for nm, my in (("Mic U4 (+Y)", micA_y), ("Mic U5 (-Y)", micB_y)):
    lo_y, hi_y = (my, out_y1 + 3) if my > 0 else (out_y0 - 3, my)
    check(f"Schallweg {nm}", tray,
          box_pts([mic_x - 2.5, lo_y, z_batt_top + 0.15], [mic_x + 2.5, hi_y, -0.50], 0.2))

print("=" * 118)
bad = [r for r in results if not r[0]]
print(f"ERGEBNIS: {len(results)-len(bad)}/{len(results)} Checks bestanden" +
      ("" if not bad else "  ->  FEHLER: " + ", ".join(b[1] for b in bad)))
