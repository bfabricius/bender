# Style-Guide, Input-Aufbereitung & Fallstricke

## 1. Professionelle Lesbarkeitsstandards (immer anwenden)

| Thema | Regel |
|---|---|
| **Beschriftung** | Fett = Name (≤ 3 Wörter), darunter eine Zeile Detail (≤ 40 Zeichen). Keine ganzen Sätze. Produkt-/Spezifikationsdetails (Grössen, Versionen) nur wenn im Input genannt. |
| **Sprache** | Wie Input; Fachbegriffe/Layer-Namen unverändert aus dem Input (z. B. «Ingress & Security Layer»). |
| **Dichte** | ≤ 25 Elemente pro Seite; sonst Detail-Diagramm abspalten. Mind. 20 px Abstand zwischen Geschwistern, 40–60 px zwischen Layern (Platz für Kantenlabels). |
| **Raster/Ausrichtung** | 10-px-Raster, Elemente bündig; gleiche Breiten pro Zeile (`layout.stretch`); Container-Padding 20 px. |
| **Farben** | Eine Farbfamilie pro Layer/Zone (Palette im Skript), Komponenten weiss mit gleicher Randfarbe. Max. 5–6 Farben, nie Farbe als einzige Information (Legende/Beschriftung ergänzen). |
| **Schrift** | Helvetica, 12 px Komponenten, 13 px Container-Titel, 11 px Kantenlabels, 18 px Titel. |
| **Kanten** | Orthogonal, gerade Verläufe via `exit`/`entry`; Pfeilspitzen an Flussrichtung; Kantenlabel knapp (1–2 Wörter) mit weissem Hintergrund; gestrichelt = Tunnel/optional/logisch; keine Kreuzungen wenn vermeidbar. |
| **Gruppierung** | Zusammengehörendes in Container (boundary/Layer), Kinder per `parent` – so bleibt das Diagramm in draw.io verschiebbar. |
| **Legende/Hinweis** | Legende nur wenn Farben nicht selbsterklärend; ein kurzer Hinweis-Text unter dem Diagramm erlaubt. |
| **Titel** | Titel + Untertitel (Art/Zweck); Datum/Version nur wenn gewünscht. |

## 2. Input-Aufbereitung

Immer zuerst in eine **Elementliste** übersetzen und dem User zur Bestätigung zeigen:
`Knoten (Name, Typ, Gruppe) · Gruppen/Container (Hierarchie) · Kanten (von → nach, Label, Stil)`.

### a) Bild / Screenshot
- Bild mit dem `view`-Tool ansehen (Pfad nur, wenn vom User genannt).
- Alle sichtbaren Texte, Gruppen (Rahmen/Farben), Pfeile inkl. Richtung erfassen; Unlesbares als
  `[unleserlich: …]` markieren und beim User nachfragen statt raten.
- Layout des Originals nur als Anhaltspunkt – Ziel ist die Standard-Ausrichtung dieses Guides.

### b) Textuelles / ASCII-Diagramm
- Boxen (`+---+`, `|…|`) = Knoten/Container; `-`-Listen in einer Box = Komponenten; `|`, `v`, `>` = Kanten.
- Aufspaltende/zusammenführende Linien (`+----+----+`) = mehrere Kanten von/zu derselben Box.
- Begleittext («Hinweis: …») als Notiz übernehmen, nicht als Knoten.

### c) Mermaid
- `flowchart`/`graph` → Knoten + Kanten (`-->` Pfeil, `-.->` gestrichelt, `<-->` bidirektional); `subgraph` = Container; Label `A[Text]`.
- `C4*`/`architecture-beta` → Container/Systeme als Container bzw. Boxen, `Rel` als Kanten.
- `sequenceDiagram`, `erDiagram`, `stateDiagram`, `gantt`: nicht von `build_drawio.py` abgedeckt.
  Optionen: (1) in draw.io **Anordnen › Einfügen › Erweitert › Mermaid** den Originalcode einfügen
  (nativ, ohne Nachbearbeitung), oder (2) manuell als XML nach Abschnitt 4 bauen.
- Mermaid-Styles/`classDef` nur auf Farbfamilien abbilden, nicht 1:1 übernehmen.

### d) Freitext / Beschreibung / mem-index
- Nur Aussagen verwenden, die im Text stehen. Keine zusätzlichen Komponenten «ergänzen»;
  Lücken als Frage an den User.

## 3. Arbeiten mit `build_drawio.py`
- Spec nach [example-architektur.spec.json](../assets/example-architektur.spec.json) schreiben (Datei im Session-Ordner
  oder `export-artefacts/`, danach löschen, wenn temporär).
- Kinder ohne `x`/`y` → Grid-Layout (`layout.cols`); `layout.stretch` füllt die Breite; Container mit `w` + Kindern
  ergibt konsistente Zeilen.
- **Mehrspaltige Zeilen ausserhalb eines Containers** (z. B. DMZ neben Intern): `x`/`y` explizit setzen; Pfeilanker
  aus den Mittelpunkten berechnen: `exit/entry-x = (Mittelpunkt_Ziel − Quelle.x) / Quelle.w` (so entstehen gerade Linien).
- Seitliche externe Knoten (z. B. «Verwaltung») rechts ausserhalb der Boundary platzieren, auf Höhe des Quellknotens.
- Titel schiebt Inhalt automatisch um 60 px nach unten; Koordinaten der Top-Level-Knoten starten bei y = 0.

## 4. Manuelle XML-Variante (Sonderformen)
Wenn Raute (Entscheidung), Sequenz-Lifelines, Swimlanes o. ä. nötig sind: `.drawio` direkt als `mxfile` schreiben.
Gerüst:

```xml
<mxfile host="app.diagrams.net"><diagram id="d1" name="Seite-1">
  <mxGraphModel grid="1" gridSize="10" page="1" pageWidth="1169" pageHeight="827">
    <root>
      <mxCell id="0"/><mxCell id="1" parent="0"/>
      <mxCell id="a" value="&lt;b&gt;Schritt&lt;/b&gt;" style="rounded=1;whiteSpace=wrap;html=1;" vertex="1" parent="1">
        <mxGeometry x="40" y="40" width="160" height="60" as="geometry"/></mxCell>
      <mxCell id="e1" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;" edge="1" parent="1" source="a" target="b">
        <mxGeometry relative="1" as="geometry"/></mxCell>
    </root></mxGraphModel></diagram></mxfile>
```
Entscheidung: `rhombus;whiteSpace=wrap;html=1;` · Swimlane: `swimlane;horizontal=0;` · Datenbank: `shape=cylinder3;`.
HTML in `value` muss XML-escaped sein (`&lt;b&gt;`, `&amp;`).

## 5. Häufige Fallstricke
- **Kinder-Koordinaten sind relativ zum Container** (parent), Top-Level absolut.
- Kante mit `parent="1"` lassen, auch wenn Quelle/Ziel in Containern liegen.
- Ohne `exit`/`entry` an Containern wählt draw.io Mittelpunkte → Schrägen/Überlagerung mit Nachbarn.
- Doppelte IDs oder fehlende `source`/`target` → `validate_drawio.py` meldet sie.
- Zu lange Labels sprengen Boxen (`whiteSpace=wrap` bricht, vergrössert aber nicht) → kürzen statt verkleinern.
- Sonderzeichen `&`, `<`, `>` im Label immer escapen (Skript macht das automatisch).
