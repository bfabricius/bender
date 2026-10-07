---
name: analysis-boot-workstream
description: Erarbeitet fuer einen Analyse-Sprint-Workstream die fachlichen Grundlagen und das Vorgehen und gibt sie als zwei Markdown-Dateien aus (Grundlagen + Workstream-Vorgehen).
argument-hint: Name des Workstreams (z. B. "Identity und Zugriffsmodell")
---

# analysis-boot-workstream

Du hilfst dem Team, fuer einen **Analyse-Sprint-Workstream** fachliche Grundlagen und ein
konkretes Bearbeitungsvorgehen zu erarbeiten. Ergebnis sind **zwei neue Markdown-Dateien**:
eine Grundlagen-Datei (fachliche/technische Basis) und eine Workstream-Datei (Rollen,
Bearbeitungsabfolge, OpenSpec-Nutzung).

Existieren im Ausgabeordner (Default `analyse-sprint/`) bereits andere `*_grundlagen-*.md` /
`*_workstream-*.md`-Dateien aus frueheren Workstreams dieses Mandats, orientiere dich an
deren Aufbau/Detailgrad als Stil-Referenz. Existiert noch keine, nutze die Gliederung aus
Schritt 4/5 unten direkt.

## Grundprinzipien (immer einhalten)

- **Nur aus dem Memory Index ableiten.** Faktenbasis ist ausschliesslich `mem-index/`. Nichts erfinden.
- **IDs referenzieren.** Verweise auf Anforderungen (`UC-`, `FA-`, `NFA-`, `OP-`), offene Fragen (`F-`) und Konflikte (`K-`) in eckigen Klammern am Satz- oder Zeilenende, sofern das Mandat solche IDs im Memory Index fuehrt.
- **Unsicherheit sichtbar halten.** Fehlende oder widerspruechliche Information wird als offene Frage/Konflikt markiert, nicht als gesetzte Anforderung dargestellt.
- **Allgemeine Technik-Erklaerungen klar abgrenzen.** Erklaerende oder architektonische Passagen ausdruecklich als noch nicht beschlossene Architektur/Loesung kennzeichnen.
- **Mermaid pruefen.** Jedes Mermaid-Diagramm mit dem Mermaid-Validator pruefen, bevor du fertig bist.
- **Stil.** Deutsch, ASCII-Umlaut-Stil (ae/oe/ue); Markdown mit Ueberschriften, Tabellen, Mermaid und (wo passend) KaTeX.

## Schritt 0 — Workstreams auflisten (optional)

Wenn der Nutzer eine Uebersicht wuenscht (z. B. "liste die Workstreams", "welche gibt es", "status") oder keinen Namen nennt, biete zuerst eine Auflistung an:

1. Ermittle die bekannten Workstreams: falls das Mandat einen eigenen Katalog pflegt (z. B.
   `analyse-sprint/workstream-katalog.md` oder eine vom Nutzer genannte Datei), lies diese.
   Sonst leite die Liste ab aus vorhandenen `analyse-sprint/*_workstream-*.md`-Dateien und/oder
   den Unterordnern von `openspec-sdd/openspec/changes/` (falls die Requirements-Engineering-Phase
   bereits initialisiert ist).
2. Bilde je Workstream den `<slug>` (kebab-case).
3. Bestimme den **Bearbeitungsstand** aus dem Ausgabeordner (Default `analyse-sprint/`): Suche nach vorhandenen Dateien `*_grundlagen-<slug>.md` und `*_workstream-<slug>.md`.
   - Beide vorhanden -> **erarbeitet**.
   - Keine vorhanden -> **nicht bearbeitet**.
   - Nur eine vorhanden -> **teilweise erarbeitet** (nenne die fehlende Datei).
4. Gib eine Tabelle aus: Workstream | Status | vorhandene Dateien.
5. Frage anschliessend, welchen Workstream der Nutzer bearbeiten moechte, und fahre mit Schritt 1 fort. Ist ein Workstream bereits **erarbeitet**, frage, ob er neu erstellt (ueberschreiben/neues Datum) oder uebersprungen werden soll.

## Schritt 1 — Workstream bestimmen

1. Frage den Nutzer nach dem **Namen des Workstreams**, falls nicht bereits als Argument uebergeben oder in Schritt 0 gewaehlt.
2. Frage, ob es fuer diesen Workstream bereits eine Katalog-Quelle (Beschreibung, Zielsetzung, betroffene IDs) gibt:
   - **Ja** -> lies diese Datei und uebernimm Zuordnung, Ziel, zu klaerende IDs und Vorgehen als Ausgangspunkt.
   - **Nein** -> stelle Detailfragen zu Name, Scope, betroffenen Akteuren und Zielsetzung des Workstreams direkt (bevorzugt ueber das Fragen-Tool).

## Schritt 2 — Ausgabeort bestimmen

1. Erklaere, dass die zwei Ausgabedateien standardmaessig im Ordner `analyse-sprint/` abgelegt werden.
2. **Frage den Nutzer**, ob er einen anderen Ausgabeordner wuenscht. Wenn ja, verwende diesen; sonst den Default.
3. Dateinamen (Datum = aktuelles Datum, `<slug>` = kebab-case des Workstream-Namens):
   - `YYYY-MM-DD_grundlagen-<slug>.md`
   - `YYYY-MM-DD_workstream-<slug>.md`

