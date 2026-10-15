---
name: fill-template
description: "Befüllt ein Template-Dokument (.md oder .docx) aus dem Memory-Index (mem-index/) und optional aus vom User explizit genannten WIP-Quellen. Struktur, Sprache, Stil, Tonalität und Flow werden aus dem Template abgeleitet. Use when: Vorlage befüllen, Template ausfüllen, Dokument aus Vorlage erzeugen, fill template, Offertanfrage/BoM/Spezifikation/E-Mail nach Vorlage erstellen, Dokument aus Wissensbasis generieren."
argument-hint: "Template-Ordner (Default vorlagen/), Template-Name, optionale Zusatzquellen (explizite Pfade)"
---

# fill-template

Erzeugt aus einem Template (Struktur + Stilvorlage) und der verifizierten Wissensbasis ein
fertig befülltes Dokument. Das Template gibt **Gliederung, Sprache, Stil, Tonalität und Flow**
vor; der Inhalt stammt aus `mem-index/` und aus Quellen, die der User **ausdrücklich** nennt.

## Grundregeln (immer einhalten)

- **Nichts erfinden.** Jede Aussage muss auf Index-Node oder genannte Zusatzquelle zurückführbar sein.
- **Quellen-Whitelist:** Lesen darfst du nur (1) `mem-index/`, (2) das gewählte Template,
  (3) Pfade, die der User in dieser Anfrage explizit nennt. Dieser Skill-Aufruf hebt die
  File-access restriction aus `AGENTS.md` **ausschliesslich** dafür auf.
  Nie selbständig in `input_client-docs/`, `raw_input-documents/`, `arbeits-dokument/` etc. suchen.
- **Verlinkte Dateien** in einer genannten Zusatzquelle (Links, Verweise auf Anhänge) nur nach
  Rückfrage beim User lesen.
- **Sprache und Stil kommen aus dem Template**, nicht aus der Session-Sprache.
- **Index-Konflikte** (Zusatzquelle widerspricht `mem-index/`) nicht stillschweigend auflösen,
  sondern dem User vorlegen.
- Ergebnis nicht committen, ausser der User verlangt es.

## Ablauf

### 1. Eingaben klären
Benötigt: **Template-Ordner** (Default `vorlagen/`), **Template-Name**, optionale **Zusatzquellen**
(explizite Pfade) und ggf. Kontextparameter (Projekt, Empfänger, Datum, Ersteller).
- Fehlende Angaben per `ask_user` erfragen. Bei Mehrdeutigkeit die Dateien des Ordners auflisten
  (Lock-Dateien `~$*` ignorieren; bei mehreren Versionen neueste vorschlagen und bestätigen lassen).
- Unterstützt: `.md`, `.docx`.

### 2. Template analysieren → Stil-Profil (Gate)
- `.md`: Datei lesen. `.docx`: `python .agents/skills/fill-template/scripts/inspect_docx.py <template.docx>`.
- Struktur, Sprache und Stil gemäss [style-profile.md](./references/style-profile.md) ableiten.
- **Kurzprofil dem User zeigen und Bestätigung/Korrektur abwarten**, bevor befüllt wird.

### 3. Quellen sammeln
1. `mem-index/00_INDEX.md` lesen; nur die 1–3 relevanten Nodes (plus `14_Glossar.md` für Terminologie).
2. Genannte Zusatzquellen lesen (`.md`/Text direkt; `.docx`/`.pdf` via `./convert-docs-to-text.ps1`,
   falls direktes Lesen/Sichten nicht reicht).
3. Eskalation auf weitere Nodes nur, wenn ein Abschnitt sonst unbelegt bleibt.

### 4. Füllplan erstellen
Pro Template-Abschnitt/Platzhalter: Quelle(n), vorgesehener Inhalt, Status (belegt / Lücke / Konflikt).

### 5. Lücken klären
- Alle Lücken/Konflikte gebündelt per `ask_user` erfragen (kein Raten).
- **Fallback:** Kann der User nicht antworten, `[TODO: <was fehlt>]` im Dokument belassen und die Lücke
  im Quellenbericht listen (Kandidat für `mem-index/08_Offene-Fragen.md` – dem User vorschlagen, nicht
  automatisch eintragen).

### 6. Dokument schreiben
- Ablage in `export-artefacts/` (Unterordner nur auf Wunsch/Bestehendes wie `emails/`).
  Name `YYMMDD_<template-slug>_<kontext-slug>.<ext>`; nie überschreiben (sonst `_v2`, `_v3`).
- Format = Template-Format (`.md` → `.md`, `.docx` → `.docx`).
- `.md`: Template als Gerüst übernehmen; Anleitungs-/Hinweistexte des Templates entfernen.
- `.docx`: Kopie des Templates bearbeiten, damit Formatvorlagen, Kopf-/Fusszeilen erhalten bleiben –
  mit [fill_docx.py](./scripts/fill_docx.py) (Format der Operationen siehe Skript-Kopf).
- Das Dokument selbst bleibt **sauber**: keine Fussnoten, Quellenverweise oder Kommentare.

### 7. Quellenbericht (Begleitdatei)
Neben dem Dokument `<name>.quellen.md` anlegen:
- Template (Pfad), Zusatzquellen (Pfade), bestätigtes Stil-Profil
- Tabelle **Abschnitt → Quelle** (Index-Node `[[xx_Name]]` bzw. Datei + Abschnitt)
- Lücken/`[TODO]`, Annahmen, aufgelöste Konflikte, Kandidaten für `08_Offene-Fragen.md`

### 8. Log-Eintrag
An `mem-index/log.md` **unten anhängen** (append-only), Typ `query`:
```markdown
## [YYYY-MM-DD] query | Template befüllt: <Template-Name> → <Ausgabedatei>

**Aktion:** Template <Name> aus mem-index (und <Zusatzquellen oder "keine">) befüllt.
**Geänderte Nodes:** keine
**Details:** Ausgabe: <Pfad>; Quellenbericht: <Pfad>; offene Lücken: <n>.

---
```

### 9. Verifikation
- Ausgabe neu einlesen (`.docx`: `inspect_docx.py`): Gliederung = Template, keine verbliebenen
  Template-Platzhalter ausser bewusste `[TODO: …]`, Terminologie konsistent mit `14_Glossar.md`.
- Abschlussmeldung kurz: Ausgabepfade, Anzahl Lücken, genutzte Index-Nodes und Zusatzquellen.
