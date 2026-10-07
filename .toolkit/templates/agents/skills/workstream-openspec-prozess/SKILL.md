---
name: workstream-openspec-prozess
description: Begleitet einen Analyse-Sprint-Workstream schrittweise durch die 10 Schritte des OpenSpec-Prozess-Leitfadens, merkt sich den Fortschritt sitzungsuebergreifend und pflegt den zugehoerigen OpenSpec-Change.
argument-hint: Name des Workstreams (optional)
---

# workstream-openspec-prozess

Du begleitest das Team dabei, fuer **einen Analyse-Sprint-Workstream** die
[analyse-sprint/openspec-prozess-leitfaden.md](../../../analyse-sprint/openspec-prozess-leitfaden.md)
Schritt fuer Schritt durchzuarbeiten. Der Leitfaden hat **10 Schritte (0–9)**:

| # | Schritt | Kernbefehl(e) |
|---|---|---|
| 0 | Triage (IDs klassifizieren) | keiner |
| 1 | `proposal.md` erfassen | `new change`, `instructions proposal` |
| 2 | `design.md`: Fakten und Optionen | `status --change` |
| 3 | Evidenz sammeln (Workshop/Review/Spike) | keiner |
| 4 | Entscheid dokumentieren | keiner — **kein Entscheid -> zurueck zu 3** |
| 5 | `spec.md`: Requirements festschreiben | `instructions specs`, `validate --strict` |
| 6 | Readiness-Gate | `validate --strict` — **nicht erfuellt -> zurueck zu 2** |
| 7 | `tasks.md` zerlegen | `instructions tasks` |
| 8 | Umsetzung | Tests + `validate --strict` |
| 9 | Abnahme und Baseline | `archive` |

**Wichtig:** Die Tabelle oben ist nur eine Gedaechtnisstuetze. Lies fuer den tatsaechlich zu
bearbeitenden Schritt **immer** den vollen Abschnitt im Leitfaden (Ziel, Wer, Was tun, Befehl,
Fertig-wenn) und wende genau diesen an. Erfinde keine eigene Variante.

Verwechsle diese 10 Leitfaden-Schritte **nicht** mit der 7-schrittigen "Bearbeitungsabfolge" in
den einzelnen `*_workstream-<slug>.md`-Dateien (Abschnitt 3 dort, erzeugt von der Skill
`analysis-boot-workstream`). Diese Datei ist nur **Quelle** fuer Scope, Rollen und IDs des
Workstreams — der prozessuale Fortschritt richtet sich ausschliesslich nach den 10
Leitfaden-Schritten.

## Grundprinzipien (immer einhalten)

- **Mensch entscheidet, AI entwirft, CLI validiert.** Nie fachlich selbst entscheiden.
- **Nur aus den Quellen ableiten.** Grundlagen-/Workstream-Datei des Workstreams und `mem-index/`;
  nichts erfinden. `instructions <artefakt>` zeigt nur die Schablone, der Inhalt kommt von dir.
- **Kein Schritt ohne Vorgaenger.** Ein Schritt gilt erst als bearbeitbar, wenn sein Vorgaenger
  im Tracker den Status `erledigt` oder `in Arbeit` hat.
- **Transparenz nach jedem Schritt.** Fasse nach jeder Bearbeitung zusammen: was wurde erarbeitet,
  welcher Schritt ist das naechste, welcher OpenSpec-Befehl wurde ausgefuehrt.
- **Unsicher? Nachfragen statt entscheiden.** Bei Unklarheit ueber Vorgehen, Loeschungen oder
  Interpretation der Quellen immer zuerst beim Nutzer nachfragen.
- **Loeschen/Bereinigen nur nach Bestaetigung.** Nie eigenmaechtig Dateien in `openspec-sdd`
  entfernen oder ueberschreiben, ohne die konkrete Aenderung vorher zu zeigen und bestaetigen zu
  lassen.

## Schritt A — Workstream bestimmen (immer zuerst)

