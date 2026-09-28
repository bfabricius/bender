---
mode: agent
description: Befüllt den leeren Memory-Index dieses Mandats aus dem Client-Input.
---

# Bootstrap-Befüllung: __MANDATE__

Du hast einen **leeren, skelettierten Memory-Index** unter `mem-index/` und eine
generische `.github/copilot-instructions.md` mit `[PLATZHALTER]`-Feldern. Deine Aufgabe
ist es, beides aus dem Client-Input zu befüllen.

## Schritt 1 — Client-Input verstehen
1. Lies das Inventar `mem-index/_client-input-inventory.md` (falls vorhanden — existiert
   nur, wenn beim Bootstrap ein Client-Input-Ordner angegeben wurde).
2. Lies die dort gelisteten Quelldateien im Client-Ordner:
   `__CLIENTFOLDER__`
   (Nicht-Text-Formate wie PDF/DOCX: Inhalt sichten/zusammenfassen.)
3. Gibt es keinen Client-Input-Ordner: frage den Nutzer, woher die Inhalte für die
   folgenden Schritte kommen sollen (z. B. Copy-Paste, weitere Dateien im Chat).

## Schritt 2 — Index-Nodes befüllen
Ersetze in jeder Node unter `mem-index/` die `[PLATZHALTER]` durch verifizierten Inhalt
aus dem Client-Input. Erfinde nichts — was nicht belegt ist, wird zur offenen Frage.
- `01_Projektkontext.md` — Mandat, zentrale Geschäftsfrage, Ziele, Scope, Deliverables, Constraints.
- `02_Stakeholder.md` — Beteiligte, Rollen, Interessen.
- `03_Anforderungen.md` — funktionale & nicht-funktionale Anforderungen, Priorisierung.
- `04_IST-Analyse.md` — Ausgangslage.
- `05_Gap-Analyse.md` — Lücken zwischen IST und Anforderungen.
- `06_Constraints.md` — Budget, Timeline, Technik, Regulatorik.
- `07_Loesungsansatz.md` — Optionen, Empfehlung, Roadmap (soweit belegbar).

## Schritt 3 — Key Questions extrahieren
Trage die **zentralen Fragen, die das Mandat beantworten muss**, sowie alle offenen
Punkte in `mem-index/08_Offene-Fragen.md` ein (mit Status 🔴🟠🟡).

## Schritt 4 — INDEX & Instructions finalisieren
1. `mem-index/00_INDEX.md`: Quelldokument-Mapping (Node-Zuordnung) und Glossar vervollständigen.
2. `mem-index/14_Glossar.md`: zentrale Begriffe/Abkürzungen aus dem Client-Input eintragen.
3. `.github/copilot-instructions.md`: alle `[PLATZHALTER]` füllen — v. a.
   *Project context* (Auftraggeber, Mandatsziel, Sprache) und *Key Constraints*.

## Schritt 5 — Loggen
Hänge einen `update`-Eintrag an `mem-index/log.md` an
(`## [YYYY-MM-DD] update | Index aus Client-Input befüllt`).

**Regeln:** Nur aus dem Client-Input ableiten. Nicht Belegtes → `08_Offene-Fragen.md`.
Nach dieser Befüllung gilt für Q&A die File-access restriction aus den Instructions
(nur `mem-index/` lesen).
