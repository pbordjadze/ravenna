"""icon.py <out.png>: Ravenna's provisional app icon, 1024 px: rows of dark lapis tesserae round a halo
of gold ones, as in an apse, and one gold tile catching the light as it is set."""
import sys, math
import numpy as np, cv2

N = 1024; S = 4  # drawn at 4x, then reduced
img = np.zeros((N * S, N * S, 3), np.float32)
img[:] = (0.10, 0.09, 0.075)  # the bed
rng = np.random.default_rng(547)
c = np.array([N / 2, N / 2]) * S
def ring(r, pitch, color, jitter, lit=None):
    n = max(int(2 * math.pi * r / pitch), 6)
    for k in range(n):
        a = 2 * math.pi * (k + 0.5 * (r // pitch % 2)) / n
        p = c + r * np.array([math.cos(a), math.sin(a)])
        t = np.array([-math.sin(a), math.cos(a)]); m = np.array([math.cos(a), math.sin(a)])
        h = (pitch - 7 * S) / 2
        poly = np.array([p + sx * h * t + sy * h * m for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))])
        col = np.clip(np.array(color) * (1 + jitter * rng.normal()), 0, 1)
        if lit is not None and k == lit: col = np.clip(col * 1.45 + 0.08, 0, 1)
        q = np.round(poly).astype(np.int32)
        cv2.fillPoly(img, [q], col.tolist(), lineType=cv2.LINE_AA)
        # A lit upper-left edge and a shaded lower-right one.
        cv2.line(img, tuple(q[0]), tuple(q[1]), (col * 1.25 + 0.03).clip(0, 1).tolist(), 2 * S, cv2.LINE_AA)
        cv2.line(img, tuple(q[2]), tuple(q[3]), (col * 0.7).tolist(), 2 * S, cv2.LINE_AA)
pitch = 44 * S
r = pitch * 0.6
while r < N * S * 0.75:
    if r < 230 * S: ring(r, pitch, (0.12, 0.16, 0.30), 0.06)          # lapis inside the halo
    elif r < 330 * S: ring(r, pitch, (0.80, 0.62, 0.25), 0.07, lit=3 if r < 290 * S else None)  # gold
    else: ring(r, pitch, (0.09, 0.11, 0.20), 0.06)                     # the dark of the apse
    r += pitch
out = cv2.resize(img, (N, N), interpolation=cv2.INTER_AREA)
cv2.imwrite(sys.argv[1], cv2.cvtColor((out * 255).astype(np.uint8), cv2.COLOR_RGB2BGR))