1. Wenn kein Workstream als Argument uebergeben wurde, oder der Nutzer eine Uebersicht wuenscht
   ("liste Workstreams", "Status"): ermittle die bekannten Workstreams wie in der Skill
   `analysis-boot-workstream` Schritt 0 beschrieben (eigener Katalog, falls vorhanden, sonst
   Ableitung aus `analyse-sprint/*_workstream-*.md` und `openspec-sdd/openspec/changes/`). Reichere jede Zeile mit
   dem Fortschritt aus `analyse-sprint/_openspec-fortschritt/<slug>.md` an, falls vorhanden (sonst
   "kein Fortschritt erfasst"). Zeige eine Tabelle: Workstream | Slug | aktueller Schritt | naechster Schritt.
2. Frage den Nutzer, an welchem Workstream gearbeitet werden soll. Ein Name, der noch nirgends
   erfasst ist, ist erlaubt (neuer Workstream).
3. Bestimme `<slug>` (kebab-case des Workstream-Namens) und den erwarteten OpenSpec-Change-Namen
   `<slug>` (Change-Name = Slug, kein fester Produkt-Prefix, ausser das Mandat hat sich auf eine
   eigene Namenskonvention geeinigt — dann konsistent beibehalten).

## Schritt B — Kontext laden

1. Suche in `analyse-sprint/` nach `*_grundlagen-<slug>.md` und `*_workstream-<slug>.md`.
   - **Fehlt eine der beiden Dateien:** Erklaere dem Nutzer, dass der Workstream zuerst mit der
     Skill `analysis-boot-workstream` ausgearbeitet werden muss, biete an, diesen Aufruf jetzt
     zu nennen/vorzubereiten, und **stoppe** den 10-Schritte-Prozess fuer diesen Workstream bis
     die Dateien existieren.
   - **Beide vorhanden:** Lies beide Dateien vollstaendig.
2. Lies (falls vorhanden) `analyse-sprint/_openspec-fortschritt/<slug>.md`. Existiert die Datei
   nicht, lege sie gemaess folgendem Format an (alle Schritte `offen`):

   ```markdown
   # OpenSpec-Fortschritt: <Workstream-Name>

   **Slug:** `<slug>` · **OpenSpec-Change:** `<slug>`
   **Grundlagen-Datei:** analyse-sprint/<...>_grundlagen-<slug>.md
   **Workstream-Datei:** analyse-sprint/<...>_workstream-<slug>.md
   **Letzter Sync-Check mit openspec-sdd:** noch keiner

   | # | Schritt | Status | Datum | Nachweis / Notiz |
   |---|---|---|---|---|
   | 0 | Triage | offen | | |
   | 1 | proposal.md | offen | | |
   | 2 | design.md (Fakten/Optionen) | offen | | |
   | 3 | Evidenz sammeln | offen | | |
   | 4 | Entscheid dokumentieren | offen | | |
   | 5 | spec.md | offen | | |
   | 6 | Readiness-Gate | offen | | |
   | 7 | tasks.md | offen | | |
   | 8 | Umsetzung | offen | | |
   | 9 | Abnahme und Baseline | offen | | |
   ```

   Status-Werte: `offen` · `in Arbeit` · `erledigt` · `blockiert` (mit Grund in der Notiz-Spalte).

## Schritt C — Sync-Check gegen openspec-sdd (vor jeder inhaltlichen Arbeit)

1. Fuehre aus:
   ```powershell
   cd openspec-sdd
   npx --yes @fission-ai/openspec@latest list
   npx --yes @fission-ai/openspec@latest status --change <slug>
   ```
2. Vergleiche das Ergebnis mit dem Tracker:
   - Existiert `<slug>` nicht, obwohl der Tracker Schritt 1+ als `erledigt` fuehrt (oder
     umgekehrt) -> Diskrepanz dem Nutzer zeigen, klaeren bevor es weitergeht.
   - Findest du andere, nicht mehr referenzierte oder offensichtlich veraltete Change-Ordner
     (z. B. Test-Artefakte aus frueherem Seeding) -> **liste sie auf und frage explizit nach**,
     ob sie geloescht werden sollen. Loesche nie ohne diese Bestaetigung.
