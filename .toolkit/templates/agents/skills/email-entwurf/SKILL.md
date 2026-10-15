---
name: email-entwurf
description: "Erstellt im Dialog mit dem User einen E-Mail-Entwurf an Projekt-Stakeholder: klärt Empfänger (To/CC/BCC), Thema/Zweck, Inhalt sowie Sprache, Stil (formell/halbformell/locker), Länge und Struktur, und legt den Entwurf als .md in export-artefacts/emails/ ab. Use when: E-Mail entwerfen, Mail an Stakeholder, E-Mail schreiben, Email-Entwurf, Nachricht an Partner/Kunde/Team, Anfrage per Mail, Follow-up-Mail, draft email."
argument-hint: "Optional: Empfänger, Thema/Zweck, Stichworte zum Inhalt, gewünschter Stil/Länge/Sprache"
---

# email-entwurf

Führt den User interaktiv durch die Definition einer E-Mail (Empfänger, Thema, Inhalt, Sprache, Stil,
Länge) und erzeugt daraus einen versandfertigen **Entwurf**. Der Skill sendet nichts – er liefert
einen Entwurf zum Kopieren in den Mailclient.

## Grundregeln (immer einhalten)

- **Immer per `ask_user` fragen**, nie als Fliesstext. Alle Fragen einer Phase **gebündelt** in einem Formular
  stellen. Bereits vom User genannte Angaben nicht erneut erfragen, sondern als Vorschlag vorbelegen.
- **Nichts erfinden.** Fakten (Termine, Zahlen, Zusagen, Anforderungen, Namen, Rollen, E-Mail-Adressen) nur aus
  (1) `mem-index/`, (2) den Angaben des Users in dieser Anfrage, (3) Dateien, die der User **explizit** nennt.
  Was fehlt, erfragen oder als `[TODO: …]` im Entwurf lassen.
- **Quellen-Whitelist:** Lesen nur `mem-index/` (zuerst `00_INDEX.md`, dann `02_Stakeholder.md` sowie 1–2 für das Thema
  relevante Nodes), `mandate.config.json` (nur für den Absender-Default), `export-artefacts/emails/` (nur als
  Stilreferenz/Duplikatprüfung) und explizit genannte Pfade. Dieser Skill-Aufruf hebt die File-access restriction
  aus `AGENTS.md` ausschliesslich dafür auf. Nie selbständig in `raw_input-documents/`,
  `input_client-docs/`, `arbeits-dokument/` suchen.
- **Keine E-Mail-Adressen oder Kontaktdaten raten.** Nur verwenden, was im Index/Input steht; sonst `[TODO: Adresse]`.
- **Keine Vertraulichkeitsverletzung:** Keine Angebotsinhalte (Preise, Lösungsdetails, Strategie, interne Einschätzungen)
  an Empfänger ausserhalb der eigenen Firma (siehe `mandate.config.json`) geben, ohne dass der User den Inhalt
  ausdrücklich freigibt. Bei internen Empfängern darf offener gesprochen werden.
- Ergebnis **nicht committen**, ausser der User verlangt es.

## Ablauf

### 1. Kontext laden (still, ohne Rückfrage)
- `mem-index/00_INDEX.md` und `mem-index/02_Stakeholder.md` lesen → Stakeholder-Liste (Name, Rolle, Kontakt, Einfluss).
- Absender-Default: `projectLead` aus `mandate.config.json` – im Schritt 2 trotzdem bestätigen lassen
  (der Absender kann ein anderes Teammitglied sein).
- `export-artefacts/emails/` auflisten (Dateinamen) für Stilreferenz und Vermeidung von Duplikaten.

### 2. Empfänger definieren (Gate)
Per `ask_user` erfragen, Vorschläge aus `02_Stakeholder.md` als Auswahlliste anbieten (Mehrfachauswahl, Freitext erlaubt):
- **An (To)**, **CC**, **BCC** (optional) – Personen oder Stakeholder-Gruppen; Rolle je Empfänger festhalten.
- **Absender** (Name, Rolle, Firma) und gewünschte **Signatur**.
- **Beziehung/Kontext** je Empfängergruppe: intern (eigene Firma), Partner/Subunternehmer, Vergabestelle/Behörde,
  Konkurrenz, Sonstige. Diese bestimmt die Warnhinweise unten.

