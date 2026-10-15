"""Erzeugt ein professionell formatiertes draw.io-Diagramm (.drawio) aus einer kompakten JSON-Spec.

Aufruf: python build_drawio.py <spec.json> <ausgabe.drawio> [--force]

Spec-Format (alle Koordinaten in px, Kinder relativ zum Container, Raster 10 px empfohlen):
{
  "title": "Zielarchitektur",              # optional, Kopfzeile
  "subtitle": "Schematische Darstellung",  # optional
  "note": "Hinweistext unter dem Diagramm",# optional
  "legend": [{"style": "red", "label": "Security"}],   # optional
  "nodes": [
    {"id": "net", "label": "Internet", "type": "cloud", "x": 300, "y": 0, "w": 240, "h": 70},
    {"id": "ing", "label": "Ingress Layer", "sub": "Optional Untertitel", "style": "red",
     "layout": {"cols": 2, "gap": 20, "padding": 20, "header": 44, "stretch": true}, "w": 800},
    {"id": "lb",  "label": "Load Balancer", "sub": "Octavia HA", "parent": "ing"}
  ],
  "edges": [
    {"from": "net", "to": "ing", "label": "Web-Traffic",
     "dashed": false, "bidirectional": false, "color": "#333333",
     "exit": [0.5, 1], "entry": [0.5, 0]}
  ]
}

Node-Felder:
  id (Pflicht, eindeutig), label (kurz, fett), sub (optional, Zusatzzeile), parent (id des Containers)
  type: box (Default) | cloud | database | actor | external | text | boundary
        (boundary = gestrichelter, ungefüllter Rahmen, z. B. Rechenzentrum/Zone/Cloud-Grenze)
  style: red | blue | green | purple | yellow | orange | gray | dark  (Farbfamilie; Kinder erben vom Container)
  x, y, w, h (optional): fehlt x/y bei Kindern -> Grid-Layout im Container (layout.cols);
         fehlt x/y bei Top-Level-Knoten -> vertikal gestapelt und zentriert (gap = 60).
  Ein Knoten mit Kindern ist automatisch ein Container (Titel oben links, Auto-Grösse).
  layout.stretch=true: Spalten füllen die Container-Breite gleichmässig aus.

Edge-Felder: from, to (Pflicht), label, dashed, bidirectional, color, exit/entry ([x, y] 0..1).
Kanten sind orthogonal; exit/entry erzwingen saubere, gerade Verläufe.
"""
import argparse
import html
import json
import os
import xml.etree.ElementTree as ET

PALETTE = {
    "red": ("#f8cecc", "#b85450"),
    "blue": ("#dae8fc", "#6c8ebf"),
    "green": ("#d5e8d4", "#82b366"),
    "purple": ("#e1d5e7", "#9673a6"),
    "yellow": ("#fff2cc", "#d6b656"),
    "orange": ("#ffe6cc", "#d79b00"),
    "gray": ("#f5f5f5", "#666666"),
    "dark": ("#e6e6e6", "#333333"),
}
DEFAULT_SIZE = {
    "box": (180, 60), "cloud": (240, 70), "database": (100, 80),
    "actor": (40, 70), "external": (160, 70), "text": (200, 30), "boundary": (0, 0),
}
FONT = "Helvetica"
MARGIN_X, MARGIN_Y, TITLE_H = 40, 40, 60


def esc(text):
    return html.escape(str(text), quote=False).replace("\n", "<br>")


def build_label(node, is_container):
    parts = []
    if node.get("label"):
        parts.append(esc(node["label"]) if node.get("type") == "text" else f"<b>{esc(node['label'])}</b>")
    if node.get("sub"):
        sub = esc(node["sub"])
        parts.append(f'<font style="font-size: 11px;">{sub}</font>' if is_container else sub)
    return "<br>".join(parts)


def resolve_style(node, parent):
    name = node.get("style") or (parent.get("_style") if parent else None) or "gray"
    if name not in PALETTE:
        raise SystemExit(f"Unbekannter style '{name}' bei Knoten '{node['id']}'. Erlaubt: {', '.join(PALETTE)}")
    node["_style"] = name
    return PALETTE[name]


