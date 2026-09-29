<#
.SYNOPSIS
    Uebernimmt aus dem Master-Schedule-Web-Editor heruntergeladene Aenderungen in den Memory-Index.

.DESCRIPTION
    Liest master-schedule-changes.json (heruntergeladen aus master-schedule-editor.html ueber den
    "Speichern"-Button), vergleicht sie mit dem aktuellen mem-index/09_Master-Schedule.json und
    zeigt eine lesbare Diff-Zusammenfassung (Projekt-Rahmendaten, Meilensteine, Arbeitsstroeme,
    Arbeitspakete: hinzugefuegt/entfernt/geaendert).

    Schreibt NICHTS, bevor der Nutzer die angezeigte Zusammenfassung explizit bestaetigt hat
    (Default bei der Rueckfrage ist NEIN). Nach Bestaetigung: `09_Master-Schedule.json` wird
    ueberschrieben, `09_Master-Schedule.md` neu generiert, ein `update`-Eintrag an `log.md`
    angehaengt, und die verarbeitete Aenderungsdatei nach
    `mem-index/_applied-schedule-changes/` verschoben (nicht geloescht).

.PARAMETER ProjectRoot
    Wurzelordner des Mandats. Default: Ordner, in dem dieses Skript liegt.

.PARAMETER MemIndexFolder
    Name des Memory-Index-Ordners relativ zu ProjectRoot. Default: "mem-index".

.PARAMETER PendingChangesPath
    Pfad zur heruntergeladenen Aenderungsdatei. Default: <ProjectRoot>/master-schedule-changes.json.

.EXAMPLE
    ./apply-master-schedule-changes.ps1
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot = $PSScriptRoot,
    [string]$MemIndexFolder = 'mem-index',
    [string]$PendingChangesPath
)

$ErrorActionPreference = 'Stop'

if (-not $PendingChangesPath) { $PendingChangesPath = Join-Path $ProjectRoot 'master-schedule-changes.json' }
if (-not (Test-Path -LiteralPath $PendingChangesPath)) {
    throw "Keine Aenderungsdatei gefunden unter: $PendingChangesPath. Im Master-Schedule-Editor (master-schedule-editor.html) zuerst auf 'Speichern' klicken und die heruntergeladene Datei in den Projekt-Root legen."
}

$MemIndexPath = Join-Path $ProjectRoot $MemIndexFolder
$JsonPath = Join-Path $MemIndexPath '09_Master-Schedule.json'
$MdPath = Join-Path $MemIndexPath '09_Master-Schedule.md'
$LogPath = Join-Path $MemIndexPath 'log.md'
$ArchiveDir = Join-Path $MemIndexPath '_applied-schedule-changes'

if (-not (Test-Path -LiteralPath $MemIndexPath -PathType Container)) {
    throw "Memory-Index-Ordner nicht gefunden: $MemIndexPath."
}

# ===========================================================================
#  Helpers (self-contained, duplicated across schedule-*.ps1 - siehe Repo-Konvention)
# ===========================================================================

function Write-FileUtf8NoBom {
    param([string]$Path, [string]$Content)
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText([System.IO.Path]::GetFullPath($Path), $Content, $enc)
}

function Read-YesNo {
    param([string]$Prompt, [bool]$DefaultYes = $false)
    $hint = if ($DefaultYes) { 'J/n' } else { 'j/N' }
    do {
        $answer = (Read-Host "$Prompt [$hint]").Trim()
        if ([string]::IsNullOrWhiteSpace($answer)) { return $DefaultYes }
        if ($answer -match '^(j|ja|y|yes)$') { return $true }
        if ($answer -match '^(n|nein|no)$') { return $false }
        Write-Warning 'Bitte j oder n eingeben.'
    } while ($true)
}

function Get-MandateName {
    param([string]$ProjectRoot)
    $configPath = Join-Path $ProjectRoot 'mandate.config.json'
    if (Test-Path -LiteralPath $configPath) {
        try {
            $cfg = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($cfg.projectName) { return [string]$cfg.projectName }
        } catch {
            # ignore, fall through to folder-name fallback
        }
    }
    return (Split-Path -Leaf $ProjectRoot)
}

