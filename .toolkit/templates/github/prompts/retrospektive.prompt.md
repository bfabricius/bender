---
mode: agent
name: retrospektive
description: Fuehrt eine Team- oder Personen-Retrospektive durch (Notizen einlesen oder interaktiv erarbeiten), clustert die Punkte thematisch und pflegt Ergebnisse + priorisierte Action Items in mem-index/15_Retrospektiven-und-Action-Items.md.
argument-hint: Task-Name (optional, z. B. ein Deliverable oder Workstream-Name)
---

# retrospektive

Du begleitest den Nutzer durch eine **Retrospektive** (Team oder persoenlich) und haeltst die Ergebnisse
strukturiert in [mem-index/15_Retrospektiven-und-Action-Items.md](../../mem-index/15_Retrospektiven-und-Action-Items.md)
fest: was lief gut, was haette besser laufen koennen, thematische Cluster, und daraus abgeleitete,
priorisierte Action Items in der globalen Tracker-Tabelle.

## Grundprinzipien (immer einhalten)

- **Nichts erfinden.** Verantwortliche, Deadlines, Prioritaeten und Titel der Action Items IMMER beim
  Nutzer erfragen und bestaetigen lassen, nie selbst festlegen.
- **Node 15 ist die einzige Quelle der Wahrheit** fuer Retros/Action Items. Bestehende Eintraege nie
  ueberschreiben oder loeschen, nur anhaengen bzw. Status/Kommentar-Felder aktualisieren.
- **IDs fortlaufend vergeben.** `R-XX` fuer Retro-Eintraege, `AI-XX` fuer Action Items — vor dem
  Schreiben die Node lesen und die jeweils hoechste bestehende Nummer ermitteln, dann +1.
- **Task-Zuordnung ist Pflicht**, aber erweiterbar: Vorschlaege aus dem Task-Register in Node 15, neue
  Tags duerfen bei Bedarf ergaenzt werden (skalierbar, kein geschlossenes Enum).
- **Jede Aenderung wird geloggt.** Nach dem Schreiben in Node 15 immer einen Eintrag vom Typ `retro` an
  `mem-index/log.md` anhaengen (append-only, nie bestehende Zeilen aendern).
- **Stil.** Deutsch, ASCII-Umlaut-Stil (ae/oe/ue) wie im restlichen Repo; Markdown-Tabellen im Format
  der Node.

## Schritt 0 — Intent bestimmen

Frage bzw. erkenne aus der Nutzeranfrage, welcher der beiden Faelle vorliegt:

