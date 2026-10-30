# Mandate Toolkit

Wiederverwendbares Repo-Template fuer Beratungs-/Analyse-Mandate: Memory-Index (Markdown-SSOT),
optional OpenSpec-basiertes Requirements Engineering, ein Satz Drop-in-PowerShell-Tools
(Export/Publish/Status/Suche) und die passenden Agent-Instructions (`AGENTS.md`) + Skills
(`.agents/skills/`), nativ nutzbar mit GitHub Copilot (VS Code) und OpenAI Codex sowie mit
Claude Code (ueber die lokale Junction `.claude/skills` -> `.agents/skills`).

## Nutzung fuer ein neues Mandat

1. Dieses Repo klonen (der Klon wird direkt das neue Mandats-Repo).
2. `./bootstrap-wizard.ps1` ausfuehren und die Fragen beantworten (Projekt-Metadaten,
   Client-Input-Ordner, Phasen, Taskboard-URL).
3. Die generierte `README.md` im Projekt-Root oeffnet sich automatisch — sie erklaert den
   weiteren Umgang mit dem Memory-Index, OpenSpec und den Drop-in-Tools.

Keine Node.js-/Internet-Abhaengigkeit fuer das Bootstrap selbst; nur die optionale
Requirements-Engineering-Phase benoetigt Node.js/npm (fuer `npx @fission-ai/openspec`).

## Aufbau dieses Toolkit-Repos

```
bootstrap-wizard.ps1        Einstiegspunkt (Fragebogen + Scaffolding)
.toolkit/
  scripts/                  generalisierte Drop-in-Tools (Quelle, wird pro Mandat kopiert)
  templates/
    mem-index/              Memory-Index-Node-Vorlagen (00_INDEX, 01-08, 14, 15, log.md)
    agents/                 AGENTS.md.tmpl + skills/*/SKILL.md (Copilot, Codex, Claude Code gemeinsam)
    analyse-sprint/         OpenSpec-Prozess-Leitfaden (nur RE-Phase)
    branding/               neutrale Slidev-Default-Vorlage
    project-README.md.tmpl  wird zur README.md des neuen Mandats
    gitignore.tmpl
  toolkit-version.json      aktuelle Toolkit-Version (SemVer)
  CHANGELOG.md              Aenderungen + Kompatibilitaet/Upgrade-Hinweise pro Version
```

## Weiterentwicklung des Toolkits selbst

Aenderungen an Skripten/Templates gehoeren unter `.toolkit/`, nicht in bereits gebootstrappte
Mandats-Repos direkt. Werden Verbesserungen doch zuerst in einem Mandat gemacht, werden sie
per Backport hierher zurueckgefuehrt und das Mandat anschliessend auf die neue Version gesynct.

### Versionierung und Kompatibilitaet

- `toolkit-version.json` folgt SemVer: **Patch** = Fix ohne Verhaltensaenderung, **Minor** =
  abwaertskompatibles Feature (z. B. neue optionale Felder, neue Skills/Skripte), **Major** =
  inkompatible Aenderung (z. B. Schema-Bruch in `09_Master-Schedule.json`, Umbenennung von
  Pflichtdateien). Solange die Version `0.x` ist, kann auch ein Minor-Bump Migrationsschritte
  erfordern - diese stehen dann im CHANGELOG.
- **Jede** Aenderung unter `.toolkit/` oder an `bootstrap-wizard.ps1` braucht einen Versions-Bump
  und einen Eintrag in [`CHANGELOG.md`](CHANGELOG.md) inkl. Abschnitt "Kompatibilitaet / Upgrade".
- `bootstrap-wizard.ps1` schreibt die verwendete Version nach `mandate.config.json`
  (`toolkitVersion`). Dieser Wert bezeichnet den Toolkit-Stand, mit dem ein Mandat zuletzt
  gebootstrappt oder gesynct wurde, und wird beim Sync eines bestehenden Mandats von Hand
  nachgefuehrt (ein automatischer Update-Mechanismus existiert noch nicht).
