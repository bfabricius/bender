---
mode: agent
name: ingest-docs
description: Findet neue, noch nicht ingestete Client-Dokumente (oder nimmt vom Nutzer genannte Pfade entgegen), prueft ob Pre-Processing hilft, leitet das Node-Mapping ab und pflegt Nodes, 00_INDEX.md, _client-input-inventory.md und log.md nach expliziter Bestaetigung.
argument-hint: Pfad(e) zu Datei(en)/Ordner (optional) - sonst werden nicht erfasste Client-Docs vorgeschlagen
---

# ingest-docs

Du fuehrst den Nutzer durch den **Ingest** eines oder mehrerer neuer Client-Dokumente in den
Memory-Index. Du bist der interaktive Vollzug des bereits in `.github/copilot-instructions.md`
definierten "Ingest workflow (neues Quelldokument)" - dieselben 7 Schritte, aber mit Kandidaten-
Erkennung, Vollstaendigkeits-Check, Pre-Processing-Analyse und Bestaetigungs-Gates dazwischen.

## Grundprinzipien (immer einhalten)

- **Nichts erfinden.** Node-Zuordnung, neue offene Fragen/Konflikte und der Commit-Text IMMER
  ableiten und dem Nutzer zur Bestaetigung vorlegen, nie stillschweigend festlegen.
- **Vier Bestaetigungs-Gates, nie ueberspringen:** Schritt 2 (Datei-Liste vollstaendig?),
  Schritt 3 (Pre-Processing/Tool-Install, falls noetig), Schritt 5 (Node-Mapping-Zusammenfassung),
  Schritt 7 (Commit-Text). Vor jedem Gate warten, bis der Nutzer explizit zustimmt.
  Node(s) aktualisieren/erstellen/committen erst NACH Schritt 5.
- **Diese Prompt-Ausfuehrung ist selbst der sanktionierte Ausloeser** der "Ingest-Workflow"-
  Ausnahme von der File-access restriction in `copilot-instructions.md` - Lesen von Rohdateien in
  `input_client-docs/` ist hier ausdruecklich erlaubt.
- **Ambiguitaet -> Frage stellen.** Wenn ein Dokument zu keiner Node eindeutig passt oder mehrere
  Nodes gleich gut passen, den Nutzer fragen statt zu raten.
- **Jede Aenderung wird geloggt.** Ein `ingest`-Eintrag pro Quelldokument (oder gruppiert, wenn
  mehrere Dateien zusammen eine Node befuellen) an `mem-index/log.md` anhaengen (append-only).
- **Stil.** Deutsch, ASCII-Umlaut-Stil (ae/oe/ue) wie im restlichen Repo; Markdown-Tabellen im
  Format der jeweiligen Node.

## Schritt 0 - Kandidaten ermitteln

1. Fuehre im Terminal `./project-status.ps1 -Action IngestCoverage` aus (nicht-interaktiver Modus,
   liefert exakt dieselbe Ingest-Abdeckungs-Logik wie Menuepunkt 6 - Wildcard-Muster-Abgleich,
   bewusst ignorierte Dateien, Retro-Log-Ausnahme, NBSP-Normalisierung; diese Logik NICHT selbst
   in Markdown/Regex nachbauen).
2. Zeige dem Nutzer die Liste unter "Noch nicht ingestete Dateien" als Kandidaten.
3. Weise den Nutzer explizit darauf hin, dass er **stattdessen** (oder zusaetzlich) eigene
   Pfade zu einzelnen Dateien oder einem Ordner nennen kann - diese werden dann statt der oder
   zusaetzlich zu den erkannten Kandidaten verwendet.

## Schritt 1 - Auswahl festlegen

1. Nutzer bestaetigt entweder die erkannten Kandidaten aus Schritt 0, nennt eigene Pfad(e), oder
   eine Kombination aus beidem.
2. Wurde ein Ordnerpfad genannt: liste rekursiv alle darin enthaltenen Dateien auf (kein `.git`,
   keine bereits als "ignoriert" gefuehrten Duplikate ohne Rueckfrage uebernehmen).
3. Ergebnis dieses Schritts ist eine konkrete, flache Liste einzelner Dateipfade.

## Schritt 2 - Vollstaendigkeits-Check (Gate 1)

1. Zeige die vollstaendig aufgeloeste Dateiliste aus Schritt 1 als nummerierte Liste.
2. Frage explizit: "Ist diese Liste vollstaendig und korrekt?" Nutzer kann Dateien ergaenzen/
   entfernen. Erst nach Bestaetigung weiter zu Schritt 3.

## Schritt 3 - Lesen & Pre-Processing-Analyse (Gate 2, nur falls Pre-Processing noetig)

1. Versuche pro Datei zunaechst das direkte Lesen/Sichten (bestehende Konvention fuer PDF/DOCX
   aus `bootstrap-mandate.prompt.md`).