function ConvertTo-MutableSchedule {
    param($Source)
    $milestones = New-Object System.Collections.Generic.List[object]
    foreach ($m in @($Source.milestones)) {
        $milestones.Add([ordered]@{ id = $m.id; name = $m.name; date = $m.date; description = $m.description })
    }
    $lanes = New-Object System.Collections.Generic.List[object]
    foreach ($l in @($Source.lanes)) {
        $workPackages = New-Object System.Collections.Generic.List[object]
        foreach ($w in @($l.workPackages)) {
            $workPackages.Add([ordered]@{
                id = $w.id; name = $w.name; startDate = $w.startDate; endDate = $w.endDate
                priority = $w.priority; effortPT = $w.effortPT; status = $w.status
            })
        }
        $lanes.Add([ordered]@{ id = $l.id; name = $l.name; owner = $l.owner; workPackages = $workPackages })
    }
    return [ordered]@{
        generated = $Source.generated
        project   = [ordered]@{ name = $Source.project.name; startDate = $Source.project.startDate; endDate = $Source.project.endDate }
        milestones = $milestones
        lanes      = $lanes
    }
}

function ConvertTo-MasterScheduleMarkdown {
    param($Schedule, [string]$MandateName)
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# Master-Schedule - $MandateName")
    $lines.Add('')
    $lines.Add('> Auto-generiert aus `09_Master-Schedule.json` (Single Source of Truth). Diese Datei nie von')
    $lines.Add('> Hand editieren - Aenderungen gehen beim naechsten Regenerieren verloren. Stattdessen:')
    $lines.Add('> `./schedule-wizard.ps1` (interaktiver Wizard), Copilot-Chat `/pflege-master-schedule`')
    $lines.Add('> (konversationell), oder `master-schedule-editor.html` + `./apply-master-schedule-changes.ps1`')
    $lines.Add('> (Web-Editor).')
    $lines.Add('')
    $lines.Add('## Projekt-Rahmendaten')
    $lines.Add('')
    $lines.Add('| Feld | Wert |')
    $lines.Add('|---|---|')
    $startText = if ($Schedule.project.startDate) { $Schedule.project.startDate } else { '[nicht gesetzt]' }
    $endText = if ($Schedule.project.endDate) { $Schedule.project.endDate } else { '[nicht gesetzt]' }
    $lines.Add("| Start | $startText |")
    $lines.Add("| Ende | $endText |")
    $lines.Add('')
    $lines.Add('## Etappen und lieferbare Meilensteine')
    $lines.Add('')
    if ($Schedule.milestones.Count -eq 0) {
        $lines.Add('_Noch keine Meilensteine erfasst._')
    } else {
        $lines.Add('| ID | Name | Datum | Beschreibung |')
        $lines.Add('|---|---|---|---|')
        foreach ($m in ($Schedule.milestones | Sort-Object { [datetime]$_.date })) {
            $desc = if ($m.description) { $m.description } else { '' }
            $lines.Add("| $($m.id) | $($m.name) | $($m.date) | $desc |")
        }
    }
    $lines.Add('')
    $lines.Add('## Arbeitsstroeme (Lanes)')
    $lines.Add('')
    if ($Schedule.lanes.Count -eq 0) {
        $lines.Add('_Noch keine Arbeitsstroeme erfasst._')
    } else {
        foreach ($lane in $Schedule.lanes) {
            $lines.Add("### $($lane.id) - $($lane.name) (Owner: $($lane.owner))")
            $lines.Add('')
            if ($lane.workPackages.Count -eq 0) {
                $lines.Add('_Noch keine Arbeitspakete in dieser Lane._')
            } else {
                $lines.Add('| ID | Name | Start | Ende | Prioritaet | Aufwand (PT) | Status |')
                $lines.Add('|---|---|---|---|---|---|---|')
                foreach ($wp in ($lane.workPackages | Sort-Object { [datetime]$_.startDate })) {
                    $lines.Add("| $($wp.id) | $($wp.name) | $($wp.startDate) | $($wp.endDate) | $($wp.priority) | $($wp.effortPT) | $($wp.status) |")
                }
            }
            $lines.Add('')
        }
    }
    $lines.Add('---')
    $lines.Add("_Zuletzt generiert: $(Get-Date -Format 'yyyy-MM-dd HH:mm') durch schedule-wizard.ps1 / apply-master-schedule-changes.ps1 / /pflege-master-schedule._")
    return ($lines -join "`n")
}

function Add-LogEntry {
    param([string]$LogPath, [string]$Type, [string]$Summary, [string]$Details)
    $date = Get-Date -Format 'yyyy-MM-dd'
    $entry = @(
        "## [$date] $Type | $Summary"
        ''
        "**Aktion:** $Summary"
        '**Geaenderte Nodes:** [[09_Master-Schedule]]'
        "**Details:** $Details"
        ''
        '---'
        ''
    ) -join "`n"
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::AppendAllText([System.IO.Path]::GetFullPath($LogPath), $entry, $enc)
}