def layout(node):
    kids = node["_children"]
    for k in kids:
        layout(k)
    if not kids:
        dw, dh = DEFAULT_SIZE.get(node.get("type", "box"), (180, 60))
        node.setdefault("w", dw)
        node.setdefault("h", dh)
        return
    cfg = node.get("layout", {})
    gap, pad, header = cfg.get("gap", 20), cfg.get("padding", 20), cfg.get("header", 44)
    auto = [k for k in kids if "x" not in k or "y" not in k]
    ncols = max(1, min(cfg.get("cols", len(auto) or 1), len(auto) or 1))
    rows = [auto[i:i + ncols] for i in range(0, len(auto), ncols)]
    colw = [max((r[c]["w"] for r in rows if c < len(r)), default=0) for c in range(ncols)]
    if cfg.get("stretch") and auto:
        total = node["w"] if "w" in node else sum(colw) + gap * (ncols - 1) + 2 * pad
        colw = [(total - 2 * pad - gap * (ncols - 1)) / ncols] * ncols
        for idx, k in enumerate(auto):
            if not k["_children"]:
                k["w"] = colw[idx % ncols]
    y = header
    for r in rows:
        rh = max(k["h"] for k in r)
        x = pad
        for c, k in enumerate(r):
            k["x"] = x + (colw[c] - k["w"]) / 2
            k["y"] = y + (rh - k["h"]) / 2
            x += colw[c] + gap
        y += rh + gap
    node.setdefault("w", max(k["x"] + k["w"] for k in kids) + pad)
    node.setdefault("h", max(k["y"] + k["h"] for k in kids) + pad)


def vertex_style(node, parent, is_container):
    t = node.get("type", "box")
    fill, stroke = resolve_style(node, parent)
    base = f"html=1;whiteSpace=wrap;fontFamily={FONT};fontSize=12;"
    if t == "text":
        return base + "text;align=left;verticalAlign=top;fontColor=#666666;"
    if t == "boundary":
        return (base + "rounded=1;arcSize=2;fillColor=none;dashed=1;dashPattern=8 4;strokeWidth=2;"
                f"strokeColor={stroke};verticalAlign=top;align=left;spacingLeft=12;spacingTop=6;fontSize=13;")
    if is_container:
        return (base + f"rounded=1;arcSize=6;fillColor={fill};strokeColor={stroke};"
                "verticalAlign=top;align=left;spacingLeft=12;spacingTop=6;fontSize=13;")
    if t == "cloud":
        return base + f"shape=cloud;fillColor={fill};strokeColor={stroke};fontSize=13;"
    if t == "database":
        return base + f"shape=cylinder3;boundedLbl=1;backgroundOutline=1;size=10;fillColor={fill};strokeColor={stroke};"
    if t == "actor":
        return base + f"shape=umlActor;verticalLabelPosition=bottom;verticalAlign=top;fillColor={fill};strokeColor={stroke};"
    if t == "external":
        return base + f"rounded=1;fillColor=#ffffff;strokeColor={stroke};dashed=1;"
    inner_fill = "#ffffff" if parent is not None else fill
    return base + f"rounded=1;fillColor={inner_fill};strokeColor={stroke};"


def edge_style(e):
    parts = [
        "edgeStyle=orthogonalEdgeStyle", "html=1", "rounded=0", "endArrow=block", "endFill=1",
        f"strokeColor={e.get('color', '#333333')}", f"strokeWidth={e.get('width', 2)}",
        f"fontFamily={FONT}", "fontSize=11", "labelBackgroundColor=#ffffff",
    ]
    if e.get("bidirectional"):
        parts += ["startArrow=block", "startFill=1"]
    if e.get("dashed"):
        parts.append("dashed=1")
    if "exit" in e:
        parts += [f"exitX={e['exit'][0]}", f"exitY={e['exit'][1]}"]
    if "entry" in e:
        parts += [f"entryX={e['entry'][0]}", f"entryY={e['entry'][1]}"]
    return ";".join(parts) + ";"


def abs_box(node, by_id, off):
    x, y = node["x"], node["y"]
    p = node.get("parent")
    while p:
        x += by_id[p]["x"]
        y += by_id[p]["y"]
        p = by_id[p].get("parent")
    return x + off[0], y + off[1], node["w"], node["h"]


