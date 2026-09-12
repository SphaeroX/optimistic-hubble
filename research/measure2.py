"""Exact outline measurements: board footprint, USB-C front face + mouth opening."""
import json
import numpy as np
from PIL import Image

T = np.load("tri.npy"); lab = np.load("labels.npy")
comps = {int(k): v for k, v in json.load(open("components.json")).items()}

# ---------- 1. board outline from solid bitmap (measure.py already computed the grid)
# recompute cheaply from board triangles: rasterize XY footprint of vertical side walls
bt = T[lab == 3]
pts = bt.reshape(-1, 3)
res = 0.05
x0, x1, y0, y1 = -12.814, 9.811, -11.079, 25.895
nx = int((x1 - x0) / res) + 2; ny = int((y1 - y0) / res) + 2
img = np.zeros((ny, nx), bool)
# side-wall triangles = ones that are vertical (normal ~horizontal) -> use all board tris whose
# 3 verts span z and are thin in XY: simply rasterize all triangles densely
p0, p1, p2 = bt[:, 0], bt[:, 1], bt[:, 2]
ar = 0.5 * np.linalg.norm(np.cross(p1 - p0, p2 - p0), axis=1)
cnt = np.maximum(1, np.round(ar * 2000).astype(int))
idx = np.repeat(np.arange(len(bt)), cnt)
s = np.random.rand(len(idx), 2); fl = s.sum(1) > 1; s[fl] = 1 - s[fl]
w0 = 1 - s[:, 0] - s[:, 1]; w1 = s[:, 0]; w2 = s[:, 1]
P = p0[idx] * w0[:, None] + p1[idx] * w1[:, None] + p2[idx] * w2[:, None]
gx = ((P[:, 0] - x0) / res).astype(int); gy = ((P[:, 1] - y0) / res).astype(int)
img[gy, gx] = True
print("footprint rows:", img.shape, "filled", img.sum())
prof = []
for j in range(ny):
    w = np.nonzero(img[j])[0]
    if len(w):
        prof.append((y0 + j * res, x0 + w.min() * res, x0 + w.max() * res))
prof = np.array(prof)
print("\nboard outline profile (y : xmin..xmax) every 1mm:")
for i in range(0, len(prof), 20):
    print(f"  y={prof[i,0]:7.2f}  x {prof[i,1]:8.3f} .. {prof[i,2]:7.3f}")
print("\nfirst 6 / last 6 rows:")
print(prof[:6]); print(prof[-6:])
xm, xM = prof[:, 1].min(), prof[:, 2].max()
print("xmin", xm, "xmax", xM)
# corner radius estimate: distance from corner where profile reaches full width
for lbl, yend in (("bottom(-Y)", prof[0, 0]), ("top(+Y)", prof[-1, 0])):
    rows = prof[np.abs(prof[:, 0] - yend) < 1.6]
    print(lbl, "rows within 1.6mm of the end:")
    for r in rows[::4]:
        print(f"    y={r[0]:7.2f} xmin_dev={r[1]-xm:6.3f} xmax_dev={xM-r[2]:6.3f}")

# ---------- 2. USB-C connector front face and mouth
cid = max((k for k, v in comps.items() if abs(v["size"][0] - 8.94) < 0.2 and v["size"][2] > 4),
          key=lambda k: comps[k]["size"][0])
print("\nUSB-C component id", cid, comps[cid])
ct = T[lab == cid]
cn = ct.reshape(-1, 3)
print("USB-C bbox", cn.min(0).round(3), cn.max(0).round(3))
yfront = cn[:, 1].min()
print("front plane y =", round(yfront, 3))
sel = ct[np.all(np.abs(ct[:, :, 1] - yfront) < 0.02, axis=1)]
print("front-plane triangles:", len(sel))
# rasterize the front face in (x,z)
res2 = 0.02
qx0, qx1 = -12.2, -2.9
qz0, qz1 = 1.5, 4.9
nqx = int((qx1 - qx0) / res2) + 2; nqz = int((qz1 - qz0) / res2) + 2
face = np.zeros((nqz, nqx), bool)
if len(sel):
    a0, a1, a2 = sel[:, 0], sel[:, 1], sel[:, 2]
    ars = 0.5 * np.linalg.norm(np.cross(a1 - a0, a2 - a0), axis=1)
    c2 = np.maximum(1, np.round(ars * 6000).astype(int))
    id2 = np.repeat(np.arange(len(sel)), c2)
    s2 = np.random.rand(len(id2), 2); f2 = s2.sum(1) > 1; s2[f2] = 1 - s2[f2]
    u0 = 1 - s2[:, 0] - s2[:, 1]; u1 = s2[:, 0]; u2 = s2[:, 1]
    Q = a0[id2] * u0[:, None] + a1[id2] * u1[:, None] + a2[id2] * u2[:, None]
    ix = ((Q[:, 0] - qx0) / res2).astype(int); iz = ((Q[:, 2] - qz0) / res2).astype(int)
    face[iz, ix] = True
    Image.fromarray((face[::-1] * 255).astype(np.uint8)).resize((nqx * 4, nqz * 4), Image.NEAREST).save("usb_face.png")
    # interior empty = mouth
    from collections import deque
    empty = ~face
    outside = np.zeros_like(empty); dq = deque()
    for i in range(nqx):
        for j in (0, nqz - 1):
            if empty[j, i]: outside[j, i] = True; dq.append((j, i))
    for j in range(nqz):
        for i in (0, nqx - 1):
            if empty[j, i]: outside[j, i] = True; dq.append((j, i))
    while dq:
        j, i = dq.popleft()
        for dj, di in ((1,0),(-1,0),(0,1),(0,-1)):
            jj, ii = j+dj, i+di
            if 0 <= jj < nqz and 0 <= ii < nqx and empty[jj,ii] and not outside[jj,ii]:
                outside[jj,ii] = True; dq.append((jj,ii))
    inner = empty & ~outside
    print("mouth pixels:", inner.sum(), "area mm2", round(inner.sum()*res2*res2, 3))
    if inner.sum():
        jz, ix2 = np.nonzero(inner)
        X = ix2 * res2 + qx0; Z = jz * res2 + qz0
        print(f"mouth  x {X.min():.3f}..{X.max():.3f} (w={X.max()-X.min():.3f})   z {Z.min():.3f}..{Z.max():.3f} (h={Z.max()-Z.min():.3f})")
        print(f"mouth center x={X.mean():.3f} z={Z.mean():.3f}")
else:
    print("no front-plane tris (front face may be inclined)")
