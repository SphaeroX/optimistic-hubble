"""Wand-Integritaet: Scan der Wand-Mittenflaechen der fertigen Teile.
Jeder Punkt in der Wandmitte MUSS im Material liegen - ausser in einer gewollten
Oeffnung (USB-Aussparung, 2 Schallschlitze, LED-Fenster).
"""
import os
import numpy as np
import trimesh

WD = r"C:\Users\MGasc\Documents\antigravity\optimistic-hubble\research\enclosure"
exec(open(os.path.join(WD, "check_collision.py")).read().split("results = []")[0])

tray = trimesh.load(os.path.join(WD, globals().get("tray_name", "tray.stl")), process=True)
lid  = trimesh.load(os.path.join(WD, "lid.stl"), process=True)
good = True


def scan(name, mesh, pts, expected, res=0.15):
    global good
    ins = inside(mesh, pts)
    holes = pts[~ins]
    if len(holes) == 0:
        print(f"OK  | {name:34s} | geschlossen")
        return
    used = np.zeros(len(holes), bool)
    regs = []
    for i in range(len(holes)):
        if used[i]:
            continue
        stack = [i]; used[i] = True; grp = []
        while stack:
            j = stack.pop(); grp.append(j)
            nb = np.nonzero((np.abs(holes - holes[j]).max(1) < 1.0) & ~used)[0]
            used[nb] = True; stack.extend(nb.tolist())
        g = holes[grp]
        regs.append((len(grp), g.min(0), g.max(0), g.mean(0)))
    regs.sort(key=lambda r: -r[0])
    for n, lo, hi, c in regs:
        exp = any(abs(c[0]-e[0]) <= e[3] and abs(c[1]-e[1]) <= e[3] and abs(c[2]-e[2]) <= e[3] for e in expected)
        print(f"{'OK ' if exp else 'FEHLER'} | {name:34s} | Oeffnung {n:5d} Punkte bbox {np.round(hi-lo,2).tolist()} "
              f"Mitte {np.round(c,2).tolist()} {'gewollt' if exp else '<<< UNGEWOLLT'}")
        good &= exp


res = 0.15
ym0, ym1 = (out_y0 + inn_y0) / 2, (out_y1 + inn_y1) / 2
xm0, xm1 = (out_x0 + inn_x0) / 2, (out_x1 + inn_x1) / 2
zs = np.arange(z_tray_bot + 0.06, rim_z - 0.06, res)

# Ecken sind gewollt abgefast (corner_ch) -> als erwartete "Oeffnungen" freigeben
zmid = (z_tray_bot + rim_z) / 2
corners_y = lambda ymid: [(cx, ymid, zmid, 4.0) for cx in (out_x0 + 0.6, out_x1 - 0.6)]
corners_x = lambda xmid: [(xmid, cy, zmid, 4.0) for cy in (out_y0 + 0.6, out_y1 - 0.6)]
for nm, ymid in (("-Y (USB-Ende)", ym0), ("+Y (Hand-Ende)", ym1)):
    X, Z = np.meshgrid(np.arange(out_x0 + 0.1, out_x1 - 0.1, res), zs)
    scan(f"Tray Wand {nm}", tray, np.c_[X.ravel(), np.full(X.size, ymid), Z.ravel()],
         [(-7.557, ymid, 3.17, 6.5), (mic_x, ymid, -1.0, 1.5)] + corners_y(ymid), res)

for nm, xmid in (("-X", xm0), ("+X", xm1)):
    Y, Z = np.meshgrid(np.arange(out_y0 + 0.1, out_y1 - 0.1, res), zs)
    scan(f"Tray Wand {nm}", tray, np.c_[np.full(Y.size, xmid), Y.ravel(), Z.ravel()],
         corners_x(xmid), res)

zm = (z_pocket_fl + z_tray_bot) / 2
X, Y = np.meshgrid(np.arange(out_x0 + 0.1, out_x1 - 0.1, 0.3), np.arange(out_y0 + 0.1, out_y1 - 0.1, 0.3))
scan("Tray Boden (ueber Bandkanal)", tray, np.c_[X.ravel(), Y.ravel(), np.full(X.size, zm)],
     [(x, y, zm, 4.0) for x in (out_x0 + 0.6, out_x1 - 0.6) for y in (out_y0 + 0.6, out_y1 - 0.6)], 0.3)

zp = rim_z + lid_t * 0.5
X, Y = np.meshgrid(np.arange(out_x0 + 0.1, out_x1 - 0.1, 0.25), np.arange(out_y0 + 0.1, out_y1 - 0.1, 0.25))
scan("Deckelplatte (Mittenebene)", lid, np.c_[X.ravel(), Y.ravel(), np.full(X.size, zp)],
     [(led1[0], (led_win_y0 + led_win_y1) / 2, zp, 1.5)])

zant = rim_z + lid_t - ant_recess - 0.40   # INNERHALB der Restwand unter der Eindrehung
X, Y = np.meshgrid(np.arange(-10.3, 3.3, 0.3), np.arange(-2.3, 4.8, 0.3))
scan("Deckel ueber Antenne (Restwand)", lid, np.c_[X.ravel(), Y.ravel(), np.full(X.size, zant)], [])

print("=" * 100)
print("WAND-INTEGRITAET:", "ALLES OK" if good else "FEHLER GEFUNDEN")