def main(spec_path, out_path, force):
    if os.path.exists(out_path) and not force:
        raise SystemExit(f"{out_path} existiert bereits (nie überschreiben; anderen Namen wählen oder --force).")
    with open(spec_path, encoding="utf-8-sig") as f:
        spec = json.load(f)

    nodes = spec["nodes"]
    by_id = {}
    for n in nodes:
        if n["id"] in by_id:
            raise SystemExit(f"Doppelte Node-ID: {n['id']}")
        n["_children"] = []
        by_id[n["id"]] = n
    roots = []
    for n in nodes:
        p = n.get("parent")
        if p:
            if p not in by_id:
                raise SystemExit(f"parent '{p}' von '{n['id']}' existiert nicht")
            by_id[p]["_children"].append(n)
        else:
            roots.append(n)
    for r in roots:
        layout(r)

    auto_roots = [r for r in roots if "x" not in r or "y" not in r]
    if auto_roots:
        max_w = max(r["w"] for r in auto_roots)
        y = 0
        for r in auto_roots:
            r["x"] = (max_w - r["w"]) / 2
            r["y"] = y
            y += r["h"] + 60

    off = (MARGIN_X, MARGIN_Y + (TITLE_H if spec.get("title") else 0))
    model = ET.Element("mxGraphModel", dx="1200", dy="900", grid="1", gridSize="10", guides="1", tooltips="1",
                       connect="1", arrows="1", fold="1", page="1", pageScale="1", math="0", shadow="0")
    cells = ET.SubElement(model, "root")
    ET.SubElement(cells, "mxCell", id="0")
    ET.SubElement(cells, "mxCell", id="1", parent="0")

    def add_vertex(cid, value, style, parent, x, y, w, h):
        c = ET.SubElement(cells, "mxCell", id=cid, value=value, style=style, vertex="1", parent=parent)
        ET.SubElement(c, "mxGeometry", x=str(round(x)), y=str(round(y)), width=str(round(w)),
                      height=str(round(h)), **{"as": "geometry"})

    ordered = []

    def walk(n):
        ordered.append(n)
        for k in n["_children"]:
            walk(k)

    for r in roots:
        walk(r)

    max_r = max_b = 0
    for n in ordered:
        parent = by_id.get(n.get("parent"))
        is_container = bool(n["_children"]) or n.get("type") == "boundary"
        style = vertex_style(n, parent, is_container)
        x, y = (n["x"] + off[0], n["y"] + off[1]) if parent is None else (n["x"], n["y"])
        add_vertex(n["id"], build_label(n, is_container), style, parent["id"] if parent else "1", x, y, n["w"], n["h"])
        ax, ay, aw, ah = abs_box(n, by_id, off)
        max_r, max_b = max(max_r, ax + aw), max(max_b, ay + ah)

    edges = spec.get("edges", [])
    for i, e in enumerate(edges, 1):
        for end in ("from", "to"):
            if e[end] not in by_id:
                raise SystemExit(f"Edge {i}: Knoten '{e[end]}' existiert nicht")
        c = ET.SubElement(cells, "mxCell", id=e.get("id", f"e{i}"), value=esc(e.get("label", "")),
                          style=edge_style(e), edge="1", parent="1", source=e["from"], target=e["to"])
        ET.SubElement(c, "mxGeometry", relative="1", **{"as": "geometry"})

    width = max(max_r - MARGIN_X, 400)
    if spec.get("title"):
        sub = (f'<br><font style="font-size: 12px; font-weight: normal;">{esc(spec["subtitle"])}</font>'
               if spec.get("subtitle") else "")
        add_vertex("title", f"<b>{esc(spec['title'])}</b>{sub}",
                   f"text;html=1;align=left;verticalAlign=middle;whiteSpace=wrap;fontSize=18;fontFamily={FONT};",
                   "1", MARGIN_X, MARGIN_Y - 20, width, 44)

    y = max_b + 30
    for i, item in enumerate(spec.get("legend", []), 1):
        fill, stroke = PALETTE[item["style"]]
        add_vertex(f"legend_box_{i}", "", f"rounded=1;fillColor={fill};strokeColor={stroke};", "1", MARGIN_X, y, 16, 16)
        add_vertex(f"legend_txt_{i}", esc(item["label"]),
                   f"text;html=1;align=left;verticalAlign=middle;fontSize=11;fontFamily={FONT};",
                   "1", MARGIN_X + 24, y - 2, 300, 20)
        y += 24
    if spec.get("note"):
        add_vertex("note", esc(spec["note"]),
                   f"text;html=1;align=left;verticalAlign=top;whiteSpace=wrap;fontSize=11;fontStyle=2;"
                   f"fontColor=#666666;fontFamily={FONT};", "1", MARGIN_X, y + 6, width, 36)
        y += 42

    model.set("pageWidth", str(int(max_r + MARGIN_X)))
    model.set("pageHeight", str(int(y + MARGIN_Y)))
    mxfile = ET.Element("mxfile", host="app.diagrams.net", agent="Copilot", version="24.0.0")
    diagram = ET.SubElement(mxfile, "diagram", id="diagram-1", name=spec.get("page_name", "Diagramm"))
    diagram.append(model)
    ET.indent(mxfile, space="  ")
    ET.ElementTree(mxfile).write(out_path, encoding="utf-8")
    print(f"Gespeichert: {out_path} ({len(ordered)} Knoten, {len(edges)} Kanten)")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("spec")
    ap.add_argument("output")
    ap.add_argument("--force", action="store_true")
    a = ap.parse_args()
    main(a.spec, a.output, a.force)
