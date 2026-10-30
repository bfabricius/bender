# Changelog - mandate-toolkit (bender)

Alle relevanten Aenderungen am Toolkit. Versionierung nach SemVer (Regeln siehe
[README.md](README.md#versionierung-und-kompatibilitaet)). Die Version steht in
`toolkit-version.json` und wird beim Bootstrap als `toolkitVersion` nach `mandate.config.json`
des Mandats geschrieben.

Jeder Eintrag hat einen Abschnitt **Kompatibilitaet / Upgrade**, der beschreibt, was ein bereits
gebootstrapptes Mandat beim Nachziehen auf diese Version tun muss.

---

## [0.8.0] - 2026-10-30

### Hinzugefuegt
- **`install.ps1` im Repo-Root:** laedt den aktuellen Stand eines Branches (Default `main`) als
  Zip-Archiv von GitHub und kopiert nur `bootstrap-wizard.ps1` und `.toolkit/` in den Zielordner -
  ohne `.git`-Ordner und ohne die Root-Dateien des Toolkit-Repos (`README.md`, `.gitignore`).
  Damit entsteht kein verschachteltes Repo im Projekt-Repo, und der Wizard legt `README.md` und
  `.gitignore` aus den Templates an (beim Klonen wurden sie bisher als „exists“ uebersprungen).
  Erneutes Ausfuehren aktualisiert `.toolkit/` und `bootstrap-wizard.ps1`. Parameter:
  `-TargetDir`, `-Branch`, `-RunWizard`.

### Behoben
- `bootstrap-wizard.ps1`, Schritt Git: erkennt jetzt auch ein uebergeordnetes Repo
  (`git rev-parse --is-inside-work-tree`) und bietet dort kein `git init` mehr an. Vorher entstand
  bei einem Mandat in einem Unterordner eines bestehenden Repos ein verschachteltes Repo.

### Kompatibilitaet / Upgrade von 0.7.x
- Keine Migration noetig. Bestehende Mandate koennen mit `./install.ps1` (bzw. dem Einzeiler aus
  `.toolkit/README.md`) im Mandats-Root auf 0.8.0 gezogen werden; danach `toolkitVersion` in
  `mandate.config.json` auf `0.8.0` setzen.

---

## [0.7.0] - 2026-10-30

Backport der Verbesserungen aus dem Mandat „RFP - Stadt Biel - KI-Suchloesung“ (gebootstrappt mit 0.3.0).

### Hinzugefuegt
- **Claude Code als dritte Plattform:** `bootstrap-wizard.ps1` legt die Directory-Junction
  `.claude/skills` -> `.agents/skills` an (`New-SkillsJunction`, ohne Admin-Rechte) und traegt
  `.claude/skills` in die `.gitignore` des Mandats ein (`Add-GitignoreEntry`, auch fuer bestehende
  `.gitignore`). `gitignore.tmpl`, `AGENTS.md.tmpl`, `project-README.md.tmpl` und `.toolkit/README.md`
  erwaehnen Claude Code (Aufruf `/<skill>` wie in Copilot).
- **Master-Schedule, Arbeitspakete:** neue optionale Felder `description`, `refId`, `refName`
  (generische Referenz, z. B. Ausschreibungskriterium, Ticket oder Requirement) in
  `schedule-wizard.ps1`, `apply-master-schedule-changes.ps1`, im Web-Editor und in der Skill
  `pflege-master-schedule`. Die Markdown-Tabelle pro Lane hat die zusaetzlichen Spalten
  `Ref-ID | Referenz | Beschreibung`.
- **Web-Editor (`build-master-schedule-editor.ps1`):**
  - Ueberlappende Arbeitspakete einer Lane werden auf Subzeilen verteilt (`assignSubRows`) statt sich zu verdecken.
  - Auto-Zoom: Sind Von **und** Bis gesetzt, passt sich die Zeitachse der verfuegbaren Breite an (`computePxPerDay`).
  - Eigene Meilenstein-Zeile (Labels werden nicht mehr abgeschnitten); Meilensteine sind per Klick editierbar.
  - Balken werden auf den sichtbaren Zeitraum begrenzt; die Balken haben einen Rahmen; der Fortschrittsmarker geht ueber die volle Zeilenhoehe.
  - Re-Render bei Fenstergroessen-Aenderung; Textareas wachsen mit dem Inhalt; die Modal-Hoehe ist an den Viewport gebunden.
  - Tooltip zeigt Referenz und Beschreibung.
- Skill `pflege-master-schedule`: neuer Schritt 6 „Web-Editor-Rebuild anbieten“.
- Skill `workstream-openspec-prozess`: Export-Regeln (Triage-Kopie, IDs ausschreiben, keine
  Em-Dashes), Ausnahme fuer vorzeitigen mem-index-Ingest, Regeln-Block.
- `CHANGELOG.md` (diese Datei) und Versionierungsregeln in `.toolkit/README.md`.

### Geaendert
- Hinweistexte in Skripten und Templates verweisen einheitlich auf „Skill `x` (Copilot: `/x`,
  Codex: `$x`)“ statt auf „Copilot-Chat `/x`“ (`09_Master-Schedule.md`, `15_Retrospektiven...`,
  Generator-Header in Wizard/Apply/Editor).
- `diagram-export/scripts/build_drawio.py`: `mxfile agent="bender"` statt `"Copilot"`.

### Behoben
- `project-status.ps1`, Ingest-Coverage: Patterns ohne `/` in der Quelldokument-Mapping-Tabelle
  werden gegen den blossen Dateinamen gematcht. Vorher galt jede Datei unter
  `input_client-docs/<Originalordner>/` faelschlich als „nicht erfasst“.
- `project-status.ps1`, Stakeholder: Die Spalte `Rolle` des Standard-Templates `02_Stakeholder.md`
  wird erkannt (vorher nur `Organisation...`).
- `AGENTS.md.tmpl`: Der Link auf `mandate.config.json` zeigt korrekt ins Projekt-Root (ohne `../`).
- `workstream-openspec-prozess`: Die Link-Tiefe zu `mem-index/` ist korrigiert (`../../../`).

### Kompatibilitaet / Upgrade von 0.6.x
- **Schema `09_Master-Schedule.json`:** abwaertskompatibel. Die neuen Felder sind optional; Schedules
  ohne sie funktionieren unveraendert. **Legacy-Felder `soId`/`soName`** (projektspezifische
  Vorabversion im Mandat Stadt Biel) werden von Wizard, Apply und Editor beim Einlesen automatisch
  auf `refId`/`refName` abgebildet und beim naechsten Schreiben unter dem neuen Namen gespeichert.
- **Bestehendes Mandat nachziehen:**
  1. `.toolkit/` und `bootstrap-wizard.ps1` durch die 0.7.0-Fassung ersetzen.
  2. Root-Skripte aus `.toolkit/scripts/` neu kopieren (`schedule-wizard.ps1`,
     `apply-master-schedule-changes.ps1`, `build-master-schedule-editor.ps1`, `project-status.ps1`).
  3. Generische Dateien unter `.agents/skills/*` aus `.toolkit/templates/agents/skills/`
     uebernehmen (Achtung: `bootstrap-mandate/SKILL.md` enthaelt mandatsspezifisch ersetzte
     Tokens und darf nicht blind ueberschrieben werden).
  4. Junction anlegen: `cmd /c mklink /J .claude\skills .agents\skills` und `.claude/skills` in die
     `.gitignore` eintragen (oder `bootstrap-wizard.ps1` erneut ausfuehren, der vorhandene Dateien ueberspringt).
  5. `./build-master-schedule-editor.ps1` ausfuehren (der Editor ist eine statische Momentaufnahme).
  6. `toolkitVersion` in `mandate.config.json` auf `0.7.0` setzen.

---

## [0.6.0] - 2026-10-21

### Hinzugefuegt
- Skill `create-template` (anonymisiertes Template aus bestehendem `.docx`/`.md`/`.pptx`/`.xlsx`,
  Scripts `extract_source.py`, `sanitize_docx.py`, `check_template.py`).
- `AGENTS.md.tmpl`: `create-template` in die Liste der Skills mit eigener File-Access-Ausnahme aufgenommen.

### Kompatibilitaet / Upgrade von 0.5.x
- Rein additiv: Skill-Ordner `create-template` nach `.agents/skills/` kopieren; Abschnitt
  „File access restriction“ in `AGENTS.md` um `create-template` ergaenzen.

---

## [0.5.0] - 2026-10-15

### Hinzugefuegt
- Skills `diagram-export` (draw.io aus Bild/Mermaid/ASCII/Text), `email-entwurf`, `fill-template`
  (inkl. Python-Scripts).
- `requirements.txt.tmpl` (`python-docx`), Python-Block in `gitignore.tmpl`.
- `bootstrap-wizard.ps1`: `Copy-TemplateSkill` kopiert ganze Skill-Ordner (nicht nur `SKILL.md`).
- `AGENTS.md.tmpl`: File-Access-Ausnahme fuer Skills, die in ihrer `SKILL.md` eine enger gefasste Regel deklarieren.

### Kompatibilitaet / Upgrade von 0.4.x
- Rein additiv: Skill-Ordner kopieren, `requirements.txt` anlegen, `pip install -r requirements.txt`,
  File-Access-Ausnahme in `AGENTS.md` ergaenzen.

---

## [0.4.0] - 2026-10-07

### Geaendert
- **Struktur-Umstellung:** `.github/copilot-instructions.md` + `.github/prompts/*.prompt.md` ->
  `AGENTS.md` + `.agents/skills/*/SKILL.md`, gemeinsam fuer GitHub Copilot und OpenAI Codex.

### Kompatibilitaet / Upgrade von 0.3.x
- **Inkompatibel fuer die Agent-Konfiguration:** `copilot-instructions.md` nach `AGENTS.md`
  ueberfuehren, Prompts als Skills unter `.agents/skills/` anlegen. Skripte und mem-index unveraendert.

---

## [0.3.0] - 2026-09-29

### Hinzugefuegt
- Master-Schedule: `09_Master-Schedule.json` (SSOT) + generierte `.md`, `schedule-wizard.ps1`,
  `build-master-schedule-editor.ps1` (statischer Web-Editor), `apply-master-schedule-changes.ps1`,
  Prompt `pflege-master-schedule`.
- Web-Editor bettet Bibliotheken und JSON als Base64 ein (Schutz gegen Script-Tag-Breakout; 2026-09-30, ohne Versions-Bump).

### Kompatibilitaet / Upgrade von 0.2.x
- Rein additiv: neue Skripte kopieren, `09_Master-Schedule.json/.md` aus den Templates anlegen.

---

## [0.2.0] - 2026-09-28

- Initialer Import: Bootstrap-Wizard, Memory-Index-Templates, Drop-in-Skripte, Copilot-Instructions/-Prompts.
