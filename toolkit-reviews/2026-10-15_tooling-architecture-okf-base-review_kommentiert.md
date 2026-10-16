# Toolkit review: tooling architecture, OKF and BASE — kommentierte Fassung

> **Zu dieser Fassung**
>
> - **Original:** `bfabricius/bender`, `toolkit-reviews/2026-10-15_tooling-architecture-okf-base-review.md`. Der Text ist unverändert übernommen.
> - **Kommentare:** 16.10.2026. Sie stehen als Zitatblöcke direkt nach der jeweiligen Stelle und sind fortlaufend nummeriert (K1, K2, …).
> - **Legende:** ✔ Zustimmung · ✖ Korrektur · ➕ Ergänzung · ❓ Rückfrage
> - **Grundlage der Kommentare:**
>   - normative OKF-Spezifikation `SPEC.md` v0.2 (24.07.2026) im Repo `GoogleCloudPlatform/open-knowledge-format`
>   - BASE v1.5.1 (vollständiges Repo, nicht nur README)
>   - lokale Kopie von Bender v0.4.0
>   - die Analysen „BASE-Ideen für Bender“ und „Bender ohne AI-Slop“
>
> **Zusammenfassung der Kommentare**
>
> 1. Der **Architekturteil (Abschnitt 1)** und der Abschnitt zu **nicht-technischen Rollen** sind stark. Ihnen wird weitgehend zugestimmt.
> 2. Der **OKF-Teil (Abschnitt 2)** beruht auf v0.1 bzw. auf der inkonsistenten Community-Seite okf.md. In v0.2 sind `status`, `sources`, `generated`, `verified` und `stale_after` **Standardfelder**. Fussnoten ersetzen den `# Citations`-Abschnitt. Der vorgeschlagene Exportstempel `generated: true` **kollidiert** mit dem OKF-Feld `generated`.
> 3. Damit verschiebt sich das Urteil: Das Frontmatter sollte gleich als **OKF-v0.2-Profil** angelegt werden. Es kostet kaum Mehraufwand und beantwortet die offene Frage zum Schema. Zurückstellen sollte man nur die Konflikte bei `log.md` und den Wikilinks.
> 4. Es fehlt eine Dimension: **Vertrauen in die Inhalte** (Prüfstatus, Veralten, menschliche Verantwortung). Gerade für nicht-technische Leser ist sie zentral.

Date: 2026-10-15

## Scope and basis

