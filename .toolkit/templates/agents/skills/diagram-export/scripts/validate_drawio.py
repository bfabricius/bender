"""Prüft ein .drawio-Diagramm auf Struktur- und Lesbarkeitsprobleme.

Aufruf: python validate_drawio.py <diagramm.drawio>
Exit-Code 1 bei Fehlern (kaputtes XML, fehlende Referenzen), Warnungen beeinflussen ihn nicht.

Geprüft: XML wohlgeformt · eindeutige IDs · parent/source/target existieren · Geometrie vorhanden ·
Geschwister überlappen nicht · Kinder liegen innerhalb des Containers · Labels knapp (<= 60 Zeichen) ·
Kanten an Containern ohne Ankerpunkte (Hinweis auf mögliche Schrägverläufe).
"""
import html
import re
import sys
import xml.etree.ElementTree as ET


def plain(value):
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", value or ""))).strip()


def main(path):
    errors, warnings = [], []
    try:
        tree = ET.parse(path)
    except ET.ParseError as ex:
        print(f"FEHLER: XML nicht wohlgeformt: {ex}")
        return 1

    cells = {}
    for c in tree.getroot().iter("mxCell"):
        cid = c.get("id")
        if cid in cells:
            errors.append(f"Doppelte ID: {cid}")
        cells[cid] = c

    geo = {}
    for cid, c in cells.items():
        p = c.get("parent")
        if p is not None and p not in cells:
            errors.append(f"{cid}: parent '{p}' existiert nicht")
        if c.get("edge") == "1":
            for end in ("source", "target"):
                if not c.get(end):
                    warnings.append(f"Kante {cid}: kein {end} (lose Kante)")
                elif c.get(end) not in cells:
                    errors.append(f"Kante {cid}: {end} '{c.get(end)}' existiert nicht")
        elif c.get("vertex") == "1":
            g = c.find("mxGeometry")
            if g is None or g.get("width") is None:
                errors.append(f"{cid}: Geometrie fehlt")
                continue
            geo[cid] = tuple(float(g.get(k, 0)) for k in ("x", "y", "width", "height"))
            label = plain(c.get("value"))
            if len(label) > 60 and not (c.get("style") or "").startswith("text"):
                warnings.append(f"{cid}: Label lang ({len(label)} Zeichen) – kürzen: '{label[:40]}…'")

    siblings = {}
    for cid in geo:
        siblings.setdefault(cells[cid].get("parent"), []).append(cid)
    for parent, ids in siblings.items():
        for i, a in enumerate(ids):
            ax, ay, aw, ah = geo[a]
            for b in ids[i + 1:]:
                bx, by, bw, bh = geo[b]
                if ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah:
                    warnings.append(f"Überlappung: {a} <-> {b} (parent {parent})")
            if parent in geo:
                _, _, pw, ph = geo[parent]
                if ax < 0 or ay < 0 or ax + aw > pw or ay + ah > ph:
                    warnings.append(f"{a} ragt aus Container {parent} heraus")

    containers = {c.get("parent") for c in cells.values() if c.get("vertex") == "1"}
    for cid, c in cells.items():
        if c.get("edge") == "1" and "exitX" not in (c.get("style") or ""):
            if c.get("source") in containers or c.get("target") in containers:
                warnings.append(f"Kante {cid}: Container-Anschluss ohne exit/entry – Verlauf prüfen")

    for e in errors:
        print("FEHLER:", e)
    for w in warnings:
        print("WARNUNG:", w)
    n_v = sum(1 for c in cells.values() if c.get("vertex") == "1")
    n_e = sum(1 for c in cells.values() if c.get("edge") == "1")
    print(f"{'OK' if not errors else 'FEHLGESCHLAGEN'}: {n_v} Knoten, {n_e} Kanten, "
          f"{len(errors)} Fehler, {len(warnings)} Warnungen")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
