<#
.SYNOPSIS
    Publiziert den Memory-Index (mem-index/) in das GitLab-Wiki des Kunden -
    isoliert in einem Unterordner, ohne bestehende Team-Seiten zu beruehren.

.DESCRIPTION
    Ein einzelnes, self-contained Skript. Es liegt im Root-Ordner des Mandats
    und wird von dort ausgefuehrt. Ablauf:

      1. mem-index/-Ordner erkennen (Ordner mit 00_INDEX.md).
      2. Kunden-Wiki nach .wiki-publish/wiki klonen bzw. aktualisieren.
      3. Alle *.md-Nodes in den Wiki-Unterordner (-Subdir, Default
         'memory-index') kopieren. Auf den KOPIEN werden Obsidian-Wikilinks
         [[Ziel]] -> [[<Subdir>/Ziel]] umgeschrieben, damit sie im
         Unterordner aufloesen, und Obsidian-Callouts leserlich gemacht.
      4. Verwaiste Seiten NUR innerhalb des Unterordners entfernen
         (Mirror-Semantik). Root-home.md, _sidebar.md und Team-Seiten
         ausserhalb des Unterordners werden NIE angefasst.
      5. Commit + Push ins GitLab-Wiki.

    Deploy-Gate: Ausser bei -WhatIf fragt das Skript vor Schritt 4/5 explizit
    per Ja/Nein-Prompt nach, da damit reale Aenderungen im Kunden-Wiki
    entstehen (Commit lokal bzw. + Push). Bei 'Nein' wird sofort abgebrochen,
    ohne irgendetwas zu schreiben, zu committen oder zu pushen.

    Der Memory-Index (mem-index/) wird NIE veraendert - nur gelesen/kopiert.
    Es werden KEINE LLM-Tokens verbraucht (reiner Git-/PowerShell-Build).

.PARAMETER WikiUrl
    Git-URL des Kunden-Wikis. Pflichtangabe; ohne Parameter wird interaktiv gefragt.

.PARAMETER Subdir
    Wiki-Unterordner fuer die Nodes. Default: 'memory-index'.

.PARAMETER MemIndexPath
    Pfad zum mem-index-Ordner relativ zum Skript-Root. Ueberschreibt den
    Auto-Detect (Ordner mit 00_INDEX.md).

.PARAMETER Message
    Commit-Nachricht. Ohne Angabe wird eine mit Quell-Commit-Hash generiert.

.PARAMETER KeepCallouts
    Obsidian-Callout-Header (> [!TIP]) NICHT in fette Labels umschreiben.

.PARAMETER NoPush
    Commit erzeugen, aber nicht pushen.

.PARAMETER Reinstall
    Verworfene lokale Wiki-Kopie neu klonen.

.PARAMETER ShowDiff
    Zeigt zusaetzlich zur Add/Update/Delete-Liste einen unified diff (via
    'git diff --no-index') je geaendertem/neuem Node gegen den zuletzt
    publizierten Wiki-Stand.

.PARAMETER WhatIf
    Nur anzeigen, was sich aendern wuerde (kein Copy/Delete/Commit/Push, kein
    Bestaetigungs-Prompt).

.EXAMPLE
    ./publish-wiki.ps1 -WhatIf
    Zeigt die geplanten Aenderungen (Add/Update/Delete) im Unterordner.

.EXAMPLE
    ./publish-wiki.ps1 -WhatIf -ShowDiff
    Zeigt zusaetzlich den Zeilen-Diff je geaendertem/neuem Node.

.EXAMPLE
    ./publish-wiki.ps1
    Publiziert den Memory-Index ins GitLab-Wiki und pusht.

.EXAMPLE
    ./publish-wiki.ps1 -NoPush -Message "wip: struktur-update"
    Committet lokal, ohne zu pushen.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$WikiUrl,
    [string]$Subdir = 'memory-index',
    [string]$MemIndexPath,
    [string]$Message,
    [switch]$KeepCallouts,
    [switch]$NoPush,
    [switch]$Reinstall,
    [switch]$ShowDiff
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($WikiUrl)) {
    $WikiUrl = Read-Host 'Git-URL des Kunden-Wikis (z.B. https://gitlab.com/<gruppe>/<projekt>.wiki.git)'
}
if ([string]::IsNullOrWhiteSpace($WikiUrl)) {
    Write-Error 'Keine Wiki-URL angegeben. Usage: ./publish-wiki.ps1 -WikiUrl <git-url> [-Subdir <name>] [...]'
    exit 1
}

