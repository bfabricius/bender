<#
.SYNOPSIS
    Interactive bootstrap wizard for a new consulting-mandate workspace: memory index,
    Copilot slash-agents, drop-in PowerShell tooling, and (optionally) an OpenSpec
    requirements-engineering workspace.

.DESCRIPTION
    Run this script once, from the root of a freshly cloned copy of this toolkit repo
    (which becomes the new mandate's project repo). It asks a short set of questions
    (project metadata, client-input folder, mem-index seeding, project phases, taskboard
    URL) and then scaffolds everything deterministically from the templates shipped in
    `.toolkit/`:

      mem-index/                     memory-index skeleton (00_INDEX, 01-08, 14, 15, log)
      .github/copilot-instructions.md + .github/prompts/*.prompt.md (phase-dependent)
      client-meetings/, export-artefacts/, input_client-docs/
      *.ps1                          drop-in tooling, copied to the project root
      openspec-sdd/                  only if the Requirements-Engineering phase is chosen
      mandate.config.json             mandate metadata (also used by other tooling)
      README.md                      generated project guide, opened at the end

    Idempotent: if `mandate.config.json` already exists, existing answers are used as
    defaults and existing files are never overwritten unless -Force is given.

.PARAMETER Force
    Overwrite files that already exist. Without it, existing files are skipped.

.PARAMETER WhatIf
    Show what would be created/changed without writing anything.

.EXAMPLE
    ./bootstrap-wizard.ps1

.EXAMPLE
    ./bootstrap-wizard.ps1 -Force
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$root       = $PSScriptRoot
$toolkitDir = Join-Path $root '.toolkit'
$tplDir     = Join-Path $toolkitDir 'templates'
$scriptsDir = Join-Path $toolkitDir 'scripts'

$script:created = 0
$script:skipped = 0

# ==========================================================================
#  Banner (single-quoted here-string: contains a literal backtick, must not
#  be interpreted/escaped, so no double-quoted string/expandable here-string)
# ==========================================================================

$banner = @'
  ____ _   _ ____   ___  ____
 / ___| | | |  _ \ / _ \/ ___|
| |   | | | | | | | | | \___ \
| |___| |_| | |_| | |_| |___) |
 \____|\___/|____/ \___/|____/          _            _     _              _
|  _ \ _ __ ___ (_) ___  ___| |_       / \   ___ ___(_)___| |_ __ _ _ __ | |_
| |_) | '__/ _ \| |/ _ \/ __| __|____ / _ \ / __/ __| / __| __/ _` | '_ \| __|
|  __/| | | (_) | |  __/ (__| ||_____/ ___ \\__ \__ \ \__ \ || (_| | | | | |_
|_|   |_|  \___// |\___|\___|\__|   /_/   \_\___/___/_|___/\__\__,_|_| |_|\__|
              |__/
'@
Write-Host $banner -ForegroundColor Cyan

# ==========================================================================
#  Helpers (same conventions as the other scripts in this toolkit)
# ==========================================================================

function Write-FileUtf8NoBom {
    param([string]$Path, [string]$Content)
    $enc  = New-Object System.Text.UTF8Encoding($false)
    $full = [System.IO.Path]::GetFullPath($Path)
    [System.IO.File]::WriteAllText($full, $Content, $enc)
}

function New-ScaffoldFile {
    param([string]$Path, [string]$Content)
    if ((Test-Path -LiteralPath $Path) -and -not $Force) {
        Write-Host "  skip (exists): $Path" -ForegroundColor DarkGray
        $script:skipped++
        return
    }
    if (-not $PSCmdlet.ShouldProcess($Path, 'Create/overwrite file')) { return }
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Write-FileUtf8NoBom -Path $Path -Content $Content
    Write-Host "  created: $Path" -ForegroundColor Green
    $script:created++
}

function New-ScaffoldDir {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) { return }
    if (-not $PSCmdlet.ShouldProcess($Path, 'Create directory')) { return }
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    Write-Host "  created: $Path\" -ForegroundColor Green
}

function Expand-Tokens {
    param([string]$Text, [hashtable]$Tokens)
    foreach ($k in $Tokens.Keys) { $Text = $Text.Replace($k, [string]$Tokens[$k]) }
    return $Text
}

function Copy-TemplateFile {
    param([string]$TemplatePath, [string]$DestPath, [hashtable]$Tokens)
    $content = Get-Content -LiteralPath $TemplatePath -Raw -Encoding UTF8
    New-ScaffoldFile -Path $DestPath -Content (Expand-Tokens -Text $content -Tokens $Tokens)
}

function Read-YesNo {
    param([string]$Prompt, [bool]$DefaultYes = $true)
    $hint = if ($DefaultYes) { 'J/n' } else { 'j/N' }
    do {
        $answer = (Read-Host "$Prompt [$hint]").Trim()
        if ([string]::IsNullOrWhiteSpace($answer)) { return $DefaultYes }
        if ($answer -match '^(j|ja|y|yes)$') { return $true }
        if ($answer -match '^(n|nein|no)$') { return $false }
        Write-Warning 'Bitte j oder n eingeben.'
    } while ($true)
}

function Read-WithDefault {
    param([string]$Prompt, [string]$Default = '')
    $hint = if ($Default) { " [$Default]" } else { '' }
    $answer = (Read-Host "$Prompt$hint").Trim()
    if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
    return $answer
}

# ==========================================================================
#  Step 0 - detect existing mandate (idempotent repair/extend mode)
# ==========================================================================

$configPath = Join-Path $root 'mandate.config.json'
$existingConfig = $null
if (Test-Path -LiteralPath $configPath) {
    Write-Host ''
    Write-Host 'Es wurde bereits eine mandate.config.json gefunden - dieses Mandat ist teilweise' -ForegroundColor Yellow
    Write-Host 'initialisiert. Fehlende Teile werden ergaenzt; bestehende Dateien bleiben ohne -Force unangetastet.' -ForegroundColor Yellow
    try { $existingConfig = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $existingConfig = $null }
    if (-not (Read-YesNo 'Fortfahren?' $true)) { Write-Host 'Abgebrochen.'; exit 0 }
}

function Get-Default {
    param([string]$Field, [string]$Fallback = '')
    if ($existingConfig -and $existingConfig.PSObject.Properties[$Field]) { return [string]$existingConfig.$Field }
    return $Fallback
}

function Get-DefaultPhase {
    param([string]$PhaseField, [bool]$Fallback = $false)
    if ($existingConfig -and $existingConfig.phases -and $existingConfig.phases.PSObject.Properties[$PhaseField]) {
        return [bool]$existingConfig.phases.$PhaseField
    }
    return $Fallback
}

# ==========================================================================
#  Step 1 - metadata questionnaire
# ==========================================================================

Write-Host ''
Write-Host '=== Mandate Bootstrap Wizard ===' -ForegroundColor Cyan
Write-Host ''

$projectName    = Read-WithDefault 'Projektname' (Get-Default 'projectName' (Split-Path -Leaf $root))
$client         = Read-WithDefault 'Kunde/Auftraggeber' (Get-Default 'client')
$rolxNumber     = Read-WithDefault 'ROLX-Projektnummer (optional)' (Get-Default 'rolxNumber')
$googleDriveUrl = Read-WithDefault 'Google-Drive-URL des Projekts (optional)' (Get-Default 'googleDriveUrl')
$projectLead    = Read-WithDefault 'Projektleiter/-in' (Get-Default 'projectLead')

Write-Host ''
$clientFolder = Read-WithDefault 'Pfad zu bereits vorhandenen Client-Beistellungen (optional, Enter = keine)' ''
$clientFolderValid = $false
if ($clientFolder) {
    if (Test-Path -LiteralPath $clientFolder -PathType Container) {
        $clientFolderValid = $true
    } else {
        Write-Warning "Ordner nicht gefunden: $clientFolder - wird ignoriert."
        $clientFolder = ''
    }
}

$seedFromClient = $false
if ($clientFolderValid) {
    $seedFromClient = Read-YesNo 'Nach dem Bootstrap sofort per Copilot-Prompt aus dem Client-Input befuellen (empfohlen)?' $true
}

Write-Host ''
$doRequirementsEngineering = Read-YesNo 'Requirements-Engineering-Phase (OpenSpec) fuer dieses Mandat vorsehen?' (Get-DefaultPhase 'requirementsEngineering' $false)

Write-Host ''
$doImplementation = Read-YesNo 'Ist eine Umsetzungsphase vorgesehen?' (Get-DefaultPhase 'implementation' $false)
$taskboardUrl = ''
if ($doImplementation) {
    $taskboardUrl = Read-WithDefault 'Taskboard-URL (Azure DevOps/GitLab/...; optional, kann spaeter ergaenzt werden)' (Get-Default 'taskboardUrl')
}

# ==========================================================================
#  Pre-flight check - Node.js/npm required only for the OpenSpec init step
# ==========================================================================

$openSpecInitPossible = $doRequirementsEngineering
if ($doRequirementsEngineering) {
    $missingTools = @('node', 'npm') | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) }
    if ($missingTools.Count -gt 0) {
        Write-Warning "Node.js/npm nicht gefunden ($($missingTools -join ', '))."
        Write-Warning 'Die Requirements-Engineering-Phase bleibt aktiviert, aber openspec-sdd/ wird jetzt NICHT initialisiert.'
        Write-Warning 'Bitte Node.js LTS installieren und danach erneut ausfuehren (bestehende Dateien werden nicht ueberschrieben).'
        $openSpecInitPossible = $false
    }
}

# ==========================================================================
#  Confirmation summary
# ==========================================================================

Write-Host ''
Write-Host '=== Zusammenfassung ===' -ForegroundColor Cyan
Write-Host "  Projektname            : $projectName"
Write-Host "  Kunde                  : $client"
Write-Host "  ROLX-Projektnummer     : $rolxNumber"
Write-Host "  Google-Drive-URL       : $googleDriveUrl"
Write-Host "  Projektleiter          : $projectLead"
Write-Host "  Client-Input-Ordner    : $(if ($clientFolderValid) { $clientFolder } else { '(keiner)' })"
Write-Host "  Sofort-Befuellung      : $seedFromClient"
Write-Host "  Requirements-Engineering (OpenSpec) : $doRequirementsEngineering $(if ($doRequirementsEngineering -and -not $openSpecInitPossible) { '(Init wird uebersprungen - Node.js fehlt)' })"
Write-Host "  Umsetzungsphase        : $doImplementation"
Write-Host "  Taskboard-URL          : $(if ($taskboardUrl) { $taskboardUrl } else { '(keine)' })"
Write-Host ''
if (-not (Read-YesNo 'Mit diesen Angaben fortfahren?' $true)) { Write-Host 'Abgebrochen.'; exit 0 }

$date = Get-Date -Format 'yyyy-MM-dd'
$tokens = @{
    '__MANDATE__'      = $projectName
    '__DATE__'         = $date
    '__CLIENTFOLDER__' = if ($clientFolderValid) { (Resolve-Path -LiteralPath $clientFolder).Path } else { '(kein Client-Input-Ordner angegeben)' }
    '__MAPPING__'      = '| [PLATZHALTER — Quelldokument] | [PLATZHALTER — Node] | [ ] offen |'
    '__COSTSECTION__'  = @'

## Cost-Report-Verhalten

**Default: kein Cost-Report.** Nur erzeugen, wenn der User es ausdruecklich verlangt.
Zu Beginn eines Requests proaktiv fragen, aber ohne explizite Aufforderung nichts erzeugen.

### Wenn ein Cost-Report verlangt wird
Datei anlegen unter `cost-report/` im Format `YYYY-MM-DD_cost-report_<slug>.json`.
GitHub Copilot rechnet in Credits: **1 Credit = $0.01 USD**. Sind Credits bekannt:
`cost_usd = credits_used * 0.01`. Sonst Token-Schaetzung, klar als Schaetzung markieren.
'@
}

# ==========================================================================
#  Step 2 - install prompts + copilot-instructions.md
# ==========================================================================

Write-Host ''
Write-Host '--- Schritt 1/9: Copilot-Instructions und Slash-Agents ---' -ForegroundColor Cyan

Copy-TemplateFile -TemplatePath (Join-Path $tplDir 'github/copilot-instructions.md.tmpl') -DestPath (Join-Path $root '.github/copilot-instructions.md') -Tokens $tokens

$alwaysOnPrompts = @('bootstrap-mandate.prompt.md', 'retrospektive.prompt.md', 'slidev-praesentation.prompt.md', 'ingest-docs.prompt.md', 'pflege-master-schedule.prompt.md')
$rePrompts       = @('analysis-boot-workstream.prompt.md', 'workstream-openspec-prozess.prompt.md')

foreach ($p in $alwaysOnPrompts) {
    Copy-TemplateFile -TemplatePath (Join-Path $tplDir "github/prompts/$p") -DestPath (Join-Path $root ".github/prompts/$p") -Tokens $tokens
}
if ($doRequirementsEngineering) {
    foreach ($p in $rePrompts) {
        Copy-TemplateFile -TemplatePath (Join-Path $tplDir "github/prompts/$p") -DestPath (Join-Path $root ".github/prompts/$p") -Tokens $tokens
    }
}

# ==========================================================================
#  Step 3 - .gitignore
# ==========================================================================

Write-Host ''
Write-Host '--- Schritt 2/9: .gitignore ---' -ForegroundColor Cyan

$gitignorePath = Join-Path $root '.gitignore'
if (-not (Test-Path -LiteralPath $gitignorePath)) {
    Copy-TemplateFile -TemplatePath (Join-Path $tplDir 'gitignore.tmpl') -DestPath $gitignorePath -Tokens $tokens
} else {
    Write-Host "  skip (exists): $gitignorePath" -ForegroundColor DarkGray
    $script:skipped++
}

# ==========================================================================
#  Step 4 - base folders
# ==========================================================================

Write-Host ''
Write-Host '--- Schritt 3/9: Ordnerstruktur ---' -ForegroundColor Cyan

@(
    'client-meetings',
    'export-artefacts/praesentationen',
    'export-artefacts/public',
    'input_client-docs',
    'mem-index'
) | ForEach-Object { New-ScaffoldDir -Path (Join-Path $root $_) }

# Neutral default branding for the shared Slidev project (restyle freely per mandate).
$brandingDest = Join-Path $root 'export-artefacts/praesentationen/styles/branding.css'
if (-not (Test-Path -LiteralPath $brandingDest)) {
    Copy-TemplateFile -TemplatePath (Join-Path $tplDir 'branding/generic.css') -DestPath $brandingDest -Tokens $tokens
}

# ==========================================================================
#  Step 5 - copy client input (only with explicit permission)
# ==========================================================================

Write-Host ''
Write-Host '--- Schritt 4/9: Client-Input kopieren ---' -ForegroundColor Cyan

$clientDocsTargetDir = $null
if ($clientFolderValid) {
    $copyPermitted = Read-YesNo "Inhalte von '$clientFolder' nach input_client-docs/ kopieren?" $true
    if ($copyPermitted) {
        $folderName = Split-Path -Leaf ($clientFolder.TrimEnd('\', '/'))
        $clientDocsTargetDir = Join-Path $root "input_client-docs/$folderName"
        if ((Test-Path -LiteralPath $clientDocsTargetDir) -and -not $Force) {
            Write-Host "  skip (exists): $clientDocsTargetDir" -ForegroundColor DarkGray
        } elseif ($PSCmdlet.ShouldProcess($clientDocsTargetDir, 'Copy client input folder')) {
            Copy-Item -LiteralPath $clientFolder -Destination $clientDocsTargetDir -Recurse -Force
            Write-Host "  copied: $clientFolder -> $clientDocsTargetDir" -ForegroundColor Green
        }
    } else {
        $clientFolderValid = $false
    }
} else {
    Write-Host '  (kein Client-Input-Ordner angegeben, uebersprungen)' -ForegroundColor DarkGray
}

# ==========================================================================
#  Step 6 - mem-index skeleton
# ==========================================================================

Write-Host ''
Write-Host '--- Schritt 5/9: Memory-Index-Skelett ---' -ForegroundColor Cyan

# *.md (Fliesstext-Nodes) und *.json (z. B. der Master-Schedule-Skeleton, 09_Master-Schedule.json)
# werden beide als Node-Vorlagen behandelt, damit zukuenftige strukturierte Nodes hier ohne
# Sonderfall ergaenzt werden koennen. Zwei -Filter-Aufrufe statt -Include, weil -Include bei
# Get-ChildItem nur mit einem wildcard-aufgeloesten -Path filtert, nicht mit -LiteralPath.
$memIndexTplDir = Join-Path $tplDir 'mem-index'
@(Get-ChildItem -LiteralPath $memIndexTplDir -Filter '*.md') + @(Get-ChildItem -LiteralPath $memIndexTplDir -Filter '*.json') | ForEach-Object {
    Copy-TemplateFile -TemplatePath $_.FullName -DestPath (Join-Path $root "mem-index/$($_.Name)") -Tokens $tokens
}

if ($clientFolderValid) {
    # Client-input inventory: auto-generated file listing + text excerpts, so the
    # /bootstrap-mandate handoff prompt has a starting point without re-reading everything itself.
    $textExt = '.md', '.txt', '.csv', '.json', '.log', '.yml', '.yaml', '.markdown'
    $clientFull = (Resolve-Path -LiteralPath $clientFolder).Path
    $relOf = @{}
    Push-Location -LiteralPath $clientFull
    try {
        $files = @(Get-ChildItem -Recurse -File -ErrorAction SilentlyContinue | Sort-Object FullName)
        foreach ($f in $files) {
            $r = (Resolve-Path -LiteralPath $f.FullName -Relative)
            $relOf[$f.FullName] = ($r -replace '^\.[\\/]', '' -replace '\\', '/')
        }
    } finally { Pop-Location }

    $invSb = New-Object System.Text.StringBuilder
    [void]$invSb.AppendLine("# Client-Input-Inventar - $projectName")
    [void]$invSb.AppendLine('')
    [void]$invSb.AppendLine("> Auto-generiert am $date durch ``bootstrap-wizard.ps1``.")
    [void]$invSb.AppendLine("> Quellordner: ``$clientFull``")
    [void]$invSb.AppendLine("> Dateien gesamt: $($files.Count)")
    [void]$invSb.AppendLine('')
    [void]$invSb.AppendLine('## Datei-Uebersicht')
    [void]$invSb.AppendLine('')
    [void]$invSb.AppendLine('| Pfad (relativ) | Typ | Groesse (KB) | Geaendert |')
    [void]$invSb.AppendLine('|---|---|---|---|')

    foreach ($f in $files) {
        $rel = $relOf[$f.FullName].Replace('|', '\|')
        $kb  = [math]::Round($f.Length / 1KB, 1)
        $ext = if ($f.Extension) { $f.Extension } else { '(none)' }
        $mtime = $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
        [void]$invSb.AppendLine("| ``$rel`` | $ext | $kb | $mtime |")
    }
    if ($files.Count -eq 0) { [void]$invSb.AppendLine('| _(keine Dateien gefunden)_ | | | |') }

    [void]$invSb.AppendLine('')
    [void]$invSb.AppendLine('## Textauszuege (Text-Formate)')
    [void]$invSb.AppendLine('')
    [void]$invSb.AppendLine('> Auszuege (max. ~2000 Zeichen) aus lesbaren Text-Dateien. Nicht-Text-Formate')
    [void]$invSb.AppendLine('> (PDF, DOCX, XLSX, Bilder) sind nur gelistet und muessen via Copilot / manuell gesichtet werden.')
    [void]$invSb.AppendLine('')

    $nonText = New-Object System.Collections.Generic.List[string]
    foreach ($f in $files) {
        $rel = $relOf[$f.FullName]
        if ($textExt -contains $f.Extension.ToLower()) {
            [void]$invSb.AppendLine("### ``$rel``")
            [void]$invSb.AppendLine('')
            try { $raw = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction Stop } catch { $raw = '' }
            if ($raw.Length -gt 2000) { $raw = $raw.Substring(0, 2000) + "`n... [gekuerzt]" }
            [void]$invSb.AppendLine('```text')
            [void]$invSb.AppendLine($raw)
            [void]$invSb.AppendLine('```')
            [void]$invSb.AppendLine('')
        } else { $nonText.Add($rel) }
    }
    if ($nonText.Count -gt 0) {
        [void]$invSb.AppendLine('## Nicht-Text-Formate (Sichtung via Copilot / manuell erforderlich)')
        [void]$invSb.AppendLine('')
        foreach ($n in $nonText) { [void]$invSb.AppendLine("- ``$n``") }
    }

    New-ScaffoldFile -Path (Join-Path $root 'mem-index/_client-input-inventory.md') -Content $invSb.ToString()
}

# ==========================================================================
#  Step 7 - copy drop-in PowerShell tooling
# ==========================================================================

Write-Host ''
Write-Host '--- Schritt 6/9: Drop-in-Tooling ---' -ForegroundColor Cyan

$alwaysOnScripts = @('export-mem-index.ps1', 'export-md-to-pdf.ps1', 'publish-wiki.ps1', 'project-status.ps1', 'glossar-suche.ps1', 'convert-docs-to-text.ps1', 'search-index.ps1', 'schedule-wizard.ps1', 'build-master-schedule-editor.ps1', 'apply-master-schedule-changes.ps1')
$reScripts       = @('install-openspec-sdd.ps1', 'build-findings-dashboard.ps1', 'apply-findings-status-changes.ps1', 'seed-openspec-from-mem-index.ps1')

function Install-Script {
    param([string]$Name)
    $dest = Join-Path $root $Name
    if ((Test-Path -LiteralPath $dest) -and -not $Force) {
        Write-Host "  skip (exists): $dest" -ForegroundColor DarkGray
        $script:skipped++
        return
    }
    if (-not $PSCmdlet.ShouldProcess($dest, 'Install script')) { return }
    Copy-Item -LiteralPath (Join-Path $scriptsDir $Name) -Destination $dest -Force
    Write-Host "  installed: $Name" -ForegroundColor Green
    $script:created++
}

foreach ($s in $alwaysOnScripts) { Install-Script -Name $s }
if ($doRequirementsEngineering) { foreach ($s in $reScripts) { Install-Script -Name $s } }

# ==========================================================================
#  Step 8 - OpenSpec init (Requirements-Engineering phase only)
# ==========================================================================

Write-Host ''
Write-Host '--- Schritt 7/9: OpenSpec-Workspace ---' -ForegroundColor Cyan

if ($doRequirementsEngineering -and $openSpecInitPossible) {
    $openSpecTarget = Join-Path $root 'openspec-sdd'
    if (Test-Path -LiteralPath $openSpecTarget) {
        Write-Host "  skip (exists): $openSpecTarget" -ForegroundColor DarkGray
    } elseif ($PSCmdlet.ShouldProcess($openSpecTarget, 'openspec init')) {
        & (Join-Path $root 'install-openspec-sdd.ps1') -InstallPath $openSpecTarget -Tools 'github-copilot' -Language 'de' -SkipGitIgnore
    }
    # Ship the generic 10-step process guide referenced by /workstream-openspec-prozess.
    New-ScaffoldDir -Path (Join-Path $root 'analyse-sprint/_openspec-fortschritt')
    Copy-TemplateFile -TemplatePath (Join-Path $tplDir 'analyse-sprint/openspec-prozess-leitfaden.md') -DestPath (Join-Path $root 'analyse-sprint/openspec-prozess-leitfaden.md') -Tokens $tokens
} elseif ($doRequirementsEngineering) {
    Write-Host '  uebersprungen (Node.js/npm fehlt - siehe Warnung oben). Spaeter nachholen mit:' -ForegroundColor Yellow
    Write-Host "    ./install-openspec-sdd.ps1 -InstallPath openspec-sdd -Tools github-copilot -Language de -SkipGitIgnore" -ForegroundColor Yellow
} else {
    Write-Host '  (Requirements-Engineering-Phase nicht gewaehlt, uebersprungen)' -ForegroundColor DarkGray
}

# ==========================================================================
#  Step 9 - mandate.config.json
# ==========================================================================

Write-Host ''
Write-Host '--- Schritt 8/9: mandate.config.json ---' -ForegroundColor Cyan

$config = [ordered]@{
    projectName    = $projectName
    client         = $client
    rolxNumber     = $rolxNumber
    googleDriveUrl = $googleDriveUrl
    projectLead    = $projectLead
    phases         = [ordered]@{
        analyse                 = $true
        requirementsEngineering = $doRequirementsEngineering
        implementation          = $doImplementation
    }
    taskboardUrl   = $taskboardUrl
    createdAt      = (Get-Default 'createdAt' (Get-Date -Format 'o'))
    toolkitVersion = (Get-Content -LiteralPath (Join-Path $toolkitDir 'toolkit-version.json') -Raw -Encoding UTF8 | ConvertFrom-Json).version
} | ConvertTo-Json -Depth 5

# mandate.config.json is pure regenerable metadata (no user-authored content to lose), so it is
# always rewritten from the current answers - unlike mem-index/prompt files, it ignores the
# skip-if-exists rule, which is what makes the repair/extend flow (e.g. enabling a phase later)
# actually take effect.
if ($PSCmdlet.ShouldProcess($configPath, 'Create/update mandate.config.json')) {
    $existed = Test-Path -LiteralPath $configPath
    Write-FileUtf8NoBom -Path $configPath -Content $config
    Write-Host "  $(if ($existed) { 'updated' } else { 'created' }): $configPath" -ForegroundColor Green
    $script:created++
}

# ==========================================================================
#  Step 10 - git init (optional, confirmed)
# ==========================================================================

Write-Host ''
Write-Host '--- Schritt 9/9: Git ---' -ForegroundColor Cyan

if (Test-Path -LiteralPath (Join-Path $root '.git')) {
    Write-Host '  (bereits ein Git-Repository, uebersprungen)' -ForegroundColor DarkGray
} elseif (Get-Command git -ErrorAction SilentlyContinue) {
    if (Read-YesNo 'Git-Repository hier initialisieren (git init)?' $true) {
        if ($PSCmdlet.ShouldProcess($root, 'git init')) {
            & git -C $root init | Out-Host
            if (Read-YesNo 'Direkt einen initialen Commit erstellen?' $false) {
                & git -C $root add -A
                & git -C $root commit -m 'chore: bootstrap mandate via mandate-toolkit' | Out-Host
            }
        }
    }
} else {
    Write-Warning 'git wurde nicht gefunden - Git-Initialisierung uebersprungen.'
}

# ==========================================================================
#  Final: generate + open project README.md
# ==========================================================================

Write-Host ''
Write-Host '--- README.md generieren ---' -ForegroundColor Cyan

$installedTools = New-Object System.Collections.Generic.List[string]
foreach ($s in $alwaysOnScripts) { $installedTools.Add($s) }
if ($doRequirementsEngineering) { foreach ($s in $reScripts) { $installedTools.Add($s) } }
$tokens['__TOOLLIST__'] = ($installedTools | ForEach-Object { "- ``$_``" }) -join "`n"
$tokens['__TASKBOARD__'] = if ($taskboardUrl) { $taskboardUrl } else { '(noch nicht gesetzt - in mandate.config.json ergaenzen)' }

Copy-TemplateFile -TemplatePath (Join-Path $tplDir 'project-README.md.tmpl') -DestPath (Join-Path $root 'README.md') -Tokens $tokens

Write-Host ''
Write-Host "=== Fertig: $script:created Datei(en)/Ordner erstellt, $script:skipped uebersprungen ===" -ForegroundColor Cyan
if ($clientFolderValid -and $seedFromClient) {
    Write-Host 'Naechster Schritt: im Copilot Chat den Prompt /bootstrap-mandate ausfuehren, um den Memory-Index zu befuellen.' -ForegroundColor Cyan
}
Write-Host 'Oeffne README.md fuer die Kurzanleitung zum KI-basierten Projekt-Assistenten.' -ForegroundColor Cyan

$readmePath = Join-Path $root 'README.md'
if (Get-Command code -ErrorAction SilentlyContinue) {
    & code $readmePath
} else {
    Invoke-Item $readmePath
}
