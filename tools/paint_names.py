#!/usr/bin/env python3
"""Writes Ravenna's paint names from their one source, docs/paint-names.json (issue #16).

    tools/paint_names.py

Each entry is a material: its name, its colour (sRGB hex), its kind (stone, pigment or glass),
what it is, its citation and link (shown in Settings › Acknowledgements), the quote that backs
it, the source's confidence and how its colour was read. This writes, in the JSON's order:

- Sources/MosaicCore/PaintNamesTable.swift: `PaintNames.table`, the names PaintCore's draw reads
  (frozen once shipped: its order takes part in the draw), and `PaintNames.credits`;
- docs/paint-names.md below its marker line, the list with quotes (the prose above it is kept).

PaintNamesTests fails when the Swift differs from the JSON.
"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "docs", "paint-names.json")
SWIFT = os.path.join(ROOT, "Sources", "MosaicCore", "PaintNamesTable.swift")
DOC = os.path.join(ROOT, "docs", "paint-names.md")
MARKER = "<!-- The list below is written by tools/paint_names.py from docs/paint-names.json. -->"
KINDS = {
    "stone": "Stones, marbles and gems",
    "pigment": "Pigments and painting materials",
    "glass": "Glass, metals, ceramics and the mosaicist's other materials",
}


def swift_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    entries = json.load(open(SOURCE, encoding="utf-8"))
    for e in entries:
        assert e["kind"] in KINDS, e["name"]
        assert len(e["hex"]) == 6 and e["hex"] == e["hex"].upper(), e["name"]

    lines = [
        "// Written by tools/paint_names.py from docs/paint-names.json: edit the JSON and run it.",
        "",
        "extension PaintNames {",
        '    public static let table = """',
    ]
    lines += [f"    {e['hex']} {e['name']}" for e in entries]
    lines += ['    """', "", "    public static let credits: [Credit] = ["]
    for e in entries:
        link = swift_string(e["link"]) if e.get("link") else "nil"
        lines.append(
            f"        Credit(name: {swift_string(e['name'])}, hex: 0x{e['hex']}, kind: .{e['kind']},\n"
            f"               what: {swift_string(e['what'])},\n"
            f"               citation: {swift_string(e['citation'])},\n"
            f"               link: {link}),")
    lines += ["    ]", "}", ""]
    open(SWIFT, "w", encoding="utf-8").write("\n".join(lines))

    doc = open(DOC, encoding="utf-8").read()
    head = doc.split(MARKER)[0].rstrip() + "\n\n" + MARKER + "\n"
    body = ""
    for kind, title in KINDS.items():
        body += f"\n## {title}\n\n"
        for e in entries:
            if e["kind"] != kind:
                continue
            link = f" <{e['link']}>" if e.get("link") else ""
            body += (f"- **{e['name']}** `#{e['hex']}`: {e['what'].rstrip('.')}. Source: {e['citation']}{link}"
                     f" ({e['confidence']}): {e['quote'].strip()} Colour: {e['colour'].rstrip('.')}.\n")
    open(DOC, "w", encoding="utf-8").write(head + body)
    print(f"{len(entries)} names")


if __name__ == "__main__":
    main()
