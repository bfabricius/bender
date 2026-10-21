"""Gibt Struktur und Text einer .pptx- oder .xlsx-Datei aus (Quellanalyse fuer create-template).

Aufruf: python extract_source.py <datei.pptx|datei.xlsx> [--max-rows N]

Nur Standardbibliothek (zipfile + xml). .pptx: Text pro Folie (Absaetze, Tabellen, Notizen).
.xlsx: pro Blatt die nicht-leeren Zeilen (Zelladresse=Wert, Formeln als {=...}); --max-rows
begrenzt die Zeilen pro Blatt (Default 60).
"""
import re
import sys
import zipfile
from xml.etree import ElementTree as ET


def local(tag):
    return tag.rsplit("}", 1)[-1]


def numeric_key(name):
    return [int(t) if t.isdigit() else t for t in re.split(r"(\d+)", name)]


def paragraph_text(p):
    return "".join(el.text or "" for el in p.iter() if local(el.tag) == "t").strip()


def walk(el, out):
    """Absaetze und Tabellen in Dokumentreihenfolge sammeln."""
    tag = local(el.tag)
    if tag == "tbl":
        for tr in (c for c in el if local(c.tag) == "tr"):
            cells = []
            for tc in (c for c in tr if local(c.tag) == "tc"):
                texts = (paragraph_text(p) for p in tc.iter() if local(p.tag) == "p")
                cells.append(" / ".join(t for t in texts if t))
            out.append("  | " + " | ".join(cells))
        return
    if tag == "p":
        text = paragraph_text(el)
        if text:
            out.append(text)
        return
    for child in el:
        walk(child, out)


def read_xml(zf, name):
    return ET.fromstring(zf.read(name))


def extract_pptx(zf):
    slides = sorted(
        (n for n in zf.namelist() if re.fullmatch(r"ppt/slides/slide\d+\.xml", n)), key=numeric_key
    )
    for i, name in enumerate(slides, 1):
        print(f"=== Folie {i} ===")
        lines = []
        walk(read_xml(zf, name), lines)
        print("\n".join(lines) if lines else "(kein Text)")
        notes = f"ppt/notesSlides/notesSlide{name.rsplit('slide', 1)[-1]}"
        if notes in zf.namelist():
            note_lines = []
            walk(read_xml(zf, notes), note_lines)
            note_lines = [l for l in note_lines if not l.isdigit()]
            if note_lines:
                print("-- Notizen --")
                print("\n".join(note_lines))
        print()
    if not slides:
        print("Keine Folien gefunden.")


def extract_xlsx(zf, max_rows):
    shared = []
    if "xl/sharedStrings.xml" in zf.namelist():
        for si in read_xml(zf, "xl/sharedStrings.xml"):
            shared.append("".join(t.text or "" for t in si.iter() if local(t.tag) == "t"))

    rels = {}
    if "xl/_rels/workbook.xml.rels" in zf.namelist():
        for rel in read_xml(zf, "xl/_rels/workbook.xml.rels"):
            rels[rel.get("Id")] = rel.get("Target")

    workbook = read_xml(zf, "xl/workbook.xml")
    for sheet in (e for e in workbook.iter() if local(e.tag) == "sheet"):
        rid = next((v for k, v in sheet.attrib.items() if local(k) == "id"), None)
        target = rels.get(rid, "")
        path = target.lstrip("/") if target.startswith("/") else "xl/" + target
        print(f"=== Blatt: {sheet.get('name')} ===")
        if path not in zf.namelist():
            print("(Blattdaten nicht gefunden)\n")
            continue
        shown = 0
        for row in (e for e in read_xml(zf, path).iter() if local(e.tag) == "row"):
            cells = []
            for c in (e for e in row if local(e.tag) == "c"):
                v = next((e for e in c if local(e.tag) == "v"), None)
                f = next((e for e in c if local(e.tag) == "f"), None)
                inline = "".join(t.text or "" for t in c.iter() if local(t.tag) == "t")
                if c.get("t") == "s" and v is not None and v.text is not None:
                    value = shared[int(v.text)]
                elif inline:
                    value = inline
                else:
                    value = v.text if v is not None and v.text is not None else ""
                if f is not None:
                    value = f"{value} {{={f.text or '...'}}}".strip()
                if value != "":
                    cells.append(f"{c.get('r')}={value}")
            if cells:
                print(" | ".join(cells))
                shown += 1
                if shown >= max_rows:
                    print(f"... (auf {max_rows} Zeilen gekuerzt)")
                    break
        if shown == 0:
            print("(leer)")
        print()


def main(argv):
    sys.stdout.reconfigure(encoding="utf-8")
    max_rows = 60
    if "--max-rows" in argv:
        i = argv.index("--max-rows")
        max_rows = int(argv[i + 1])
        del argv[i : i + 2]
    if len(argv) != 1:
        sys.exit(__doc__)
    path = argv[0]
    ext = path.lower().rsplit(".", 1)[-1]
    if ext not in ("pptx", "xlsx"):
        sys.exit(f"Nicht unterstuetztes Format: .{ext} (erwartet .pptx oder .xlsx)")
    with zipfile.ZipFile(path) as zf:
        if ext == "pptx":
            extract_pptx(zf)
        else:
            extract_xlsx(zf, max_rows)


if __name__ == "__main__":
    main(sys.argv[1:])