3. Aktualisiere im Tracker das Feld "Letzter Sync-Check mit openspec-sdd" mit dem heutigen Datum.

## Schritt D — Stand zusammenfassen

Ermittle aus dem Tracker den letzten `erledigt`-Schritt und den naechsten `offen`/`in Arbeit`-Schritt.
Fasse dem Nutzer zusammen:

- Was fuer diesen Workstream bereits erarbeitet wurde (kurz, mit Verweis auf Change-Artefakt).
- Welcher Schritt als naechstes ansteht — zitiere dafuer Ziel/Wer/Was tun/Befehl/Fertig-wenn aus
  dem Leitfaden fuer genau diesen Schritt.

## Schritt E — Nutzerentscheid einholen

Frage: **weiter zum naechsten Schritt** oder **Korrektur an einem frueheren Schritt**?

- Korrektur ist nur fuer Schritte mit Status `erledigt` oder `in Arbeit` erlaubt.
- Wuenscht der Nutzer einen Schritt, der noch `offen` ist und **nicht** der unmittelbar naechste
  Schritt ist (also ein noch nicht erarbeiteter, weiter in der Zukunft liegender Schritt): **ablehnen**,
  kurz begruenden ("Schritt X setzt Schritt Y voraus, der noch offen ist") und den tatsaechlich
  naechsten Schritt anbieten.

## Schritt F — Schritt gemeinsam bearbeiten

1. Setze den gewaehlten Schritt im Tracker auf `in Arbeit`.
2. Wende exakt die im Leitfaden fuer diesen Schritt beschriebene Vorgehensweise an: die dort
   angegebenen Prompt-Vorlagen ausfuellen (Quellen: Grundlagen-/Workstream-Datei,
   `mem-index/`, ggf. vorheriger Change-Inhalt) und die dort genannten OpenSpec-CLI-Befehle im
   Ordner `openspec-sdd` ausfuehren, sofern der Schritt einen Befehl vorsieht.
3. Arbeite die Inhalte **gemeinsam mit dem Nutzer** aus — schlage Text vor, hole Bestaetigung
   ein, uebernimm keine Fachentscheidung selbst. Bei Unsicherheit nachfragen.
4. Nach Abschluss: Tracker-Zeile auf `erledigt` setzen, Datum und kurzen Nachweis (z. B. Pfad der
   aktualisierten Datei, Ergebnis von `validate --strict`) eintragen.
5. Gib eine transparente Kurz-Zusammenfassung: was wurde erarbeitet, aktueller Fortschritt,
   naechster Schritt.

## Schritt G — Eingebaute Rueckspruenge des Leitfadens erkennen

Beachte die zwei im Leitfaden-Flowchart vorgesehenen automatischen Rueckspruenge und schlage sie
**aktiv vor**, sobald sie eintreten (nicht erst auf Nachfrage):

- **Schritt 4 ohne Entscheid** -> Status `blockiert` mit Grund, Vorschlag: zurueck zu Schritt 3
  (weitere Evidenz sammeln).
- **Schritt 6 (Readiness-Gate) nicht bestanden** -> Vorschlag: zurueck zu Schritt 2 (`design.md`
  schaerfen), nicht sprintreife Punkte bleiben als Analyseaufgabe im Tracker vermerkt.

## Schritt H — Schritt 9: Abnahme und Baseline

`archive` ist schwer reversibel. Fuehre den Archivierungsbefehl erst aus, nachdem der Nutzer die
fachliche Abnahme **ausdruecklich bestaetigt** hat. Trage danach im Tracker Schritt 9 als
`erledigt` ein und weise auf die neue Baseline unter `openspec-sdd/openspec/specs/` hin.

## Zusaetzliche Agenten-Standards (ergaenzen den Leitfaden, ersetzen ihn nicht)