## Schritt 3 — Faktenbasis aus dem Memory Index sammeln

1. Lies `mem-index/00_INDEX.md` und navigiere gezielt zu den fuer den Workstream relevanten Nodes — typischerweise `03_Anforderungen`, `05_Gap-Analyse`, `06_Constraints`, `08_Offene-Fragen`, `14_Glossar`, sowie alle weiteren mandatsspezifischen Nodes (z. B. `10_...` und hoeher), die thematisch zum Workstream passen.
2. Sammle die zum Workstream gehoerenden `UC-`/`FA-`/`NFA-`/`OP-`-Anforderungen, die offenen Fragen `F-` und ggf. Konflikte `K-` (sofern das Mandat ein Konflikt-Register fuehrt).
3. Notiere, was belegt ist und was offen bzw. widerspruechlich ist.

## Schritt 4 — Datei 1 erstellen: Grundlagen

Erzeuge `..._grundlagen-<slug>.md` mit folgender Gliederung:

- Titel `# Grundlagen: <Workstream-Thema>`
- Kopfblock: **Zweck**, **Dokumentierter Stand** (mit Node-Wikilinks), **Wichtige Abgrenzung**
- `## 1.` Worum es im Thema geht (inkl. der zentralen Fragen, die der Workstream beantworten muss)
- `## 2.` Begriffe und Grundmechaniken (fachliche Einordnung; Konzepte erklaeren)
- `## 3.` Zentrale Optionen/Varianten des Themas verstehen (Vergleichstabelle: Funktionsweise, adressiertes Problem, offene Pruefpunkte)
- `## 4.` Moegliches Architekturbild (Mermaid; ausdruecklich als nicht beschlossen markiert)
- `## 5.` Warum die offenen Punkte vor einer Umsetzung geklaert werden muessen (Tabelle: offene Frage/Konflikt -> was unbestimmt bleibt -> warum nicht spezifizierbar)
- `## 6.` Beruehrungspunkte zu anderen Workstreams (Mermaid + Tabelle der Abhaengigkeiten mit IDs)
- `## 7.` Fragen fuer den Analyse-Workshop (je Frage 1-2 Saetze *Warum/Zweck* mit Bezug zu F-/K-ID)
- `## 8.` Von Erkenntnis zu OpenSpec (Beispiel-Requirement mit Platzhalter fuer den noch offenen Entscheid)
- `## 9.` Glossar mit `### 9.1 Abkuerzungen` (Kuerzel ausschreiben + Kurzdefinition) und `### 9.2 Fachbegriffe` (Kurzdefinition). Schlusshinweis auf `[[mem-index/14_Glossar]]` als verbindliche Domaenensprache.

## Schritt 5 — Datei 2 erstellen: Workstream-Vorgehen

Erzeuge `..._workstream-<slug>.md` mit folgender Gliederung:

- Titel `# Analyse-Sprint: Workstream <Name>`
- Kopfblock: **Status** (Arbeitsvorschlag), **Faktenbasis** (Node-Wikilinks), **Ziel**
- `## 1.` Umfang (gekoppelte F-/K-/FA-/NFA-/OP-IDs; Mermaid-Flowchart des Ablaufs; benachbarte Abhaengigkeiten benennen)
- `## 2.` Rollen und Verantwortungen (Tabelle: Success Lead/PO, Architekt, Entwickler; externe Rollen erst wenn bestaetigt)
- `## 3.` Bearbeitungsabfolge in 7 Schritten (Kick-off/Triage, Optionen vergleichbar machen, Entscheidungsunterlagen, Workshop/Evidenz, Spike/PoC, OpenSpec spezifizieren, Sprint-Readiness) + Mermaid-Sequenzdiagramm
- `## 4.` Sprint-Readiness-Check (Kriterienliste)
- `## 5.` Erwartete OpenSpec-Ergebnisse (Tabelle: proposal.md, design.md, specs, tasks.md)
- `## 6.` Abgrenzung (validate --strict prueft Struktur, nicht fachliche Richtigkeit)
- `## 7.` Durchgehendes Beispiel: Arbeit im Analyse-Change (Beispiele zu Schritt 1-7 mit konkreten OpenSpec-CLI-Aufrufen `npx --yes @fission-ai/openspec@latest ...`, proposal/design/spec/tasks-Ausschnitten). Beispiele klar als illustrativ markieren; keine erfundenen Fachentscheide.

## Schritt 6 — Validierung und Abschluss

1. Pruefe jedes Mermaid-Diagramm mit dem Mermaid-Validator.
2. Pruefe beide Dateien auf Markdown-Fehler.
3. Gib eine kurze **Traceability-Zusammenfassung** aus: verwendete Nodes, uebernommene IDs (UC/FA/NFA/OP), offene Punkte (F/K) und die Pfade der zwei erzeugten Dateien.

## Regeln

- Erstelle die zwei Ausgabedateien; erstelle keine weiteren Dateien ohne Zustimmung.
- Aendere den Memory Index nur, wenn der Nutzer es ausdruecklich verlangt (und dann nach dem Ingest-/Log-Protokoll der Instructions).
- Wenn eine Angabe fehlt, frage nach oder markiere sie als offene Frage; nichts erfinden.
