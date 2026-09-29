<#
.SYNOPSIS
    Interaktiver Wizard zum Erfassen und Pflegen des Master-Schedules im Memory-Index.

.DESCRIPTION
    Portables, self-contained PowerShell-Skript (wird von bootstrap-wizard.ps1 in den Projekt-Root
    kopiert). Fuehrt den Nutzer per Menue durch das Erfassen/Anpassen von:

        - Projekt-Rahmendaten (Start-/Enddatum)
        - Etappen und lieferbaren Meilensteinen
        - Arbeitsstroemen (Lanes) inkl. Owner
        - Arbeitspaketen pro Lane (Name, Start/Ende, Prioritaet, Aufwand in PT, Status)

    Single Source of Truth ist `mem-index/09_Master-Schedule.json`. Nach jedem Speichern wird
    zusaetzlich `mem-index/09_Master-Schedule.md` als lesbare Zusammenfassung neu generiert und ein
    `update`-Eintrag an `mem-index/log.md` angehaengt.

    Wiederholt ausfuehrbar: bestehende Werte werden als Vorschlaege/Defaults geladen, es handelt
    sich also nicht nur um eine Erstbefuellung, sondern ein laufendes Verwaltungs-Tool.

.PARAMETER ProjectRoot
    Wurzelordner des Mandats. Default: Ordner, in dem dieses Skript liegt.

.PARAMETER MemIndexFolder
    Name des Memory-Index-Ordners relativ zu ProjectRoot. Default: "mem-index".

.EXAMPLE
    ./schedule-wizard.ps1
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot = $PSScriptRoot,
    [string]$MemIndexFolder = 'mem-index'
)

$ErrorActionPreference = 'Stop'

$MemIndexPath = Join-Path $ProjectRoot $MemIndexFolder
$JsonPath = Join-Path $MemIndexPath '09_Master-Schedule.json'
$MdPath = Join-Path $MemIndexPath '09_Master-Schedule.md'
$LogPath = Join-Path $MemIndexPath 'log.md'

if (-not (Test-Path -LiteralPath $MemIndexPath -PathType Container)) {
    throw "Memory-Index-Ordner nicht gefunden: $MemIndexPath. Zuerst ./bootstrap-wizard.ps1 ausfuehren."
}

$PriorityOptions = @('Must', 'Should', 'Could', "Won't")
$StatusOptions = @('To Do', 'In Progress', 'Done')

# ===========================================================================
#  Helpers
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

function Read-WithDefault {
    param([string]$Prompt, [string]$Default = '')
    $hint = if ($Default) { " [$Default]" } else { '' }
    $answer = (Read-Host "$Prompt$hint").Trim()
    if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
    return $answer
}

function Read-DateValue {
    param([string]$Prompt, [string]$Default = '', [bool]$AllowEmpty = $true)
    while ($true) {
        $hint = if ($Default) { " [$Default]" } else { '' }
        $answer = (Read-Host "$Prompt (JJJJ-MM-TT)$hint").Trim()
        if ([string]::IsNullOrWhiteSpace($answer)) {
            if ($Default) { return $Default }
            if ($AllowEmpty) { return '' }
            Write-Warning 'Bitte ein Datum im Format JJJJ-MM-TT eingeben.'
            continue
        }
        $parsed = [datetime]::MinValue
        if ([datetime]::TryParseExact($answer, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsed)) {
            return $parsed.ToString('yyyy-MM-dd')
        }
        Write-Warning 'Ungueltiges Format. Bitte JJJJ-MM-TT verwenden (z. B. 2026-03-15).'
    }
}

function Read-NumberValue {
    param([string]$Prompt, [string]$Default = '')
    while ($true) {
        $hint = if ($Default -ne '') { " [$Default]" } else { '' }
        $answer = (Read-Host "$Prompt$hint").Trim()
        if ([string]::IsNullOrWhiteSpace($answer)) {
            if ($Default -ne '') { return [double]$Default }
            Write-Warning 'Bitte eine Zahl eingeben.'
            continue
        }
        $num = 0.0
        if ([double]::TryParse($answer, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$num) -and $num -ge 0) { return $num }
        Write-Warning 'Bitte eine nicht-negative Zahl eingeben (Punkt als Dezimaltrennzeichen).'
    }
}

