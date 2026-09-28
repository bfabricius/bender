# Mandate Toolkit

Wiederverwendbares Repo-Template fuer Beratungs-/Analyse-Mandate: Memory-Index (Markdown-SSOT),
optional OpenSpec-basiertes Requirements Engineering, ein Satz Drop-in-PowerShell-Tools
(Export/Publish/Status/Suche) und die passenden GitHub-Copilot-Slash-Agents.

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
    github/                 copilot-instructions.md + Slash-Agent-Prompts
    analyse-sprint/         OpenSpec-Prozess-Leitfaden (nur RE-Phase)
    branding/               neutrale Slidev-Default-Vorlage
    project-README.md.tmpl  wird zur README.md des neuen Mandats
    gitignore.tmpl
  toolkit-version.json
```

## Weiterentwicklung des Toolkits selbst

Aenderungen an Skripten/Templates gehoeren unter `.toolkit/`, nicht in bereits gebootstrappte
Mandats-Repos direkt. `toolkit-version.json` ist als Grundlage fuer einen spaeteren
Update-Mechanismus gedacht (fuer v1 nicht implementiert).
