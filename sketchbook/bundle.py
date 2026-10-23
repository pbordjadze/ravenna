"""bundle.py <catalog.json> <work dir> <out dir>: the app's bundled mosaics, from public-domain works in the
Met's Open Access collection. For each work: the Met's image and record (medium, accession, credit), the
picture at 724, 1024 and 1448 px (the detail option's Fewer, Standard and More pieces), its contours
(paint-by-number's HED, through hed.py), its face's features (features.py, for faces), the tight set
(mosaic_faces.py, GROUT=2 TIGHT=1), and B's painted bed. Writes to <out dir>: <id>-<detail>.json (the
design in Standard's canvas units: "size", "grout", "palette" as sRGB 0...1, "tiles" each {"c": flat
corners, "p": paint, "s": 1 when stone (inside the face)}), <id>-bed.jpg, <id>-photo.jpg and catalog.json.
Run from the scratch directory that holds venv/, pbn/ (paint-by-number) and models/face_landmarker.task."""
import json, os, subprocess, sys, urllib.request
from PIL import Image

catalog, work, out = sys.argv[1:4]
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
PY = ["venv/bin/python", "-I"]
DETAILS = {"fewer": 724, "standard": 1024, "more": 1448}
os.makedirs(work, exist_ok=True); os.makedirs(out, exist_ok=True)
spec = json.load(open(catalog))
entries = []
for m in spec["mosaics"]:
    i = m["id"]
    rec = json.load(urllib.request.urlopen(f"https://collectionapi.metmuseum.org/public/collection/v1/objects/{m['met']}"))
    assert rec["isPublicDomain"], f"{i}: not public domain"
    src = f"{work}/{i}.jpg"
    if not os.path.exists(src): urllib.request.urlretrieve(rec["primaryImage"], src)
    im = Image.open(src).convert("RGB")
    std = None
    counts = {}
    for detail, side in DETAILS.items():
        k = side / max(im.size); ppm = f"{work}/{i}-{side}.ppm"
        im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS).save(ppm)
        if side == 1024:
            std = (round(im.width * k), round(im.height * k))
            subprocess.run(PY + [f"{HERE}/hed.py", "pbn/tools/models/convert_hed.py", "--map", ppm, f"{work}/{i}-contours.pgm"], check=True, capture_output=True)
    env = dict(os.environ, FINE="17", CUT_FINE="0.45", GROUT="2", TIGHT="1")
    box = None
    for detail, side in DETAILS.items():
        e = dict(env)
        if m["face"]:
            subprocess.run(PY + [f"{HERE}/features.py", f"{work}/{i}-{side}.ppm", "models/face_landmarker.task", f"{work}/{i}-{side}-features.json"], check=True, capture_output=True)
            e["FEATURES"] = f"{work}/{i}-{side}-features.json"
        r = subprocess.run(PY + [f"{ROOT}/prototype/mosaic_faces.py", f"{work}/{i}-{side}.ppm", f"{work}/{i}-contours.pgm", f"{work}/{i}-{side}", "30", "18", "0.72"], env=e, check=True, capture_output=True, text=True)
        print(i, detail, r.stdout.strip())
        d = json.load(open(f"{work}/{i}-{side}.json"))
        k = std[0] / (d["size"][0] / d["scale"])
        if m["face"]:
            bx = json.load(open(f"{work}/{i}-{side}-features.json"))["box"]
            if side == 1024: box = bx
        tiles = []
        for t in d["tiles"]:
            c = [round(v * k, 1) for xy in t["corners"] for v in xy]
            tile = {"c": c, "p": t["paint"]}
            if m["face"]:
                cx = sum(t["corners"][j][0] for j in range(len(t["corners"]))) / len(t["corners"])
                cy = sum(t["corners"][j][1] for j in range(len(t["corners"]))) / len(t["corners"])
                if bx[0] <= cx <= bx[2] and bx[1] <= cy <= bx[3]: tile["s"] = 1
            tiles.append(tile)
        counts[detail] = len(tiles)
        json.dump({"size": list(std), "grout": d["grout"], "palette": d["palette"], "tiles": tiles},
                  open(f"{out}/{i}-{detail}.json", "w"), separators=(",", ":"))
        if side == 1024:
            subprocess.run(PY + [f"{HERE}/render.py", f"{work}/{i}-1024.json", f"{work}/{i}-1024.ppm", "bed", f"{work}/{i}-bed.png"], check=True)
            bed = Image.open(f"{work}/{i}-bed.png").convert("RGB").resize(std, Image.LANCZOS)
            bed.save(f"{out}/{i}-bed.jpg", quality=82)
            ph = Image.open(f"{work}/{i}-1024.ppm"); ph.save(f"{out}/{i}-photo.jpg", quality=85)
    entries.append({"id": i, "title": m["title"], "date": m["date"], "place": m["place"],
                    "medium": rec["medium"], "credit": f"The Metropolitan Museum of Art, {rec['creditLine']} ({rec['accessionNumber']}). Public domain.",
                    "url": rec["objectURL"], "tiles": counts})
json.dump({"mosaics": entries}, open(f"{out}/catalog.json", "w"), indent=1, ensure_ascii=False)