function Read-EnumChoice {
    param([string]$Prompt, [string[]]$Options, [string]$Default)
    $labelled = for ($i = 0; $i -lt $Options.Count; $i++) { "$($i + 1))$($Options[$i])" }
    $optionsText = $labelled -join '  '
    while ($true) {
        $hint = if ($Default) { " [$Default]" } else { '' }
        $answer = (Read-Host "$Prompt - $optionsText$hint").Trim()
        if ([string]::IsNullOrWhiteSpace($answer)) {
            if ($Default) { return $Default }
            Write-Warning 'Bitte eine Auswahl treffen.'
            continue
        }
        if ($answer -match '^\d+$') {
            $idx = [int]$answer - 1
            if ($idx -ge 0 -and $idx -lt $Options.Count) { return $Options[$idx] }
        }
        $match = $Options | Where-Object { $_ -eq $answer }
        if ($match) { return $match }
        Write-Warning "Ungueltige Auswahl. Bitte Zahl oder exakten Wert eingeben ($($Options -join ', '))."
    }
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

function Get-NextId {
    param([System.Collections.Generic.List[object]]$Items, [string]$Prefix)
    $max = 0
    foreach ($item in $Items) {
        if ($item.id -match "^$Prefix(\d+)$") {
            $n = [int]$Matches[1]
            if ($n -gt $max) { $max = $n }
        }
    }
    return "$Prefix$($max + 1)"
}

# Recursively converts JSON-deserialized PSCustomObjects/arrays into ordered hashtables and
# List[object] so menu actions can Add()/Remove() without PowerShell's array-immutability/
# single-item-unwrap quirks.
function ConvertTo-MutableSchedule {
    param($Source)
    $milestones = New-Object System.Collections.Generic.List[object]
    foreach ($m in @($Source.milestones)) {
        $milestones.Add([ordered]@{
            id          = $m.id
            name        = $m.name
            date        = $m.date
            description = $m.description
        })
    }
    $lanes = New-Object System.Collections.Generic.List[object]
    foreach ($l in @($Source.lanes)) {
        $workPackages = New-Object System.Collections.Generic.List[object]
        foreach ($w in @($l.workPackages)) {
            $workPackages.Add([ordered]@{
                id        = $w.id
                name      = $w.name
                startDate = $w.startDate
                endDate   = $w.endDate
                priority  = $w.priority
                effortPT  = $w.effortPT
                status    = $w.status
            })
        }
        $lanes.Add([ordered]@{
            id           = $l.id
            name         = $l.name
            owner        = $l.owner
            workPackages = $workPackages
        })
    }
    return [ordered]@{
        generated = $Source.generated
        project   = [ordered]@{
            name      = $Source.project.name
            startDate = $Source.project.startDate
            endDate   = $Source.project.endDate
        }
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

function Save-Schedule {
    param($Schedule, [string]$MandateName, [string]$LogSummary, [string]$LogDetails)
    $Schedule.generated = (Get-Date -Format 'yyyy-MM-dd')
    $json = $Schedule | ConvertTo-Json -Depth 10
    Write-FileUtf8NoBom -Path $JsonPath -Content $json
    $md = ConvertTo-MasterScheduleMarkdown -Schedule $Schedule -MandateName $MandateName
    Write-FileUtf8NoBom -Path $MdPath -Content $md
    Add-LogEntry -LogPath $LogPath -Type 'update' -Summary $LogSummary -Details $LogDetails
    Write-Host "Gespeichert: $JsonPath, $MdPath. Log-Eintrag ergaenzt." -ForegroundColor Green
}

function Select-FromList {
    param([System.Collections.Generic.List[object]]$Items, [string]$Prompt, [scriptblock]$Formatter)
    if ($Items.Count -eq 0) { return $null }
    for ($i = 0; $i -lt $Items.Count; $i++) { Write-Host ("  {0}) {1}" -f ($i + 1), (& $Formatter $Items[$i])) }
    $answer = (Read-Host "$Prompt (Zahl oder ID, leer = abbrechen)").Trim()
    if ([string]::IsNullOrWhiteSpace($answer)) { return $null }
    if ($answer -match '^\d+$') {
        $idx = [int]$answer - 1
        if ($idx -ge 0 -and $idx -lt $Items.Count) { return $Items[$idx] }
    }
    return ($Items | Where-Object { $_.id -eq $answer } | Select-Object -First 1)
}

# ===========================================================================
#  Load / init
# ===========================================================================

$mandateName = Get-MandateName -ProjectRoot $ProjectRoot

if (Test-Path -LiteralPath $JsonPath) {
    $raw = Get-Content -LiteralPath $JsonPath -Raw -Encoding UTF8
    $schedule = ConvertTo-MutableSchedule -Source ($raw | ConvertFrom-Json)
    Write-Host "Bestehender Master-Schedule geladen: $JsonPath" -ForegroundColor Cyan
} else {
    $schedule = ConvertTo-MutableSchedule -Source ([PSCustomObject]@{
        generated  = ''
        project    = [PSCustomObject]@{ name = $mandateName; startDate = ''; endDate = '' }
        milestones = @()
        lanes      = @()
    })
    Write-Host 'Kein bestehender Master-Schedule gefunden - neuer Schedule wird angelegt.' -ForegroundColor Yellow
}
if (-not $schedule.project.name) { $schedule.project.name = $mandateName }

# ===========================================================================
#  Menu actions
# ===========================================================================

function Edit-ProjectDates {
    Write-Host ''
    Write-Host '--- Projekt-Rahmendaten ---' -ForegroundColor Cyan
    $schedule.project.startDate = Read-DateValue -Prompt 'Startdatum' -Default $schedule.project.startDate
    $schedule.project.endDate = Read-DateValue -Prompt 'Enddatum' -Default $schedule.project.endDate
}

function Invoke-MilestonesMenu {
    while ($true) {
        Write-Host ''
        Write-Host '--- Meilensteine ---' -ForegroundColor Cyan
        if ($schedule.milestones.Count -eq 0) { Write-Host '  (keine erfasst)' -ForegroundColor DarkGray }
        else {
            foreach ($m in $schedule.milestones) { Write-Host ("  {0}: {1} ({2})" -f $m.id, $m.name, $m.date) }
        }
        Write-Host '1) Hinzufuegen  2) Bearbeiten  3) Entfernen  0) Zurueck'
        switch ((Read-Host 'Auswahl').Trim()) {
            '1' {
                $name = Read-WithDefault -Prompt 'Name des Meilensteins'
                if (-not $name) { continue }
                $date = Read-DateValue -Prompt 'Datum' -AllowEmpty:$false
                $desc = Read-WithDefault -Prompt 'Beschreibung (optional)'
                $id = Get-NextId -Items $schedule.milestones -Prefix 'M'
                $schedule.milestones.Add([ordered]@{ id = $id; name = $name; date = $date; description = $desc })
                Write-Host "Meilenstein $id hinzugefuegt." -ForegroundColor Green
            }
            '2' {
                $m = Select-FromList -Items $schedule.milestones -Prompt 'Meilenstein bearbeiten' -Formatter { param($x) "$($x.id): $($x.name) ($($x.date))" }
                if ($m) {
                    $m.name = Read-WithDefault -Prompt 'Name' -Default $m.name
                    $m.date = Read-DateValue -Prompt 'Datum' -Default $m.date -AllowEmpty:$false
                    $m.description = Read-WithDefault -Prompt 'Beschreibung' -Default $m.description
                }
            }
            '3' {
                $m = Select-FromList -Items $schedule.milestones -Prompt 'Meilenstein entfernen' -Formatter { param($x) "$($x.id): $($x.name) ($($x.date))" }
                if ($m -and (Read-YesNo "Meilenstein $($m.id) - '$($m.name)' wirklich entfernen?" $false)) {
                    [void]$schedule.milestones.Remove($m)
                    Write-Host 'Entfernt.' -ForegroundColor Green
                }
            }
            '0' { return }
            default { Write-Warning 'Ungueltige Auswahl.' }
        }
    }
}

function Invoke-LanesMenu {
    while ($true) {
        Write-Host ''
        Write-Host '--- Arbeitsstroeme (Lanes) ---' -ForegroundColor Cyan
        if ($schedule.lanes.Count -eq 0) { Write-Host '  (keine erfasst)' -ForegroundColor DarkGray }
        else {
            foreach ($l in $schedule.lanes) { Write-Host ("  {0}: {1} (Owner: {2}, {3} Arbeitspakete)" -f $l.id, $l.name, $l.owner, $l.workPackages.Count) }
        }
        Write-Host '1) Hinzufuegen  2) Bearbeiten  3) Entfernen  0) Zurueck'
        switch ((Read-Host 'Auswahl').Trim()) {
            '1' {
                $name = Read-WithDefault -Prompt 'Name des Arbeitsstroms'
                if (-not $name) { continue }
                $owner = Read-WithDefault -Prompt 'Owner'
                $id = Get-NextId -Items $schedule.lanes -Prefix 'L'
                $schedule.lanes.Add([ordered]@{ id = $id; name = $name; owner = $owner; workPackages = (New-Object System.Collections.Generic.List[object]) })
                Write-Host "Arbeitsstrom $id hinzugefuegt." -ForegroundColor Green
            }
            '2' {
                $l = Select-FromList -Items $schedule.lanes -Prompt 'Arbeitsstrom bearbeiten' -Formatter { param($x) "$($x.id): $($x.name) (Owner: $($x.owner))" }
                if ($l) {
                    $l.name = Read-WithDefault -Prompt 'Name' -Default $l.name
                    $l.owner = Read-WithDefault -Prompt 'Owner' -Default $l.owner
                }
            }
            '3' {
                $l = Select-FromList -Items $schedule.lanes -Prompt 'Arbeitsstrom entfernen' -Formatter { param($x) "$($x.id): $($x.name) (Owner: $($x.owner))" }
                if ($l) {
                    $warnText = if ($l.workPackages.Count -gt 0) { " (inkl. $($l.workPackages.Count) Arbeitspakete!)" } else { '' }
                    if (Read-YesNo "Arbeitsstrom $($l.id) - '$($l.name)'$warnText wirklich entfernen?" $false) {
                        [void]$schedule.lanes.Remove($l)
                        Write-Host 'Entfernt.' -ForegroundColor Green
                    }
                }
            }
            '0' { return }
            default { Write-Warning 'Ungueltige Auswahl.' }
        }
    }
}

function Get-AllWorkPackages {
    $all = New-Object System.Collections.Generic.List[object]
    foreach ($l in $schedule.lanes) { foreach ($w in $l.workPackages) { $all.Add($w) } }
    return $all
}

function Invoke-WorkPackagesMenu {
    if ($schedule.lanes.Count -eq 0) {
        Write-Warning 'Zuerst mindestens einen Arbeitsstrom anlegen (Menuepunkt "Arbeitsstroeme verwalten").'
        return
    }
    $lane = Select-FromList -Items $schedule.lanes -Prompt 'Arbeitsstrom waehlen' -Formatter { param($x) "$($x.id): $($x.name) (Owner: $($x.owner))" }
    if (-not $lane) { return }
    while ($true) {
        Write-Host ''
        Write-Host "--- Arbeitspakete: $($lane.id) - $($lane.name) ---" -ForegroundColor Cyan
        if ($lane.workPackages.Count -eq 0) { Write-Host '  (keine erfasst)' -ForegroundColor DarkGray }
        else {
            foreach ($w in $lane.workPackages) { Write-Host ("  {0}: {1} [{2} -> {3}] Prio={4} Aufwand={5}PT Status={6}" -f $w.id, $w.name, $w.startDate, $w.endDate, $w.priority, $w.effortPT, $w.status) }
        }
        Write-Host '1) Hinzufuegen  2) Bearbeiten  3) Entfernen  0) Zurueck'
        switch ((Read-Host 'Auswahl').Trim()) {
            '1' {
                $name = Read-WithDefault -Prompt 'Name des Arbeitspakets'
                if (-not $name) { continue }
                $start = Read-DateValue -Prompt 'Startdatum' -AllowEmpty:$false
                $end = Read-DateValue -Prompt 'Enddatum' -AllowEmpty:$false
                $priority = Read-EnumChoice -Prompt 'Prioritaet' -Options $PriorityOptions -Default 'Should'
                $effort = Read-NumberValue -Prompt 'Aufwand in Personentagen (PT)'
                $status = Read-EnumChoice -Prompt 'Status' -Options $StatusOptions -Default 'To Do'
                $id = Get-NextId -Items (Get-AllWorkPackages) -Prefix 'WP'
                $lane.workPackages.Add([ordered]@{ id = $id; name = $name; startDate = $start; endDate = $end; priority = $priority; effortPT = $effort; status = $status })
                Write-Host "Arbeitspaket $id hinzugefuegt." -ForegroundColor Green
            }
            '2' {
                $w = Select-FromList -Items $lane.workPackages -Prompt 'Arbeitspaket bearbeiten' -Formatter { param($x) "$($x.id): $($x.name)" }
                if ($w) {
                    $w.name = Read-WithDefault -Prompt 'Name' -Default $w.name
                    $w.startDate = Read-DateValue -Prompt 'Startdatum' -Default $w.startDate -AllowEmpty:$false
                    $w.endDate = Read-DateValue -Prompt 'Enddatum' -Default $w.endDate -AllowEmpty:$false
                    $w.priority = Read-EnumChoice -Prompt 'Prioritaet' -Options $PriorityOptions -Default $w.priority
                    $w.effortPT = Read-NumberValue -Prompt 'Aufwand in Personentagen (PT)' -Default $w.effortPT
                    $w.status = Read-EnumChoice -Prompt 'Status' -Options $StatusOptions -Default $w.status
                }
            }
            '3' {
                $w = Select-FromList -Items $lane.workPackages -Prompt 'Arbeitspaket entfernen' -Formatter { param($x) "$($x.id): $($x.name)" }
                if ($w -and (Read-YesNo "Arbeitspaket $($w.id) - '$($w.name)' wirklich entfernen?" $false)) {
                    [void]$lane.workPackages.Remove($w)
                    Write-Host 'Entfernt.' -ForegroundColor Green
                }
            }
            '0' { return }
            default { Write-Warning 'Ungueltige Auswahl.' }
        }
    }
}

function Show-Summary {
    Write-Host ''
    Write-Host '=== Zusammenfassung ===' -ForegroundColor Cyan
    Write-Host "Projekt: $($schedule.project.name)  Start: $($schedule.project.startDate)  Ende: $($schedule.project.endDate)"
    Write-Host "Meilensteine: $($schedule.milestones.Count)"
    Write-Host "Arbeitsstroeme: $($schedule.lanes.Count)  Arbeitspakete gesamt: $((Get-AllWorkPackages).Count)"
    foreach ($l in $schedule.lanes) { Write-Host ("  - {0}: {1} (Owner: {2}, {3} Arbeitspakete)" -f $l.id, $l.name, $l.owner, $l.workPackages.Count) }
}

# ===========================================================================
#  Main menu
# ===========================================================================

Write-Host ''
Write-Host "=== Master-Schedule Wizard - $mandateName ===" -ForegroundColor Cyan

$dirty = $false
while ($true) {
    Write-Host ''
    Write-Host '1) Projekt-Rahmendaten (Start/Ende)'
    Write-Host '2) Meilensteine verwalten'
    Write-Host '3) Arbeitsstroeme verwalten'
    Write-Host '4) Arbeitspakete verwalten'
    Write-Host '5) Zusammenfassung anzeigen'
    Write-Host '6) Speichern & Beenden'
    Write-Host '0) Abbrechen ohne Speichern'
    switch ((Read-Host 'Auswahl').Trim()) {
        '1' { Edit-ProjectDates; $dirty = $true }
        '2' { Invoke-MilestonesMenu; $dirty = $true }
        '3' { Invoke-LanesMenu; $dirty = $true }
        '4' { Invoke-WorkPackagesMenu; $dirty = $true }
        '5' { Show-Summary }
        '6' {
            Save-Schedule -Schedule $schedule -MandateName $mandateName -LogSummary 'Master-Schedule ueber schedule-wizard.ps1 gepflegt' -LogDetails "Projekt-Rahmendaten, $($schedule.milestones.Count) Meilenstein(e), $($schedule.lanes.Count) Arbeitsstrom/Arbeitsstroeme, $((Get-AllWorkPackages).Count) Arbeitspaket(e)."
            return
        }
        '0' {
            if (-not $dirty -or (Read-YesNo 'Ungespeicherte Aenderungen wirklich verwerfen?' $false)) {
                Write-Host 'Abgebrochen ohne Speichern.' -ForegroundColor Yellow
                return
            }
        }
        default { Write-Warning 'Ungueltige Auswahl.' }
    }
}
