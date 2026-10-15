---
name: diagram-export
description: "Erzeugt aus Bild, ASCII-/Textdiagramm, Mermaid oder Freitext ein professionelles draw.io-Diagramm (.drawio): Architektur, Infrastruktur/Deployment, Netzwerk-/System-Topologie, Systemkontext, Datenfluss, Prozess. Berät bei unklarer Diagrammart mit Fragen und Vorschlägen. Use when: draw.io Diagramm erstellen, drawio export, Diagramm aus Bild/Mermaid/ASCII/Text, Architekturdiagramm, Infrastrukturdiagramm, Topologie, Netzwerkdiagramm, Diagramm professionell formatieren, diagram export."
argument-hint: "Input (Pfad zu Bild/.md/.mmd/Text oder Freitext), Diagrammart (optional – sonst Beratung)"
---

# diagram-export

Bringt ein Diagramm-Input in ein **sauberes, editierbares draw.io-Format** nach professionellen
Lesbarkeitsstandards. Der User definiert **Input** und **Diagrammart**; ist er bei der Art unsicher,
berät der Agent per Fragen und Vorschlägen.

## Grundregeln (immer einhalten)

- **Nichts erfinden.** Jedes Element und jede Verbindung muss aus dem Input (oder einer vom User
  bestätigten Ergänzung) stammen. Ergänzungen wie Kantenlabels oder Zonenbezeichnungen im Abschlussbericht nennen.
- **Quellen-Whitelist:** Lesen nur, was der User in der Anfrage nennt (Bildpfad, Datei, eingefügter Text) –
  und `mem-index/`, falls der User ihn ausdrücklich als Quelle angibt. Dieser Skill hebt die
  File-access restriction aus `AGENTS.md` ausschliesslich dafür auf.
- **Lesbarkeit vor Vollständigkeit:** knappe Labels, ≤ 25 Elemente pro Seite, sonst Aufteilung vorschlagen.
- **Nie überschreiben:** Ausgabe `export-artefacts/YYMMDD_<diagramm-slug>.drawio`; bei Kollision `_v2`, `_v3`.
- Ergebnis nicht committen, ausser der User verlangt es.

## Ablauf

### 1. Eingaben klären
Benötigt: **Input** (Bild · textuelles/ASCII-Diagramm · Mermaid · Freitext/mem-index-Auszug),
**Diagrammart**, optional Zweck/Publikum, Sprache, Titel, Ausgabepfad.
- Fehlendes gebündelt per `ask_user` erfragen (max. 3–4 Fragen, Auswahl-Felder mit Defaults).
- Input-Typ selbst erkennen (Dateiendung `.png/.jpg/.svg` · `.mmd`/«```mermaid» · «+---+»-Boxen · Prosa).

### 2. Diagrammart festlegen
- Nennt der User eine Art → mit [diagram-types.md](./references/diagram-types.md) auf Passung prüfen
  (z. B. Sequenz/ER werden von `build_drawio.py` nicht abgedeckt → Alternative anbieten).
- **Ist der User unsicher oder nennt keine Art:** Beratungs-Dialog aus
  [diagram-types.md](./references/diagram-types.md) durchführen (Kernfrage, Publikum, Verwendung, Detailgrad),
  dann **1–2 Arten mit Begründung** vorschlagen und bestätigen lassen. Bei Mischfällen genau eine Hauptart wählen.

### 3. Input → Elementliste (Gate)
Input gemäss [style-guide.md](./references/style-guide.md) §2 aufbereiten und dem User **kompakt** zeigen:
Knoten (inkl. Gruppe), Container-Hierarchie, Kanten (von → nach, Label, gestrichelt?), vorgesehenes Layout
(Richtung, Zeilen/Spalten, Farbzuordnung). Unklares/Unleserliches als Frage markieren.
**Bestätigung oder Korrekturen abwarten**, bevor gebaut wird.

### 4. Diagramm bauen
1. Spec (JSON) nach [example-architektur.spec.json](./assets/example-architektur.spec.json) schreiben
   (Session-Ordner `files/` oder temporär; nach Abschluss entfernen).
2. `python .agents/skills/diagram-export/scripts/build_drawio.py <spec.json> export-artefacts/<name>.drawio`
   (Feldreferenz im Skript-Kopf). Für Sonderformen (Raute, Sequenz, Swimlane): manuelle XML-Variante
   in [style-guide.md](./references/style-guide.md) §4 oder – bei Mermaid – nativer Import in draw.io.
3. Layout nach den Standards in [style-guide.md](./references/style-guide.md) §1/§3 und den Art-Konventionen
   in [diagram-types.md](./references/diagram-types.md) wählen.

### 5. Verifikation
- `python .agents/skills/diagram-export/scripts/validate_drawio.py <datei.drawio>` → 0 Fehler; Warnungen
  (Überlappung, Label zu lang, Container-Anschluss ohne exit/entry) beheben oder begründen.
- Abgleich Elementliste ↔ Diagramm: nichts fehlt, nichts Zusätzliches.
- Optional Vorschau: `python .agents/skills/diagram-export/scripts/export_drawio.py <datei.drawio> png`
  (benötigt draw.io-Desktop-CLI; sonst Exit-Code 2 → User bitten, die Datei in draw.io zu öffnen und
  Auffälligkeiten zu melden). PNG/SVG nur auf Wunsch behalten.

### 6. Abschlussmeldung (kurz)
Ausgabepfad, gewählte Art (+ Begründung, falls beraten), Aufbau in 3–5 Stichpunkten, **Ergänzungen gegenüber
dem Input** (Kantenlabels, Gruppenbezeichnungen, Legende), offene Punkte. Bei Nutzung von `mem-index/`:
Log-Eintrag Typ `query` an `mem-index/log.md` anhängen (append-only, Format laut `AGENTS.md`).
Iterationen («Beschriftung kürzen», «Layer tauschen») durch Anpassen der Spec und Neubau als `_v2`.

## Dateien
- [diagram-types.md](./references/diagram-types.md) – Arten, Beratungs-Dialog, Layout je Art
- [style-guide.md](./references/style-guide.md) – Lesbarkeitsstandards, Input-Aufbereitung, XML-Fallback, Fallstricke
- [build_drawio.py](./scripts/build_drawio.py) · [validate_drawio.py](./scripts/validate_drawio.py) · [export_drawio.py](./scripts/export_drawio.py)
- [example-architektur.spec.json](./assets/example-architektur.spec.json) – Beispiel-Spec (Schichtenarchitektur mit DMZ/VPN)
