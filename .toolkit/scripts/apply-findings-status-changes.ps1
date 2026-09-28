<#
.SYNOPSIS
    Applies status changes queued in the Findings Dashboard (findings-dashboard.html) to the overlay.

.DESCRIPTION
    Reads a pending-status-changes.json file (downloaded from the "Ausstehende Aenderungen" panel in
    openspec-sdd/findings-dashboard.html), applies each change to openspec-sdd/findings-status-overlay.md,
    and appends a reconciliation to-do entry to openspec-sdd/mem-index-sync-todo.md so the change is not
    lost or fragmented - mem-index (08_Offene-Fragen.md / 13_Offene-Konflikte.md / 05_Gap-Analyse.md)
    remains the single source of truth and must still be updated there (manually, or via a Copilot-chat
    request) following the log.md protocol in .github/copilot-instructions.md.

    The consumed pending-status-changes.json is archived (moved, not deleted) so re-running this script
    does not double-apply the same changes.

.PARAMETER RepoRoot
    Repository root. Defaults to the folder containing this script.

.PARAMETER PendingChangesPath
    Path to the pending-status-changes.json file. Defaults to <RepoRoot>/pending-status-changes.json.

.EXAMPLE
    ./apply-findings-status-changes.ps1
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = $PSScriptRoot,
    [string]$PendingChangesPath
)

$ErrorActionPreference = 'Stop'

if (-not $PendingChangesPath) { $PendingChangesPath = Join-Path $RepoRoot 'pending-status-changes.json' }
if (-not (Test-Path -LiteralPath $PendingChangesPath)) {
    throw "Keine pending-status-changes.json gefunden unter: $PendingChangesPath. Im Findings-Dashboard (openspec-sdd/findings-dashboard.html) zuerst Aenderungen sammeln und ueber 'Als JSON herunterladen' speichern."
}

$Sym = @{
    Check = [System.Char]::ConvertFromUtf32(0x2705)
}

$OverlayPath  = Join-Path $RepoRoot 'openspec-sdd/findings-status-overlay.md'
$SyncTodoPath = Join-Path $RepoRoot 'openspec-sdd/mem-index-sync-todo.md'
$ArchiveDir   = Join-Path $RepoRoot 'openspec-sdd/_applied-status-changes'

if (-not (Test-Path -LiteralPath $OverlayPath)) {
    throw "Overlay-Datei nicht gefunden: $OverlayPath. Zuerst ./build-findings-dashboard.ps1 ausfuehren."
}

function Split-TableRow {
    param([string]$Line)
    $trimmed = $Line.Trim()
    if (-not $trimmed.StartsWith('|')) { return $null }
    $cells = $trimmed.Trim('|') -split '\|'
    return @($cells | ForEach-Object { $_.Trim() })
}

function Read-Overlay {
    param([string]$Path)
    $rows = [ordered]@{}
    $lines = Get-Content -LiteralPath $Path -Encoding UTF8
    foreach ($line in $lines) {
        if ($line -notmatch '^\|\s*((?:F|K|G)-\d+)\s*\|') { continue }
        $cells = Split-TableRow $line
        if ($cells.Count -lt 4) { continue }
        $rows[$cells[0]] = [PSCustomObject]@{
            ID        = $cells[0]
            Status    = $cells[1]
            Kommentar = $cells[2]
            Datum     = $cells[3]
        }
    }
    return $rows
}

function Write-Overlay {
    # Preamble text is intentionally identical to the one written by build-findings-dashboard.ps1,
    # so a diff between runs of either script only ever shows table-row changes.
    param([string]$Path, [System.Collections.Specialized.OrderedDictionary]$Rows)
    $preamble = @(
        '# Findings Status Overlay'
        ''
        '> Manuell gepflegt. `build-findings-dashboard.ps1` ergaenzt hier NUR neu erkannte IDs (angehaengt am Ende);'
        '> bestehende Zeilen werden nie automatisch veraendert oder geloescht. Status/Kommentar frei anpassbar.'
        '>'
        '> Status-Werte: siehe findings-dashboard.html (Legende) bzw. die Symbole in dieser Tabelle.'
        '>'
        '> Gilt nur fuer Findings (F-/K-/G-). UC-/FA-/NFA-/OP-IDs sind Anforderungs-Anker ohne eigenen Lifecycle-Status'
        '> und erscheinen nur zur Traceability im Dashboard.'
        ''
        '| ID | Status | Kommentar | Zuletzt aktualisiert |'
        '|---|---|---|---|'
    )
    $tableLines = foreach ($row in $Rows.Values) {
        "| $($row.ID) | $($row.Status) | $($row.Kommentar) | $($row.Datum) |"
    }
    $content = ($preamble + $tableLines) -join "`n"
    Set-Content -LiteralPath $Path -Value $content -Encoding UTF8
}

