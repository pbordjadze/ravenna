"""prep.py <marks.txt> <dir>: each photo at a 1024 px long side (the prototype's scale), and its marks
scaled to match, into <dir>/marks-1024.txt."""
import sys
from PIL import Image
out = []
for line in open(sys.argv[1]):
    n, box, eyes = line.strip().split("|")[:3]
    im = Image.open(f"{sys.argv[2]}/{n}.ppm"); k = 1024 / max(im.size)
    im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS).save(f"{sys.argv[2]}/{n}-1024.ppm")
    sc = lambda s: ";".join(",".join(f"{float(v) * k:.0f}" for v in m.split(",")) for m in s.split(";") if m)
    out.append(f"{n}|{sc(box)}|{sc(eyes)}")
open(f"{sys.argv[2]}/marks-1024.txt", "w").write("\n".join(out) + "\n")
