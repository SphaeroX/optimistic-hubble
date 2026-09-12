"""Definitive hole detection: ray-cast point-in-solid test on the PCB slab.

Board component = the 22.63 x 36.97 x 1.6 mm slab. Points tested at z where only the
board exists (z=0.8). A point inside solid => board material; outside => hole.
"""
import json
import numpy as np
from PIL import Image

T = np.load("tri.npy")            # (n,3,3)
lab = np.load("labels.npy")       # (n,)
comps = json.load(open("components.json"))

# board component id: size x>20 and z<2
board_id = max((int(k) for k, v in comps.items() if v["size"][2] < 2.0 and v["size"][0] > 20),
               key=lambda k: comps[str(k)]["size"][0] * comps[str(k)]["size"][1])
comps = {int(k): v for k, v in comps.items()}
BT = T[lab == board_id]
print("board id", board_id, comps[board_id], "tris", len(BT))
mn = np.array(comps[board_id]["min"]); mx = np.array(comps[board_id]["max"])

D = np.array([0.311, 0.927, 0.207]); D /= np.linalg.norm(D)


def inside(pts):
    """pts (N,3) -> bool inside-solid via parity of ray hits with board triangles."""
    p0, e1, e2 = BT[:, 0], BT[:, 1] - BT[:, 0], BT[:, 2] - BT[:, 0]
    out = np.zeros(len(pts), bool)
    for i in range(0, len(pts), 4000):
        P = pts[i:i + 4000]
        h = np.cross(D, e2)                       # (nT,3)
        a = np.einsum("ij,ij->i", e1, h)
        ok = np.abs(a) > 1e-12
        f = np.where(ok, 1.0 / np.where(ok, a, 1.0), 0.0)
        s = P[:, None, :] - p0[None, :, :]        # (N,nT,3)
        u = f[None, :] * (s * h[None, :, :]).sum(2)
        q = np.cross(s, e1[None, :, :])
        v = f[None, :] * (q * D[None, None, :]).sum(2)
        t = f[None, :] * (q * e2[None, :, :]).sum(2)
        hit = ok[None, :] & (u >= -1e-9) & (v >= -1e-9) & (u + v <= 1 + 1e-9) & (t > 1e-9)
        out[i:i + 4000] = (hit.sum(axis=1) % 2) == 1
    return out


def grid(x0, x1, y0, y1, res, z):
    xs = np.arange(x0, x1, res); ys = np.arange(y0, y1, res)
    X, Y = np.meshgrid(xs, ys)
    P = np.stack([X.ravel(), Y.ravel(), np.full(X.size, z)], 1)
    return xs, ys, P


def report(name, xs, ys, ins, res):
    img = ins.reshape(len(ys), len(xs))
    print(f"\n=== {name}: {img.sum()} solid cells of {img.size} ({100*img.mean():.1f}%)")
    # interior empty regions (holes)
    holes = ~img
    # flood from border to mark outside
    from collections import deque
    ny, nx = img.shape
    outside = np.zeros_like(holes); dq = deque()
    for x in range(nx):
        for y in (0, ny - 1):
            if holes[y, x] and not outside[y, x]: outside[y, x] = True; dq.append((y, x))
    for y in range(ny):
        for x in (0, nx - 1):
            if holes[y, x] and not outside[y, x]: outside[y, x] = True; dq.append((y, x))
    while dq:
        y, x = dq.popleft()
        for dy, dx in ((1,0),(-1,0),(0,1),(0,-1)):
            yy, xx = y+dy, x+dx
            if 0 <= yy < ny and 0 <= xx < nx and holes[yy,xx] and not outside[yy,xx]:
                outside[yy,xx] = True; dq.append((yy,xx))
    inner = holes & ~outside
    seen = np.zeros_like(inner); regions = []
    ys_i, xs_i = np.nonzero(inner)
    for y0, x0 in zip(ys_i, xs_i):
        if seen[y0, x0]: continue
        dq = deque([(y0, x0)]); seen[y0, x0] = True; cells = []
        while dq:
            y, x = dq.popleft(); cells.append((y, x))
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    yy, xx = y+dy, x+dx
                    if 0 <= yy < ny and 0 <= xx < nx and inner[yy,xx] and not seen[yy,xx]:
                        seen[yy,xx] = True; dq.append((yy,xx))
        cy = np.array([c[0] for c in cells]); cx = np.array([c[1] for c in cells])
        X = xs[cx]; Y = ys[cy]
        regions.append(dict(area=len(cells)*res*res, cx=float(X.mean()), cy=float(Y.mean()),
                            dx=float(X.max()-X.min()), dy=float(Y.max()-Y.min()),
                            x0=float(X.min()), x1=float(X.max()), y0=float(Y.min()), y1=float(Y.max())))
    regions.sort(key=lambda r: -r["area"])
    for r in regions:
        print(f"  area={r['area']:7.3f}mm2  d=({r['dx']:.2f}x{r['dy']:.2f})  center=({r['cx']:.2f},{r['cy']:.2f})  bbox x[{r['x0']:.2f},{r['x1']:.2f}] y[{r['y0']:.2f},{r['y1']:.2f}]")
    # png: white = solid, red = hole through
    rgb = np.zeros((ny, nx, 3), np.uint8); rgb[img] = (255, 255, 255)
    rgb[inner] = (255, 0, 0); rgb[~img & ~inner] = (40, 40, 90)
    Image.fromarray(rgb[::-1]).resize((nx*2, ny*2), Image.NEAREST).save(f"holes_{name}.png")
    return regions


# 1) whole board at z=0.8 (mid-slab) - full hole map
res = 0.05
xs, ys, P = grid(mn[0], mx[0] + res, mn[1], mx[1] + res, res, 0.8)
print("points:", len(P))
inside_board = inside(P)
regs = report("board_z0.8", xs, ys, inside_board, res)
json.dump(regs, open("holes_board.json", "w"), indent=1)

# 2) high-res around each mic  (mic ports)
mics = dict(micA=(5.495, 23.83), micB=(5.495, -7.54))
for nm, (cx, cy) in mics.items():
    xs2, ys2, P2 = grid(cx - 3, cx + 3, cy - 3, cy + 3, 0.03, 0.8)
    ins2 = inside(P2)
    report(nm, xs2, ys2, ins2, 0.03)
