---
mode: agent
name: pflege-master-schedule
description: Pflegt den Master-Schedule (mem-index/09_Master-Schedule.json) konversationell - Projekt-Rahmendaten, Meilensteine, Arbeitsstroeme und Arbeitspakete anlegen/aendern/entfernen, unabhaengig vom Web-Editor. Schreibt erst nach expliziter Bestaetigung.
argument-hint: Kurzbeschreibung der gewuenschten Aenderung (optional, z. B. "neues Arbeitspaket in Lane L2")
---

# pflege-master-schedule

Du pflegst mit dem Nutzer gemeinsam den **Master-Schedule** direkt in
[mem-index/09_Master-Schedule.json](../../mem-index/09_Master-Schedule.json) - unabhaengig vom
Web-Editor (`master-schedule-editor.html`). Beide Pfade schreiben in dieselbe Datei; du musst also
nicht mit dem Web-Editor synchronisieren, nur konsistent mit ihrem Datenmodell bleiben.

## Datenmodell (verbindlich, exakt so einhalten)

`09_Master-Schedule.json`:
- `generated`: Datum der letzten Aenderung (`JJJJ-MM-TT`), von dir beim Schreiben gesetzt.
- `project`: `{ name, startDate, endDate }` (Daten im Format `JJJJ-MM-TT`).
- `milestones[]`: `{ id, name, date, description? }` - IDs `M1`, `M2`, ... fortlaufend, unabhaengig
  von Lanes (Etappen/lieferbare Meilensteine, wirken als Marker ueber die gesamte Zeitachse).
- `lanes[]`: `{ id, name, owner, workPackages[] }` - IDs `L1`, `L2`, ... . Owner ist ausschliesslich
  pro Lane erfasst (nicht pro Arbeitspaket).
- `workPackages[]` (pro Lane): `{ id, name, startDate, endDate, priority, effortPT, status }` - IDs
  `WP1`, `WP2`, ... **fortlaufend ueber den GESAMTEN Schedule** (nicht pro Lane neu bei 1 beginnend).
  - `priority` (MoSCoW): exakt `Must` / `Should` / `Could` / `Won't`.
  - `effortPT`: Aufwand in Personentagen (Zahl, >= 0).
  - `status`: exakt `To Do` / `In Progress` / `Done`.

`09_Master-Schedule.md` ist eine rein **auto-generierte** Zusammenfassung (nie von Hand editieren) -
du regenerierst sie nach jeder Aenderung nach exakt dieser Struktur (Ueberschriften/Reihenfolge
1:1 wie in `schedule-wizard.ps1` / `apply-master-schedule-changes.ps1`, damit alle drei
Pflege-Pfade dieselbe Datei erzeugen):

```markdown
# Master-Schedule - <Mandatsname>

> Auto-generiert aus `09_Master-Schedule.json` (Single Source of Truth). Diese Datei nie von
> Hand editieren - Aenderungen gehen beim naechsten Regenerieren verloren. Stattdessen:
> `./schedule-wizard.ps1` (interaktiver Wizard), Copilot-Chat `/pflege-master-schedule`
> (konversationell), oder `master-schedule-editor.html` + `./apply-master-schedule-changes.ps1`
> (Web-Editor).

## Projekt-Rahmendaten

| Feld | Wert |
|---|---|
| Start | <startDate oder "[nicht gesetzt]"> |
| Ende | <endDate oder "[nicht gesetzt]"> |

## Etappen und lieferbare Meilensteine

<Tabelle "| ID | Name | Datum | Beschreibung |" sortiert nach Datum, oder "_Noch keine
Meilensteine erfasst._" falls leer>

## Arbeitsstroeme (Lanes)

<pro Lane ein Abschnitt "### L1 - <Name> (Owner: <Owner>)" mit Tabelle
"| ID | Name | Start | Ende | Prioritaet | Aufwand (PT) | Status |" sortiert nach Start,
oder "_Noch keine Arbeitspakete in dieser Lane._"; falls gar keine Lanes: "_Noch keine
Arbeitsstroeme erfasst._">

---
_Zuletzt generiert: <JJJJ-MM-TT HH:mm> durch schedule-wizard.ps1 / apply-master-schedule-changes.ps1 / /pflege-master-schedule._
```

## Grundprinzipien (immer einhalten)

- **Nichts erfinden.** Namen, Daten, Prioritaet, Aufwand, Status und Owner IMMER beim Nutzer
  erfragen/bestaetigen, nie selbst festlegen oder schaetzen.
- **`09_Master-Schedule.json` ist die einzige Quelle der Wahrheit.** `09_Master-Schedule.md` wird
  nach jeder Aenderung 1:1 nach obiger Struktur neu geschrieben (komplett ersetzt, nicht
  gepatcht).
