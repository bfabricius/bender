<#
.SYNOPSIS
    Builds a cross-workstream findings dashboard from mem-index, triage and OpenSpec design docs.

.DESCRIPTION
    Parses the canonical finding registries in mem-index (Offene Fragen F-, Offene Konflikte K-,
    Gap-Analyse G-, High-Level-Requirements UC-/FA-/NFA-/OP-), then scans the per-workstream
    triage-*.md and openspec-sdd design.md files to determine which workstream(s) reference each
    ID (cross-workstream findings = referenced by more than one workstream).

    Manually maintained lifecycle status (offen/in Arbeit/erledigt/vertagt/geschlossen) for F-/K-/G-
    findings lives in a separate overlay file (findings-status-overlay.md) that this script only
    ever APPENDS to for newly discovered IDs - existing rows are never modified or removed, so
    re-running the script never overwrites manual edits.

.PARAMETER RepoRoot
    Repository root. Defaults to the folder containing this script.

.EXAMPLE
    ./build-findings-dashboard.ps1
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'

# --- Unicode symbols built from code points -------------------------------------------------
# Built via ConvertFromUtf32 instead of literal characters in source: avoids the known
# PowerShell 5.1 risk of the script's own source being mis-read under a non-UTF8 codepage,
# which would silently corrupt literal multi-byte characters used in comparisons/regex.
$Sym = @{
    Red    = [System.Char]::ConvertFromUtf32(0x1F534) # critical / open
    Orange = [System.Char]::ConvertFromUtf32(0x1F7E0) # important / in progress
    Yellow = [System.Char]::ConvertFromUtf32(0x1F7E1) # nice-to-have / deferred
    Green  = [System.Char]::ConvertFromUtf32(0x1F7E2) # resolved (Konflikte legend)
    Check  = [System.Char]::ConvertFromUtf32(0x2705)  # resolved (Offene-Fragen legend)
    Purple = [System.Char]::ConvertFromUtf32(0x1F7E3) # overlay-only: deprioritized
    Black  = [System.Char]::ConvertFromUtf32(0x26AB)  # overlay-only: closed
    New    = [System.Char]::ConvertFromUtf32(0x1F195) # newly discovered
    Warn   = [System.Char]::ConvertFromUtf32(0x26A0)  # stale / needs attention
    Dash   = [System.Char]::ConvertFromUtf32(0x2014)  # em dash used in "### ID -- Title" headings
}

# --- Paths ------------------------------------------------------------------------------------
$MemIndexPath        = Join-Path $RepoRoot 'mem-index'
$TriagePath          = Join-Path $RepoRoot 'analyse-sprint/_openspec-fortschritt'
$OpenSpecChangesPath = Join-Path $RepoRoot 'openspec-sdd/openspec/changes'
$DashboardPath       = Join-Path $RepoRoot 'openspec-sdd/findings-dashboard.md'
$HtmlDashboardPath   = Join-Path $RepoRoot 'openspec-sdd/findings-dashboard.html'
$OverlayPath         = Join-Path $RepoRoot 'openspec-sdd/findings-status-overlay.md'

$FOffenePath   = Join-Path $MemIndexPath '08_Offene-Fragen.md'
$KKonfliktePath = Join-Path $MemIndexPath '13_Offene-Konflikte.md'
$GGapPath      = Join-Path $MemIndexPath '05_Gap-Analyse.md'
$ReqPath       = Join-Path $MemIndexPath '03b_HighLevel-Requirements.md'

# Workstreams are discovered dynamically from the OpenSpec changes folder (one workstream per
# change directory, excluding archive/ and helper folders prefixed with an underscore) instead of
# a hardcoded project-specific slug list, so this script works for any mandate's workstream set.
function Get-Workstreams {
    param([string]$ChangesPath)
    $result = [ordered]@{}
    if (-not (Test-Path -LiteralPath $ChangesPath)) { return $result }
    $dirs = Get-ChildItem -LiteralPath $ChangesPath -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne 'archive' -and $_.Name -notlike '_*' } |
        Sort-Object Name
    $i = 0
    foreach ($d in $dirs) {
        $i++
        $niceName = (Get-Culture).TextInfo.ToTitleCase(($d.Name -replace '[-_]', ' '))
        $result[$d.Name] = @{ Code = "WS$i"; Name = $niceName }
    }
    return $result
}

$Workstreams = Get-Workstreams -ChangesPath $OpenSpecChangesPath

function Get-StatusSymbol {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    foreach ($key in 'Red', 'Orange', 'Yellow', 'Green', 'Check') {
        if ($Text.Contains($Sym[$key])) { return $key }
    }
    return $null
}

function ConvertTo-OverlayDefault {
    param([string]$SourceSymbolKey)
    switch ($SourceSymbolKey) {
        'Red'    { return "$($Sym.Red) offen" }
        'Orange' { return "$($Sym.Orange) in Arbeit" }
        'Yellow' { return "$($Sym.Yellow) nachgelagert" }
        'Green'  { return "$($Sym.Check) erledigt" }
        'Check'  { return "$($Sym.Check) erledigt" }
        default  { return "$($Sym.Red) offen" }
    }
}

function Split-TableRow {
    param([string]$Line)
    $trimmed = $Line.Trim()
    if (-not $trimmed.StartsWith('|')) { return $null }
    $cells = $trimmed.Trim('|') -split '\|'
    return @($cells | ForEach-Object { $_.Trim() })
}

# --- Parsers: mem-index source registries -----------------------------------------------------

function Get-FOverview {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $lines = Get-Content -LiteralPath $Path -Encoding UTF8
    $result = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -notmatch '^\|\s*F-\d+\s*\|') { continue }
        $cells = Split-TableRow $line
        if ($cells.Count -lt 5) { continue }
        $result += [PSCustomObject]@{
            ID          = $cells[0]
            Type        = 'F'
            Title       = $cells[1]
            Description = $cells[2]
            SourceRaw   = $cells[3]
            SourceSym   = Get-StatusSymbol $cells[3]
            Prio        = $cells[4]
            Line        = $i + 1
        }
    }
    return $result
}

function Get-GOverview {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $lines = Get-Content -LiteralPath $Path -Encoding UTF8
    $result = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -notmatch '^\|\s*G-\d+\s*\|') { continue }
        $cells = Split-TableRow $line
        if ($cells.Count -lt 4) { continue }
        $result += [PSCustomObject]@{
            ID          = $cells[0]
            Type        = 'G'
            Title       = $cells[1]
            Description = $cells[3]
            SourceRaw   = $cells[2]
            SourceSym   = Get-StatusSymbol $cells[2]
            Prio        = $null
            Line        = $i + 1
        }
    }
    return $result
}

function Get-LineNumberFromIndex {
    param([string]$Text, [int]$Index)
    return (($Text.Substring(0, $Index)) -split "`n").Count
}

function Get-KEntries {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $headerPattern = "(?m)^### (K-\d+) $([regex]::Escape($Sym.Dash)) (.+)$"
    # Note: must NOT be named $matches - PowerShell variable names are case-insensitive, so
    # $matches IS the automatic $Matches variable and would get clobbered by any -match below.
    $kMatches = [regex]::Matches($text, $headerPattern)
    $result = @()
    for ($i = 0; $i -lt $kMatches.Count; $i++) {
        $m = $kMatches[$i]
        $blockStart = $m.Index + $m.Length
        $blockEnd = if ($i -lt $kMatches.Count - 1) { $kMatches[$i + 1].Index } else { $text.Length }
        $block = $text.Substring($blockStart, $blockEnd - $blockStart)
        $statusLine = ($block -split "`n" | Where-Object { $_ -match '^\s*-\s*\*\*Status:\*\*' } | Select-Object -First 1)
        $statusText = if ($statusLine) { ($statusLine -replace '^\s*-\s*\*\*Status:\*\*\s*', '').Trim() } else { '' }
        # Prefer a richer body line over the bare title for the hover/tooltip description.
        $bodyDescription = $null
        foreach ($label in 'Kern des Widerspruchs', 'Auswirkung') {
            $labelMatch = [regex]::Match($block, '(?m)^\s*-\s*\*\*' + [regex]::Escape($label) + ':\*\*\s*(.+)$')
            if ($labelMatch.Success) { $bodyDescription = $labelMatch.Groups[1].Value.Trim(); break }
        }
        $result += [PSCustomObject]@{
            ID          = $m.Groups[1].Value
            Type        = 'K'
            Title       = $m.Groups[2].Value.Trim()
            Description = if ($bodyDescription) { $bodyDescription } else { $m.Groups[2].Value.Trim() }
            SourceRaw   = $statusText
            SourceSym   = Get-StatusSymbol $statusText
            Prio        = $null
            Line        = Get-LineNumberFromIndex -Text $text -Index $m.Index
        }
    }
    return $result
}

