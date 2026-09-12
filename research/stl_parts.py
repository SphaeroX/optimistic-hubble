"""Split STL into connected components (welded verts) -> bbox per component."""
import struct
import numpy as np
from collections import defaultdict

PATH = r"C:\Users\MGasc\Documents\antigravity\optimistic-hubble\research\3D_PCB1_2026-09-08.stl"
with open(PATH, "rb") as f:
    f.read(80)
    n = struct.unpack("<I", f.read(4))[0]
    raw = f.read(n * 50)
dt = np.dtype([("n", "<f4", 3), ("v", "<f4", (3, 3)), ("attr", "<u2")])
arr = np.frombuffer(raw, dtype=dt)
T = arr["v"].astype(np.float64)          # (n,3,3)

# weld vertices
V = T.reshape(-1, 3)
key = np.round(V * 1e3).astype(np.int64)  # 1 µm resolution
uniq, inv = np.unique(key, axis=0, return_inverse=True)
print("verts:", len(V), "welded:", len(uniq))
F = inv.reshape(-1, 3)                    # triangle -> vertex ids

# union-find
parent = np.arange(len(uniq))
def find(a):
    while parent[a] != a:
        parent[a] = parent[parent[a]]
        a = parent[a]
    return a
for f in F:
    a, b, c = find(f[0]), find(f[1]), find(f[2])
    if a != b: parent[b] = a
    if find(a) != c: parent[find(c)] = find(a)

roots = np.array([find(i) for i in range(len(uniq))])
comp_of_tri = roots[F[:, 0]]
comps = defaultdict(list)
for i, c in enumerate(comp_of_tri):
    comps[c].append(i)
print("components:", len(comps))

rows = []
for c, tris in comps.items():
    tv = T[np.array(tris)]                     # (m,3,3)
    pts = tv.reshape(-1, 3)
    mn, mx = pts.min(axis=0), pts.max(axis=0)
    size = mx - mn
    area = 0.0
    p0, p1, p2 = tv[:, 0], tv[:, 1], tv[:, 2]
    area = 0.5 * np.linalg.norm(np.cross(p1 - p0, p2 - p0), axis=1).sum()
    rows.append((len(tris), mn, mx, size, area, c))

rows.sort(key=lambda r: -r[2][2])  # by top z
print(f"\n{'tris':>6} {'min(x,y,z)':>26} {'max(x,y,z)':>26} {'size(x,y,z)':>24} {'area':>9}")
for num, mn, mx, size, area, c in rows:
    print(f"{num:6d} [{mn[0]:8.2f},{mn[1]:8.2f},{mn[2]:7.2f}] [{mx[0]:8.2f},{mx[1]:8.2f},{mx[2]:7.2f}] "
          f"[{size[0]:7.2f},{size[1]:7.2f},{size[2]:6.2f}] {area:9.2f}")

with open("components.txt", "w") as fh:
    fh.write(f"{'tris':>6} {'min':>26} {'max':>26} {'size':>24} {'area':>9}\n")
    for num, mn, mx, size, area, c in rows:
        fh.write(f"{num:6d} [{mn[0]:8.2f},{mn[1]:8.2f},{mn[2]:7.2f}] [{mx[0]:8.2f},{mx[1]:8.2f},{mx[2]:7.2f}] "
                 f"[{size[0]:7.2f},{size[1]:7.2f},{size[2]:6.2f}] {area:9.2f}\n")
np.save("tri.npy", T)
