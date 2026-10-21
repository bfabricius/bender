# Template-Konventionen (fill-template-tauglich)

Ein gutes Template liefert dem Befüller **Gliederung + Stilvorlage**, aber keine fremden Inhalte.

## Entscheidung pro Element

| Aktion | Wann | Beispiel |
|---|---|---|
| **Fest** | Standardtext, der in jeder Instanz gleich ist (Rechtliches, Haftungs-/Vertraulichkeitssätze, Grussformeln, Pflicht-Überschriften, feste Spaltenköpfe) | «Dieses Dokument ist vertraulich zu behandeln.» |
| **Platzhalter** | Inhalt, der pro Instanz anders ist (Namen, Daten, Beträge, Projektbezug, Fliesstext-Inhalt) | `[Projektname]`, `[Datum, TT.MM.JJJJ]` |
| **Streichen** | Nur für die Ursprungsinstanz relevant und nicht generalisierbar | Verweis auf ein konkretes früheres Projekt |
| **Mehrfach** | Listen/Tabellenzeilen/Absätze, die sich wiederholen | 1–2 Platzhalter-Zeilen als Stilmuster belassen |

Im Zweifel (fest oder variabel?) beim User nachfragen, nicht raten.

## Platzhalter schreiben

- Format `[Beschreibung]` – wird von `inspect_docx.py` und `fill-template` erkannt.
- **Sprechend und mit Format-Hinweis:** `[Datum, TT.MM.JJJJ]`, `[Betrag in CHF]`, `[Beschreibung in 2–3 Sätzen]`,
  `[Name Vorname, Funktion]`.
- **Gleicher Wert → gleicher Platzhalter** (z. B. `[Kundenname]` überall), damit der Befüller konsistent ersetzt.
- Platzhalter in der **Sprache der Quelle** formulieren.
- Die Satzstruktur um den Platzhalter bleibt stehen (Stilmuster):
  «Die [Kundenname] beabsichtigt, [Vorhaben in einem Satz] umzusetzen.»
- Bei komplett variablem Fliesstext genügt **ein** Platzhalter pro Absatz mit Längenhinweis;
  Tonalitäts-/Stilhinweise (Sie-Form, Nominalstil) gehören in einen `> Hinweis:`-Block, nicht in den Platzhalter.
- Keine verschachtelten Klammern, keine eckigen Klammern für andere Zwecke.

## Hinweise für den Befüller (Markdown)

```markdown
> Hinweis: Max. 5 Bullets, Verbalstil, Zeitform Präsens.
```

`fill-template` entfernt Anleitungs-/Hinweistexte beim Befüllen. Sparsam einsetzen.

## Was nie im Template bleiben darf

Kunden-/Firmen-/Personennamen, E-Mail-Adressen, Telefonnummern, Projektnummern, konkrete Daten, Beträge,
interne Systemnamen, Dokument-Metadaten (Autor, Titel, Kommentare), eingebettete Kundenlogos/-bilder
(melden, User entscheidet). Ausnahme: ausdrücklich als **fest** bestätigte Bausteine (z. B. eigener
Firmenname im Briefkopf der eigenen Organisation).

## Format-spezifisch

- **`.docx`:** Formatvorlagen, Kopf-/Fusszeilen, Tabellenstile bleiben erhalten; Inhalt nur in den
  vorhandenen Formatvorlagen ändern. Mehrere Beispiel-Paragraphen mit `delete_paragraph` auf 1–2 reduzieren.
  `replace_text` für wiederkehrende Werte (wirkt auch in Kopf-/Fusszeilen).
- **`.pptx` → `.md`:** Folientitel → Überschrift (`##`), Folieninhalt → Platzhalter-Bullets,
  Sprechernotizen nur übernehmen, wenn sie stilprägend sind. Bilder/Diagramme als
  `> Hinweis: Hier Diagramm «[Thema]» einfügen` markieren.
- **`.xlsx` → `.md`:** Blatt → Abschnitt, Spaltenköpfe als Tabellenkopf, Datenzeilen → 1–2 Platzhalter-Zeilen;
  Formeln/Berechnungslogik nur als `> Hinweis:` beschreiben. Das Template ersetzt kein Rechenmodell.
