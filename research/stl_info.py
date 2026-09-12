"""Parse binary STL: bbox, size, and a coarse occupancy grid to understand the shape."""
import struct, sys, math
import numpy as np

PATH = r"C:\Users\MGasc\Documents\antigravity\optimistic-hubble\research\3D_PCB1_2026-09-08.stl"

with open(PATH, "rb") as f:
    header = f.read(80)
    (n) = struct.unpack("<I", f.read(4))[0]
    raw = f.read(n * 50)
print("header:", header[:40])
print("triangles:", n, "expected bytes:", n * 50, "got:", len(raw))

dt = np.dtype([("n", "<f4", 3), ("v", "<f4", (3, 3)), ("attr", "<u2")])
arr = np.frombuffer(raw, dtype=dt)
V = arr["v"].reshape(-1, 3).astype(np.float64)
mn, mx = V.min(axis=0), V.max(axis=0)
print("bbox min:", np.round(mn, 3))
print("bbox max:", np.round(mx, 3))
print("size XYZ:", np.round(mx - mn, 3))

np.save("verts.npy", V)

# occupancy: which volume is filled? use triangle centroid z-histogram in XY slices
# count vertices per z-band
for zlo in np.arange(math.floor(mn[2]), mx[2], 2.0):
    band = V[(V[:, 2] >= zlo) & (V[:, 2] < zlo + 2.0)]
    if len(band):
        print(f"z {zlo:6.1f}..{zlo+2.0:6.1f}: {len(band):8d} verts  x[{band[:,0].min():7.2f},{band[:,0].max():7.2f}] y[{band[:,1].min():7.2f},{band[:,1].max():7.2f}]")