**Pflicht-Warnhinweise** (dem User vor dem Weitergehen zeigen, falls zutreffend; Entscheid des Users abwarten):
- **Vergabestelle / öffentliche Beschaffung:** Prüfe `02_Stakeholder.md` auf Kontaktbeschränkungen (z. B. direkte
  Kontakte untersagt, Fragen nur über ein offizielles Portal/Frageforum zulässig). Ist das der Fall, statt einer
  E-Mail die passende **Portal-/Frageforum-Eingabe** formulieren. Ausnahme nur, wenn der User bewusst eine andere
  Kontaktart bestätigt (z. B. eine in `02_Stakeholder.md` ausdrücklich erlaubte Kontaktadresse).
- **Konkurrenzanbieter** (gemäss `02_Stakeholder.md` oder Angabe des Users): auf das Risiko hinweisen
  (Vertraulichkeit, Wettbewerbs-/Submissionsrecht). Nur mit ausdrücklicher Bestätigung des Users weitermachen.
- **Empfänger nicht im Index:** Rolle/Beziehung nachfragen; Adresse als `[TODO]` markieren.
- **BCC bei externen Empfängern:** Zweck kurz bestätigen lassen (Datenschutz/Transparenz).

### 3. Thema und Zweck klären
Per `ask_user` erfragen:
- **Zweck** (Auswahl): Anfrage/Klärung · Information/Status-Update · Einladung/Terminvereinbarung · Follow-up/Erinnerung ·
  Entscheidungs-/Freigabeanfrage · Dank/Feedback · Eskalation · Sonstiges.
- **Betreff-Thema** in einem Satz.
- **Gewünschtes Ergebnis** (Call-to-Action): Was soll der Empfänger tun, bis wann? (Frist nur, wenn der User sie nennt.)
- **Bezug**: Auslöser/Vorgeschichte, frühere E-Mails (Dateien in `export-artefacts/emails/` auf Wunsch als Kontext lesen),
  relevante Index-Nodes oder offene Fragen (`08_Offene-Fragen.md`, z. B. ID F-xx).

### 4. Inhalt definieren
Per `ask_user` erfragen:
- **Kernbotschaften / Stichworte** (Freitext); bei Bedarf Vorschläge aus relevanten Index-Nodes machen
  und zur Auswahl stellen (Mehrfachauswahl) – jeweils mit Node-Verweis, damit der User die Herkunft sieht.
- **Fragen an den Empfänger** (nummerierte Liste gewünscht? Tabelle bei > 5 Punkten sinnvoll?).
- **Anhänge/Links** (nur Namen/Pfade vermerken, nichts erfinden).
- **Tabu-Themen / nicht erwähnen** (z. B. Preise, Konkurrenz, interne Strategie).

### 5. Format-Parameter definieren
Optionen und Details siehe [email-parameter.md](./references/email-parameter.md). Per `ask_user` (Auswahlfelder mit
Default-Vorschlag, abgeleitet aus Empfänger und Zweck) erfragen:
- **Sprache:** Deutsch (CH) · Deutsch (DE) · Französisch · Englisch · Mehrsprachig (z. B. DE + FR).
- **Stil/Tonalität:** formell · halbformell (professionell-freundlich) · locker/kollegial · knapp-direkt.
- **Anrede:** Sie/Du, Vorname/Nachname/„Sehr geehrte Damen und Herren“, Grussformel.
- **Länge:** sehr kurz (≤ 80 Wörter) · kurz (80–150) · mittel (150–300) · ausführlich (> 300).
- **Struktur:** Fliesstext · Aufzählung · nummerierte Fragen · Tabelle · Kombination.
- **Betreff-Stil:** sachlich-beschreibend · mit Präfix (z. B. „Aktion erforderlich“) · knapp.
- **Anzahl Varianten:** 1 Entwurf (Default) oder 2 Varianten (z. B. formeller vs. lockerer).

Nicht gewählte Parameter nicht erzwingen: Defaults gemäss [email-parameter.md](./references/email-parameter.md)
verwenden und im Entwurfsprotokoll als „Default“ kennzeichnen.

