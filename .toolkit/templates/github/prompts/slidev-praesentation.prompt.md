---
mode: agent
description: Generiert interaktiv eine Slidev-Präsentation aus dem Memory-Index (optional weiteren Verzeichnissen) und legt sie lauffähig in export-artefacts/praesentationen/ ab.
---

# Slidev-Präsentation erstellen

Du bist ein Assistent, der aus der verifizierten Wissensbasis dieses Mandats eine
**Slidev-Präsentation** erzeugt (Slidev = Open-Source-Tool für Präsentationen aus Vue +
Markdown). Arbeite dialogisch: erst klären, dann generieren.

## Schritt 1 — Inhalt besprechen
Frage den User, **was** in die Präsentation soll:
- Thema / Titel der Präsentation,
- Zielgruppe (z. B. Steering Committee, Kunde, Team),
- Kernbotschaft / Ziel der Präsentation,
- optionale Schwerpunkte oder auszulassende Themen.

## Schritt 2 — Umfang & Detailtiefe abfragen
1. **Anzahl Slides** (Richtwert). Ist der User unsicher, schlage eine Anzahl anhand der
   Inhaltsmenge vor.
2. **Detailtiefe** — biete drei Stufen an:
   - **Kompakt** — nur Stichworte pro Slide, keine/kaum Presenter-Notes.
   - **Standard** — Bullets + kurze Presenter-Notes (`<!-- -->` am Slide-Ende).
   - **Ausführlich** — ausformulierte Bullets + vollständige Presenter-Notes.

## Schritt 3 — Quellen festlegen
- **Default:** ausschliesslich der Memory-Index unter `mem-index/`. Halte das
  token-effiziente Leseprotokoll ein: **zuerst `mem-index/00_INDEX.md`**, dann nur die
  relevanten Nodes über die Quick-Navigation.
- **Zusätzliche Quellen nur auf Ansage:** Nennt der User weitere Verzeichnisse
  (z. B. `analyse-sprint/`), darfst du diese ebenfalls lesen.
  > Nur für diesen Präsentations-Workflow ist damit die File-access-Restriction aus
  > `.github/copilot-instructions.md` (Q&A: nur `mem-index/`) bewusst aufgehoben — aber
  > **ausschliesslich für die vom User explizit genannten Pfade**. Lies keine weiteren
  > Verzeichnisse ungefragt.
- Erfinde nichts. Fehlt Inhalt in den freigegebenen Quellen, sag es und schlage vor, die
  Quelle zu erweitern.

## Schritt 4 — Slidev-Markdown erzeugen
Erstelle den Deck-Inhalt entsprechend Detailtiefe und Slide-Anzahl:
- Titel-Slide, danach Agenda/Überblick, Inhalts-Slides, Abschluss/Nächste Schritte.
- Sprache: **Deutsch** (Session-Sprache), sofern der User nichts anderes sagt.
- Nutze Slidev-Layouts (`layout: cover`, `layout: section`, `layout: two-cols`) sinnvoll.
- Presenter-Notes je Slide als HTML-Kommentar am Slide-Ende, passend zur Detailstufe.

## Schritt 5 — Ablage im gemeinsamen Slidev-Projekt
Alle Präsentationen liegen im **gemeinsamen Projekt** `export-artefacts/praesentationen/`.
1. Prüfe, ob das Projektskelett existiert (`package.json`, `.gitignore`, `styles/branding.css`,
   `slides/_template/`). Fehlt etwas, lege es idempotent an (Vorlage: `slides/_template/`;
   `styles/branding.css` aus der mitgelieferten neutralen Vorlage, falls noch nicht vorhanden).
2. Erzeuge ein neues Deck-Verzeichnis:
   `export-artefacts/praesentationen/slides/<YYYY-MM-DD>_<slug>/` mit:
   - `slides.md` — die Präsentation (headmatter mit `theme: default`, `title`).
   - `style.css` — enthält `@import '../../styles/branding.css';` (Plattform-Branding).
     Pro Deck überschreibbar durch zusätzliche Regeln darunter.
   - `README.md` — die CLI-Befehle zum Ausführen genau dieses Decks (siehe unten).
   - optional `assets/` für deck-spezifische Bilder.

### Inhalt der Deck-`README.md`
```markdown
# <Titel> — Slidev-Deck

Teil des gemeinsamen Projekts `export-artefacts/praesentationen/`.

## Einmalig: Abhängigkeiten installieren
    cd export-artefacts/praesentationen
    npm install

## Dev-Server (mit Live-Reload)
    npm run dev -- slides/<YYYY-MM-DD>_<slug>/slides.md

## Als PDF exportieren
    npx slidev export slides/<YYYY-MM-DD>_<slug>/slides.md

## Statisch bauen (SPA)
    npx slidev build slides/<YYYY-MM-DD>_<slug>/slides.md
```

## Schritt 6 — Branding
Standard ist ein **neutrales Graustufen-Theme** mit generischem Akzent-Blau
(`styles/branding.css`, siehe Key Constraints in `.github/copilot-instructions.md` für ein
ggf. mandatsspezifisches Farbschema), Mobile-First. Passe die Farben in `branding.css`
an das Corporate Design des Mandats an, sobald bekannt. Wünscht der User ein anderes
Theme (z. B. `seriph`), passe headmatter `theme:` entsprechend an.

## Schritt 7 — Installation/Start (nur nach Rückfrage)
Führe `npm install` oder den Dev-Server **nicht automatisch** aus. Nenne dem User die
Befehle (stehen im Deck-README) und frage, ob du Installation/Start jetzt für ihn ausführen
sollst. Nur bei ausdrücklicher Bestätigung Terminalbefehle ausführen.

## Regeln
- Nur aus den freigegebenen Quellen ableiten, nichts erfinden.
- Kein Eintrag in `mem-index/log.md` nötig — die Präsentation ist ein Export-Artefakt, keine
  Änderung am Memory-Index.
- Bestehende Decks nicht überschreiben; bei Namenskollision Slug/Datum anpassen.
