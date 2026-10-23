"""prep.py <marks.txt> <dir> [long side]: each photo at a long side of 1024 px (the prototype's scale) or
the one given, and its marks scaled to match, into <dir>/marks-<side>.txt. A larger side with the same
pitch lays more, smaller tiles: about (side / 1024)² times as many."""
import sys
from PIL import Image
side = int(sys.argv[3]) if len(sys.argv) > 3 else 1024
out = []
for line in open(sys.argv[1]):
    n, box, eyes = line.strip().split("|")[:3]
    im = Image.open(f"{sys.argv[2]}/{n}.ppm"); k = side / max(im.size)
    im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS).save(f"{sys.argv[2]}/{n}-{side}.ppm")
    sc = lambda s: ";".join(",".join(f"{float(v) * k:.0f}" for v in m.split(",")) for m in s.split(";") if m)
    out.append(f"{n}|{sc(box)}|{sc(eyes)}")
open(f"{sys.argv[2]}/marks-{side}.txt", "w").write("\n".join(out) + "\n")
