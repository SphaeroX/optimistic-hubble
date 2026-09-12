"""Component split (saved to JSON) + hole detection in the PCB slab via top/bottom face coverage."""
import struct, json
import numpy as np
from collections import defaultdict

PATH = r"C:\Users\MGasc\Documents\antigravity\optimistic-hubble\research\3D_PCB1_2026-09-08.stl"
with open(PATH, "rb") as f:
    f.read(80); n = struct.unpack("<I", f.read(4))[0]; raw = f.read(n * 50)
dt = np.dtype([("n", "<f4", 3), ("v", "<f4", (3, 3)), ("attr", "<u2")])
T = np.frombuffer(raw, dtype=dt)["v"].astype(np.float64)
V = T.reshape(-1, 3)
key = np.round(V * 1e3).astype(np.int64)
uniq, inv = np.unique(key, axis=0, return_inverse=True)
F = inv.reshape(-1, 3)
parent = np.arange(len(uniq))
def find(a):
    while parent[a] != a:
        parent[a] = parent[parent[a]]; a = parent[a]
    return a
for f_ in F:
    a, b, c = find(f_[0]), find(f_[1]), find(f_[2])
    if a != b: parent[b] = a
    cc = find(c)
    if find(a) != cc: parent[cc] = find(a)
roots = np.array([find(i) for i in range(len(uniq))])
lab = roots[F[:, 0]]
np.save("labels.npy", lab)

comps = {}
for c in np.unique(lab):
    m = lab == c
    tv = T[m]; pts = tv.reshape(-1, 3)
    mn, mx = pts.min(0), pts.max(0)
    comps[int(c)] = dict(tris=int(m.sum()), min=mn.round(3).tolist(), max=mx.round(3).tolist(),
                         size=(mx - mn).round(3).tolist())
print("n comps", len(comps))
# the big flat board = largest XY bbox with z-size <= 2.0
board = max((k for k, v in comps.items() if v["size"][2] < 2.0 and v["size"][0] > 20),
            key=lambda k: comps[k]["size"][0] * comps[k]["size"][1])
print("board comp", board, comps[board])
json.dump(comps, open("components.json", "w"), indent=1)

# --- hole detection: rasterize top face (z~1.6) and bottom face (z~0) of board component
bt = T[lab == board]
for face, z0 in (("top", 1.60), ("bottom", 0.0)):
    sel = bt[np.all(np.abs(bt[:, :, 2] - z0) < 0.05, axis=1)]
    if not len(sel):
        print(face, "no flat tris"); continue
    print(f"\n{face} face: {len(sel)} tris")
    p0, p1, p2 = sel[:, 0], sel[:, 1], sel[:, 2]
    ar = 0.5 * np.abs((p1[:, 0] - p0[:, 0]) * (p2[:, 1] - p0[:, 1]) - (p2[:, 0] - p0[:, 0]) * (p1[:, 1] - p0[:, 1]))
    tot = ar.sum()
    dens = 400.0  # samples per mm^2
    cnt = np.maximum(1, np.round(ar * dens).astype(int))
    idx = np.repeat(np.arange(len(sel)), cnt)
    s = np.random.rand(len(idx), 2)
    flip = (s.sum(1) > 1); s[flip] = 1 - s[flip]
    w0 = 1 - s[:, 0] - s[:, 1]; w1 = s[:, 0]; w2 = s[:, 1]
    pts = (p0[idx] * w0[:, None] + p1[idx] * w1[:, None] + p2[idx] * w2[:, None])
    res = 0.05
    mn, mx = bt.reshape(-1, 3)[:, :2].min(0), bt.reshape(-1, 3)[:, :2].max(0)
    nx = int((mx[0] - mn[0]) / res) + 2; ny = int((mx[1] - mn[1]) / res) + 2
    gx = ((pts[:, 0] - mn[0]) / res).astype(int); gy = ((pts[:, 1] - mn[1]) / res).astype(int)
    img = np.zeros((ny, nx), bool); img[gy, gx] = True
    print(f"grid {nx}x{ny} filled {img.sum()} ({100*img.sum()/(nx*ny):.1f}%) area={tot:.1f}mm2")
    np.save(f"face_{face}.npy", img)
    # flood fill from outside -> interior unfilled = holes
    from collections import deque
    outside = np.zeros_like(img)
    dq = deque()
    for x in range(nx):
        for y in (0, ny - 1):
            if not img[y, x] and not outside[y, x]: outside[y, x] = True; dq.append((y, x))
    for y in range(ny):
        for x in (0, nx - 1):
            if not img[y, x] and not outside[y, x]: outside[y, x] = True; dq.append((y, x))
    while dq:
        y, x = dq.popleft()
        for dy, dx in ((1,0),(-1,0),(0,1),(0,-1)):
            yy, xx = y+dy, x+dx
            if 0 <= yy < ny and 0 <= xx < nx and not img[yy,xx] and not outside[yy,xx]:
                outside[yy,xx] = True; dq.append((yy,xx))
    holes = (~img) & (~outside)
    print(f"hole pixels: {holes.sum()}  -> {holes.sum()*res*res:.2f} mm2")
    seen = np.zeros_like(holes); regions = []
    ys, xs = np.nonzero(holes)
    for y0, x0 in zip(ys, xs):
        if seen[y0, x0]: continue
        dq = deque([(y0, x0)]); seen[y0, x0] = True; cells = []
        while dq:
            y, x = dq.popleft(); cells.append((y, x))
            for dy, dx in ((1,0),(-1,0),(0,1),(0,-1),(1,1),(1,-1),(-1,1),(-1,-1)):
                yy, xx = y+dy, x+dx
                if 0 <= yy < ny and 0 <= xx < nx and holes[yy,xx] and not seen[yy,xx]:
                    seen[yy,xx] = True; dq.append((yy,xx))
        cy = np.array([c[0] for c in cells]); cx = np.array([c[1] for c in cells])
        X = cx*res + mn[0]; Y = cy*res + mn[1]
        regions.append(dict(area=round(len(cells)*res*res, 3),
                            cx=round(X.mean(), 3), cy=round(Y.mean(), 3),
                            w=round(X.max()-X.min(), 3), h=round(Y.max()-Y.min(), 3)))
    regions.sort(key=lambda r: -r["area"])
    for r in regions[:40]:
        print(f"  hole area={r['area']:6.2f}mm2 bbox {r['w']:.2f}x{r['h']:.2f} center=({r['cx']:.2f},{r['cy']:.2f})")