Diese Standards praezisieren, **wie** du Schritt 0, 2 und 3 des Leitfadens umsetzt. Sie
widersprechen dem Leitfaden nicht, sondern legen ein konsistentes Format fest.

### Triage-Dokument (Schritt 0)

- Biete zusaetzlich zur Arbeitsliste im Chat **optional** an, sie als eigenes Dokument unter
  `analyse-sprint/_openspec-fortschritt/triage-<slug>.md` abzulegen. Erst nach Zustimmung anlegen.
- Tabellen-Spalten fuer den Kernumfang: `ID | Kurzinhalt (voller Thementext) | Typ | Status |
  Domain-Stakeholder (vermutete Reihenfolge, mit vermutetem Beitrag je Person) | Spielraum |
  Naechste Aktivitaet`.
  - **Kurzinhalt:** immer den **vollen Thementext** aus der Quelle einsetzen (z. B. Name +
    Beschreibung aus dem jeweiligen Requirements-Node, oder Frage-/Kern-des-Widerspruchs-Text aus
    `08_Offene-Fragen.md` bzw. einem projektspezifischen Konflikt-Register, falls vorhanden), nicht
    nur eine Kurzfassung. Ist die zugrunde liegende ID bereits **teilweise** durch einen anderen
    mem-index-Node beantwortet, das explizit mit Verweis auf die entlastende Quelle im Kurzinhalt
    vermerken, statt die ID pauschal als ungeklaert zu fuehren.
  - **Domain-Stakeholder:** vermutete Reihenfolge, wer zuerst antworten/entscheiden sollte.
    Quelle fuer Rollen/Organisation: `mem-index/02_Stakeholder.md`. Als Vorschlag kennzeichnen,
    nie als Tatsache. **Bei jeder Person in der Kette in Klammern konkret vermerken, welchen
    Beitrag genau sie vermutlich liefern soll** (nicht nur "entscheidet" oder "bestaetigt",
    sondern was fachlich/technisch von ihr erwartet wird).
  - **Spielraum:** 🟢 Hoch (Team kann Optionen/Entwuerfe selbst erarbeiten, externe Seite
    bestaetigt nur) · 🟡 Mittel (Team bereitet vor, Entscheid liegt extern) · 🔴 Gering (reine
    Governance-/Fachentscheidung extern).
  - **Naechste Aktivitaet:** nie nur ein Schlagwort, sondern konkret und ausformuliert angeben,
    **was inhaltlich fehlt und wie ein Ergebnis beispielhaft aussehen koennte**. Muster: kurzer
    Titel in Fettschrift, danach stichwortartig die konkret zu klaerenden Teilpunkte.
    Nur mem-index-belegte oder aus der Quelle klar ableitbare Teilpunkte auffuehren; nichts
    fachlich Neues erfinden, das nicht schon in einer Quelle angelegt ist.
  - Trenne im Dokument klar **Kernumfang** (im Workstream zu klaerende IDs) von **nur als
    Abhaengigkeit vermerkt** (IDs mit Federfuehrung bei einem anderen Workstream).

### ID-Verlinkung (fuer alle in diesem Prozess erzeugten Dokumente)

Jede erwaehnte mem-index-ID (`UC-`, `FA-`, `NFA-`, `OP-`, `F-`, `K-`) als Markdown-Link auf ihre
**Definitionsstelle** setzen, z. B. Zeilennummer im jeweiligen Requirements-Node (fuer UC/FA/NFA/OP)
bzw. `mem-index/08_Offene-Fragen.md` (fuer F-) bzw. dem projektspezifischen Konflikt-Register
(fuer K-, falls vorhanden), z. B. `[F-01](../../mem-index/08_Offene-Fragen.md#L99)`. Zeilennummer
per Suche ermitteln, nicht schaetzen.

### Schritt 2: Sanity-Check gegen das Triage-Dokument

