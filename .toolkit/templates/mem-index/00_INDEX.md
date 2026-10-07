# Memory Index – __MANDATE__

> Zentraler Navigations-Hub des Memory-Index. Bei jeder neuen Session zuerst
> diese Datei lesen, dann gezielt zu den relevanten Nodes navigieren.

## Navigationsbaum

```
mem-index/
├── 00_INDEX.md                  ← Einstieg · Navigation · Quelldokument-Mapping
├── 01_Projektkontext.md         ← Mandat, Ziel, Scope, Deliverables
├── 02_Stakeholder.md            ← Ansprechpartner, Rollen, Interessen
├── 03_Anforderungen.md          ← Funktionale & nicht-funktionale Anforderungen
├── 04_IST-Analyse.md            ← Ausgangslage / IST-Zustand
├── 05_Gap-Analyse.md            ← Lücken, Pain-Points, Priorisierung
├── 06_Constraints.md            ← Budget, Timeline, Technik, Rahmenbedingungen
├── 07_Loesungsansatz.md         ← Lösungsoptionen, Empfehlung, Roadmap
├── 08_Offene-Fragen.md          ← Offene Fragen mit Status (🔴🟠🟡)
├── 09_Master-Schedule.md        ← Planungs-/Lieferansicht (Etappen, Lanes, Arbeitspakete) - SSOT in 09_Master-Schedule.json
├── 14_Glossar.md                ← Glossar & Domänensprache · Single Source of Truth
├── 15_Retrospektiven-und-Action-Items.md  ← Retro-Log + globale Action-Item-Liste
├── _client-input-inventory.md   ← Auto-Inventar des Client-Input-Ordners
└── log.md                       ← Append-only Änderungs-Log
```

> Weitere Nodes (z. B. `10_...` für Governance, Personas, ein domänenspezifisches
> Objektmodell o. Ä.) können jederzeit ergänzt werden, wenn eine neue Domäne das
> rechtfertigt — siehe "Neue Node hinzufügen" in `AGENTS.md`.
> Trage sie dann hier im Navigationsbaum nach.

## Quick-Navigation

| Fragetyp | Zuerst lesen | Danach |
|---|---|---|
| Mandat / Scope / Ziele | [[01_Projektkontext]] | [[03_Anforderungen]] |
| Wer ist beteiligt | [[02_Stakeholder]] | [[01_Projektkontext]] |
| Anforderungen / Umfang | [[03_Anforderungen]] | [[06_Constraints]] |
| Ausgangslage / IST | [[04_IST-Analyse]] | [[05_Gap-Analyse]] |
| Lücken / Probleme | [[05_Gap-Analyse]] | [[04_IST-Analyse]] |
| Rahmenbedingungen | [[06_Constraints]] | [[01_Projektkontext]] |
| Lösung / Empfehlung / Roadmap | [[07_Loesungsansatz]] | [[05_Gap-Analyse]] |
| Blocker / offene Punkte | [[08_Offene-Fragen]] | referenzierte Nodes |
| Master-Schedule / Termine / Lanes / Arbeitspakete | [[09_Master-Schedule]] | `./schedule-wizard.ps1`, `/pflege-master-schedule` |
| Begriff / Abkürzung nachschlagen | [[14_Glossar]] | — |
| Retrospektiven / Action Items | [[15_Retrospektiven-und-Action-Items]] | — |
| Volle Synthese (Bericht) | Alle Nodes 01→08 | — |

## Kontext für KI-Abfragen

- **Niemals alle Nodes gleichzeitig lesen.** Immer mit `00_INDEX.md` starten und
  über die Quick-Navigation nur die 1–3 relevanten Nodes öffnen.
- Nur bei domänenübergreifenden Fragen (z. B. Lösung × Gap) zusätzliche Nodes lesen.
- Antworten ausschliesslich aus dem Index ableiten. Fehlt Information → in
  [[08_Offene-Fragen]] als Kandidat markieren, nicht erfinden.

## Quelldokument-Mapping

> Nachverfolgbarkeit: welches Client-Dokument in welche Node eingeflossen ist.
> Vollständiges Datei-Inventar siehe [[_client-input-inventory]].

| Quelldokument | Ziel-Node(s) | Status |
|---|---|---|
__MAPPING__

## Glossar

> Verbindliche Domänensprache siehe [[14_Glossar]]. Diese Zeile nur für schnelle
> Einzelbegriffe, die noch keinen Platz in Node 14 gefunden haben.

| Begriff | Bedeutung |
|---|---|
| [PLATZHALTER] | [PLATZHALTER — vom Client-Kontext ableiten] |

---
_Erstellt am __DATE__ durch `bootstrap-wizard.ps1`._