- **IDs fortlaufend vergeben.** Vor dem Schreiben immer zuerst die aktuelle Datei lesen, die
  hoechste bestehende Nummer je Praefix (`M`, `L`, `WP`) ermitteln und mit `+1` weitermachen. Nie
  IDs wiederverwenden, auch nicht nach dem Entfernen eines Eintrags.
- **Loeschen von Lanes:** falls die Lane noch Arbeitspakete enthaelt, das explizit benennen und
  extra bestaetigen lassen, bevor sie mitsamt ihren Arbeitspaketen entfernt wird.
- **Bestaetigungs-Gate vor jedem Schreiben** (siehe Schritt 3) - nie stillschweigend in die Datei
  schreiben.
- **Jede Aenderung wird geloggt.** Nach dem Schreiben von `09_Master-Schedule.json`/`.md` immer
  einen `update`-Eintrag an `mem-index/log.md` anhaengen (append-only, Format wie in
  `.github/copilot-instructions.md` beschrieben, `**Geaenderte Nodes:** [[09_Master-Schedule]]`).
- **Stil.** Deutsch, ASCII-Umlaut-Stil (ae/oe/ue) wie im restlichen Repo.

## Schritt 0 - Intent bestimmen

Frage bzw. erkenne aus der Nutzeranfrage (ggf. bereits im `argument-hint` mitgegeben), welcher Fall
vorliegt:

1. Projekt-Rahmendaten aendern (Name/Start/Ende).
2. Meilenstein verwalten (hinzufuegen/bearbeiten/entfernen).
3. Arbeitsstrom (Lane) verwalten (hinzufuegen/bearbeiten/entfernen, inkl. Owner).
4. Arbeitspaket verwalten (hinzufuegen/bearbeiten/entfernen/Status aendern) - IMMER zuerst klaeren,
   zu welcher Lane es gehoert (bei "Status aendern" reicht die ID, falls der Nutzer sie kennt).
5. Gesamtuebersicht zeigen (nur lesen, keine Aenderung - dann Schritte 1-4 ueberspringen und direkt
   den aktuellen Inhalt zusammengefasst darstellen).

Mehrere Aenderungen in einer Anfrage sind erlaubt (z. B. "neue Lane UND gleich 2 Arbeitspakete
dafuer") - sammle sie alle vor dem Bestaetigungs-Gate in Schritt 3.

## Schritt 1 - Node lesen

Lies `mem-index/09_Master-Schedule.json` vollstaendig, bevor du irgendetwas vorschlaegst. Zeige dem
Nutzer die fuer den Fall relevanten bestehenden Eintraege (z. B. bei Fall 3/4: Liste der Lanes mit
IDs+Owner; bei Fall 4 zusaetzlich die Arbeitspakete der betroffenen Lane), damit er sich orientieren
kann, bevor er Details nennt.

## Schritt 2 - Aenderungen erarbeiten

Erfrage/bestaetige je nach Fall alle noetigen Felder explizit, einzeln oder als kurze
Zusammenfassung, die der Nutzer korrigieren kann - nutze dabei ausschliesslich die oben
dokumentierten Enums/Formate (Datum `JJJJ-MM-TT`, `priority` MoSCoW, `status` To Do/In
Progress/Done, `effortPT` als nicht-negative Zahl).

## Schritt 3 - Zusammenfassung & Bestaetigung (Gate)

1. Zeige alle geplanten Aenderungen als kompakte Liste (Art der Aenderung, betroffene ID(s) -
   neue IDs an dieser Stelle bereits final vergeben, s. o. -, alte -> neue Werte bei Bearbeitungen).
2. Hole explizites Go durch den Nutzer ("Sollen diese Aenderungen jetzt in
   `09_Master-Schedule.json` uebernommen werden?"). Erst danach beginnt Schritt 4 - vorher wird
   nichts geschrieben.

## Schritt 4 - Ausfuehren

1. `mem-index/09_Master-Schedule.json` mit den bestaetigten Aenderungen schreiben (`generated` auf
   das heutige Datum setzen).
2. `mem-index/09_Master-Schedule.md` komplett neu schreiben, exakt nach der oben dokumentierten
   Struktur.
3. Einen `update`-Eintrag an `mem-index/log.md` anhaengen:

   ```markdown
   ## [JJJJ-MM-TT] update | Master-Schedule ueber /pflege-master-schedule aktualisiert

   **Aktion:** <ein Satz was gemacht wurde>
   **Geaenderte Nodes:** [[09_Master-Schedule]]
   **Details:** <betroffene IDs und Art der Aenderung>

   ---
   ```

## Schritt 5 - Zusammenfassung an den Nutzer

Fasse kurz zusammen, was geschrieben wurde (neue/geaenderte/entfernte IDs) und bestaetige, dass
`log.md` ergaenzt wurde.