$here = $PSScriptRoot
$workRoot = Join-Path $here '.wiki-publish'      # gecachte Wiki-Kopie (gitignored)
$wikiDir = Join-Path $workRoot 'wiki'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# ===========================================================================
#  Hilfsfunktionen
# ===========================================================================

function Assert-Git {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "git wurde nicht gefunden. Bitte Git installieren."
    }
}

# Long-path-sicher loeschen (robocopy-Mirror-Trick).
function Remove-DirRobust([string]$Target) {
    if (-not (Test-Path $Target)) { return }
    $empty = Join-Path $env:TEMP ("empty_" + [guid]::NewGuid().ToString('N'))
    [void][System.IO.Directory]::CreateDirectory($empty)
    robocopy $empty $Target /MIR /NFL /NDL /NJH /NJS /NC /NS /NP | Out-Null
    Remove-Item $Target -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $empty -Recurse -Force -ErrorAction SilentlyContinue
}

# git-Befehl im angegebenen Repo ausfuehren; stderr nicht als Fehler werten
# (git schreibt Fortschritt nach stderr). Erfolg wird am Exit-Code gemessen.
function Invoke-Git {
    param([string]$RepoDir, [string[]]$GitArgs, [switch]$AllowFail)
    $prevEA = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & git -C $RepoDir @GitArgs 2>&1
        if ($LASTEXITCODE -ne 0 -and -not $AllowFail) {
            throw "git $($GitArgs -join ' ') fehlgeschlagen (Code $LASTEXITCODE):`n$out"
        }
        return $out
    } finally { $ErrorActionPreference = $prevEA }
}

# Obsidian-Wikilinks auf den Unterordner umschreiben: [[Ziel]] ->
# [[Subdir/Ziel]] bzw. [[Text|Ziel]] -> [[Text|Subdir/Ziel]]. Ziele, die
# bereits einen Slash enthalten (schon ein Pfad), bleiben unveraendert.
function Convert-Wikilinks {
    param([string]$Text, [string]$Prefix)
    $evaluator = {
        param($m)
        $inner = $m.Groups[1].Value
        $parts = $inner.Split('|')
        $target = $parts[-1]
        if ($target -match '/') { return $m.Value }   # schon ein Pfad
        $parts[-1] = "$Prefix/$target"
        return '[[' + ($parts -join '|') + ']]'
    }
    return [regex]::Replace($Text, '\[\[([^\]]+)\]\]', $evaluator)
}

# Obsidian-Callout-Header leserlich machen: '> [!TIP] Titel' -> '> **TIP** Titel'.
# GitLab rendert [!TIP] sonst als sichtbaren Klartext.
function Convert-Callouts {
    param([string]$Text)
    $lines = $Text -split "`n", 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^(\s*>+\s*)\[!(\w+)\][+-]?\s*(.*)$') {
            $prefix = $matches[1]
            $type = $matches[2].ToUpper()
            $title = $matches[3].TrimEnd("`r")
            $lines[$i] = if ($title) { "$prefix**$type** $title" } else { "$prefix**$type**" }
        }
    }
    return ($lines -join "`n")
}