2. Empfehle Pre-Processing **nur bei klarem Grund**, z. B.:
   - Direktes Lesen liefert erkennbar binaeren/verstuemmelten Text (typisch bei DOCX/PPTX).
   - PDF liefert beim direkten Lesen keinen oder kaum extrahierbaren Text (moeglicherweise
     gescannt/Bild-PDF).
   - Sehr grosse/unuebersichtliche Datei, bei der eine saubere Text-Extraktion die Zuordnung
     zu Nodes in Schritt 4 klar erleichtern wuerde.
   Liegt keiner dieser Gruende vor: das explizit so benennen und ohne Pre-Processing fortfahren.
3. Falls Pre-Processing empfohlen: `./convert-docs-to-text.ps1 -Path <Datei-oder-Ordner>`
   ausfuehren (DOCX/PPTX brauchen keine externen Tools). Meldet das Skript ein fehlendes
   PDF-Tool, dem Nutzer an dieser Stelle - nicht vorher - **Poppler (`pdftotext`)** als Option
   erklaeren (Pandoc kann technisch kein PDF lesen und ist daher keine Option); nur nach
   expliziter Zustimmung erneut mit `-InstallMissingTool` aufrufen (laedt Poppler lokal nach
   `.ingest-tools/poppler/`, nie systemweit, nie git-getrackt).
4. Die resultierenden `.txt`-Dateien unter `.ingest-tools/extracted/` einlesen und fuer Schritt 4
   verwenden.

## Schritt 4 - Node-Mapping ableiten

1. Lies `mem-index/00_INDEX.md` (Navigationsbaum + Quick-Navigation-Tabelle) um die Node-Zwecke
   nachzuschlagen.
2. Schlage pro Datei (oder pro inhaltlichem Abschnitt einer Datei) die Ziel-Node(s) vor.
3. Pruefe zusaetzlich:
   - Ergeben sich neue offene Fragen -> Kandidaten fuer `08_Offene-Fragen.md` (Status 🔴🟠🟡).
   - Ergeben sich Widersprueche zu bestehendem Wissen -> Kandidaten fuer `13_Offene-Konflikte.md`.
   - Wuerde eine Ziel-Node dadurch ~400 Zeilen ueberschreiten -> Split vorschlagen (siehe
     "Node splitten, wenn..." Regel in `copilot-instructions.md`).
   - Passt der Inhalt zu keiner bestehenden Node -> neue Node vorschlagen (siehe
     "Neue Node hinzufuegen, wenn..." Regel).
4. Bei Ambiguitaet: **nachfragen**, nicht selbst entscheiden.

## Schritt 5 - Zusammenfassung & Bestaetigung (Gate 3)

1. Praesentiere eine Tabelle: `Datei | Ziel-Node(s) | Art der Aenderung | Sonstiges (neue Node/
   Split/neue offene Frage/neuer Konflikt)`.
2. Hole explizites Go durch den Nutzer. Erst danach beginnt Schritt 6 - vorher wird keine Node,
   kein Index und kein Log veraendert.

## Schritt 6 - Ausfuehren

1. Pro Ziel-Node: Node **vor** dem Editieren lesen, dann aktualisieren/erstellen (Zusammenfassung
   oben, Detailinhalt unten - repo-Konvention).
2. `mem-index/00_INDEX.md`: Quelldokument-Mapping-Tabelle um die neuen Zeilen ergaenzen (Status
   `✅ eingeflossen` bzw. `↳ ignoriert (<Grund>)` bei bewusst nicht ingesteten Begleitdateien).
3. `mem-index/_client-input-inventory.md`: entsprechenden Nachtrag/Zeile ergaenzen (gleiche
   Information wie 00_INDEX, als lesbare Zusammenfassung - siehe bestehende "Nachtrag"-Abschnitte
   als Vorlage).
4. Falls in Schritt 4 identifiziert: neue Zeilen/Abschnitte in `08_Offene-Fragen.md` bzw.
   `13_Offene-Konflikte.md` ergaenzen.
5. Pro Quelldokument (oder gruppiert) einen `ingest`-Eintrag an `mem-index/log.md` anhaengen,
   exakt im in `copilot-instructions.md` definierten Format:

   ```markdown
   ## [YYYY-MM-DD] ingest | <Kurzbeschreibung>

   **Aktion:** `<relativer Pfad zur Quelldatei>` gesichtet und in den Index eingepflegt.
   **Geaenderte Nodes:** [[node1]], [[node2]]
   **Details:** Optional - was genau uebernommen wurde, neue F-/K-IDs, etc.

   ---
   ```

## Schritt 7 - Commit anbieten (Gate 4)

1. Schlage eine Commit-Message nach dem Muster `ingest: <kurze Beschreibung der Quelle(n)>` vor
   (Konvention aus `copilot-instructions.md`).
2. Nutzer kann den Text bestaetigen oder anpassen.
3. Erst nach Bestaetigung: `git add` auf die geaenderten Node-/Index-/Log-Dateien, dann
   `git commit -m "<bestaetigte Message>"` lokal ausfuehren. **Niemals pushen.**

## Schritt 8 - Zusammenfassung

Fasse zusammen: welche Datei(en) wurden ingestet, in welche Node(s), welche neuen F-/K-IDs
entstanden (falls vorhanden), und ob committet wurde (mit Commit-Message).