function Get-RequirementEntries {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $lines = Get-Content -LiteralPath $Path -Encoding UTF8
    $result = @()
    $ucPattern = "^### (UC-\d+) $([regex]::Escape($Sym.Dash)) (.+?) ``(.+?)``\s*$"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match $ucPattern) {
            $result += [PSCustomObject]@{
                ID          = $Matches[1]
                Type        = 'UC'
                Title       = $Matches[2].Trim()
                Description = $Matches[2].Trim()
                Tag         = $Matches[3].Trim()
                Line        = $i + 1
            }
            continue
        }
        if ($line -match '^\|\s*((?:FA|NFA|OP)-\d+)\s*\|') {
            $cells = Split-TableRow $line
            if ($cells.Count -lt 5) { continue }
            $prefix = ($cells[0] -split '-')[0]
            $result += [PSCustomObject]@{
                ID          = $cells[0]
                Type        = $prefix
                Title       = $cells[1]
                Description = $cells[2]
                Tag         = $cells[4]
                Line        = $i + 1
            }
        }
    }

    # Enrich UC- entries with the "Ergebnis" body line (bare title is not informative enough for
    # the hover/tooltip description) - separate raw-text block scan, same header shape as above.
    $rawText = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $ucHeaderRegex = [regex]::new("(?m)^### (UC-\d+) $([regex]::Escape($Sym.Dash)) .+$")
    $ucBlockMatches = $ucHeaderRegex.Matches($rawText)
    for ($i = 0; $i -lt $ucBlockMatches.Count; $i++) {
        $bm = $ucBlockMatches[$i]
        $blockStart = $bm.Index + $bm.Length
        $blockEnd = if ($i -lt $ucBlockMatches.Count - 1) { $ucBlockMatches[$i + 1].Index } else { $rawText.Length }
        $block = $rawText.Substring($blockStart, $blockEnd - $blockStart)
        $resultMatch = [regex]::Match($block, '(?m)^\s*-\s*\*\*Ergebnis:\*\*\s*(.+)$')
        if ($resultMatch.Success) {
            $id = $bm.Groups[1].Value
            foreach ($r in $result) { if ($r.ID -eq $id) { $r.Description = $resultMatch.Groups[1].Value.Trim() } }
        }
    }

    return $result
}

# --- Parser: generic ID occurrence scan (drives workstream membership) ------------------------

function Get-IdReferences {
    # Returns the FIRST line number per distinct ID found in the file (used for jump-to-source links).
    # Deliberately named $lineMatches / $idHits below, never $matches (see note in Get-KEntries).
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $lines = Get-Content -LiteralPath $Path -Encoding UTF8
    $idHits = [ordered]@{}
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $lineMatches = [regex]::Matches($lines[$i], '\b(?:F|K|G|UC|FA|NFA|OP)-\d{1,3}\b')
        foreach ($lm in $lineMatches) {
            if (-not $idHits.Contains($lm.Value)) { $idHits[$lm.Value] = $i + 1 }
        }
    }
    $result = @()
    foreach ($id in $idHits.Keys) { $result += [PSCustomObject]@{ Id = $id; Line = $idHits[$id] } }
    return $result
}

function Get-WorkstreamKeyFromTriageFile {
    # The workstream key equals the OpenSpec change folder name; the triage file's slug (after the
    # 'triage-' prefix) is expected to match that folder name exactly, with no fixed product prefix.
    param([string]$FileName)
    return ($FileName -replace '^triage-', '' -replace '\.md$', '')
}

function ConvertTo-VscodeUri {
    # Builds a vscode://file/<path>:<line> URI so dashboard links jump straight to the source line.
    param([string]$AbsolutePath, [int]$Line = 1)
    $normalized = $AbsolutePath -replace '\\', '/'
    return 'vscode://file/' + $normalized + ':' + $Line
}

# --- Overlay: read/merge without ever overwriting existing rows -------------------------------

