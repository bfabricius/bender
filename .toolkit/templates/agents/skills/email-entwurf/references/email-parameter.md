# E-Mail-Parameter – Optionen und Defaults

Referenz für Schritt 5 des Skills [email-entwurf](../SKILL.md). Die Defaults dienen als **Vorschlag** im
`ask_user`-Formular; der User entscheidet.

## Sprache

| Option | Hinweise |
|---|---|
| Deutsch (CH) | Default für Schweizer Empfänger. „ss“ statt „ß“, Schweizer Grussformeln („Freundliche Grüsse“). |
| Deutsch (DE) | Nur auf Wunsch. |
| Französisch | Bei zweisprachigen Regionen/Empfängern (z. B. gewisse Schweizer Kantone/Gemeinden): Formeln
„Veuillez agréer…“ (formell), „Cordialement“ (halbformell). |
| Englisch | Für internationale Partner; „Kind regards“ / „Best regards“. |
| Mehrsprachig | Reihenfolge und Trennung (Abschnitte pro Sprache) mit dem User festlegen. |

## Stil / Tonalität

| Stil | Merkmale | Typische Empfänger |
|---|---|---|
| Formell | Vollständige Sätze, „Sehr geehrte(r) Frau/Herr …“, „Sie“, „Freundliche Grüsse“, keine Umgangssprache | Behörden, Geschäftsleitung, erste Kontaktaufnahme |
| Halbformell | Professionell-freundlich, „Sie“ oder „Du“ nach Absprache, „Guten Tag Herr …“ / „Hallo Anna“, „Besten Dank und freundliche Grüsse“ | Partner, Lieferanten, bekannte Kunden |
| Locker/kollegial | Kurze Sätze, „Du“, „Hoi/Hallo“, „Beste Grüsse“ | Interne Teammitglieder |
| Knapp-direkt | Kernaussage in Satz 1, Bullet-Points, minimale Floskeln | Eilige Statusabfragen, interne Abstimmungen |

**Default-Ableitung:** intern → locker/halbformell; Partner/Lieferanten → halbformell; Behörden → formell.

## Länge

| Stufe | Richtwert | Einsatz |
|---|---|---|
| Sehr kurz | ≤ 80 Wörter | Bestätigung, Terminfrage, Erinnerung |
| Kurz | 80–150 Wörter | Einfache Anfrage, kurzes Update |
| Mittel | 150–300 Wörter | Anfrage mit Kontext, Entscheidungsvorlage (Default) |
| Ausführlich | > 300 Wörter | Mehrere Fragen/Tabelle, Erstkontakt mit Hintergrund |

## Struktur

- **Fliesstext:** persönliche Mails, kurze Nachrichten.
- **Aufzählung:** 3–6 gleichwertige Punkte.
- **Nummerierte Fragen:** wenn der Empfänger einzeln antworten soll (Bezug „zu Frage 3“ möglich).
- **Tabelle:** ab ca. 5 Punkten mit mehreren Attributen (Frage, Bezug, Status).
- **Empfohlener Aufbau:** Anrede → Anlass/Kontext (1–2 Sätze) → Kernpunkte → Call-to-Action mit Frist
  (nur wenn vom User genannt) → Grussformel → Signatur.

## Anrede und Grussformeln (CH)

| Stil | Anrede | Schluss |
|---|---|---|
| Formell | Sehr geehrter Herr Muster / Sehr geehrte Frau Muster / Sehr geehrte Damen und Herren | Freundliche Grüsse |
| Halbformell | Guten Tag Herr Muster / Guten Tag Frau Muster | Besten Dank und freundliche Grüsse |
| Locker | Hallo Anna / Hoi zusammen | Beste Grüsse |

Frühere Entwürfe in `export-artefacts/emails/` dienen als Stilreferenz (Anrede-/Schlussformel-Konventionen,
die sich im Projekt bereits bewährt haben) – vor dem Schreiben kurz sichten, falls vorhanden.

## Betreff

- **Sachlich-beschreibend (Default):** „<Thema> – <Bezug/Projekt>“.
- **Mit Präfix:** „Aktion erforderlich: …“, „Zur Information: …“, „Terminanfrage: …“ – nur wenn nötig.
- **Knapp:** ≤ 6 Wörter, für interne Mails.
- Keine vertraulichen Details (Preise, Konkurrenznamen) im Betreff.

## Standard-Defaults (wenn User nichts wählt)

| Parameter | Default |
|---|---|
| Sprache | Deutsch (CH) |
| Stil | gemäss Empfänger-Ableitung (oben), sonst halbformell |
| Anrede | „Sie“ bei Externen; „Du“ bei internen Kolleg:innen nur nach Bestätigung |
| Länge | Mittel |
| Struktur | Fliesstext; bei > 5 Fragen nummerierte Liste bzw. Tabelle |
| Betreff | Sachlich-beschreibend |
| Varianten | 1 |
| Signatur | Name, Rolle \| Firma (gemäss `mandate.config.json`) |

## Typische Zwecke → empfohlene Bausteine

| Zweck | Bausteine |
|---|---|
| Anfrage/Klärung | Kontext, Fragenliste, Bitte um Rückmeldung (Call/schriftlich), Dank |
| Status-Update | Kernaussage, Fortschritt, nächste Schritte, offene Punkte/Risiken |
| Einladung/Termin | Zweck, Dauer, Terminvorschläge (nur vom User genannte), Teilnehmende |
| Follow-up | Bezug auf frühere Mail (Datum/Thema), kurze Erinnerung, konkrete Bitte |
| Entscheidung/Freigabe | Entscheidungsfrage, Optionen mit Empfehlung, Konsequenzen, Frist |
| Dank/Feedback | Konkreter Anlass, Wirkung, nächster Schritt |
| Eskalation | Sachverhalt, Auswirkung, gewünschte Massnahme, Frist; sachlich bleiben |