# Flat id -> object map, work packages additionally carry their owning lane id for the diff.
function Get-MilestoneMap { param($Schedule) $map = @{}; foreach ($m in $Schedule.milestones) { $map[$m.id] = $m }; return $map }
function Get-LaneMap { param($Schedule) $map = @{}; foreach ($l in $Schedule.lanes) { $map[$l.id] = $l }; return $map }
function Get-WorkPackageMap {
    param($Schedule)
    $map = @{}
    foreach ($l in $Schedule.lanes) { foreach ($w in $l.workPackages) { $map[$w.id] = [PSCustomObject]@{ wp = $w; laneId = $l.id } } }
    return $map
}

# ===========================================================================
#  Load current + incoming
# ===========================================================================

$mandateName = Get-MandateName -ProjectRoot $ProjectRoot

if (Test-Path -LiteralPath $JsonPath) {
    $currentRaw = Get-Content -LiteralPath $JsonPath -Raw -Encoding UTF8
    $current = ConvertTo-MutableSchedule -Source ($currentRaw | ConvertFrom-Json)
} else {
    $current = ConvertTo-MutableSchedule -Source ([PSCustomObject]@{
        generated = ''; project = [PSCustomObject]@{ name = $mandateName; startDate = ''; endDate = '' }
        milestones = @(); lanes = @()
    })
}

$incomingRaw = Get-Content -LiteralPath $PendingChangesPath -Raw -Encoding UTF8
try {
    $incomingSource = $incomingRaw | ConvertFrom-Json
} catch {
    throw "Aenderungsdatei ist kein gueltiges JSON: $PendingChangesPath. Details: $($_.Exception.Message)"
}
if (-not $incomingSource.PSObject.Properties['project'] -or -not $incomingSource.PSObject.Properties['lanes']) {
    throw "Aenderungsdatei hat nicht die erwartete Master-Schedule-Struktur (project/milestones/lanes): $PendingChangesPath"
}
$incoming = ConvertTo-MutableSchedule -Source $incomingSource

# ===========================================================================
#  Diff
# ===========================================================================

Write-Host ''
Write-Host '=== Master-Schedule: Aenderungen aus master-schedule-changes.json ===' -ForegroundColor Cyan

$projectChanged = $false
foreach ($f in 'name', 'startDate', 'endDate') {
    if ([string]$current.project[$f] -ne [string]$incoming.project[$f]) {
        Write-Host ("  Projekt.{0}: '{1}' -> '{2}'" -f $f, $current.project[$f], $incoming.project[$f]) -ForegroundColor Yellow
        $projectChanged = $true
    }
}
if (-not $projectChanged) { Write-Host '  Projekt-Rahmendaten: unveraendert' -ForegroundColor DarkGray }

$curMilestones = Get-MilestoneMap $current
$newMilestones = Get-MilestoneMap $incoming
$addedM = @($newMilestones.Keys | Where-Object { -not $curMilestones.Contains($_) })
$removedM = @($curMilestones.Keys | Where-Object { -not $newMilestones.Contains($_) })
$changedM = @($newMilestones.Keys | Where-Object { $curMilestones.Contains($_) -and ($curMilestones[$_].name -ne $newMilestones[$_].name -or $curMilestones[$_].date -ne $newMilestones[$_].date -or $curMilestones[$_].description -ne $newMilestones[$_].description) })
Write-Host ("  Meilensteine: {0} neu, {1} entfernt, {2} geaendert" -f $addedM.Count, $removedM.Count, $changedM.Count)
foreach ($id in $addedM) { Write-Host ("    + {0}: {1} ({2})" -f $id, $newMilestones[$id].name, $newMilestones[$id].date) -ForegroundColor Green }
foreach ($id in $removedM) { Write-Host ("    - {0}: {1}" -f $id, $curMilestones[$id].name) -ForegroundColor Red }
foreach ($id in $changedM) { Write-Host ("    ~ {0}: {1}" -f $id, $newMilestones[$id].name) -ForegroundColor Yellow }

$curLanes = Get-LaneMap $current
$newLanes = Get-LaneMap $incoming
$addedL = @($newLanes.Keys | Where-Object { -not $curLanes.Contains($_) })
$removedL = @($curLanes.Keys | Where-Object { -not $newLanes.Contains($_) })
$changedL = @($newLanes.Keys | Where-Object { $curLanes.Contains($_) -and ($curLanes[$_].name -ne $newLanes[$_].name -or $curLanes[$_].owner -ne $newLanes[$_].owner) })
Write-Host ("  Arbeitsstroeme: {0} neu, {1} entfernt, {2} geaendert" -f $addedL.Count, $removedL.Count, $changedL.Count)
foreach ($id in $addedL) { Write-Host ("    + {0}: {1} (Owner: {2})" -f $id, $newLanes[$id].name, $newLanes[$id].owner) -ForegroundColor Green }
foreach ($id in $removedL) { Write-Host ("    - {0}: {1}" -f $id, $curLanes[$id].name) -ForegroundColor Red }
foreach ($id in $changedL) { Write-Host ("    ~ {0}: {1}" -f $id, $newLanes[$id].name) -ForegroundColor Yellow }