Reviewed:
- the 14 PowerShell scripts in `.toolkit/scripts/`
- the three new Python-based skills (`diagram-export`, `email-entwurf`, `fill-template`)
- `AGENTS.md.tmpl` and the mem-index templates
- the OKF spec (https://okf.md/spec, read in full)
- the BASE README (https://github.com/ai-swiss/base). I did not read its detailed standard, CLI or MCP docs.

> **K1 ✖ Quelle für OKF.** `okf.md` ist offenbar eine Community-Seite und widerspricht sich selbst:
> - Die Startseite spricht von „semver“, die Spezifikation von `<major>.<minor>`.
> - Der Footer nennt die Lizenz MIT, das Repo Apache-2.0.
> - Sie verlinkt auf `fabricioctelles/skills`.
>
> Massgebend ist die `SPEC.md` im Repo `GoogleCloudPlatform/open-knowledge-format`, aktuell **v0.2 vom 24.07.2026**. Die Aussagen in Abschnitt 2 sollten gegen diese Quelle geprüft werden (siehe K12–K18).

> **K2 ➕ BASE nur über das README.** Damit fehlen genau die Teile, die für Bender am meisten bringen:
> - `base doctor` mit seinen Signalen (u. a. `derived_stale`)
> - Gates
> - `derived_from` und `review_by`
> - das Sensitivitätsmodell
> - Lexikon- und Schreibprüfungen (`check-lexique`, `human-writing`)
>
> Die Schlüsse in Abschnitt 3 bleiben trotzdem vertretbar (siehe K20).

Not checked: which PS scripts depend on Windows-only APIs (e.g. Office COM). Tool and standard references not fetched live come from background knowledge and should be verified before relying on them.

> **K3 ➕ Nachgeprüft (lokale Kopie v0.4.0, 14 Skripte).** Kein Skript nutzt Office-COM. Plattformspezifisch sind nur zwei Stellen:
> - `export-md-to-pdf.ps1` sucht Edge oder Chrome unter Windows-Pfaden. Es braucht einen headless Chromium; das lässt sich portieren.
> - `convert-docs-to-text.ps1` lädt bei Bedarf Poppler für Windows (`pdftotext`) nach `.ingest-tools/poppler/`.
>
> Die Portierung nach Linux und macOS ist damit einfacher, als die offene Frage vermuten lässt. Die drei neuen Python-Skills sind in v0.4.0 noch nicht enthalten. Hier ist der Repo-Stand also neuer.

## Requirements as clarified

| Topic | Answer |
|---|---|
| Runtime | Assume Python. If the user rejects it, agree on an alternative runtime with the user. |
| Platforms | Priority 1 Windows, 2 Linux, 3 macOS. Not all needed immediately. |
| Users | Many project actor roles: sales/acquisition managers, executives, project leads, POs, QA, non-software engineering roles, stakeholders from varied backgrounds. Supporting these non-technical roles is a paramount requirement. |
| CLI vs skills | CLI users are assumed to be the more technical ones. Skills are the main interface for everyone else. How to maximise ease of use for the non-technical roles is not yet decided. |
| mem-index | Key knowledge DB of every project. Collaborative via git. |
| Exports | Transient snapshots (wiki, flat files, PDF). Never written back to the project. |
| Privacy | Decided per project and per client. |

> **K4 ❓ Annahme „Python“.** Auf typischen Windows-Rechnern in Beratung und Verwaltung ist kein Python installiert. Auf dem Rechner, auf dem diese Kommentare entstanden sind, ist das nachweislich so. Mit `uv` lässt sich das grundsätzlich lösen (siehe K9). Firmen-Policies sind aber ein echtes Risiko: Proxy, AppLocker/WDAC, keine Admin-Rechte, gesperrte Downloads.
>
> **Vorschlag:** In der Anforderungstabelle eine Zeile „Zielumgebung: verwaltete Firmen-Laptops ohne Admin-Rechte“ ergänzen und früh testen (siehe K23).

> **K5 ➕ Fehlende Anforderung: Vertrauen in die Inhalte.** Die Tabelle beschreibt Laufzeitumgebung, Rollen und Datenschutz. Ob ein Leser erkennen kann, **was im mem-index belegt, geprüft und aktuell ist**, fehlt.
>
> Für Vertrieb, Geschäftsleitung und Stakeholder, die Inhalte nicht selbst prüfen können, ist das mindestens so wichtig wie leichte Bedienung. Vorschlag für eine Zeile: „Vertrauen: Jede Node zeigt Herkunft, Prüfstatus (ungeprüft/maschinell/menschlich) und Ablaufdatum“.

## 1. Tooling architecture

### Assessment

The new Python skills use a better pattern than the PS scripts:

1. The agent writes a declarative spec (`spec.json`, `ops.json`).
2. A deterministic script builds the artefact.
3. A validator checks it (`validate_drawio.py`).
4. The agent fixes problems and rebuilds.

This is the strongest current pattern for reliable agent tooling. Interactive PS tools (the `search-index.ps1` REPL, the wizards) work for humans but not for agents.

> **K6 ✔ Zustimmung.** Dasselbe Prinzip steht hinter der Forderung „Zahlen nicht vom Modell“ aus der Slop-Analyse. Aufwände, FTE und Termine sollten deterministisch aus `09_Master-Schedule.json` berechnet und nicht vom Modell abgeschrieben werden.
>
> OKF v0.2 hat dafür einen eigenen Typ: `Attested Computation` (Runtime, Parameter, Berechnung, Executor mit Receipt, deterministischer Attester). Das kann später eine Option für Kennzahlen sein, ist aber nicht dringend.

### Recommendations

- **One CLI with a stable contract.** A single `bender <verb>` entry point, Python core. Each command should:
  - run without prompts
  - support `--json` output and `--dry-run`
  - use fixed exit codes (`export_drawio.py` already uses 2 = missing dependency)
  - report validator diagnostics as machine-readable codes and locations
- **Thin launchers.** `bender.ps1` and a `bender` shell script locate Python and run the CLI. If Python is missing, ask the user which runtime to use, store it in `mandate.config.json`, and provide `bender doctor` to check the setup. The JSON/exit-code contract keeps the runtime swappable.

> **K7 ✔ Zustimmung zum CLI-Vertrag.** Die Diagnose-Codes sollten von Anfang an stabil sein (z. B. `L01`, `L02` … wie die Lint-Regeln in den BASE-Ideen). Skills und Szenario-Tests können sich dann auf die Codes beziehen statt auf Meldungstexte.

> **K8 ➕ Zwei Bedeutungen von `doctor`.** Hier prüft `bender doctor` die **Umgebung** (Runtime, Abhängigkeiten). In BASE prüft `doctor` den **Inhalt**: veraltete Ableitungen, überfällige Reviews, fehlende Quellen.
>
> Beides ist wertvoll. Vorschlag: `bender doctor` für die Umgebung und `bender lint` bzw. `bender health` für den Inhalt, oder `bender doctor --env` und `--content`. Dann verwechseln Skills und Nutzer die beiden nicht.

- **Zero-setup dependencies.** PEP 723 inline script metadata with `uv run` instead of `requirements.txt.tmpl` plus manual pip.

> **K9 ✔ mit Vorbehalt.** `uv` kann bei Bedarf selbst ein Python herunterladen. Das ist der beste verfügbare Weg zu „zero setup“. Zu prüfen ist:
> - ob Downloads von `astral.sh`, GitHub und PyPI im Firmennetz erlaubt sind (Proxy, Allowlist)
> - wie mit einem internen Paket-Mirror umgegangen wird
> - ob ein **Offline-Bundle** (vorgepackte Wheels) als Rückfallebene nötig ist

- **Skills call the same commands.** Skills invoke `bender ...` instead of `python .agents/skills/.../x.py`. A small per-tool manifest (name, JSON Schema for inputs, read-only or writes, exit codes) could generate CLI help and SKILL.md snippets, and makes a later MCP wrapper cheap.
- **Port agent-facing tools first.** `log add`, `lint`, `search --json`, `export`, `status`, docs-to-text. Keep interactive wizards in PS where still useful. Agents currently append to `log.md` by hand in a strict format, which is brittle; `bender log add --type query ...` removes that.

> **K10 ✔ und ➕ `log add` als Hebel für die Migration.** Wenn nur noch `bender log add` in `log.md` schreibt, kann das Log-Format später an einer einzigen Stelle umgestellt werden, etwa auf das OKF-Format: neueste Einträge zuerst, `## YYYY-MM-DD`, `* **Update**: …`. Skills und Agenten bemerken die Umstellung nicht. Das entschärft die offene Frage zum Log-Format (siehe K13).
>
> Die Lint-Regel zum Log-Format und `project-status.ps1`, das `log.md` parst, sollten dieselbe Parser-Funktion nutzen.

- **Search at the right size.** SQLite FTS5 (Python stdlib) gives BM25 ranking plus frontmatter filters. Keep the index local, derived and gitignored. Embeddings/vector RAG are overkill for hundreds of nodes and usually send client data to a remote embedding API, which conflicts with per-client privacy.
- **Tests.** pytest golden-file tests against a small fixture mem-index.
- **Doc conversion.** Evaluate local tools (e.g. MarkItDown, Docling) in place of any Windows-only conversion.

> **K11 ✔ Zustimmung.** Zwei Hinweise:
> - Bei FTS5 kurz prüfen, ob das `sqlite3`-Modul des gewählten Python-Builds FTS5 mitbringt. Bei den gängigen Builds ist das so; ein Test in `bender doctor` kostet wenig.
> - Docling bringt grosse ML-Abhängigkeiten mit. Für „zero setup“ auf Firmen-Laptops ist MarkItDown die leichtere Wahl, Docling nur optional für schwierige PDFs.

**Not first:** an MCP server. For local scripts, CLI plus skill costs less context. Add MCP only for harnesses without shell access.

### Implications of the non-technical user requirement

The CLI serves technical users directly. For everyone else it is an implementation detail that skills call. This changes the priorities above:

- **Skills are the primary product surface for most roles.** Judge each skill by whether a non-technical person can complete a task in conversation, without knowing the CLI, git or file layout. The "Skills call the same commands" recommendation is therefore the central one, not a convenience.
- **Setup must be invisible to them.** Python/runtime checks, `bender doctor` and dependency installs should be run and explained by the skill, in plain language. A non-technical user should never have to debug a runtime problem; the "ask the user which runtime to use" fallback needs a guided, jargon-free flow.
- **Role-oriented skills.** Group skills by what a role wants to do (e.g. a sales manager preparing an offer, an executive getting a status summary, QA checking open questions) rather than by technical operation. Roles also differ in which nodes they should see or edit, which links to the sensitivity policy in section 3.
- **Safe-by-default writes.** Two-stage plan/apply writes matter more here, because non-technical users cannot easily review or repair a bad edit. Skills should show a plain-language summary of the change before applying it.
- **Reading and contributing paths differ.** Many roles will mostly read, and the transient exports (wiki, PDF, flat files) are likely their main read interface. Contributing via git is probably unrealistic for them, so skills need to mediate contributions (e.g. propose a change, a technical user or a review step merges it). How this should work is open.
- **Guardrails over expertise.** `lint`, generated indexes and read-only export stamps protect the mem-index from changes by users who cannot judge the structure themselves.

> **K12 ✔ Stärkster Abschnitt des Reviews.** Zwei Ergänzungen:
>
> 1. **Prüfstatus sichtbar machen.** Wer hauptsächlich über Exporte liest, braucht pro Abschnitt oder Node eine klare Kennzeichnung, z. B. „ungeprüft (KI-erzeugt am …)“, „vom PO geprüft am …“ oder „veraltet seit …“. Sonst wirken alle Inhalte gleich verlässlich, und das ist die Hauptursache für „AI-Slop“-Wahrnehmung.
>
>    OKF v0.2 liefert dafür die Felder `generated {by, at}`, `verified [{by, at}]` und `stale_after`. Die Vertrauensstufe *human-reviewed* ergibt sich, wenn ein Akteur `human:<id>` geprüft hat. Exporte sollten diese Stufe als Badge darstellen.
> 2. **Verantwortung bleibt menschlich.** Vermittelte Beiträge („propose a change“) brauchen eine benannte Person, die prüft und freigibt. Im Mandat ist das in der Regel der PO bzw. die Projektleitung. Diese Rolle sollte im Rollenmodell aus Schritt 0 ausdrücklich vorkommen, mit Zeitbudget. Sonst entstehen Freigaben, die nur formal erteilt werden.

## 2. OKF (Open Knowledge Format)

**Verdict: borrow ideas, don't chase conformance yet.** OKF is a v0.1 draft aimed at data catalogs; real-world adoption is unverified. The mem-index is already close to it (markdown tree, index, `log.md`, cross-links). Conformance needs only frontmatter with a non-empty `type` on every non-reserved `.md` file.

> **K13 ✖ Version und Ausrichtung.**
> - Aktuell ist **v0.2 (24.07.2026)**.
> - v0.2 ergänzt Felder für Vertrauen und Aktualität: `sources` (mit `id`, `resource`, `title`, `author`, `last_modified`), `generated`, `verified`, `status` (`draft | stable | deprecated`), `stale_after` sowie den Typ `Attested Computation`.
> - Damit richtet sich OKF ausdrücklich auch an Wissen, das Agenten erzeugen und pflegen, nicht nur an Datenkataloge.
> - Richtig bleibt: Die Spezifikation ist vor 1.0, und belastbare Belege für eine breite Verbreitung fehlen.
>
> **Folge für das Urteil:** Fürs Frontmatter ist Konformität praktisch gratis, denn Bender will diese Felder ohnehin einführen (Punkt 1 unten). Man sollte sie **gleich in OKF-Form** anlegen, statt eigene Varianten zu bauen. Zurückstellen sollte man nur die strukturellen Konflikte (`log.md`, Wikilinks).
>
> **Neue Formulierung:** „Frontmatter als OKF-v0.2-Profil übernehmen. Volle Konformität (log.md, Links) erst, wenn der Nutzen belegt ist.“

### Conflicts with the current mem-index

| OKF | bender today |
|---|---|
| Reserved `log.md`: date headings, newest first | Append-only at the bottom, `## [date] typ \| ...` |
| Standard markdown links | `[[wikilinks]]` |
| One concept per file | Aggregate nodes (`03_Anforderungen.md`) |

> **K14 ✖ und ➕ zur Tabelle.**
> - **„One concept per file“ ist keine OKF-Pflicht.** Die Beispiele sind eher atomar, Sammel-Nodes sind aber konform. Diese Zeile ist kein Konflikt und sollte gestrichen oder als „Konvention“ markiert werden.
>
>   Empfehlung: Sammel-Nodes beibehalten. Benders Leseprotokoll („1–3 Nodes lesen“) lebt davon. Optional nur Entscheide und Konflikte als Einzeldateien führen (`type: Decision`).
> - **Fehlende Zeile: Index.** OKF reserviert `index.md` als reine Liste (`* [Titel](/pfad) - Beschreibung`), ohne Frontmatter. Ausnahme ist `okf_version` im Wurzel-Index.
>
>   Benders `00_INDEX.md` vereint Navigationsbaum, Quick-Navigation, Quelldokument-Mapping und KI-Leseregeln. Lösung: `index.md` aus dem Frontmatter **generieren** (passt zu „generated index“ in Schritt 2). `00_INDEX.md` wird zu einer normalen Node (`type: Guide`). Das Quellen-Mapping wandert in die `sources` der einzelnen Nodes.
> - **Fehlende Zeile: Frontmatter.** Heute hat keine Template-Node Frontmatter. Das ist der eigentliche Hauptkonflikt und zugleich der einfachste.
> - **Wikilinks:** 24 Vorkommen allein in den Templates. `publish-wiki.ps1` schreibt sie heute um. Mit Standard-Links (`/08_Offene-Fragen.md#f-01`) entfällt dieses Umschreiben, und die Inhalte funktionieren in GitHub, GitLab, VS Code und Obsidian gleichermassen.

### Worth adopting

1. **Frontmatter on every node** (`type`, `description`, `tags`, `timestamp`), plus own keys such as `status`, `sources`, `sensitivity`. Enables lint, generated indexes, filtered exports and staleness checks. Highest value for lowest cost.

> **K15 ✖ `status` und `sources` sind keine eigenen Keys mehr.** In OKF v0.2 sind sie Standardfelder mit fester Struktur. Ergänzt um `generated`, `verified` und `stale_after` sähe das Profil zum Beispiel so aus:
>
> ```yaml
> ---
> type: Gap Analysis                 # OKF, Pflicht
> title: Gap-Analyse                 # OKF, empfohlen
> description: Lücken zwischen IST und Ziel, priorisiert.
> tags: [analyse, gap]
> timestamp: 2026-10-11T09:00:00+02:00
> sources:                           # OKF v0.2
>   - id: kickoff
>     resource: /input_client-docs/Kickoff-Protokoll_2026-03-12.docx
>     last_modified: 2026-03-12T00:00:00+01:00
> generated: { by: agent:codex/ingest-docs, at: 2026-10-10T14:20:00+02:00 }
> verified:
>   - { by: human:hkuhn, at: 2026-10-11T09:00:00+02:00 }
> status: stable                     # draft | stable | deprecated
> stale_after: 2026-11-15T00:00:00+01:00
> sensitivity: intern                # Bender-Erweiterung
> owner: human:hkuhn                 # Bender-Erweiterung
> ---
> ```
>
> OKF verlangt, dass unbekannte Keys bei Lesen und Schreiben erhalten bleiben. Bender-Erweiterungen wie `sensitivity` und `owner` sind daher zulässig. Damit sind die Staleness-Checks konkret: Sie werten `stale_after` aus und vergleichen `sources[].last_modified` mit `verified[].at`. Das entspricht `derived_stale` aus BASE.

2. **A `# Citations` section** for provenance. Fits the "nothing invented" rule; the fill-template `.quellen.md` report is already a version of this.

> **K16 ✖ In v0.2 ersetzt.** Statt einer Liste am Ende der Node gibt es Fussnoten pro Aussage (`…120'000 Datensätze.[^kickoff]`), die über `sources[].id` aufgelöst werden. Das ist feiner und passt noch besser zu „nothing invented“: Jede Aussage hat ihren Beleg, und Aussagen ohne Fussnote fallen auf. Lint kann das prüfen.
>
> Ergänzend bleibt im Text eine Markierung für Abgeleitetes sinnvoll, z. B. `[ZU BESTÄTIGEN: abgeleitet aus …]`. Der `.quellen.md`-Report von `fill-template` sollte dasselbe `sources`-Schema verwenden.

3. **Tolerance for broken links.** Lint should only warn.

> **K17 ✖ Missverständnis der Spezifikation.** OKF verpflichtet nur **Leser** eines Bundles, kaputte Links zu tolerieren. Ein Bundle darf deswegen nicht abgelehnt werden. Für Benders **eigenes** Lint folgt daraus nichts. Es darf strenger sein und sollte es auch, im Sinne von „Guardrails over expertise“ aus Abschnitt 1.
>
> Vorschlag: Kaputte interne Links sind ein Fehler (im Pre-Commit blockierend), Links nach aussen nur eine Warnung.

4. **Structured data as source of truth, generated markdown views.** Already done with `09_Master-Schedule.json`. Extend to requirements, open questions and action items. Also reduces git merge conflicts.

> **K18 ❓ Spannung zum Ziel „nicht-technische Rollen“.** JSON als Quelle der Wahrheit ist für Nicht-Techniker noch schwerer zu bearbeiten als Markdown. Das funktioniert nur, wenn **ausschliesslich** Skills oder ein Editor schreiben, wie beim Master-Schedule-Editor mit `apply`. Das sollte ausdrücklich gesagt werden.
>
> Alternative mit weniger Umbau: Markdown-Nodes mit strengem Eintragsformat (Anker pro Eintrag, z. B. `### F-12 {#f-12}`). `bender lint` prüft dieses Format, `bender` erzeugt bei Bedarf eine JSON-Sicht. Die Wahl sollte nach Schritt 0 fallen.

### Exports are read-only: make it a mechanism

Today this is only a convention.
- Stamp every export with `generated: true`, the source commit and a timestamp.
- Make `ingest` and `lint` refuse files carrying that stamp.
- Keep exports outside the paths the agent is allowed to read.

> **K19 ✖ Kollision mit OKF.** In OKF v0.2 ist `generated` ein Objekt `{by, at}` mit der Bedeutung „maschinell verfasst“. Ein boolescher Exportstempel unter diesem Namen bricht jedes OKF-Frontmatter. Ausserdem tragen auch reguläre, KI-erzeugte Nodes `generated`; `ingest` und `lint` würden sie dann fälschlich ablehnen.
>
> Vorschlag mit eigenem Key:
>
> ```yaml
> export: { readonly: true, commit: 3f2a9c1, at: 2026-10-16T08:00:00+02:00, audience: kunde }
> ```
>
> Der Mechanismus selbst wird ausdrücklich unterstützt. Ergänzung: Exporte für Kunden sollten den Sensitivitätsfilter anwenden. Ein Export im OKF-Format (`bender export --format okf --audience kunde`) eignet sich zudem als **Übergabe des Mandatswissens** an den Kunden bei Mandatsende.

## 3. BASE

**Verdict: useful concepts, don't integrate.** BASE is young, French-authoritative, a self-declared standard with no third-party ratification or security review, and states it has no published measurements. Its CLI and Studio add a Node dependency. Its agent/process/sources model overlaps with `AGENTS.md` and `SKILL.md`, which Copilot and Codex already read natively.

> **K20 ✔ Urteil geteilt.** Es deckt sich mit der Analyse „BASE-Ideen für Bender“. Hinweis bei einer späteren Doppelnutzung: BASE und OKF verwenden beide das Feld `type`, aber in anderer Bedeutung. In BASE ist es eine Ressourcenart (z. B. `document`), in OKF ein freier Fachtyp. Für mem-index-Nodes gilt die OKF-Bedeutung.

### Ideas worth taking

- **Instruction versus mechanism.** The "strictly enforced" file-access rule in `AGENTS.md` is only an instruction, and skills lift it by instruction. Enforce it where it matters through bender tools that read via an allowlist. Direct file reads still bypass this; hard guarantees also need harness-level permissions or hooks (check what each harness supports).
- **Two-stage mediated writes.** Tools produce a plan or diff and apply only with `--apply`/`--yes`. Use for ingest, mem-index edits and `log add`, so prose "Gates" become real ones.
- **Declarative sources and write targets per skill.** `reads:` and `writes:` in SKILL.md frontmatter; lint checks skills against the rules instead of relying on prose "Quellen-Whitelist" text.
- **Sensitivity classes per project.** A per-project policy (in `mandate.config.json` or node frontmatter) classifies paths and nodes; tools filter on it. Suits client-by-client privacy. Only protects paths going through the tools.
- **Scenario replay.** A demo mandate with expected answers, replayed across models. Skills currently have no regression testing.

> **K21 ➕ Weitere BASE-Ideen, die im README nicht sichtbar sind:**
> - **Inhalts-Doctor:** Signale wie „Ableitung veraltet“ (`derived_stale`), „Review überfällig“ (`review_by`) und „Quelle fehlt“. Mit OKF v0.2 lässt sich das über `stale_after`, `sources` und `verified` abbilden (siehe K15).
> - **Schreibprüfung:** Lexikon- und Stilprüfung gegen typische KI-Floskeln (`check-lexique`, `human-writing`). Das ist günstig umzusetzen und sichtbar wirksam gegen „AI-Slop“, gerade in Kundendokumenten.
> - **`use_when` / `avoid_when` in Skill-Beschreibungen.** Das hilft Agenten, den richtigen Skill zu wählen, und ist wichtig, wenn rollenorientierte Skills zahlreicher werden.
> - **Benannte Widersprüche** zwischen Quellen statt stiller Auflösung durch das Modell.

## 4. Suggested order

0. Identify the target roles and their top tasks, and decide how non-technical roles will interact with bender. This is the main unknown, and it shapes every step below.
1. CLI contract, launcher and `doctor` (with skill-driven, plain-language setup).
2. Node frontmatter, `bender lint`, `bender log add`, generated index.
3. Port agent-facing PS tools to Python, keeping PS shims.
4. Plan/apply writes and read-only stamps on exports.
5. Per-project sensitivity policy.
6. Skill scenario tests.

**Not now:** full OKF conformance, BASE integration, MCP, embeddings.

> **K22 ✔ Reihenfolge plausibel.** Anpassungen:
> - **Schritt 0:** Neben den Rollen auch die **prüfende Rolle** (PO/Projektleitung) mit Zeitbudget festlegen (siehe K12).
> - **Schritt 2:** Frontmatter direkt als **OKF-v0.2-Profil** definieren (K15), einschliesslich `generated` und `verified`. Lint prüft das Fussnoten-Format (K16) und kaputte interne Links als Fehler (K17).
> - **Zusätzlicher Schritt 2b:** Migrationsskript für laufende Mandate (Frontmatter nachrüsten, optional Wikilinks umwandeln) und ein Update-Mechanismus für das Toolkit in bestehenden Repos. Das fehlt im Review.
> - **„Not now“ präzisieren:** „Volle OKF-Konformität bei `log.md` und Links“ statt „full OKF conformance“. Das Frontmatter ist dann bereits konform.
> - **Aufwand:** Es fehlen Grössenordnungen. Grobe Schätzung als Diskussionsbasis:
>
>   | Schritt | Aufwand |
>   |---|---|
>   | 1 | 3–5 PT |
>   | 2 | 3–4 PT |
>   | 2b | 1–2 PT |
>   | 3 | 5–8 PT |
>   | 4 | 2–3 PT |
>   | 5 | 2–3 PT |
>   | 6 | 3–5 PT |
>
>   Schritt 0 ist ein bis zwei Workshops.

> **K23 ➕ Machbarkeitstest vor Schritt 1.** Einen halben Tag auf einem verwalteten Firmen-Laptop ohne Admin-Rechte einplanen: Ist `uv` installierbar, ist der Python-Download erlaubt, funktioniert `bender doctor`? Das Ergebnis entscheidet, ob Python als Runtime trägt oder ob die Alternative aus der Anforderungstabelle sofort nötig ist.

## 5. Open decisions for you

- Is `bender` as a single CLI name and entry point acceptable, or should tools stay separate scripts?
- Frontmatter schema: which `type` values and custom keys fit a mandate mem-index?
- Keep `[[wikilinks]]` and the log format, or accept OKF-style changes for compatibility?
- Which PS scripts are worth keeping as PS-only (wizards) versus porting?
- Which harnesses (Copilot, Codex, others) must be supported, and what permission/hook controls do they offer? Do the non-technical roles even have access to a coding-agent harness today, or do they need a different front end (e.g. a chat tool reading exports)?
- Which roles come first, and what are their top 2-3 tasks? This should drive which skills get built and tested first.
- How should non-technical roles contribute to the mem-index (git, skill-mediated proposals, review by a technical owner)?
- Which roles may read or edit which nodes (feeds the per-project sensitivity policy)?

> **K24 ➕ Vorschläge zu den offenen Entscheidungen.**
>
> | Entscheidung | Vorschlag |
> |---|---|
> | Ein CLI `bender` | Ja (siehe K7). |
> | Frontmatter-Schema | OKF-v0.2-Profil (K15) mit Bender-Erweiterungen `sensitivity` und `owner`. Erste `type`-Werte orientieren sich an den Nodes: `Guide`, `Stakeholder Map`, `Requirements Register`, `As-Is Analysis`, `Gap Analysis`, `Constraint Set`, `Decision Log`, `Open Questions`, `Master Schedule`, `Glossary`, `Retrospective`, `Source Inventory`, optional `Decision`. |
> | Wikilinks und Log-Format | **Log-Format:** über `bender log add` kapseln (K10). Dann ist der Wechsel auf das OKF-Format billig und kann mit Schritt 2 erfolgen. **Wikilinks:** auf Standard-Links umstellen, sobald das Migrationsskript (K22) steht. Das vereinfacht `publish-wiki` und den Zugriff aus mehreren Tools. |
> | PS-only vs. Portierung | Wizards und Editoren (Schedule, Findings, Bootstrap) vorerst in PS lassen. Alles, was Agenten aufrufen, portieren (wie im Review). |
> | Harnesses und Frontends | Erst Schritt 0 klären. Wenn Nicht-Techniker keinen Coding-Agenten haben, wird der **Export** (inklusive Prüfstatus-Badges, K12) zur wichtigsten Lese-Oberfläche. Eine Chat-Oberfläche auf einem OKF-Export ist dann eine naheliegende Option, später auch per MCP. |
>
> **Zusätzliche offene Entscheidung:** Wer gibt Inhalte frei (`verified: human:…`), und wie viel Zeit ist dafür im Mandat vorgesehen?

## Next possible steps

- Sketch the CLI contract (verbs, flags, exit codes, JSON shapes).
- Draft the node frontmatter schema and a `lint` ruleset.
- Map project roles to tasks and skills, to find where non-technical users are served worst today.

> **K25 ➕ Konkreter Vorschlag für den nächsten Schritt.** Den Entwurf des Frontmatter-Schemas als **OKF-v0.2-Profil** erstellen. Dazu gehören:
> - eine Musternode pro Template
> - ein `log.md` im Zielformat
> - erste Lint-Regeln: `type` vorhanden; `sources[].id` für jede Fussnote; kaputte interne Links sind Fehler; `stale_after` überschritten gibt eine Warnung; `verified` fehlt bei `status: stable` gibt eine Warnung
>
> Das ist klein, unabhängig von der Runtime-Entscheidung und gibt Schritt 2 eine feste Grundlage.
