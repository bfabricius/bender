---
name: create-template
description: "Baut aus einem bestehenden Dokument (.docx, .md, .pptx, .xlsx) ein wiederverwendbares, anonymisiertes Template (.md oder .docx) für den Skill fill-template: konkrete Inhalte werden durch [Platzhalter] ersetzt, Gliederung, Sprache, Stil und feste Textbausteine bleiben erhalten. Use when: Template erstellen, Vorlage aus Dokument bauen, Dokument in Vorlage umwandeln, Dokument zu Template umbauen, Beispieldokument als Vorlage, Template für fill-template vorbereiten, create template."
argument-hint: "Quelldatei (expliziter Pfad), optional: Template-Name, Zielformat (.md/.docx), Hinweise welche Inhalte fest bleiben sollen"
---

# create-template

Wandelt ein vorhandenes, ausgefülltes Dokument in ein **Template** um, das der Skill `fill-template`
direkt verwenden kann. Das Template behält **Gliederung, Sprache, Stil, Tonalität, Formatvorlagen und
feste Textbausteine**; alle konkreten Inhalte (Namen, Zahlen, Projektbezüge, Beschreibungen) werden zu
`[Platzhaltern]`. Der Skill befüllt nichts und beschreibt keinen Mandatsinhalt.

## Grundregeln (immer einhalten)

- **Immer per `ask_user` fragen**, nie als Fliesstext; Fragen einer Phase gebündelt stellen.
- **Quellen-Whitelist:** Lesen nur die Quelldatei, die der User in dieser Anfrage **explizit** nennt, sowie
  `export-artefacts/templates/` (Namenskollisionen, Stilreferenz). Dieser Skill-Aufruf hebt die
  File-access restriction aus `AGENTS.md` **ausschliesslich** dafür auf. `mem-index/` wird nicht benötigt.
  Nie selbständig in `input_client-docs/`, `raw-input-docs/` etc. nach Quellen suchen.
- **Nichts erfinden, nichts umformulieren.** Struktur, Überschriften, Formulierungsstil und feste
  Textbausteine stammen 1:1 aus der Quelle. Nur Konkretes wird ersetzt.
- **Quelle nie verändern.** Immer mit einer Kopie bzw. neuer Ausgabedatei arbeiten.
- **Keine Kundendaten im Template.** Nach dem Umbau darf kein quellspezifischer Konkretwert übrig sein
  (Prüfung in Schritt 5). Metadaten (Autor, Titel, Kommentare) werden bei `.docx` bereinigt.
- Ergebnis nicht committen, ausser der User verlangt es.
- Unterstützte Quellformate: `.docx`, `.md`, `.pptx`, `.xlsx`. **PDF wird nicht unterstützt.**
  Ausgabeformate (damit `fill-template` sie verarbeiten kann): `.md` oder `.docx`.

## Ablauf

### 1. Eingaben klären
Benötigt: **Quelldatei** (Pfad), **Template-Name/Slug**, **Zielformat**. Fehlendes per `ask_user` erfragen.

| Quelle | Mögliche Ausgabe | Weg |
|---|---|---|
| `.docx` | `.docx` (Default, erhält Formatvorlagen, Kopf-/Fusszeilen) oder `.md` | `inspect_docx.py` + `fill_docx.py` |
| `.md` | `.md` | direkt lesen, neue Datei schreiben |
| `.pptx` | `.md` (Folie → Abschnitt) | `extract_source.py` |
| `.xlsx` | `.md` (Blatt → Abschnitt/Tabelle) | `extract_source.py` |

Lock-Dateien (`~$*`) ignorieren. Andere Formate (z. B. `.pdf`) ablehnen und einen `.docx`/`.md`-Export vorschlagen.

### 2. Quelle analysieren
- `.docx`: `python .agents/skills/fill-template/scripts/inspect_docx.py <quelle.docx>`
  (Paragraph-Index, Formatvorlage, Tabellen, Kopf-/Fusszeile).
- `.pptx`/`.xlsx`: `python .agents/skills/create-template/scripts/extract_source.py <quelle>`
- `.md`: Datei lesen.
- Stil und Struktur gemäss [style-profile.md](../fill-template/references/style-profile.md) erfassen.