### 6. Zusammenfassung bestätigen (Gate)
Kompakte **Briefing-Zusammenfassung** zeigen (Empfänger, Betreff-Thema, Zweck/CTA, Kernpunkte, Sprache, Stil, Länge,
Struktur, Quellen) und per `ask_user` bestätigen/korrigieren lassen, **bevor** der Entwurf geschrieben wird.
Offene Lücken gebündelt erfragen; ist keine Antwort möglich, `[TODO: …]` im Entwurf setzen.

### 7. Entwurf schreiben
Datei: `export-artefacts/emails/YYMMDD_email_<kontext-slug>.md` (Datum heute, Slug klein, `-` statt Leerzeichen,
z. B. `261015_email_statusupdate-partner`); **nie überschreiben** (sonst `_v2`, `_v3`).
Struktur (analog zu bestehenden E-Mail-Entwürfen):

```markdown
# E-Mail an <Empfänger/Gruppe> – <Thema>

**Entwurf – Stand YYYY-MM-DD**

## Metadaten

- **An:** <Name, Rolle, Firma>
- **Von:** <Name, Rolle, Firma>
- **CC:** <…>            (Zeile weglassen, wenn leer)
- **BCC:** <…>           (Zeile weglassen, wenn leer)
- **Betreff:** <Betreff>

---

## E-Mail-Entwurf

<Anrede>

<Text gemäss Stil, Länge, Struktur>

<Grussformel>

<Name>
<Rolle> | <Firma>
```

Regeln:
- Text exakt gemäss bestätigten Parametern; Fachbegriffe wie in `14_Glossar.md`.
- Der Entwurf selbst bleibt **sauber**: keine Quellenverweise, Kommentare oder Wiki-Links im E-Mail-Text.
- Bei 2 Varianten: `## E-Mail-Entwurf – Variante A` / `Variante B` im selben File.
- Tabellen nur, wenn im Format-Schritt gewählt; einfach halten, damit sie sich in Outlook einfügen lassen.

### 8. Entwurfsprotokoll (Begleitdatei)
`<name>.quellen.md` neben dem Entwurf anlegen:
- Bestätigtes Briefing (Empfänger, Zweck, CTA, Sprache, Stil, Länge, Struktur; Defaults gekennzeichnet)
- Tabelle **Aussage/Abschnitt → Quelle** (Index-Node `[[xx_Name]]`, User-Angabe oder genannte Datei)
- `[TODO]`-Lücken, Annahmen, gezeigte Warnhinweise samt User-Entscheid
- Kandidaten für `08_Offene-Fragen.md` (dem User vorschlagen, nicht automatisch eintragen)

### 9. Log-Eintrag
An `mem-index/log.md` **unten anhängen** (append-only), Typ `query`:
```markdown
## [YYYY-MM-DD] query | E-Mail-Entwurf erstellt: <Betreff-Thema> → <Ausgabedatei>

**Aktion:** E-Mail-Entwurf an <Empfänger> im Dialog mit dem User definiert und aus mem-index (und <Zusatzquellen oder "keine">) erstellt.
**Geänderte Nodes:** keine
**Details:** Ausgabe: <Pfad>; Protokoll: <Pfad>; Sprache/Stil/Länge: <…>; offene Lücken: <n>.

---
```

### 10. Verifikation und Übergabe
- Entwurf neu einlesen: alle Pflichtfelder gesetzt, keine ungewollten Platzhalter (nur bewusste `[TODO: …]`),
  Anrede/Grussformel passen zu Sie/Du und Stil, Länge im gewählten Bereich (Wortzahl grob prüfen),
  Aussagen nur aus bestätigten Quellen, keine nicht freigegebenen vertraulichen Inhalte.
- Abschlussmeldung kurz: Ausgabepfade, Anzahl Lücken, genutzte Index-Nodes, Hinweis auf offene Warnhinweise.
- Anschliessend per `ask_user` Anpassungen anbieten (kürzer/länger, formeller/lockerer, Sprache wechseln, Übersetzung);
  Überarbeitungen als neue Version (`_v2`) speichern und im Log ergänzen.