$overlayRows = Read-Overlay -Path $OverlayPath
$pendingRaw = Get-Content -LiteralPath $PendingChangesPath -Raw -Encoding UTF8
$pending = @($pendingRaw | ConvertFrom-Json)

if ($pending.Count -eq 0) {
    Write-Host 'Die Datei enthaelt keine Eintraege - nichts zu tun.' -ForegroundColor Yellow
    return
}

$today = Get-Date -Format 'yyyy-MM-dd'
$applied = @()
$skipped = @()

foreach ($change in $pending) {
    $id = $change.id
    if (-not $overlayRows.Contains($id)) {
        $skipped += $change
        continue
    }
    $old = $overlayRows[$id]
    $overlayRows[$id] = [PSCustomObject]@{
        ID        = $id
        Status    = $change.newStatus
        Kommentar = "Dashboard-Aenderung am $today (vorher: $($old.Status))"
        Datum     = $today
    }
    $applied += [PSCustomObject]@{ ID = $id; OldStatus = $old.Status; NewStatus = $change.newStatus }
}

Write-Overlay -Path $OverlayPath -Rows $overlayRows
Write-Host ("Overlay aktualisiert: {0} Aenderung(en) uebernommen, {1} uebersprungen (unbekannte ID)." -f $applied.Count, $skipped.Count) -ForegroundColor Green

if ($applied.Count -gt 0) {
    if (-not (Test-Path -LiteralPath $SyncTodoPath)) {
        $header = @(
            '# Mem-Index Sync TODO'
            ''
            '> Diese Datei listet Status-Aenderungen, die ueber das Findings-Dashboard vorgenommen wurden und noch'
            '> manuell (oder per Copilot-Chat-Anfrage, z.B. "gleiche mem-index-sync-todo.md mit dem Memory-Index ab")'
            '> in die mem-index SSOT (08_Offene-Fragen.md / 13_Offene-Konflikte.md / 05_Gap-Analyse.md) uebertragen'
            '> werden sollten, inkl. log.md-Eintrag gemaess .github/copilot-instructions.md.'
            '>'
            '> Diese Datei ist KEINE Single Source of Truth, nur eine Erinnerungsliste. Nach Abgleich Zeile abhaken.'
        )
        Set-Content -LiteralPath $SyncTodoPath -Value ($header -join "`n") -Encoding UTF8
    }
    $todoLines = @('', "## $today - via apply-findings-status-changes.ps1", '')
    foreach ($a in $applied) {
        $todoLines += "- [ ] $($a.ID): Dashboard-Status geaendert von `"$($a.OldStatus)`" zu `"$($a.NewStatus)`" - in mem-index (F-/K-/G-Quelle) + log.md nachziehen."
    }
    $todoLines += ''
    $todoLines += '---'
    Add-Content -LiteralPath $SyncTodoPath -Value ($todoLines -join "`n") -Encoding UTF8
    Write-Host "Reconciliation-TODO ergaenzt: $SyncTodoPath" -ForegroundColor Green
}

if ($skipped.Count -gt 0) {
    Write-Warning ("Uebersprungene IDs (nicht im Overlay gefunden): " + (($skipped | ForEach-Object { $_.id }) -join ', '))
}

New-Item -ItemType Directory -Path $ArchiveDir -Force | Out-Null
$archivePath = Join-Path $ArchiveDir ('pending-status-changes_' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
Move-Item -LiteralPath $PendingChangesPath -Destination $archivePath -Force
Write-Host "Verarbeitete Datei archiviert: $archivePath" -ForegroundColor Green

Write-Host ''
Write-Host 'Naechster Schritt: openspec-sdd/mem-index-sync-todo.md durchgehen und die Punkte in mem-index nachziehen' -ForegroundColor Cyan
Write-Host '(SSOT), damit Dashboard-Status und mem-index nicht auseinanderlaufen. Danach ./build-findings-dashboard.ps1' -ForegroundColor Cyan
Write-Host 'erneut ausfuehren, um das Dashboard zu aktualisieren.' -ForegroundColor Cyan