### 3. Template-Plan erstellen (Gate)
Pro Abschnitt/Element entscheiden gemäss [template-konventionen.md](./references/template-konventionen.md):
**Fest** (unverändert lassen) · **Platzhalter** (ersetzen) · **Streichen** (nur für diese Instanz relevant) ·
**Mehrfach** (Beispiele als Stilmuster belassen, 1–2 Stück).
Dem User zeigen: Kurzprofil (Sprache, Anrede, Tonalität, Gliederung), Plan-Tabelle
(Abschnitt → Aktion → vorgesehener Platzhalter) und die **Liste sensibler/quellspezifischer Begriffe**
(Kundenname, Projektname, Personen, Orte, Beträge, Daten), die nicht im Template bleiben dürfen.
**Bestätigung/Korrektur abwarten**, bevor geschrieben wird. Unklare Fälle (fest oder variabel?) gebündelt
per `ask_user` klären.

### 4. Template schreiben
Ablage `export-artefacts/templates/<slug>.<ext>`; nie überschreiben (sonst `_v2`, `_v3`).
Ordner bei Bedarf anlegen.

- **`.docx`:**
  1. Operationsliste `ops.json` (Format siehe Kopf von
     [fill_docx.py](../fill-template/scripts/fill_docx.py)) schreiben: `set_paragraph`, `set_cell`,
     `replace_text`, `delete_paragraph`, `insert_after`. Paragraph-Indizes aus Schritt 2.
     `ops.json` im Session-Ordner ablegen, nicht im Projekt.
  2. `python .agents/skills/fill-template/scripts/fill_docx.py <quelle.docx> <template.docx> <ops.json>`
     (schreibt in eine neue Datei, die Quelle bleibt unverändert).
  3. `python .agents/skills/create-template/scripts/sanitize_docx.py <template.docx>`
     (leert Autor/Titel/Kommentar-Metadaten, meldet Kommentare, Änderungsverfolgung und Bilder; diese
     bei Bedarf vom User in Word entfernen lassen).
- **`.md`** (aus `.md`/`.pptx`/`.xlsx`): neue Datei mit `create` schreiben. Gliederung der Quelle
  übernehmen; bei `.pptx` Folientitel → Überschriften, Folieninhalt → Platzhalter-Listen; bei `.xlsx`
  Spaltenköpfe als Tabellenkopf, Datenzeilen durch 1–2 Platzhalter-Zeilen ersetzen.

Platzhalter-Konvention: **`[Beschreibung]`** in eckigen Klammern, inhaltlich sprechend
(`[Projektname]`, `[Ziel des Mandats in 2–3 Sätzen]`). Anleitung für den Befüller als Blockquote
`> Hinweis: …` (Markdown); `fill-template` entfernt sie beim Befüllen. Eckige Klammern nicht für anderes
verwenden.

### 5. Prüfen
`python .agents/skills/create-template/scripts/check_template.py <template> --forbid "<Begriff>" --forbid "<Begriff>" …`
mit der bestätigten Begriffsliste aus Schritt 3. Das Skript meldet: gefundene verbotene Begriffe,
Platzhalter-Anzahl/-Liste, verdächtige Konkretwerte (E-Mail, Telefon, Datum, Beträge, grosse Zahlen).
Treffer beheben und erneut prüfen, bis keine verbotenen Begriffe mehr gefunden werden;
Warnungen mit dem User klären (bewusst fest oder Platzhalter?).

### 6. Verifikation
- `.docx`: `inspect_docx.py <template.docx>` – Gliederung, Formatvorlagen, Tabellen = Quelle;
  Abschnitt «PLATZHALTER» zeigt alle Platzhalter und keine Kundendaten.
- `.md`: Datei neu einlesen; Überschriften-Struktur = Quelle.
- Das Template muss für `fill-template` ohne Nacharbeit nutzbar sein (Platzhalter erkannt, Ablage in
  `export-artefacts/templates/`).

### 7. Abschlussmeldung
Kurz: Ausgabepfad, Quellformat → Zielformat, Anzahl Platzhalter, bewusst festgehaltene Textbausteine,
gestrichene Abschnitte, offene Warnungen und Hinweis zum Aufruf von `fill-template`
(Template-Ordner `export-artefacts/templates/`, Template-Name).