function Read-Overlay {
    param([string]$Path)
    $rows = [ordered]@{}
    if (-not (Test-Path -LiteralPath $Path)) { return $rows }
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
    param([string]$Path, [System.Collections.Specialized.OrderedDictionary]$Rows)
    $preamble = @(
        '# Findings Status Overlay'
        ''
        '> Manuell gepflegt. `build-findings-dashboard.ps1` ergaenzt hier NUR neu erkannte IDs (angehaengt am Ende);'
        '> bestehende Zeilen werden nie automatisch veraendert oder geloescht. Status/Kommentar frei anpassbar.'
        '>'
        "> Status-Werte: $($Sym.Red) offen . $($Sym.Orange) in Arbeit . $($Sym.Yellow) nachgelagert . $($Sym.Check) erledigt . $($Sym.Purple) vertagt . $($Sym.Black) geschlossen"
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

# --- Main ---------------------------------------------------------------------------------------

Write-Host 'Parsing mem-index finding registries ...' -ForegroundColor Cyan
$fEntries = Get-FOverview -Path $FOffenePath
$kEntries = Get-KEntries -Path $KKonfliktePath
$gEntries = Get-GOverview -Path $GGapPath
$reqEntries = Get-RequirementEntries -Path $ReqPath

Write-Host ("  F-: {0}  K-: {1}  G-: {2}  UC-/FA-/NFA-/OP-: {3}" -f $fEntries.Count, $kEntries.Count, $gEntries.Count, $reqEntries.Count)

$allFindings = [ordered]@{}
foreach ($e in @($fEntries) + @($kEntries) + @($gEntries)) { $allFindings[$e.ID] = $e }
$allRequirements = [ordered]@{}
foreach ($e in $reqEntries) { $allRequirements[$e.ID] = $e }

Write-Host 'Scanning triage files and design.md files for workstream references ...' -ForegroundColor Cyan
$idWorkstreams = [ordered]@{}
function Add-IdWorkstream {
    param([string]$Id, [string]$WsKey, [string]$Kind, [int]$Line)
    if (-not $idWorkstreams.Contains($Id)) { $idWorkstreams[$Id] = [ordered]@{} }
    if (-not $idWorkstreams[$Id].Contains($WsKey)) {
        $idWorkstreams[$Id][$WsKey] = [PSCustomObject]@{ TriageLine = $null; DesignLine = $null }
    }
    if ($Kind -eq 'Triage') { $idWorkstreams[$Id][$WsKey].TriageLine = $Line }
    else { $idWorkstreams[$Id][$WsKey].DesignLine = $Line }
}

if (Test-Path -LiteralPath $TriagePath) {
    Get-ChildItem -LiteralPath $TriagePath -Filter 'triage-*.md' | ForEach-Object {
        $wsKey = Get-WorkstreamKeyFromTriageFile -FileName $_.Name
        if (-not $Workstreams.Contains($wsKey)) { return }
        foreach ($ref in Get-IdReferences -Path $_.FullName) { Add-IdWorkstream -Id $ref.Id -WsKey $wsKey -Kind 'Triage' -Line $ref.Line }
    }
}

foreach ($wsKey in $Workstreams.Keys) {
    $designPath = Join-Path $OpenSpecChangesPath ($wsKey + '/design.md')
    foreach ($ref in Get-IdReferences -Path $designPath) { Add-IdWorkstream -Id $ref.Id -WsKey $wsKey -Kind 'Design' -Line $ref.Line }
}

Write-Host 'Merging with manually maintained status overlay ...' -ForegroundColor Cyan
$overlay = Read-Overlay -Path $OverlayPath
$today = Get-Date -Format 'yyyy-MM-dd'
$newCount = 0
foreach ($id in $allFindings.Keys) {
    if ($overlay.Contains($id)) { continue }
    $entry = $allFindings[$id]
    $overlay[$id] = [PSCustomObject]@{
        ID        = $id
        Status    = ConvertTo-OverlayDefault -SourceSymbolKey $entry.SourceSym
        Kommentar = "$($Sym.New) neu erkannt"
        Datum     = $today
    }
    $newCount++
}
Write-Overlay -Path $OverlayPath -Rows $overlay
Write-Host ("  Overlay: {0} bestehende + {1} neue Zeile(n)" -f ($overlay.Count - $newCount), $newCount)

$staleIds = @($overlay.Keys | Where-Object { -not $allFindings.Contains($_) })

# --- Build dashboard content ---------------------------------------------------------------------

function Get-CrossWorkstreamCodes {
    param([string]$Id)
    if (-not $idWorkstreams.Contains($Id)) { return @() }
    return @($idWorkstreams[$Id].Keys | ForEach-Object { $Workstreams[$_].Code } | Sort-Object)
}

function Get-SourceLinks {
    # One link per workstream that references this ID: prefers the triage-file line (richer context),
    # falls back to the design.md line if the ID was only found there.
    param([string]$Id)
    if (-not $idWorkstreams.Contains($Id)) { return @() }
    $list = @()
    foreach ($wsKey in $idWorkstreams[$Id].Keys) {
        $info = $idWorkstreams[$Id][$wsKey]
        $ws = $Workstreams[$wsKey]
        if ($info.TriageLine) {
            $triageFile = Join-Path $TriagePath ('triage-' + $wsKey + '.md')
            $list += [PSCustomObject]@{ ws = $ws.Code; kind = 'triage'; link = (ConvertTo-VscodeUri -AbsolutePath $triageFile -Line $info.TriageLine) }
        } elseif ($info.DesignLine) {
            $designFile = Join-Path $OpenSpecChangesPath ($wsKey + '/design.md')
            $list += [PSCustomObject]@{ ws = $ws.Code; kind = 'design'; link = (ConvertTo-VscodeUri -AbsolutePath $designFile -Line $info.DesignLine) }
        }
    }
    return $list
}

function Get-DefinitionLink {
    param([string]$Type, [int]$Line)
    $path = switch ($Type) {
        'F' { $FOffenePath }
        'K' { $KKonfliktePath }
        'G' { $GGapPath }
        default { $ReqPath }
    }
    return ConvertTo-VscodeUri -AbsolutePath $path -Line $Line
}

$rows = foreach ($id in $allFindings.Keys) {
    $entry = $allFindings[$id]
    $wsCodes = Get-CrossWorkstreamCodes -Id $id
    [PSCustomObject]@{
        ID          = $id
        Type        = $entry.Type
        Title       = $entry.Title
        Description = $entry.Description
        Workstreams = $wsCodes
        CrossWs     = $wsCodes.Count -gt 1
        Status      = $overlay[$id].Status
        Kommentar   = $overlay[$id].Kommentar
        DefLink     = (Get-DefinitionLink -Type $entry.Type -Line $entry.Line)
        Sources     = @(Get-SourceLinks -Id $id)
    }
}

$reqRows = foreach ($id in $allRequirements.Keys) {
    $entry = $allRequirements[$id]
    $wsCodes = Get-CrossWorkstreamCodes -Id $id
    [PSCustomObject]@{
        ID          = $id
        Type        = $entry.Type
        Title       = $entry.Title
        Description = $entry.Description
        Workstreams = $wsCodes
        CrossWs     = $wsCodes.Count -gt 1
        Tag         = $entry.Tag
        DefLink     = (Get-DefinitionLink -Type $entry.Type -Line $entry.Line)
        Sources     = @(Get-SourceLinks -Id $id)
    }
}

# Summary counts
$summaryByType = $rows | Group-Object Type | Sort-Object Name
$summaryByStatus = $rows | Group-Object { ($_.Status -replace '\s.*$', '') } | Sort-Object Count -Descending
$crossCount = @($rows | Where-Object { $_.CrossWs }).Count
$criticalOpenCount = @($rows | Where-Object { $_.Status.StartsWith($Sym.Red) }).Count

$topList = @($rows | Where-Object { $_.CrossWs -or $_.Status.StartsWith($Sym.Red) } | Sort-Object @{Expression = { -not $_.Status.StartsWith($Sym.Red) }}, @{Expression = { -not $_.CrossWs }}, ID)

# Mermaid: workstream nodes + finding nodes for critical/cross-ws findings only
$mermaidLines = @('```mermaid', 'flowchart LR', '    classDef cross fill:#ffdcdc,stroke:#c0392b,stroke-width:3px;', '    classDef normal fill:#eef,stroke:#999;')
foreach ($wsKey in $Workstreams.Keys) {
    $ws = $Workstreams[$wsKey]
    $mermaidLines += "    $($ws.Code)[`"$($ws.Name)`"]"
}
$mermaidFindings = @($rows | Where-Object { $_.CrossWs -or $_.Status.StartsWith($Sym.Red) })
foreach ($f in $mermaidFindings) {
    $nodeId = $f.ID -replace '-', ''
    $label = $f.Title -replace '"', "'"
    if ($label.Length -gt 50) { $label = $label.Substring(0, 47) + '...' }
    $class = if ($f.CrossWs) { 'cross' } else { 'normal' }
    $mermaidLines += "    $nodeId[`"$($f.ID): $label`"]:::$class"
    foreach ($wsCode in $f.Workstreams) { $mermaidLines += "    $nodeId --- $wsCode" }
}
$mermaidLines += '```'

# --- Render markdown ------------------------------------------------------------------------------

$md = New-Object System.Collections.Generic.List[string]
$md.Add('# Findings Dashboard - Cross-Workstream Uebersicht')
$md.Add('')
$md.Add("> Automatisch generiert von ``build-findings-dashboard.ps1`` am $today. Nicht von Hand editieren -")
$md.Add('> Status/Kommentar werden in `findings-status-overlay.md` gepflegt (siehe dort) und beim naechsten Lauf uebernommen.')
$md.Add('> Regenerieren: `./build-findings-dashboard.ps1` im Repo-Root ausfuehren.')
$md.Add('')
$md.Add('**Interaktive Ansicht:** [`findings-dashboard.html`](./findings-dashboard.html) im Browser oeffnen fuer')
$md.Add('sortierbare/filterbare Tabellen, einen ein-/ausklappbaren Cross-Workstream-Graph und klickbare')
$md.Add('Status-Aktionen (siehe Anleitung dort). Diese Markdown-Datei bleibt die git-diffbare Referenzansicht.')
$md.Add('')
$md.Add('Dieses Dashboard ist ein Ausgangsdokument fuer Gespraeche mit Team/Stakeholdern. Fuer Details je Finding')
$md.Add('in die Quellen wechseln: mem-index (`08_Offene-Fragen.md`, `13_Offene-Konflikte.md`, `05_Gap-Analyse.md`),')
$md.Add('die Triage-Dateien (`analyse-sprint/_openspec-fortschritt/`) und die jeweiligen `design.md` je Change.')
$md.Add('')
$md.Add('## Workstreams')
$md.Add('')
$md.Add('| Code | Workstream | OpenSpec-Change |')
$md.Add('|---|---|---|')
foreach ($wsKey in $Workstreams.Keys) {
    $ws = $Workstreams[$wsKey]
    $md.Add("| $($ws.Code) | $($ws.Name) | ``$wsKey`` |")
}
$md.Add('')
$md.Add('## Kennzahlen')
$md.Add('')
$md.Add("- Findings total (F-/K-/G-): $($rows.Count)")
$md.Add("- davon Cross-Workstream (in mehr als einem Workstream referenziert): $crossCount")
$md.Add("- davon aktuell $($Sym.Red) offen/kritisch: $criticalOpenCount")
$md.Add("- Anforderungs-Anker zur Traceability (UC-/FA-/NFA-/OP-): $($reqRows.Count)")
if ($staleIds.Count -gt 0) {
    $md.Add("- $($Sym.Warn) Overlay-Eintraege ohne aktuell auffindbare Quelle: $($staleIds -join ', ')")
}
$md.Add('')
$md.Add('### Nach Typ')
$md.Add('')
$md.Add('| Typ | Anzahl |')
$md.Add('|---|---|')
foreach ($g in $summaryByType) { $md.Add("| $($g.Name) | $($g.Count) |") }
$md.Add('')
$md.Add('### Nach Overlay-Status')
$md.Add('')
$md.Add('| Status | Anzahl |')
$md.Add('|---|---|')
foreach ($g in $summaryByStatus) { $md.Add("| $($g.Name) | $($g.Count) |") }
$md.Add('')
$md.Add('## Top: kritisch und/oder Cross-Workstream')
$md.Add('')
$md.Add('| ID | Typ | Kurzinhalt | Workstreams | Status |')
$md.Add('|---|---|---|---|---|')
foreach ($f in $topList) {
    $wsText = ($f.Workstreams -join ', ')
    $md.Add("| $($f.ID) | $($f.Type) | $($f.Title) | $wsText | $($f.Status) |")
}
$md.Add('')
$md.Add('## Visualisierung (Cross-Workstream + kritische Findings)')
$md.Add('')
$md.Add(($mermaidLines -join "`n"))
$md.Add('')
$md.Add('## Matrix: alle Findings (F-/K-/G-)')
$md.Add('')
$md.Add('| ID | Typ | Kurzinhalt | Workstreams | Cross-WS | Status | Kommentar |')
$md.Add('|---|---|---|---|---|---|---|')
foreach ($f in $rows) {
    $wsText = ($f.Workstreams -join ', ')
    $cross = if ($f.CrossWs) { 'ja' } else { '' }
    $md.Add("| $($f.ID) | $($f.Type) | $($f.Title) | $wsText | $cross | $($f.Status) | $($f.Kommentar) |")
}
$md.Add('')
$md.Add('## Matrix: Anforderungs-Anker (UC-/FA-/NFA-/OP-, nur Traceability)')
$md.Add('')
$md.Add('| ID | Typ | Kurzinhalt | Workstreams | Cross-WS | Korrelations-Tag |')
$md.Add('|---|---|---|---|---|---|')
foreach ($f in $reqRows) {
    $wsText = ($f.Workstreams -join ', ')
    $cross = if ($f.CrossWs) { 'ja' } else { '' }
    $md.Add("| $($f.ID) | $($f.Type) | $($f.Title) | $wsText | $cross | $($f.Tag) |")
}
$md.Add('')

Set-Content -LiteralPath $DashboardPath -Value ($md -join "`n") -Encoding UTF8
Write-Host "Dashboard geschrieben: $DashboardPath" -ForegroundColor Green
Write-Host "Overlay geschrieben: $OverlayPath" -ForegroundColor Green

# --- Build interactive HTML companion (sortable/filterable tables + collapsible graph) -----------

Write-Host 'Building interactive HTML dashboard ...' -ForegroundColor Cyan

$findingsForJson = foreach ($f in $rows) {
    [PSCustomObject]@{
        id          = $f.ID
        type        = $f.Type
        title       = $f.Title
        description = $f.Description
        workstreams = @($f.Workstreams)
        crossWs     = [bool]$f.CrossWs
        status      = $f.Status
        kommentar   = $f.Kommentar
        defLink     = $f.DefLink
        sources     = @($f.Sources)
    }
}
$reqForJson = foreach ($f in $reqRows) {
    [PSCustomObject]@{
        id          = $f.ID
        type        = $f.Type
        title       = $f.Title
        description = $f.Description
        workstreams = @($f.Workstreams)
        crossWs     = [bool]$f.CrossWs
        tag         = $f.Tag
        defLink     = $f.DefLink
        sources     = @($f.Sources)
    }
}
$wsForJson = foreach ($wsKey in $Workstreams.Keys) {
    [PSCustomObject]@{ key = $wsKey; code = $Workstreams[$wsKey].Code; name = $Workstreams[$wsKey].Name }
}

# Ensure the export destination exists so the dashboard's "Als Markdown exportieren" instructions
# point at a folder that already exists (the browser download itself still needs a manual save/move).
$ExportDir = Join-Path $RepoRoot 'project-reports/findings-dash-export'
New-Item -ItemType Directory -Path $ExportDir -Force | Out-Null

$dashboardData = [PSCustomObject]@{
    generated    = $today
    workstreams  = @($wsForJson)
    findings     = @($findingsForJson)
    requirements = @($reqForJson)
}
# Guard against "</script>" breaking out of the embedding <script> tag if any title ever contains it.
$dashboardJson = ($dashboardData | ConvertTo-Json -Depth 8 -Compress).Replace('</', '<\/')

$htmlTemplate = @'
<!doctype html>
<html lang="de">
<head>
<meta charset="utf-8">
<title>Findings Dashboard - Cross-Workstream Uebersicht</title>
<style>
  body { font-family: Segoe UI, Arial, sans-serif; margin: 1.5rem; color: #222; }
  h1 { margin-bottom: 0.2rem; }
  #summary { color: #555; margin-bottom: 1rem; }
  details.instructions { background: #f4f7fb; border: 1px solid #cdd8e6; border-radius: 6px; padding: 0.6rem 1rem; margin-bottom: 1rem; }
  details.instructions summary { cursor: pointer; font-weight: 600; }
  details.instructions ol { margin: 0.5rem 0 0.2rem 1.2rem; }
  .tabs { margin-bottom: 0.6rem; }
  .tab-btn { padding: 0.4rem 0.9rem; border: 1px solid #99a; background: #eef; cursor: pointer; margin-right: 0.3rem; border-radius: 4px 4px 0 0; }
  .tab-btn.active { background: #335; color: #fff; }
  .filterbar { display: flex; flex-wrap: wrap; gap: 1rem; align-items: flex-start; background: #fafafa; border: 1px solid #ddd; border-radius: 6px; padding: 0.6rem 0.9rem; margin-bottom: 0.6rem; }
  .filter-group { display: flex; flex-direction: column; gap: 0.15rem; font-size: 0.85rem; }
  .filter-group .grp-title { font-weight: 600; margin-bottom: 0.15rem; }
  .chk { display: inline-flex; align-items: center; gap: 0.2rem; white-space: nowrap; }
  input[type=text] { padding: 0.3rem 0.5rem; min-width: 220px; }
  table { border-collapse: collapse; width: 100%; margin-bottom: 1.2rem; font-size: 0.88rem; }
  th, td { border: 1px solid #ddd; padding: 0.35rem 0.5rem; text-align: left; vertical-align: top; }
  th { background: #eef2f8; cursor: pointer; position: sticky; top: 0; user-select: none; }
  th:hover { background: #dde6f2; }
  tr:nth-child(even) { background: #fafcff; }
  .action-btn { font-size: 0.75rem; padding: 0.15rem 0.4rem; margin: 0 0.1rem 0.1rem 0; cursor: pointer; border-radius: 3px; border: 1px solid #999; background: #fff; }
  .action-btn:hover { background: #eee; }
  .toolbar-row { display: flex; gap: 0.6rem; margin-bottom: 0.6rem; }
  .toolbar-row button { padding: 0.35rem 0.8rem; cursor: pointer; }
  .help-icon { display: inline-flex; align-items: center; justify-content: center; width: 1.1rem; height: 1.1rem; border-radius: 50%; border: 1px solid #789; color: #789; font-size: 0.7rem; font-weight: bold; cursor: help; user-select: none; background: #fff; }
  #hover-tooltip { position: fixed; max-width: 380px; background: #222; color: #fff; padding: 0.5rem 0.7rem; border-radius: 5px; font-size: 0.82rem; line-height: 1.3; z-index: 1000; display: none; box-shadow: 0 2px 8px rgba(0,0,0,0.3); }
  #graph-container { border: 1px solid #ddd; border-radius: 6px; margin-bottom: 0.8rem; }
  #cy { width: 100%; height: 520px; }
  #graph-fallback { padding: 1rem; color: #900; }
  #graph-toolbar { display:flex; gap:1rem; align-items:center; padding: 0.4rem 0.8rem; border-bottom: 1px solid #eee; font-size: 0.85rem; }
  #pending-panel { position: sticky; bottom: 0; background: #fff8e6; border: 1px solid #e0c467; border-radius: 6px; padding: 0.6rem 0.9rem; margin-top: 1rem; }
  #pending-panel h3 { margin: 0 0 0.4rem 0; font-size: 0.95rem; }
  #pending-table { font-size: 0.8rem; }
  #pending-actions { margin-top: 0.4rem; display: flex; gap: 0.5rem; }
  #pending-actions button { padding: 0.35rem 0.8rem; cursor: pointer; }
  a { color: #245; }
</style>
</head>
<body>
<h1>Findings Dashboard - Cross-Workstream Uebersicht</h1>
<div id="summary"></div>

<details class="instructions" closed>
<summary>Anleitung: Sortieren, Filtern, Graph, Status aendern</summary>
<ol>
  <li><b>Sortieren:</b> auf eine Spaltenueberschrift klicken (nochmal klicken kehrt die Richtung um).</li>
  <li><b>Filtern:</b> Typ/Status/Workstream-Checkboxen, "nur Cross-Workstream" und Freitextsuche kombinieren sich (UND-Verknuepfung). Wirkt auf Tabelle UND Graph.</li>
  <li><b>Graph:</b> Mausrad = zoomen, Ziehen = verschieben. Auf einen Workstream-Knoten klicken blendet dessen Findings ein/aus. "Alle Findings anzeigen" schaltet zwischen nur kritisch/Cross-Workstream und allen um. Auf ein Finding klicken oeffnet dessen Definition. Ueber "Graph ausblenden"/"Graph anzeigen" laesst sich der komplette Graph einklappen, wenn er gerade nicht gebraucht wird.</li>
  <li><b>IDs anklicken:</b> "[Def]" oeffnet die kanonische Definition in mem-index; die Workstream-Kuerzel (WS1 etc.) daneben oeffnen die jeweilige Triage-/Design-Quelle. Beide Links nutzen <code>vscode://</code> und oeffnen VS Code direkt an der Zeile (falls der Link-Handler nicht registriert ist, Pfad manuell oeffnen). Das "?"-Symbol neben der ID zeigt beim Ueberfahren mit der Maus die Definition direkt als Tooltip, ohne die Seite zu verlassen.</li>
  <li><b>Status aendern:</b> Buttons in der Spalte "Aktionen" klicken (nur bei F-/K-/G-Findings). Die Aenderung erscheint sofort unten im Bereich "Ausstehende Aenderungen" (bleibt auch nach Neuladen der Seite erhalten, da lokal im Browser gespeichert) - <b>sie wird noch NICHT in irgendeine Datei geschrieben.</b></li>
  <li><b>Uebernehmen:</b> Wenn fertig, unten auf "Als JSON herunterladen" klicken und die Datei <code>pending-status-changes.json</code> in den Projekt-Ordner (Repo-Root) legen. Danach im Terminal <code>./apply-findings-status-changes.ps1</code> ausfuehren: das schreibt die Aenderungen in <code>findings-status-overlay.md</code> und traegt jeden Punkt zusaetzlich in <code>openspec-sdd/mem-index-sync-todo.md</code> ein.</li>
  <li><b>Report exportieren:</b> "Als Markdown exportieren" (oberhalb der jeweiligen Tabelle) laedt eine <code>.md</code>-Datei mit genau den aktuell gefilterten/sortierten Zeilen herunter (Dateiname mit Datum/Uhrzeit). Bitte die heruntergeladene Datei manuell nach <code>project-reports/findings-dash-export/</code> verschieben/speichern (der Ordner existiert bereits im Repo) - der Browser kann nicht direkt in Projektordner schreiben.</li>
  <li><b>Wichtig - Single Source of Truth:</b> Die eigentliche Wissensbasis bleibt mem-index. Die Eintraege in <code>mem-index-sync-todo.md</code> muessen periodisch manuell (oder per Copilot-Chat-Anfrage, z.B. "gleiche mem-index-sync-todo.md mit dem Memory-Index ab") in <code>08_Offene-Fragen.md</code> / <code>13_Offene-Konflikte.md</code> / <code>05_Gap-Analyse.md</code> + <code>log.md</code> uebertragen werden, damit der Status nicht zwischen Dashboard und mem-index auseinanderlaeuft.</li>
  <li>Nach dem naechsten Lauf von <code>build-findings-dashboard.ps1</code> wird diese Seite neu generiert und zeigt den aktuellen Overlay-Stand.</li>
</ol>
</details>

<div class="tabs">
  <button class="tab-btn active" data-tab="findings">Findings (F-/K-/G-)</button>
  <button class="tab-btn" data-tab="requirements">Anforderungs-Anker (UC-/FA-/NFA-/OP-)</button>
</div>

<section id="tab-findings">
  <div class="filterbar">
    <div class="filter-group"><div class="grp-title">Suche</div><input type="text" id="f-search" placeholder="ID oder Titel..."></div>
    <div class="filter-group"><div class="grp-title">Typ</div><div id="f-type-filter"></div></div>
    <div class="filter-group"><div class="grp-title">Status</div><div id="f-status-filter"></div></div>
    <div class="filter-group"><div class="grp-title">Workstream</div><div id="f-ws-filter"></div></div>
    <div class="filter-group"><div class="grp-title">&nbsp;</div><label class="chk"><input type="checkbox" id="f-crossonly"> nur Cross-Workstream</label></div>
  </div>

  <div class="toolbar-row">
    <button id="graph-toggle-btn">Graph ausblenden</button>
    <button id="f-export-btn">Als Markdown exportieren (aktuelle Filterung)</button>
  </div>

  <div id="graph-container">
    <div id="graph-toolbar">
      <label class="chk"><input type="checkbox" id="graph-show-all"> alle Findings im Graph anzeigen (statt nur kritisch/Cross-WS)</label>
      <span>Workstream-Knoten anklicken zum Ein-/Ausklappen.</span>
    </div>
    <div id="cy"></div>
    <div id="graph-fallback" style="display:none">Graph-Bibliothek (Cytoscape.js) konnte nicht geladen werden (z.B. kein Internetzugriff). Die Tabellen unten funktionieren unabhaengig davon.</div>
  </div>

  <div>Angezeigt: <span id="findings-count"></span></div>
  <table id="findings-table">
    <thead><tr>
      <th data-key="id">ID</th>
      <th>?</th>
      <th data-key="type">Typ</th>
      <th data-key="title">Kurzinhalt</th>
      <th data-key="workstreams">Workstreams</th>
      <th>Quelle</th>
      <th data-key="crossWs">Cross-WS</th>
      <th data-key="status">Status</th>
      <th>Aktionen</th>
    </tr></thead>
    <tbody></tbody>
  </table>
</section>

<section id="tab-requirements" style="display:none">
  <div class="filterbar">
    <div class="filter-group"><div class="grp-title">Suche</div><input type="text" id="r-search" placeholder="ID oder Titel..."></div>
    <div class="filter-group"><div class="grp-title">Typ</div><div id="r-type-filter"></div></div>
    <div class="filter-group"><div class="grp-title">Workstream</div><div id="r-ws-filter"></div></div>
    <div class="filter-group"><div class="grp-title">&nbsp;</div><label class="chk"><input type="checkbox" id="r-crossonly"> nur Cross-Workstream</label></div>
  </div>
  <div class="toolbar-row">
    <button id="r-export-btn">Als Markdown exportieren (aktuelle Filterung)</button>
  </div>
  <div>Angezeigt: <span id="requirements-count"></span></div>
  <table id="requirements-table">
    <thead><tr>
      <th data-key="id">ID</th>
      <th>?</th>
      <th data-key="type">Typ</th>
      <th data-key="title">Kurzinhalt</th>
      <th data-key="workstreams">Workstreams</th>
      <th>Quelle</th>
      <th data-key="crossWs">Cross-WS</th>
      <th data-key="tag">Korrelations-Tag</th>
    </tr></thead>
    <tbody></tbody>
  </table>
</section>

<div id="pending-panel">
  <h3>Ausstehende Status-Aenderungen (<span id="pending-count">0</span>) - noch nicht gespeichert</h3>
  <table id="pending-table"><thead><tr><th>ID</th><th>Bisheriger Status</th><th>Neuer Status</th><th></th></tr></thead><tbody></tbody></table>
  <div id="pending-actions">
    <button id="download-pending-btn">Als JSON herunterladen (pending-status-changes.json)</button>
    <button id="clear-pending-btn">Alle verwerfen</button>
  </div>
</div>

<div id="hover-tooltip"></div>

<script src="https://unpkg.com/cytoscape@3.28.1/dist/cytoscape.min.js" onerror="window.__cyLoadFailed=true"></script>
<script>
const DATA = __DASHBOARD_DATA_JSON__;

const ACTION_BUTTONS = [
  { key: 'check',  text: '__SYM_CHECK__ erledigt' },
  { key: 'orange', text: '__SYM_ORANGE__ in Arbeit' },
  { key: 'purple', text: '__SYM_PURPLE__ vertagt' },
  { key: 'black',  text: '__SYM_BLACK__ geschlossen' }
];
const STATUS_ITEMS = [
  { key: 'red',    label: '__SYM_RED__ offen' },
  { key: 'orange', label: '__SYM_ORANGE__ in Arbeit' },
  { key: 'yellow', label: '__SYM_YELLOW__ nachgelagert' },
  { key: 'check',  label: '__SYM_CHECK__ erledigt' },
  { key: 'purple', label: '__SYM_PURPLE__ vertagt' },
  { key: 'black',  label: '__SYM_BLACK__ geschlossen' }
];

function computeStatusKey(f) {
  const s = f.status || '';
  for (const item of STATUS_ITEMS) {
    const sym = item.label.split(' ')[0];
    if (s.indexOf(sym) === 0) return item.key;
  }
  return 'other';
}

function escapeHtml(s) {
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

const state = {
  findings: {
    search: '', crossOnly: false, sortKey: 'id', sortDir: 1,
    types: new Set(['F', 'K', 'G']),
    statuses: new Set(STATUS_ITEMS.map(s => s.key)),
    workstreams: new Set(DATA.workstreams.map(w => w.code))
  },
  requirements: {
    search: '', crossOnly: false, sortKey: 'id', sortDir: 1,
    types: new Set(['UC', 'FA', 'NFA', 'OP']),
    workstreams: new Set(DATA.workstreams.map(w => w.code))
  }
};

let pending = [];
try { pending = JSON.parse(localStorage.getItem('fd_pending') || '[]'); } catch (e) { pending = []; }

function sortRows(rows, key, dir) {
  return rows.slice().sort(function (a, b) {
    let av = a[key], bv = b[key];
    if (Array.isArray(av)) av = av.join(',');
    if (Array.isArray(bv)) bv = bv.join(',');
    if (typeof av === 'boolean') av = av ? 1 : 0;
    if (typeof bv === 'boolean') bv = bv ? 1 : 0;
    if (av == null) av = '';
    if (bv == null) bv = '';
    if (av < bv) return -1 * dir;
    if (av > bv) return 1 * dir;
    return 0;
  });
}

function matchesWorkstream(item, st) {
  if (st.workstreams.size >= DATA.workstreams.length) return true;
  const ws = item.workstreams || [];
  return ws.some(function (w) { return st.workstreams.has(w); });
}

function filterFindings() {
  const st = state.findings;
  return DATA.findings.filter(function (f) {
    if (!st.types.has(f.type)) return false;
    if (!st.statuses.has(computeStatusKey(f))) return false;
    if (st.crossOnly && !f.crossWs) return false;
    if (!matchesWorkstream(f, st)) return false;
    if (st.search) {
      const q = st.search.toLowerCase();
      if ((f.id + ' ' + f.title).toLowerCase().indexOf(q) === -1) return false;
    }
    return true;
  });
}

function filterRequirements() {
  const st = state.requirements;
  return DATA.requirements.filter(function (f) {
    if (!st.types.has(f.type)) return false;
    if (st.crossOnly && !f.crossWs) return false;
    if (!matchesWorkstream(f, st)) return false;
    if (st.search) {
      const q = st.search.toLowerCase();
      if ((f.id + ' ' + f.title).toLowerCase().indexOf(q) === -1) return false;
    }
    return true;
  });
}

function sourcesHtml(f) {
  return (f.sources || []).map(function (s) {
    return '<a href="' + s.link + '" target="_blank" title="Quelle in ' + s.ws + ' (' + s.kind + ')">' + s.ws + '</a>';
  }).join(' ');
}

let lastFindingsRows = [];
let lastRequirementsRows = [];

function renderFindingsTable() {
  const rows = sortRows(filterFindings(), state.findings.sortKey, state.findings.sortDir);
  lastFindingsRows = rows;
  const tbody = document.querySelector('#findings-table tbody');
  tbody.innerHTML = '';
  rows.forEach(function (f) {
    const pendingEntry = pending.find(function (p) { return p.id === f.id; });
    const displayStatus = pendingEntry ? escapeHtml(pendingEntry.newStatus) + ' <i>(ausstehend)</i>' : escapeHtml(f.status);
    const tr = document.createElement('tr');
    tr.innerHTML =
      '<td>' + f.id + ' <a href="' + f.defLink + '" target="_blank" title="Definition oeffnen">[Def]</a></td>' +
      '<td></td>' +
      '<td>' + f.type + '</td>' +
      '<td>' + escapeHtml(f.title) + '</td>' +
      '<td>' + (f.workstreams || []).join(', ') + '</td>' +
      '<td>' + sourcesHtml(f) + '</td>' +
      '<td>' + (f.crossWs ? 'ja' : '') + '</td>' +
      '<td class="status-cell">' + displayStatus + '</td>' +
      '<td class="actions"></td>';
    attachHelpIcon(tr.children[1], f);
    const actionsTd = tr.querySelector('.actions');
    ACTION_BUTTONS.forEach(function (btn) {
      const b = document.createElement('button');
      b.textContent = btn.text;
      b.className = 'action-btn';
      b.title = 'Status auf "' + btn.text + '" setzen (nur vorgemerkt)';
      b.onclick = function () { queueChange(f.id, f.status, btn.text); };
      actionsTd.appendChild(b);
    });
    tbody.appendChild(tr);
  });
  document.getElementById('findings-count').textContent = rows.length + ' / ' + DATA.findings.length;
}

function renderRequirementsTable() {
  const rows = sortRows(filterRequirements(), state.requirements.sortKey, state.requirements.sortDir);
  lastRequirementsRows = rows;
  const tbody = document.querySelector('#requirements-table tbody');
  tbody.innerHTML = '';
  rows.forEach(function (f) {
    const tr = document.createElement('tr');
    tr.innerHTML =
      '<td>' + f.id + ' <a href="' + f.defLink + '" target="_blank" title="Definition oeffnen">[Def]</a></td>' +
      '<td></td>' +
      '<td>' + f.type + '</td>' +
      '<td>' + escapeHtml(f.title) + '</td>' +
      '<td>' + (f.workstreams || []).join(', ') + '</td>' +
      '<td>' + sourcesHtml(f) + '</td>' +
      '<td>' + (f.crossWs ? 'ja' : '') + '</td>' +
      '<td>' + escapeHtml(f.tag) + '</td>';
    attachHelpIcon(tr.children[1], f);
    tbody.appendChild(tr);
  });
  document.getElementById('requirements-count').textContent = rows.length + ' / ' + DATA.requirements.length;
}

function renderSummary() {
  const total = DATA.findings.length;
  const cross = DATA.findings.filter(function (f) { return f.crossWs; }).length;
  const critical = DATA.findings.filter(function (f) { return computeStatusKey(f) === 'red'; }).length;
  document.getElementById('summary').textContent =
    'Findings: ' + total + ' (Cross-Workstream: ' + cross + ', kritisch/offen: ' + critical + ') - generiert am ' + DATA.generated;
}

function buildCheckboxGroup(container, items, selectedSet, keyFn, labelFn, onChange) {
  container.innerHTML = '';
  items.forEach(function (item) {
    const key = keyFn(item);
    const wrap = document.createElement('label');
    wrap.className = 'chk';
    const cb = document.createElement('input');
    cb.type = 'checkbox';
    cb.checked = selectedSet.has(key);
    cb.addEventListener('change', function () {
      if (cb.checked) selectedSet.add(key); else selectedSet.delete(key);
      onChange();
    });
    wrap.appendChild(cb);
    wrap.appendChild(document.createTextNode(' ' + labelFn(item)));
    container.appendChild(wrap);
  });
}

function buildFilterUI() {
  buildCheckboxGroup(document.getElementById('f-type-filter'), ['F', 'K', 'G'], state.findings.types, function (x) { return x; }, function (x) { return x; }, onFindingsFilterChange);
  buildCheckboxGroup(document.getElementById('f-status-filter'), STATUS_ITEMS, state.findings.statuses, function (x) { return x.key; }, function (x) { return x.label; }, onFindingsFilterChange);
  buildCheckboxGroup(document.getElementById('f-ws-filter'), DATA.workstreams, state.findings.workstreams, function (x) { return x.code; }, function (x) { return x.code; }, onFindingsFilterChange);
  buildCheckboxGroup(document.getElementById('r-type-filter'), ['UC', 'FA', 'NFA', 'OP'], state.requirements.types, function (x) { return x; }, function (x) { return x; }, onRequirementsFilterChange);
  buildCheckboxGroup(document.getElementById('r-ws-filter'), DATA.workstreams, state.requirements.workstreams, function (x) { return x.code; }, function (x) { return x.code; }, onRequirementsFilterChange);

  document.getElementById('f-search').addEventListener('input', function (e) { state.findings.search = e.target.value; onFindingsFilterChange(); });
  document.getElementById('f-crossonly').addEventListener('change', function (e) { state.findings.crossOnly = e.target.checked; onFindingsFilterChange(); });
  document.getElementById('r-search').addEventListener('input', function (e) { state.requirements.search = e.target.value; onRequirementsFilterChange(); });
  document.getElementById('r-crossonly').addEventListener('change', function (e) { state.requirements.crossOnly = e.target.checked; onRequirementsFilterChange(); });
  document.getElementById('graph-show-all').addEventListener('change', refreshGraph);

  document.querySelectorAll('#findings-table th[data-key]').forEach(function (th) {
    th.addEventListener('click', function () {
      const key = th.getAttribute('data-key');
      if (state.findings.sortKey === key) state.findings.sortDir *= -1; else { state.findings.sortKey = key; state.findings.sortDir = 1; }
      renderFindingsTable();
    });
  });
  document.querySelectorAll('#requirements-table th[data-key]').forEach(function (th) {
    th.addEventListener('click', function () {
      const key = th.getAttribute('data-key');
      if (state.requirements.sortKey === key) state.requirements.sortDir *= -1; else { state.requirements.sortKey = key; state.requirements.sortDir = 1; }
      renderRequirementsTable();
    });
  });

  document.querySelectorAll('.tab-btn').forEach(function (btn) {
    btn.addEventListener('click', function () {
      document.querySelectorAll('.tab-btn').forEach(function (b) { b.classList.remove('active'); });
      btn.classList.add('active');
      const tab = btn.getAttribute('data-tab');
      document.getElementById('tab-findings').style.display = tab === 'findings' ? '' : 'none';
      document.getElementById('tab-requirements').style.display = tab === 'requirements' ? '' : 'none';
    });
  });

  document.getElementById('download-pending-btn').addEventListener('click', downloadPending);
  document.getElementById('clear-pending-btn').addEventListener('click', clearPending);
  document.getElementById('graph-toggle-btn').addEventListener('click', toggleGraphVisibility);
  document.getElementById('f-export-btn').addEventListener('click', function () {
    exportMarkdown(lastFindingsRows, [
      { key: 'id', label: 'ID' }, { key: 'type', label: 'Typ' }, { key: 'title', label: 'Kurzinhalt' },
      { key: 'workstreams', label: 'Workstreams' }, { key: 'crossWs', label: 'Cross-WS' }, { key: 'status', label: 'Status' }
    ], 'findings-report', state.findings);
  });
  document.getElementById('r-export-btn').addEventListener('click', function () {
    exportMarkdown(lastRequirementsRows, [
      { key: 'id', label: 'ID' }, { key: 'type', label: 'Typ' }, { key: 'title', label: 'Kurzinhalt' },
      { key: 'workstreams', label: 'Workstreams' }, { key: 'crossWs', label: 'Cross-WS' }, { key: 'tag', label: 'Korrelations-Tag' }
    ], 'requirements-report', state.requirements);
  });
}

function onFindingsFilterChange() { renderFindingsTable(); refreshGraph(); }
function onRequirementsFilterChange() { renderRequirementsTable(); }

// --- Hover tooltip ("?" icon shows the finding/requirement definition text) -------------------

function attachHelpIcon(cell, item) {
  const icon = document.createElement('span');
  icon.className = 'help-icon';
  icon.textContent = '?';
  icon.addEventListener('mouseenter', function (e) { showTooltip(e, item.description || item.title); });
  icon.addEventListener('mousemove', function (e) { positionTooltip(e); });
  icon.addEventListener('mouseleave', hideTooltip);
  cell.appendChild(icon);
}

function showTooltip(e, text) {
  const tip = document.getElementById('hover-tooltip');
  tip.textContent = text || '(keine Beschreibung verfuegbar)';
  tip.style.display = 'block';
  positionTooltip(e);
}

function positionTooltip(e) {
  const tip = document.getElementById('hover-tooltip');
  const offset = 14;
  let x = e.clientX + offset;
  let y = e.clientY + offset;
  if (x + 380 > window.innerWidth) x = e.clientX - 380 - offset;
  if (y + 120 > window.innerHeight) y = e.clientY - offset - 100;
  tip.style.left = x + 'px';
  tip.style.top = y + 'px';
}

function hideTooltip() {
  document.getElementById('hover-tooltip').style.display = 'none';
}

// --- Graph show/hide toggle ---------------------------------------------------------------------

let graphVisible = true;
function toggleGraphVisibility() {
  graphVisible = !graphVisible;
  document.getElementById('graph-container').style.display = graphVisible ? '' : 'none';
  document.getElementById('graph-toggle-btn').textContent = graphVisible ? 'Graph ausblenden' : 'Graph anzeigen';
  if (graphVisible) refreshGraph();
}

// --- Markdown export of the currently filtered/sorted table -------------------------------------

function describeActiveFilters(st) {
  const parts = [];
  if (st.search) parts.push('Suche: "' + st.search + '"');
  if (st.types) parts.push('Typen: ' + Array.from(st.types).join(', '));
  if (st.statuses) parts.push('Status: ' + Array.from(st.statuses).join(', '));
  if (st.workstreams && st.workstreams.size < DATA.workstreams.length) parts.push('Workstreams: ' + Array.from(st.workstreams).join(', '));
  if (st.crossOnly) parts.push('nur Cross-Workstream');
  return parts.length ? parts.join(' | ') : 'keine (alle Zeilen)';
}

function pad2(n) { return (n < 10 ? '0' : '') + n; }

function exportMarkdown(rows, columns, filenamePrefix, filterState) {
  const now = new Date();
  const stamp = now.getFullYear() + '-' + pad2(now.getMonth() + 1) + '-' + pad2(now.getDate()) + '_' + pad2(now.getHours()) + pad2(now.getMinutes()) + pad2(now.getSeconds());
  const lines = [];
  lines.push('# Findings-Dashboard Export');
  lines.push('');
  lines.push('- Generiert: ' + now.toISOString());
  lines.push('- Aktive Filter: ' + describeActiveFilters(filterState));
  lines.push('- Zeilen: ' + rows.length);
  lines.push('');
  lines.push('| ' + columns.map(function (c) { return c.label; }).join(' | ') + ' |');
  lines.push('|' + columns.map(function () { return '---'; }).join('|') + '|');
  rows.forEach(function (r) {
    const cells = columns.map(function (c) {
      let v = r[c.key];
      if (Array.isArray(v)) v = v.join(', ');
      if (typeof v === 'boolean') v = v ? 'ja' : '';
      if (v == null) v = '';
      return String(v).replace(/\|/g, '\\|');
    });
    lines.push('| ' + cells.join(' | ') + ' |');
  });
  const blob = new Blob([lines.join('\n')], { type: 'text/markdown' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filenamePrefix + '_' + stamp + '.md';
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
  alert('Export heruntergeladen: ' + a.download + '\nBitte manuell nach project-reports/findings-dash-export/ verschieben.');
}

// --- Pending status changes (queued locally, applied later via apply-findings-status-changes.ps1) --

function persistPending() { localStorage.setItem('fd_pending', JSON.stringify(pending)); }

function queueChange(id, oldStatus, newStatus) {
  pending = pending.filter(function (p) { return p.id !== id; });
  pending.push({ id: id, oldStatus: oldStatus, newStatus: newStatus, timestamp: new Date().toISOString() });
  persistPending();
  renderPending();
  renderFindingsTable();
}

function removePending(id) {
  pending = pending.filter(function (p) { return p.id !== id; });
  persistPending();
  renderPending();
  renderFindingsTable();
}

function clearPending() {
  if (pending.length && !confirm('Alle ausstehenden Aenderungen verwerfen?')) return;
  pending = [];
  persistPending();
  renderPending();
  renderFindingsTable();
}

function downloadPending() {
  if (!pending.length) { alert('Keine ausstehenden Aenderungen.'); return; }
  const blob = new Blob([JSON.stringify(pending, null, 2)], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = 'pending-status-changes.json';
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

function renderPending() {
  document.getElementById('pending-count').textContent = pending.length;
  const tbody = document.querySelector('#pending-table tbody');
  tbody.innerHTML = '';
  pending.forEach(function (p) {
    const tr = document.createElement('tr');
    const tdActions = document.createElement('td');
    const btn = document.createElement('button');
    btn.textContent = 'Entfernen';
    btn.onclick = function () { removePending(p.id); };
    tdActions.appendChild(btn);
    tr.innerHTML = '<td>' + p.id + '</td><td>' + escapeHtml(p.oldStatus) + '</td><td>' + escapeHtml(p.newStatus) + '</td>';
    tr.appendChild(tdActions);
    tbody.appendChild(tr);
  });
}

// --- Cytoscape graph: workstream clusters, collapsible, filtered ------------------------------

let cy = null;
const collapsedWs = new Set();

function buildGraphElements() {
  const els = [];
  DATA.workstreams.forEach(function (ws) { els.push({ data: { id: ws.code, label: ws.name }, classes: 'ws' }); });
  const showAll = document.getElementById('graph-show-all').checked;
  const candidates = filterFindings().filter(function (f) { return showAll || f.crossWs || computeStatusKey(f) === 'red'; });
  candidates.forEach(function (f) {
    const wsList = f.workstreams || [];
    if (!wsList.length) return;
    const primary = wsList[0];
    let cls = 'finding';
    if (f.crossWs) cls += ' cross';
    if (computeStatusKey(f) === 'red') cls += ' statusred';
    els.push({ data: { id: 'n_' + f.id, label: f.id, parent: primary, defLink: f.defLink }, classes: cls });
    wsList.forEach(function (w) {
      if (w !== primary) {
        els.push({ data: { id: 'e_' + f.id + '_' + w, source: 'n_' + f.id, target: w }, classes: f.crossWs ? 'crossedge' : '' });
      }
    });
  });
  return els;
}

function applyCollapse() {
  if (!cy) return;
  cy.nodes('.finding').forEach(function (n) {
    const parent = n.data('parent');
    if (collapsedWs.has(parent)) { n.addClass('hiddenel'); n.connectedEdges().addClass('hiddenel'); }
    else { n.removeClass('hiddenel'); n.connectedEdges().removeClass('hiddenel'); }
  });
}

function toggleWorkstream(code) {
  if (collapsedWs.has(code)) collapsedWs.delete(code); else collapsedWs.add(code);
  applyCollapse();
}

function initGraph() {
  if (typeof cytoscape === 'undefined' || window.__cyLoadFailed) {
    document.getElementById('graph-fallback').style.display = 'block';
    document.getElementById('cy').style.display = 'none';
    return;
  }
  cy = cytoscape({
    container: document.getElementById('cy'),
    elements: buildGraphElements(),
    style: [
      { selector: 'node.ws', style: { 'background-color': '#dde3f0', 'label': 'data(label)', 'text-valign': 'top', 'text-halign': 'center', 'font-weight': 'bold', 'padding': '14px', 'shape': 'round-rectangle' } },
      { selector: 'node.finding', style: { 'label': 'data(label)', 'background-color': '#eef', 'border-width': 1, 'border-color': '#999', 'font-size': 9, 'width': 'label', 'height': 'label', 'padding': '6px', 'shape': 'round-rectangle' } },
      { selector: 'node.finding.cross', style: { 'background-color': '#ffdcdc', 'border-color': '#c0392b', 'border-width': 3 } },
      { selector: 'node.finding.statusred', style: { 'border-color': '#c0392b' } },
      { selector: 'edge', style: { 'width': 1, 'line-color': '#ccc', 'curve-style': 'bezier' } },
      { selector: 'edge.crossedge', style: { 'line-color': '#c0392b', 'width': 2 } },
      { selector: '.hiddenel', style: { 'display': 'none' } }
    ],
    layout: { name: 'cose', padding: 30, animate: false }
  });
  cy.on('tap', 'node.ws', function (evt) { toggleWorkstream(evt.target.id()); });
  cy.on('tap', 'node.finding', function (evt) { const link = evt.target.data('defLink'); if (link) window.open(link, '_blank'); });
  applyCollapse();
}

function refreshGraph() {
  if (!cy) { initGraph(); return; }
  cy.elements().remove();
  cy.add(buildGraphElements());
  cy.layout({ name: 'cose', padding: 30, animate: false }).run();
  applyCollapse();
}

document.addEventListener('DOMContentLoaded', function () {
  renderSummary();
  buildFilterUI();
  renderFindingsTable();
  renderRequirementsTable();
  renderPending();
  initGraph();
});
</script>
</body>
</html>
'@

$htmlContent = $htmlTemplate.Replace('__DASHBOARD_DATA_JSON__', $dashboardJson)
$htmlContent = $htmlContent.Replace('__SYM_RED__', $Sym.Red)
$htmlContent = $htmlContent.Replace('__SYM_ORANGE__', $Sym.Orange)
$htmlContent = $htmlContent.Replace('__SYM_YELLOW__', $Sym.Yellow)
$htmlContent = $htmlContent.Replace('__SYM_CHECK__', $Sym.Check)
$htmlContent = $htmlContent.Replace('__SYM_PURPLE__', $Sym.Purple)
$htmlContent = $htmlContent.Replace('__SYM_BLACK__', $Sym.Black)
$htmlContent = $htmlContent.Replace('__SYM_WARN__', $Sym.Warn)

Set-Content -LiteralPath $HtmlDashboardPath -Value $htmlContent -Encoding UTF8
Write-Host "HTML-Dashboard geschrieben: $HtmlDashboardPath" -ForegroundColor Green