Nachdem `design.md` erstellt **und** vom Nutzer geprueft/bestaetigt wurde (Ende Schritt 2, bevor
zu Schritt 3 uebergegangen wird), biete dem Nutzer **immer** einen Sanity-Check an, falls ein
Triage-Dokument (`analyse-sprint/_openspec-fortschritt/triage-<slug>.md`) existiert:

1. Liste jede Kernumfang-ID aus dem Triage-Dokument auf und pruefe, ob sie in `design.md`
   aufgegriffen ist — entweder als belegte Tatsache (`Context`) oder als offener
   Entscheidungsbereich (`Decisions`/offene Punkte).
2. Melde explizit:
   - **Fehlende IDs:** im Triage-Dokument gelistet, aber in `design.md` nirgends erwaehnt.
   - **Widerspruechliche Einordnung:** z. B. eine ID, die im Triage-Dokument als `Konflikt` oder
     `Luecke` gilt, in `design.md` aber faelschlich als bereits belegte Tatsache dargestellt wird
     (oder umgekehrt).
   - **Abweichende Nachfolgehinweise:** wenn eine im Triage-Dokument dokumentierte Klarstellung
     in `design.md` nicht oder nur unvollstaendig uebernommen wurde.
3. Bei Uebereinstimmung ohne Befund: dem Nutzer kurz bestaetigen, dass alle Kernumfang-IDs
   abgedeckt sind, mit einer knappen Zuordnungstabelle oder -liste (ID -> Abschnitt in `design.md`).
4. Nur nach diesem Sanity-Check (und nach Behebung gemeldeter Abweichungen, falls der Nutzer das
   wuenscht) Schritt 2 im Tracker auf `erledigt` setzen und zu Schritt 3 uebergehen.

### Schritt 3: Standard-Exportangebot

Sobald Schritt 3 (Evidenz sammeln) bearbeitet wird, biete dem Nutzer **standardmaessig** drei
unabhaengig voneinander waehlbare Export-Dokumente an (alle, einzelne oder keines):

1. **Slidev-Praesentation** fuer den Workshop/die externe Klaerung.
2. **Ausformulierter Export des `design.md`** aus Schritt 2 (alle mem-index-IDs im Fliesstext
   aufgeloest).
3. **Kopie des Triage-Dokuments** aus Schritt 0.

Der Nutzer kann auch ein alternatives Exportformat wuenschen; erarbeite es dann gemeinsam mit ihm,
statt eines der drei Standardformate zu erzwingen.

#### Falls Slidev gewaehlt wird

- Existieren bereits fruehere Workshop-Decks unter
  `export-artefacts/praesentationen/slides/openspecs/`, lehne Struktur/Format daran an (Headmatter-
  Stil, `layout: section`/`center`, Presenter-Notes, Branding via `styles/branding.css`). Existiert
  noch keines, folge dem Vorgehen aus der Skill `slidev-praesentation`.
- Inhalt fokussiert **ausschliesslich** auf die zu klaerenden Punkte (Kontext, Optionen, "Zu
  klaeren", "Wer entscheidet", "Beratung durch ..."). Der interne OpenSpec-Prozess (Schritte,
  Tracker, CLI-Befehle) wird in den Slides **nie** erwaehnt.
- Ablage unter `export-artefacts/praesentationen/slides/openspecs/<YYYY-MM-DD>_<slug>-workshop/`;
  Ordnername vor dem Anlegen mit dem Nutzer bestaetigen.

#### Falls das Change-Proposal (`design.md`) exportiert wird

- Als eigenstaendige Kopie unter dem Namen `design-erklaert.md` ablegen: gleiche Gliederung wie
  `design.md`, aber alle mem-index-IDs im Fliesstext ausformuliert, IDs nur noch in Klammern.
- Ablageort: derselbe Ordner wie die exportierte Slidev-Praesentation, falls in derselben
  Session erzeugt. Existiert noch kein Export-Ordner, einen neuen Ordner unter `export-artefacts/`
  vorschlagen und vom Nutzer **bestaetigen lassen** (er kann Ort/Namen aendern).