$curWp = Get-WorkPackageMap $current
$newWp = Get-WorkPackageMap $incoming
$addedWp = @($newWp.Keys | Where-Object { -not $curWp.Contains($_) })
$removedWp = @($curWp.Keys | Where-Object { -not $newWp.Contains($_) })
$changedWp = @($newWp.Keys | Where-Object {
    $curWp.Contains($_) -and (
        $curWp[$_].laneId -ne $newWp[$_].laneId -or
        $curWp[$_].wp.name -ne $newWp[$_].wp.name -or
        $curWp[$_].wp.startDate -ne $newWp[$_].wp.startDate -or
        $curWp[$_].wp.endDate -ne $newWp[$_].wp.endDate -or
        $curWp[$_].wp.priority -ne $newWp[$_].wp.priority -or
        [string]$curWp[$_].wp.effortPT -ne [string]$newWp[$_].wp.effortPT -or
        $curWp[$_].wp.status -ne $newWp[$_].wp.status
    )
})
Write-Host ("  Arbeitspakete: {0} neu, {1} entfernt, {2} geaendert" -f $addedWp.Count, $removedWp.Count, $changedWp.Count)
foreach ($id in $addedWp) { Write-Host ("    + {0}: {1} [{2}]" -f $id, $newWp[$id].wp.name, $newWp[$id].laneId) -ForegroundColor Green }
foreach ($id in $removedWp) { Write-Host ("    - {0}: {1}" -f $id, $curWp[$id].wp.name) -ForegroundColor Red }
foreach ($id in $changedWp) { Write-Host ("    ~ {0}: {1}" -f $id, $newWp[$id].wp.name) -ForegroundColor Yellow }

$totalChanges = [int]$projectChanged + $addedM.Count + $removedM.Count + $changedM.Count + $addedL.Count + $removedL.Count + $changedL.Count + $addedWp.Count + $removedWp.Count + $changedWp.Count
Write-Host ''
if ($totalChanges -eq 0) {
    Write-Host 'Keine Unterschiede zum aktuellen Memory-Index gefunden - nichts zu tun.' -ForegroundColor Yellow
    return
}

# ===========================================================================
#  Confirm (default: nein) + write
# ===========================================================================

if (-not (Read-YesNo "Diese $totalChanges Aenderung(en) jetzt in den Memory-Index uebernehmen?" $false)) {
    Write-Host 'Abgebrochen - es wurde nichts geschrieben.' -ForegroundColor Yellow
    return
}

$incoming.generated = (Get-Date -Format 'yyyy-MM-dd')
Write-FileUtf8NoBom -Path $JsonPath -Content ($incoming | ConvertTo-Json -Depth 10)
Write-FileUtf8NoBom -Path $MdPath -Content (ConvertTo-MasterScheduleMarkdown -Schedule $incoming -MandateName $mandateName)
Add-LogEntry -LogPath $LogPath -Type 'update' -Summary 'Master-Schedule ueber master-schedule-editor.html aktualisiert' -Details ("Meilensteine: +$($addedM.Count)/-$($removedM.Count)/~$($changedM.Count). Arbeitsstroeme: +$($addedL.Count)/-$($removedL.Count)/~$($changedL.Count). Arbeitspakete: +$($addedWp.Count)/-$($removedWp.Count)/~$($changedWp.Count). Projekt-Rahmendaten geaendert: $projectChanged.")

if (-not (Test-Path -LiteralPath $ArchiveDir)) { New-Item -ItemType Directory -Path $ArchiveDir -Force | Out-Null }
$archiveName = (Get-Date -Format 'yyyyMMdd-HHmmss') + '_master-schedule-changes.json'
Move-Item -LiteralPath $PendingChangesPath -Destination (Join-Path $ArchiveDir $archiveName) -Force

Write-Host ''
Write-Host "Uebernommen: $JsonPath, $MdPath aktualisiert. Log-Eintrag ergaenzt." -ForegroundColor Green
Write-Host "Aenderungsdatei archiviert: $(Join-Path $ArchiveDir $archiveName)" -ForegroundColor Green