# Unified diff zweier Inhalte via 'git diff --no-index' (Temp-Dateien, kein echtes Repo noetig).
function Show-NodeDiff {
    param([string]$Name, [string]$OldText, [string]$NewText)
    $tmp = Join-Path $env:TEMP ("wikidiff_" + [guid]::NewGuid().ToString('N'))
    [void][System.IO.Directory]::CreateDirectory($tmp)
    $oldFile = Join-Path $tmp 'old.md'
    $newFile = Join-Path $tmp 'new.md'
    [System.IO.File]::WriteAllText($oldFile, $OldText, $utf8NoBom)
    [System.IO.File]::WriteAllText($newFile, $NewText, $utf8NoBom)
    Write-Host "`n--- diff: $Name ---" -ForegroundColor Cyan
    # Exit-Code 1 bei Unterschieden ist bei --no-index normal, kein Fehler.
    & git diff --no-index --color=always -- $oldFile $newFile
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# ===========================================================================
#  1. mem-index-Ordner bestimmen (Auto-Detect oder -MemIndexPath)
# ===========================================================================

Assert-Git

if ($MemIndexPath) {
    $candidate = if ([System.IO.Path]::IsPathRooted($MemIndexPath)) { $MemIndexPath }
                 else { Join-Path $here $MemIndexPath }
    if (-not (Test-Path $candidate -PathType Container)) {
        throw "Angegebener MemIndexPath existiert nicht: $candidate"
    }
    $SourceDir = (Resolve-Path $candidate).Path
} else {
    $indexHits = Get-ChildItem -Path $here -Recurse -File -Filter '00_INDEX.md' -ErrorAction SilentlyContinue |
        Where-Object {
            $_.FullName -notmatch '\\\.obsidian\\' -and
            $_.FullName -notmatch '\\\.git\\' -and
            $_.FullName -notmatch '\\\.wiki-publish\\' -and
            $_.FullName -notmatch '\\\.mem-index-export\\' -and
            $_.FullName -notmatch '\\export-artefacts\\'
        } |
        Sort-Object { $_.FullName.Length }
    if (-not $indexHits) { throw "Kein mem-index-Ordner mit 00_INDEX.md gefunden. Bitte -MemIndexPath angeben." }
    $SourceDir = $indexHits[0].DirectoryName
}
Write-Host "==> Memory-Index: $SourceDir" -ForegroundColor Green
Write-Host "==> Wiki-Unterordner: $Subdir" -ForegroundColor Green

$nodes = Get-ChildItem -Path $SourceDir -File -Filter '*.md' | Sort-Object Name
if (-not $nodes) { throw "Keine *.md-Nodes in $SourceDir gefunden." }

# ===========================================================================
#  2. Wiki klonen / aktualisieren
# ===========================================================================

if ($Reinstall) { Remove-DirRobust $wikiDir }

if (Test-Path (Join-Path $wikiDir '.git')) {
    Write-Host "==> Aktualisiere lokale Wiki-Kopie (fetch + reset) ..." -ForegroundColor Yellow
    Invoke-Git $wikiDir @('fetch', '--depth', '1', 'origin') | Out-Null
    $branch = (Invoke-Git $wikiDir @('rev-parse', '--abbrev-ref', 'HEAD')).ToString().Trim()
    Invoke-Git $wikiDir @('reset', '--hard', "origin/$branch") | Out-Null
} else {
    # Cache-Ordner ist Lese-Voraussetzung fuer den Diff - muss auch bei -WhatIf existieren.
    [void][System.IO.Directory]::CreateDirectory($workRoot)
    Remove-DirRobust $wikiDir
    Write-Host "==> Klone Kunden-Wiki ..." -ForegroundColor Yellow
    Invoke-Git $workRoot @('clone', '--depth', '1', $WikiUrl, 'wiki') | Out-Null
}
$branch = (Invoke-Git $wikiDir @('rev-parse', '--abbrev-ref', 'HEAD')).ToString().Trim()
Write-Host "==> Wiki-Branch: $branch" -ForegroundColor Green

# ===========================================================================
#  3. Ziel-Inhalte aufbauen (transformierte Kopien)
# ===========================================================================

$targetSubdir = Join-Path $wikiDir $Subdir
$newContent = [ordered]@{}   # relativer Dateiname -> transformierter Inhalt
foreach ($node in $nodes) {
    $text = [System.IO.File]::ReadAllText($node.FullName)
    $text = Convert-Wikilinks -Text $text -Prefix $Subdir
    if (-not $KeepCallouts) { $text = Convert-Callouts -Text $text }
    $newContent[$node.Name] = $text
}

# Vorhandene Nodes im Unterordner ermitteln (nur *.md, flache Struktur).
$existing = @{}
if (Test-Path $targetSubdir) {
    Get-ChildItem -Path $targetSubdir -File -Filter '*.md' | ForEach-Object {
        $existing[$_.Name] = [System.IO.File]::ReadAllText($_.FullName)
    }
}

# Diff berechnen: Add / Update / Delete (Delete NUR innerhalb des Unterordners).
$adds = @(); $updates = @(); $deletes = @()
foreach ($name in $newContent.Keys) {
    if (-not $existing.ContainsKey($name)) { $adds += $name }
    elseif ($existing[$name] -ne $newContent[$name]) { $updates += $name }
}
foreach ($name in $existing.Keys) {
    if (-not $newContent.Contains($name)) { $deletes += $name }
}

Write-Host ""
Write-Host "==> Geplante Aenderungen in '$Subdir/':" -ForegroundColor Cyan
Write-Host ("    Add    : {0}" -f $adds.Count) -ForegroundColor Green
$adds    | ForEach-Object { Write-Host "      + $_" -ForegroundColor DarkGreen }
Write-Host ("    Update : {0}" -f $updates.Count) -ForegroundColor Yellow
$updates | ForEach-Object { Write-Host "      ~ $_" -ForegroundColor DarkYellow }
Write-Host ("    Delete : {0}" -f $deletes.Count) -ForegroundColor Red
$deletes | ForEach-Object { Write-Host "      - $_" -ForegroundColor DarkRed }

if ($ShowDiff) {
    foreach ($name in $updates) { Show-NodeDiff -Name $name -OldText $existing[$name] -NewText $newContent[$name] }
    foreach ($name in $adds)    { Show-NodeDiff -Name $name -OldText ''               -NewText $newContent[$name] }
}

if ($adds.Count -eq 0 -and $updates.Count -eq 0 -and $deletes.Count -eq 0) {
    Write-Host "`n==> Nichts zu tun. Wiki ist bereits aktuell." -ForegroundColor Green
    return
}

# ===========================================================================
#  Deploy-Gate: ausserhalb von -WhatIf explizite Bestaetigung einholen, da
#  dieser Lauf reale Aenderungen im GESCHAEFTSKUNDEN-Wiki erzeugt (Commit
#  lokal bzw. + Push, ausser -NoPush ist gesetzt).
# ===========================================================================

if (-not $WhatIfPreference) {
    $target = if ($NoPush) { "lokal committet (kein Push, -NoPush gesetzt)" } else { "ins Kunden-Wiki '$WikiUrl' (Branch '$branch') gepusht" }
    Write-Host ""
    Write-Host "==> ACHTUNG: $($adds.Count) neue, $($updates.Count) geaenderte und $($deletes.Count) geloeschte Seite(n) unter '$Subdir/' werden gleich $target." -ForegroundColor Red
    $choice = $Host.UI.PromptForChoice(
        'Publish bestaetigen',
        'Diese Version wirklich deployen? Zum Pruefen ohne Wirkung stattdessen mit -WhatIf abbrechen und erneut mit -WhatIf aufrufen.',
        @('&Ja, deployen', '&Nein, abbrechen'),
        1)
    if ($choice -ne 0) {
        Write-Host "`n==> Abgebrochen durch Nutzer. Keine Aenderungen geschrieben, committet oder gepusht." -ForegroundColor Yellow
        return
    }
}

# ===========================================================================
#  4. Anwenden (Copy/Delete) - ausser bei -WhatIf
# ===========================================================================

if (-not $PSCmdlet.ShouldProcess("$Subdir/ im Kunden-Wiki", "Nodes schreiben & verwaiste entfernen")) {
    Write-Host "`n==> -WhatIf: keine Aenderungen geschrieben." -ForegroundColor Cyan
    return
}

if (-not (Test-Path $targetSubdir)) { New-Item -ItemType Directory -Path $targetSubdir -Force | Out-Null }
foreach ($name in $newContent.Keys) {
    [System.IO.File]::WriteAllText((Join-Path $targetSubdir $name), $newContent[$name], $utf8NoBom)
}
foreach ($name in $deletes) {
    Remove-Item (Join-Path $targetSubdir $name) -Force
}

# ===========================================================================
#  5. Commit + Push
# ===========================================================================

# Quell-Commit-Hash fuer die Nachvollziehbarkeit (falls Mandats-Repo existiert).
$srcHash = (Invoke-Git $here @('rev-parse', '--short', 'HEAD') -AllowFail)
if ($LASTEXITCODE -ne 0 -or -not $srcHash) { $srcHash = 'n/a' }
else { $srcHash = $srcHash.ToString().Trim() }

if (-not $Message) {
    $stamp = Get-Date -Format 'yyyy-MM-dd'
    $Message = "publish: mem-index $stamp (source $srcHash)"
}

Invoke-Git $wikiDir @('add', '--', $Subdir) | Out-Null
$status = (Invoke-Git $wikiDir @('status', '--porcelain', '--', $Subdir)).ToString()
if ([string]::IsNullOrWhiteSpace($status)) {
    Write-Host "`n==> Keine gestagten Aenderungen - nichts zu committen." -ForegroundColor Yellow
    return
}

Invoke-Git $wikiDir @('commit', '-m', $Message) | Out-Null
Write-Host "==> Commit erstellt: $Message" -ForegroundColor Green

if ($NoPush) {
    Write-Host "==> -NoPush: Commit bleibt lokal in $wikiDir." -ForegroundColor Cyan
    return
}

Write-Host "==> Push ins GitLab-Wiki ..." -ForegroundColor Yellow
Invoke-Git $wikiDir @('push', 'origin', "HEAD:$branch") | Out-Null
Write-Host "`n==> Fertig. Memory-Index im Wiki-Unterordner '$Subdir' publiziert." -ForegroundColor Green