- **Fall A — Neue Retrospektive erfassen** (Standardfall, weiter mit Schritt 1).
- **Fall B — Nur Status/Feld eines bestehenden Action Items aendern** (z. B. "AI-03 ist jetzt
  abgeschlossen", "wer arbeitet gerade an was"). In diesem Fall:
  1. Lies die Action-Items-Tabelle in Node 15.
  2. Frage nach, falls die ID oder die gewuenschte Aenderung nicht eindeutig ist.
  3. Aktualisiere nur die betroffene(n) Zelle(n) (Status/Kommentar/Deadline/Verantwortlich), lasse
     alle anderen Felder unveraendert.
  4. Haenge einen `update`-Log-Eintrag an (nicht `retro`, da keine neue Retro stattfand).
  5. Fasse die Aenderung kurz zusammen und **beende hier** — die folgenden Schritte gelten nur fuer Fall A.

## Schritt 1 — Task/Workstream bestimmen (Pflicht)

1. Lies den Abschnitt "Task-Register" in Node 15 und zeige die vorhandenen Tags.
2. Frage den Nutzer, welchem Task die Retrospektive zuzuordnen ist — nutze das `argument-hint`, falls
   beim Aufruf bereits ein Task-Name mitgegeben wurde, aber bestaetige ihn trotzdem kurz.
3. Nennt der Nutzer einen Tag, der noch nicht im Task-Register steht: bestaetige, dass ein neuer Tag
   ergaenzt wird, und fuege ihn spaeter beim Schreiben (Schritt 5) als neue Zeile hinzu.

## Schritt 2 — Input-Modus waehlen

Frage den Nutzer, welcher Modus gilt:

- **Modus A — Vorhandene Meeting-Notes:** Der Nutzer liefert (einfuegt/anhaengt) Notizen einer bereits
  stattgefundenen Retrospektive. Extrahiere daraus Kandidaten-Punkte fuer "was lief gut" und "was haette
  besser laufen koennen" und lege sie dem Nutzer zur Bestaetigung/Korrektur vor, bevor du weitermachst
  (nichts stillschweigend uebernehmen, was nicht eindeutig aus den Notizen hervorgeht).
- **Modus B — Interaktive Retro-Sitzung:** Fuehre den Nutzer im Dialog durch die Retro. Stelle
  nacheinander offene Fragen, z. B.:
  1. "Was ist in diesem Zeitraum gut gelaufen?"
  2. "Was haette besser laufen koennen?"
  3. Optional ergaenzend: "Was sollten wir starten / stoppen / weiterhin tun (Start/Stop/Continue)?"
  Sammle die Antworten als Rohliste, bevor du zu Schritt 3 uebergehst.

Frage zusaetzlich nach **Ebene** (Team oder Persoenlich) und **Datum** der Retro (Default: heutiges Datum,
sofern der Nutzer nichts anderes nennt) sowie optional den Teilnehmenden.

## Schritt 3 — Clustern

1. Schlage dem Nutzer eine thematische Gruppierung der gesammelten "gut"/"besser"-Punkte vor (z. B.
   "Kommunikation", "Planung/Schaetzung", "Tooling"). Cluster sind optional — bei wenigen/unklaren
   Punkten reicht auch keine Clusterung.
2. Bespreche die Cluster-Vorschlaege mit dem Nutzer, passe Benennung/Zuordnung nach Feedback an.

## Schritt 4 — Action Items erarbeiten

1. Gehe mit dem Nutzer durch die (geclusterten) "besser"-Punkte und leite gemeinsam konkrete,
   priorisierte Action Items ab. Nicht jeder Punkt muss zwingend ein Action Item ergeben.
2. Erfrage pro Action Item **einzeln und explizit**:
   - **Titel** (kurz, praegnant)
   - **Erklaerung** (was konkret erreicht werden soll)
   - **Verantwortlich** (Name/Rolle)
   - **Deadline** (Zieldatum)
   - **Prioritaet** (1 = hoechste, 2, 3)
   - Task-Bezug uebernimmt standardmaessig den in Schritt 1 gewaehlten Tag, frage nach falls ein
     einzelnes Item einem anderen Task zuzuordnen ist.
3. Status neuer Action Items ist immer `🔴 offen`.

## Schritt 5 — Node 15 aktualisieren

1. Lies [mem-index/15_Retrospektiven-und-Action-Items.md](../../mem-index/15_Retrospektiven-und-Action-Items.md)
   vollstaendig, ermittle die naechste freie `R-`- und `AI-`-Nummer.
2. Falls in Schritt 1 ein neuer Task-Tag noetig war: ergaenze eine neue Zeile im Task-Register.
3. Haenge im Abschnitt "Retrospektiven-Log" einen neuen Eintrag `### R-XX — <Kurztitel>` an (Datum,
   Ebene, Task-Bezug, Teilnehmer falls genannt, "Was lief gut", "Was haette besser laufen koennen",
   Cluster/Themen falls vorhanden, Liste der neuen `AI-`-IDs).
4. Haenge im Abschnitt "Action-Items (global)" fuer jedes neue Item eine Tabellenzeile an (ersetze dabei
   die Platzhalterzeile `| — | — | ... |`, falls es der allererste Eintrag ist).
5. Bestehende Zeilen/Eintraege werden **nie** entfernt oder inhaltlich umgeschrieben.

## Schritt 6 — Log-Eintrag anhaengen

Haenge an `mem-index/log.md` einen Eintrag vom Typ `retro` an (Format wie im Root-`copilot-instructions.md`
beschrieben):

```markdown
## [YYYY-MM-DD] retro | <Kurzbeschreibung>

**Aktion:** Retrospektive (<Ebene>, Task <Tag>) durchgefuehrt, Cluster erarbeitet, Action Items abgeleitet.
**Geaenderte Nodes:** [[15_Retrospektiven-und-Action-Items]]
**Details:** R-XX erfasst (<n> "gut"-Punkte, <n> "besser"-Punkte, Cluster: <Liste oder "keine">).
Neue Action Items: AI-XX (<Titel>, Prio <n>), ...

---
```

## Schritt 7 — Zusammenfassung

Gib dem Nutzer eine kurze Zusammenfassung: neue `R-`-ID, neue `AI-`-IDs mit Titel/Verantwortlich/Deadline/
Prioritaet, und einen Hinweis, dass der Log-Eintrag geschrieben wurde.
