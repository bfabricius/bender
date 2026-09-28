<#
.SYNOPSIS
    Drop-in Projekt-Status-Tool fuer Mandate nach dem Memory-Index-/OpenSpec-Muster.

.DESCRIPTION
    Portables, self-contained PowerShell-Skript. Es wird in den Root-Ordner eines aehnlich
    aufgebauten Mandats (mem-index/, openspec-sdd/, input_client-docs/, export-artefacts/,
    analyse-sprint/) kopiert und von dort ausgefuehrt. Bietet ein interaktives Menue mit
    High-Level-Status zu Ingest-Historie, Stakeholdern, Requirements/Traceability,
    Ingest-Abdeckung, Analyse-Sprints/Workstreams, OpenSpec-Changes und Export-Artefakten.

    Das Skript ist read-only, ausser fuer den optionalen Report-Export (schreibt ausschliesslich
    in den ReportOutputFolder). Alle Quell-Ordner sind ueber Parameter konfigurierbar, um das
    Skript unveraendert in andere Mandate dieser Art kopieren zu koennen.

.PARAMETER ProjectRoot
    Wurzelordner des Mandats. Default: Ordner, in dem dieses Skript liegt.

.PARAMETER MemIndexFolder
    Name des Memory-Index-Ordners relativ zu ProjectRoot. Default: "mem-index".

.PARAMETER OpenSpecFolder
    Name des OpenSpec-SDD-Ordners relativ zu ProjectRoot. Default: "openspec-sdd".

.PARAMETER InputDocsFolder
    Name des Client-Input-Ordners relativ zu ProjectRoot. Default: "input_client-docs".

.PARAMETER ExportArtefactsFolder
    Name des Export-Artefakte-Ordners relativ zu ProjectRoot. Default: "export-artefacts".

.PARAMETER AnalyseSprintFolder
    Name des Analyse-Sprint-Ordners relativ zu ProjectRoot. Default: "analyse-sprint".

.PARAMETER ReportOutputFolder
    Zielordner fuer den optionalen Markdown-Report-Export. Default: "project-reports".

.PARAMETER Action
    Optional. Fuehrt genau einen Menuepunkt nicht-interaktiv aus und beendet danach, statt das
    Menue zu zeigen (fuer Skript-/Agent-Aufrufe, z. B. durch den /ingest-docs Slash-Agent). Default:
    "Menu" (bisheriges interaktives Verhalten, unveraendert).

.EXAMPLE
    ./project-status.ps1
    Startet das interaktive Menue mit den Standard-Ordnernamen.

.EXAMPLE
    ./project-status.ps1 -MemIndexFolder "wiki" -OpenSpecFolder "specs-sdd"
    Nutzt das Skript in einem Mandat mit abweichenden Ordnernamen.

.EXAMPLE
    ./project-status.ps1 -Action IngestCoverage
    Zeigt nur die Ingest-Abdeckung (inkl. nicht erfasster Dateien) und beendet, ohne Menue.
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot = $PSScriptRoot,
    [string]$MemIndexFolder = 'mem-index',
    [string]$OpenSpecFolder = 'openspec-sdd',
    [string]$InputDocsFolder = 'input_client-docs',
    [string]$ExportArtefactsFolder = 'export-artefacts',
    [string]$AnalyseSprintFolder = 'analyse-sprint',
    [string]$ReportOutputFolder = 'project-reports',
    [ValidateSet('Menu', 'HighLevelStatus', 'IngestHistory', 'Stakeholders', 'RequirementsNodeLevel',
        'Traceability', 'IngestCoverage', 'AnalyseSprints', 'OpenSpecStatus', 'ExportArtefacts', 'FullReport')]
    [string]$Action = 'Menu'
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
# Non-ASCII-Literale (Paragraphzeichen, Gedankenstriche) als Zeichencode statt Literal,
# damit die Regex-Matches unabhaengig von der Datei-Kodierung dieses Skripts funktionieren.
$Script:SectionSign = [char]0x00A7
$Script:EmDash = [char]0x2014

$Paths = [ordered]@{
    Root            = $ProjectRoot
    MemIndex        = Join-Path $ProjectRoot $MemIndexFolder
    OpenSpec        = Join-Path $ProjectRoot $OpenSpecFolder
    InputDocs       = Join-Path $ProjectRoot $InputDocsFolder
    ExportArtefacts = Join-Path $ProjectRoot $ExportArtefactsFolder
    AnalyseSprint   = Join-Path $ProjectRoot $AnalyseSprintFolder
    Reports         = Join-Path $ProjectRoot $ReportOutputFolder
}

# ===========================================================================
#  1. Allgemeine Hilfsfunktionen
# ===========================================================================

function Write-SectionHeader {
    param([string]$Title)
    Write-Host ''
    Write-Host ("=== {0} ===" -f $Title) -ForegroundColor Cyan
}

function Test-FolderOrWarn {
    param([string]$Path, [string]$Label)
    if (Test-Path -LiteralPath $Path) { return $true }
    Write-Warning "Ordner '$Label' nicht gefunden ($Path) - Abschnitt wird uebersprungen."
    return $false
}

function Write-FileUtf8NoBom {
    param([string]$Path, [string]$Content)
    $full = [System.IO.Path]::GetFullPath($Path)
    $dir = [System.IO.Path]::GetDirectoryName($full)
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($full, $Content, $utf8NoBom)
}

function Read-TextFileLines {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    return [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)
}

# Zerlegt eine Zeilenliste in Bloecke aufeinanderfolgender Markdown-Tabellenzeilen
# (Zeilen, die mit '|' beginnen) und parst jeden Block in Objekte anhand der Kopfzeile.
function ConvertFrom-MarkdownTableBlock {
    param([string[]]$Lines)
    $rows = @()
    foreach ($line in $Lines) {
        $trimmed = $line.Trim()
        if ($trimmed -notmatch '^\|.*\|$') { continue }
        $cells = $trimmed.Trim('|') -split '\|' | ForEach-Object { $_.Trim() }
        $rows += , $cells
    }
    if ($rows.Count -lt 2) { return @() }
    $header = $rows[0]
    $dataRows = @()
    for ($i = 1; $i -lt $rows.Count; $i++) {
        $r = $rows[$i]
        $isSeparator = $true
        foreach ($c in $r) { if ($c -notmatch '^:?-{2,}:?$') { $isSeparator = $false; break } }
        if ($isSeparator) { continue }
        $obj = [ordered]@{}
        for ($j = 0; $j -lt $header.Count; $j++) {
            $val = ''
            if ($j -lt $r.Count) { $val = $r[$j] }
            $obj[$header[$j]] = $val
        }
        $dataRows += [pscustomobject]$obj
    }
    return $dataRows
}

function Get-AllMarkdownTables {
    param([string[]]$Lines)
    $blocks = @()
    $current = @()
    foreach ($line in $Lines) {
        if ($line.TrimStart().StartsWith('|')) {
            $current += $line
        }
        elseif ($current.Count -gt 0) {
            $blocks += , $current
            $current = @()
        }
    }
    if ($current.Count -gt 0) { $blocks += , $current }
    $result = @()
    foreach ($b in $blocks) {
        $result += [pscustomobject]@{ HeaderLine = $b[0]; Rows = (ConvertFrom-MarkdownTableBlock -Lines $b) }
    }
    return $result
}

function Get-WikiLinks {
    param([string]$Text)
    if (-not $Text) { return @() }
    $matches2 = [regex]::Matches($Text, '\[\[([^\]]+)\]\]')
    return @($matches2 | ForEach-Object { $_.Groups[1].Value })
}

function Get-BacktickPaths {
    param([string]$Text)
    if (-not $Text) { return @() }
    $matches2 = [regex]::Matches($Text, '`([^`]+\.(pdf|docx|pptx|txt|html|png|drawio|md|xlsx))`')
    return @($matches2 | ForEach-Object { $_.Groups[1].Value })
}

# Findet alle Requirement-Kuerzel (SS-NN, UC/FA/NFA/OP-NN) in einem Text; Bereiche wie
# "SS22-29" werden expandiert. Rein heuristisch - dient der ID-Ebene der Traceability.
function Get-IdMentions {
    param([string]$Text)
    $ids = New-Object System.Collections.Generic.HashSet[string]
    if (-not $Text) { return $ids }
    foreach ($m in [regex]::Matches($Text, '\u00A7\s*(\d{1,3})(?:\s*[\u2013-]\s*(\d{1,3}))?')) {
        $start = [int]$m.Groups[1].Value
        $end = $start
        if ($m.Groups[2].Success) { $end = [int]$m.Groups[2].Value }
        for ($n = $start; $n -le $end; $n++) { [void]$ids.Add("$Script:SectionSign$n") }
    }
    foreach ($m in [regex]::Matches($Text, '\b(UC|FA|NFA|OP)-(\d{1,3})\b')) {
        [void]$ids.Add("$($m.Groups[1].Value)-$($m.Groups[2].Value)")
    }
    return $ids
}

function ConvertTo-MarkdownTable {
    param([array]$Objects, [string[]]$Properties)
    if (-not $Objects -or $Objects.Count -eq 0) { return "_(keine Eintraege)_`r`n" }
    if (-not $Properties) { $Properties = $Objects[0].PSObject.Properties.Name }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('| ' + ($Properties -join ' | ') + ' |')
    [void]$sb.AppendLine('|' + (($Properties | ForEach-Object { '---' }) -join '|') + '|')
    foreach ($o in $Objects) {
        $cells = foreach ($p in $Properties) {
            $v = $o.$p
            if ($null -eq $v) { $v = '' }
            $v = [string]$v
            $v = $v -replace '\|', '\|'
            $v = $v -replace '\r?\n', ' '
            $v
        }
        [void]$sb.AppendLine('| ' + ($cells -join ' | ') + ' |')
    }
    return $sb.ToString()
}

# ===========================================================================
#  2. Datenzugriff mem-index
# ===========================================================================

function Get-LogEntries {
    param([string]$MemIndexPath)
    $logPath = Join-Path $MemIndexPath 'log.md'
    $entries = @()
    $lines = Read-TextFileLines -Path $logPath
    $current = $null
    foreach ($line in $lines) {
        if ($line -match '^## \[(?<date>\d{4}-\d{2}-\d{2})\]\s+(?<type>\S+)\s+\|\s+(?<title>.+)$') {
            if ($current) { $entries += [pscustomobject]$current }
            $current = [ordered]@{
                Date = $Matches['date']; Type = $Matches['type']; Title = $Matches['title']
                Aktion = ''; Nodes = ''; Details = ''
            }
            continue
        }
        if ($current -and $line -match '^\*\*(?<field>[^:]+):\*\*\s*(?<value>.*)$') {
            $field = $Matches['field'].Trim()
            $value = $Matches['value']
            if ($field -eq 'Aktion') { $current['Aktion'] = $value }
            elseif ($field -match '^Ge.nderte Nodes$') { $current['Nodes'] = $value }
            elseif ($field -eq 'Details') { $current['Details'] = $value }
        }
    }
    if ($current) { $entries += [pscustomobject]$current }
    return $entries
}

function Get-QuelldokumentMapping {
    param([string]$MemIndexPath)
    $indexPath = Join-Path $MemIndexPath '00_INDEX.md'
    $lines = Read-TextFileLines -Path $indexPath
    if ($lines.Count -eq 0) { return @() }
    $tables = Get-AllMarkdownTables -Lines $lines
    $mappingTable = $tables | Where-Object { $_.HeaderLine -match 'Quelldokument' } | Select-Object -First 1
    if (-not $mappingTable) { return @() }
    $result = @()
    foreach ($row in $mappingTable.Rows) {
        $sourceRaw = $row.Quelldokument
        if (-not $sourceRaw) { $sourceRaw = ($row.PSObject.Properties | Select-Object -First 1).Value }
        $isDerived = $sourceRaw -match '^_.*Analyse.*_$' -or $sourceRaw -match 'kein Client-Dokument'
        $clean = $sourceRaw -replace '`', ''
        $clean = ($clean -replace '\s*\([^)]*\)\s*$', '').Trim()
        $result += [pscustomobject]@{
            SourceRaw     = $sourceRaw
            SourcePattern = $clean
            Nodes         = Get-WikiLinks -Text $row.'Ziel-Node(s)'
            NodesRaw      = $row.'Ziel-Node(s)'
            Status        = $row.Status
            IsDerived     = [bool]$isDerived
        }
    }
    return $result
}

function Get-Stakeholders {
    param([string]$MemIndexPath)
    $path = Join-Path $MemIndexPath '02_Stakeholder.md'
    $lines = Read-TextFileLines -Path $path
    if ($lines.Count -eq 0) { return @() }
    $tables = Get-AllMarkdownTables -Lines $lines
    $stakeholderTable = $tables | Where-Object { $_.HeaderLine -match 'Name' -and $_.HeaderLine -match 'Einfluss' } | Select-Object -First 1
    if (-not $stakeholderTable) { return @() }
    $result = @()
    foreach ($row in $stakeholderTable.Rows) {
        $nameRaw = $row.Name
        $email = '-'
        if ($nameRaw -match '\(([^)]*@[^)]*)\)') { $email = $Matches[1] }
        $cleanName = ($nameRaw -replace '\s*\([^)]*@[^)]*\)\s*', '').Trim()
        $orgRoleKey = ($row.PSObject.Properties.Name | Where-Object { $_ -match 'Organisation' }) | Select-Object -First 1
        $interestKey = ($row.PSObject.Properties.Name | Where-Object { $_ -match 'Interesse' }) | Select-Object -First 1
        $result += [pscustomobject]@{
            Name      = $cleanName
            OrgRolle  = if ($orgRoleKey) { $row.$orgRoleKey } else { '' }
            Interesse = if ($interestKey) { $row.$interestKey } else { '' }
            Einfluss  = $row.Einfluss
            Kontakt   = $email
        }
    }
    return $result
}

function Get-RequirementsNumbered {
    param([string]$MemIndexPath)
    $path = Join-Path $MemIndexPath '03_Anforderungen.md'
    $lines = Read-TextFileLines -Path $path
    $result = @()
    foreach ($line in $lines) {
        if ($line -match '^(?<num>\d{1,3})\.\s+\*\*(?<title>[^:]+):\*\*\s*(?<desc>.+)$') {
            $result += [pscustomobject]@{
                ID          = "$Script:SectionSign$($Matches['num'])"
                Kind        = 'Anforderung'
                Title       = $Matches['title'].Trim()
                Description = $Matches['desc'].Trim()
                Node        = '03_Anforderungen'
            }
        }
    }
    return $result
}

function Get-RequirementsHighLevel {
    param([string]$MemIndexPath)
    $path = Join-Path $MemIndexPath '03b_HighLevel-Requirements.md'
    $lines = Read-TextFileLines -Path $path
    $result = @()
    if ($lines.Count -eq 0) { return $result }
    foreach ($line in $lines) {
        if ($line -match "^### (?<id>UC-\d+)\s+$Script:EmDash\s+(?<title>.+?)\s*``(?<tag>\S+)``\s*`$") {
            $result += [pscustomobject]@{
                ID = $Matches['id']; Kind = 'UC'; Title = $Matches['title'].Trim()
                Description = ''; Node = '03b_HighLevel-Requirements'; Tag = $Matches['tag']
            }
        }
    }
    $tables = Get-AllMarkdownTables -Lines $lines
    foreach ($t in ($tables | Where-Object { $_.HeaderLine -match '^\|\s*ID\s*\|' })) {
        foreach ($row in $t.Rows) {
            if ($row.ID -match '^(FA|NFA|OP)-\d+$') {
                $kind = $Matches[1]
                $titleKey = ($row.PSObject.Properties.Name | Where-Object { $_ -match 'Name|Thema' }) | Select-Object -First 1
                $descKey = ($row.PSObject.Properties.Name | Where-Object { $_ -match 'Beschreibung|Fragestellung' }) | Select-Object -First 1
                $result += [pscustomobject]@{
                    ID = $row.ID; Kind = $kind; Title = if ($titleKey) { $row.$titleKey } else { '' }
                    Description = if ($descKey) { $row.$descKey } else { '' }
                    Node = '03b_HighLevel-Requirements'; Tag = $row.Tag
                }
            }
        }
    }
    return $result
}

function Get-AllRequirements {
    param([string]$MemIndexPath)
    return @(Get-RequirementsNumbered -MemIndexPath $MemIndexPath) + @(Get-RequirementsHighLevel -MemIndexPath $MemIndexPath)
}

# ===========================================================================
#  3. Ingest-Historie & Ingest-Abdeckung
# ===========================================================================

function Get-IngestHistory {
    param([string]$MemIndexPath)
    $entries = Get-LogEntries -MemIndexPath $MemIndexPath | Where-Object { $_.Type -eq 'ingest' }
    $result = @()
    foreach ($e in $entries) {
        $docs = Get-BacktickPaths -Text $e.Aktion
        $nodes = Get-WikiLinks -Text $e.Nodes
        $result += [pscustomobject]@{
            Datum         = $e.Date
            Titel         = $e.Title
            Quelldokument = if ($docs.Count -gt 0) { $docs -join ', ' } else { '(kein Pfad im Text erkannt)' }
            ZielNodes     = $nodes -join ', '
        }
    }
    return @($result | Sort-Object Datum)
}

function Get-IngestCoverage {
    param([string]$MemIndexPath, [string]$InputDocsPath)
    $mapping = @(Get-QuelldokumentMapping -MemIndexPath $MemIndexPath | Where-Object { -not $_.IsDerived })
    # Retro-Eintraege (Slash-Agent /retrospektive) tragen ihre Quelle bewusst NICHT in die
    # Quelldokument-Mapping-Tabelle von 00_INDEX.md ein (Node 15 ist von dieser Regel
    # ausgenommen, siehe copilot-instructions.md), sondern nennen den Pfad als Backtick-
    # Referenz direkt im log.md-Eintrag (Aktion/Details). Ohne diese als "erfasst" zu
    # beruecksichtigen, wuerden Retro-Quelldateien immer faelschlich als Luecke auftauchen.
    $inputDocsLeaf = Split-Path -Path $InputDocsPath -Leaf
    # NBSP (U+00A0) vs. normalem Leerzeichen in Dateinamen (z. B. rund um Gedankenstriche) kann
    # zwischen Dateisystem und log.md-Text abweichen - beim Vergleich daher auf normale
    # Leerzeichen vereinheitlichen.
    $retroPaths = New-Object System.Collections.Generic.HashSet[string]
    foreach ($e in (Get-LogEntries -MemIndexPath $MemIndexPath | Where-Object { $_.Type -eq 'retro' })) {
        foreach ($p in (@(Get-BacktickPaths -Text $e.Aktion) + @(Get-BacktickPaths -Text $e.Details))) {
            $norm = ($p -replace '\\', '/') -replace [char]0x00A0, ' '
            $prefix = "$inputDocsLeaf/"
            if ($norm.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                $norm = $norm.Substring($prefix.Length)
            }
            [void]$retroPaths.Add($norm)
        }
    }
    $result = [ordered]@{ Total = 0; Ingested = @(); Ignored = @(); NotTracked = @() }
    if (-not (Test-Path -LiteralPath $InputDocsPath)) { return $result }
    $files = Get-ChildItem -LiteralPath $InputDocsPath -Recurse -File | Where-Object { $_.Name -notmatch '^~\$' }
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($InputDocsPath.Length).TrimStart('\', '/') -replace '\\', '/'
        $matchRow = $null
        foreach ($m in $mapping) {
            $pattern = $m.SourcePattern -replace '\\', '/'
            if ($pattern -match '\*') {
                if ($rel -like $pattern) { $matchRow = $m; break }
            }
            elseif ($rel -ieq $pattern) { $matchRow = $m; break }
        }
        $result.Total++
        if (-not $matchRow) {
            $relForRetroMatch = $rel -replace [char]0x00A0, ' '
            if ($retroPaths.Contains($relForRetroMatch)) { $result.Ingested += $rel } else { $result.NotTracked += $rel }
        }
        elseif ($matchRow.Status -match 'ignoriert') { $result.Ignored += $rel }
        else { $result.Ingested += $rel }
    }
    # Bewusst ignorierte Dateien (Duplikate/aktuell nicht wichtig, siehe 00_INDEX) zaehlen nicht als Luecke.
    $result.RelevantTotal = $result.Total - $result.Ignored.Count
    $result.PercentIngested = if ($result.RelevantTotal -gt 0) { [math]::Round(($result.Ingested.Count / $result.RelevantTotal) * 100, 1) } else { 0 }
    return $result
}

# Traceability-Vergleich: Node-Ebene (zuverlaessig, aus 00_INDEX-Mapping) vs.
# ID-Ebene (heuristisch, Scan von log.md nach Requirement-Kuerzeln je Ingest-Eintrag).
function Get-TraceabilityComparison {
    param([string]$MemIndexPath)
    $requirements = Get-AllRequirements -MemIndexPath $MemIndexPath
    if ($requirements.Count -eq 0) { return $null }
    $mapping = Get-QuelldokumentMapping -MemIndexPath $MemIndexPath
    $nodeSources = @{}
    foreach ($m in $mapping) {
        foreach ($n in $m.Nodes) {
            if (-not $nodeSources.ContainsKey($n)) { $nodeSources[$n] = New-Object System.Collections.Generic.List[string] }
            if (-not $m.IsDerived) { $nodeSources[$n].Add($m.SourcePattern) }
        }
    }
    $ingestEntries = @(Get-LogEntries -MemIndexPath $MemIndexPath | Where-Object { $_.Type -eq 'ingest' })
    $idToSource = @{}
    foreach ($e in $ingestEntries) {
        $mentioned = Get-IdMentions -Text ("$($e.Title) $($e.Aktion) $($e.Details)")
        $docs = Get-BacktickPaths -Text $e.Aktion
        foreach ($id in $mentioned) {
            if (-not $idToSource.ContainsKey($id)) { $idToSource[$id] = New-Object System.Collections.Generic.List[string] }
            foreach ($d in $docs) { $idToSource[$id].Add($d) }
        }
    }
    $rows = @()
    $nodeMatchCount = 0
    $idMatchCount = 0
    foreach ($r in $requirements) {
        $nodeHasSource = ($nodeSources.ContainsKey($r.Node) -and $nodeSources[$r.Node].Count -gt 0)
        $idHasSource = $idToSource.ContainsKey($r.ID) -and $idToSource[$r.ID].Count -gt 0
        if ($nodeHasSource) { $nodeMatchCount++ }
        if ($idHasSource) { $idMatchCount++ }
        $rows += [pscustomobject]@{
            ID              = $r.ID
            Titel           = $r.Title
            NodeEbene       = if ($nodeHasSource) { 'Ja' } else { 'Nein' }
            IdEbene         = if ($idHasSource) { 'Ja' } else { 'Nein' }
            IdQuelle        = if ($idHasSource) { ($idToSource[$r.ID] | Select-Object -Unique) -join ', ' } else { '' }
        }
    }
    $total = $requirements.Count
    $ratio = 0
    if ($nodeMatchCount -gt 0) { $ratio = [math]::Round(($idMatchCount / $nodeMatchCount) * 100, 1) }
    return [pscustomobject]@{
        Total          = $total
        NodeMatchCount = $nodeMatchCount
        IdMatchCount   = $idMatchCount
        RatioPercent   = $ratio
        Rows           = $rows
    }
}

# ===========================================================================
#  4. Analyse-Sprints & Workstreams
# ===========================================================================

function Get-AnalyseSprintFiles {
    param([string]$AnalyseSprintPath)
    $result = @{ Files = @(); Workstreams = @(); Fortschritt = @() }
    if (-not (Test-Path -LiteralPath $AnalyseSprintPath)) { return $result }
    $mdFiles = Get-ChildItem -LiteralPath $AnalyseSprintPath -Filter '*.md' -File
    foreach ($f in $mdFiles) {
        if ($f.Name -match '^(?<date>\d{4}-\d{2}-\d{2})_(?<slug>.+)\.md$') {
            $slug = $Matches['slug']
            $type = 'Sonstige'
            if ($slug -match 'workstream') { $type = 'Workstream' }
            elseif ($slug -match 'grundlagen') { $type = 'Grundlagen' }
            elseif ($slug -match 'openspec') { $type = 'OpenSpec-Prozess' }
            elseif ($slug -match 'fragen|offene') { $type = 'Offene Fragen' }
            $result.Files += [pscustomobject]@{ Datum = $Matches['date']; Datei = $f.Name; Typ = $type; Slug = $slug }
        }
    }
    $wsSlugs = @($result.Files | Where-Object { $_.Typ -eq 'Workstream' } | ForEach-Object { ($_.Slug -replace '^workstream-', '') })
    foreach ($ws in ($wsSlugs | Select-Object -Unique)) {
        $hasGrundlagen = @($result.Files | Where-Object { $_.Typ -eq 'Grundlagen' -and $_.Slug -match [regex]::Escape($ws) }).Count -gt 0
        $result.Workstreams += [pscustomobject]@{
            Workstream    = $ws -replace '-', ' '
            HatGrundlagen = if ($hasGrundlagen) { 'Ja' } else { 'Nein' }
            HatWorkstream = 'Ja'
        }
    }
    $fortschrittPath = Join-Path $AnalyseSprintPath '_openspec-fortschritt'
    if (Test-Path -LiteralPath $fortschrittPath) {
        $result.Fortschritt = @(Get-ChildItem -LiteralPath $fortschrittPath -Filter '*.md' -File | ForEach-Object { $_.Name })
    }
    return $result
}

# ===========================================================================
#  5. OpenSpec-Status
# ===========================================================================

function Get-OpenSpecChanges {
    param([string]$OpenSpecPath)
    $changesPath = Join-Path (Join-Path $OpenSpecPath 'openspec') 'changes'
    $result = @()
    if (-not (Test-Path -LiteralPath $changesPath)) { return $result }
    $stageNames = @('Nicht gestartet', 'Analyse gestartet (proposal)', 'Optionen dokumentiert (+design)', 'Sprintready (+specs)', 'Tasks definiert (+tasks)')
    $changeDirs = @(Get-ChildItem -LiteralPath $changesPath -Directory | Where-Object { $_.Name -ne 'archive' })
    foreach ($dir in $changeDirs) {
        $cf = $dir.FullName
        $hasProposal = Test-Path (Join-Path $cf 'proposal.md')
        $hasDesign = Test-Path (Join-Path $cf 'design.md')
        $specsPath = Join-Path $cf 'specs'
        $hasSpecs = $false
        if (Test-Path -LiteralPath $specsPath) {
            $hasSpecs = @(Get-ChildItem -LiteralPath $specsPath -Filter 'spec.md' -Recurse -ErrorAction SilentlyContinue).Count -gt 0
        }
        $hasTasks = Test-Path (Join-Path $cf 'tasks.md')
        $stageIndex = 0
        if ($hasProposal) { $stageIndex = 1 }
        if ($hasProposal -and $hasDesign) { $stageIndex = 2 }
        if ($hasProposal -and $hasDesign -and $hasSpecs) { $stageIndex = 3 }
        if ($hasProposal -and $hasDesign -and $hasSpecs -and $hasTasks) { $stageIndex = 4 }
        $result += [pscustomobject]@{
            Name     = $dir.Name
            Proposal = $hasProposal
            Design   = $hasDesign
            Specs    = $hasSpecs
            Tasks    = $hasTasks
            Stufe    = $stageNames[$stageIndex]
            Pfad     = $cf
        }
    }
    return $result
}

function Get-OpenSpecBaselineAndArchive {
    param([string]$OpenSpecPath)
    $result = [ordered]@{ Baseline = @(); Archiv = @() }
    $specsPath = Join-Path (Join-Path $OpenSpecPath 'openspec') 'specs'
    if (Test-Path -LiteralPath $specsPath) {
        $result.Baseline = @(Get-ChildItem -LiteralPath $specsPath -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    }
    $archivePath = Join-Path (Join-Path $OpenSpecPath 'openspec') (Join-Path 'changes' 'archive')
    if (Test-Path -LiteralPath $archivePath) {
        $result.Archiv = @(Get-ChildItem -LiteralPath $archivePath -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    }
    return $result
}

function Invoke-OpenSpecValidate {
    param([string]$OpenSpecPath, [string]$ChangeName)
    if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
        Write-Warning "npx nicht gefunden - Tiefen-Validierung wird uebersprungen."
        return
    }
    Push-Location $OpenSpecPath
    try {
        Write-Host "--- npx openspec validate $ChangeName --strict ---" -ForegroundColor DarkGray
        & npx --yes @fission-ai/openspec@latest validate $ChangeName --strict
        if ($LASTEXITCODE -ne 0) { Write-Warning "Validate fuer '$ChangeName' meldete Exit-Code $LASTEXITCODE." }
    }
    catch {
        Write-Warning "npx-Validate fehlgeschlagen: $($_.Exception.Message)"
    }
    finally {
        Pop-Location
    }
}

# ===========================================================================
#  6. Export-Artefakte
# ===========================================================================

# Liefert die per .gitignore ignorierten Dateien/Ordner unterhalb von RelativePath als Set
# (Ordner mit abschliessendem '/', siehe --directory). $null wenn git/Repo nicht verfuegbar.
function Get-GitIgnoredEntries {
    param([string]$RepoRoot, [string]$RelativePath)
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $null }
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot '.git'))) { return $null }
    $out = $null
    try {
        $out = & git -C $RepoRoot ls-files --others --ignored --exclude-standard --directory -- $RelativePath 2>$null
    }
    catch { return $null }
    if ($LASTEXITCODE -ne 0) { return $null }
    $set = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($line in @($out)) { if ($line) { [void]$set.Add(($line.Trim() -replace '\\', '/')) } }
    return $set
}

# Rekursive Dateiauflistung, die komplette gitignorierte Ordner (z. B. node_modules/) gar
# nicht erst betritt - schneller und deckt sich mit 'was git tracken wuerde'.
function Get-FilesPruned {
    param([string]$Path, [string]$RepoRoot, [System.Collections.Generic.HashSet[string]]$Ignored)
    $result = @()
    $items = Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    foreach ($item in $items) {
        $rel = ($item.FullName.Substring($RepoRoot.Length).TrimStart('\', '/')) -replace '\\', '/'
        if ($item.PSIsContainer) {
            if ($Ignored -and $Ignored.Contains("$rel/")) { continue }
            $result += Get-FilesPruned -Path $item.FullName -RepoRoot $RepoRoot -Ignored $Ignored
        }
        elseif (-not ($Ignored -and $Ignored.Contains($rel))) {
            $result += $item
        }
    }
    return $result
}

function Get-ExportArtefactsOverview {
    param([string]$ExportPath, [string]$RepoRoot)
    if (-not (Test-Path -LiteralPath $ExportPath)) { return $null }
    $relPath = ($ExportPath.Substring($RepoRoot.Length).TrimStart('\', '/')) -replace '\\', '/'
    $ignored = Get-GitIgnoredEntries -RepoRoot $RepoRoot -RelativePath $relPath
    if ($null -eq $ignored) { Write-Warning "git nicht verfuegbar/kein Repo - .gitignore wird bei Export-Artefakten nicht beruecksichtigt." }
    # Einmaliger rekursiver Scan (statt pro Unterordner erneut) - relevant bei grossen
    # Baeumen wie node_modules unter export-artefacts/praesentationen.
    $allFiles = @(Get-FilesPruned -Path $ExportPath -RepoRoot $RepoRoot -Ignored $ignored)
    $topFolders = Get-ChildItem -LiteralPath $ExportPath -Directory
    $groups = @(foreach ($tf in $topFolders) {
        $prefix = $tf.FullName.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
        $filesIn = @($allFiles | Where-Object { $_.FullName.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) })
        [pscustomobject]@{
            Ordner          = $tf.Name
            Dateien         = $filesIn.Count
            LetzteAenderung = if ($filesIn.Count -gt 0) { ($filesIn | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime } else { $null }
        }
    })
    $rootFiles = @(Get-ChildItem -LiteralPath $ExportPath -File -ErrorAction SilentlyContinue)
    return [pscustomobject]@{
        TotalDateien = $allFiles.Count
        Gruppen      = $groups
        RootDateien  = @($rootFiles | ForEach-Object { $_.Name })
    }
}

# Findet alle Ordner unterhalb von export-artefacts/praesentationen/..., die eine
# slides.md enthalten - je einer pro getrackter Slidev-Praesentation.
function Get-SlidevDecks {
    param([string]$PraesentationenPath)
    $decks = @()
    if (-not (Test-Path -LiteralPath $PraesentationenPath)) { return $decks }
    $slideFiles = @(Get-ChildItem -LiteralPath $PraesentationenPath -Filter 'slides.md' -Recurse -File -ErrorAction SilentlyContinue)
    foreach ($sf in $slideFiles) {
        $relPath = ($sf.Directory.FullName.Substring($PraesentationenPath.Length).TrimStart('\', '/')) -replace '\\', '/'
        $decks += [pscustomobject]@{ Ordner = $sf.Directory.Name; Pfad = $relPath }
    }
    return $decks
}

# ===========================================================================
#  7. Anzeige-Funktionen (Konsole)
# ===========================================================================

function Show-HighLevelStatus {
    Write-SectionHeader 'High-Level Projekt-Status'
    if (Test-FolderOrWarn -Path $Paths.MemIndex -Label $MemIndexFolder) {
        $nodeCount = @(Get-ChildItem -LiteralPath $Paths.MemIndex -Filter '*.md' -File | Where-Object { $_.Name -match '^\d' }).Count
        $log = Get-LogEntries -MemIndexPath $Paths.MemIndex
        $ingestCount = @($log | Where-Object { $_.Type -eq 'ingest' }).Count
        $stakeholders = Get-Stakeholders -MemIndexPath $Paths.MemIndex
        $requirements = Get-AllRequirements -MemIndexPath $Paths.MemIndex
        $coverage = Get-IngestCoverage -MemIndexPath $Paths.MemIndex -InputDocsPath $Paths.InputDocs
        Write-Host "Mem-Index Nodes            : $nodeCount"
        Write-Host "Log-Eintraege gesamt        : $($log.Count) (davon $ingestCount ingest)"
        Write-Host "Stakeholder erfasst         : $($stakeholders.Count)"
        Write-Host "Requirements erfasst        : $($requirements.Count)"
        if ($coverage.RelevantTotal -gt 0) {
            Write-Host "Ingest-Abdeckung Client-Docs: $($coverage.PercentIngested) % ($($coverage.Ingested.Count)/$($coverage.RelevantTotal), ohne $($coverage.Ignored.Count) bewusst ignorierte), nicht erfasst: $($coverage.NotTracked.Count)"
        }
    }
    if (Test-FolderOrWarn -Path $Paths.AnalyseSprint -Label $AnalyseSprintFolder) {
        $sprints = Get-AnalyseSprintFiles -AnalyseSprintPath $Paths.AnalyseSprint
        Write-Host "Analyse-Sprint-Dateien      : $($sprints.Files.Count) (davon $($sprints.Workstreams.Count) Workstreams)"
    }
    if (Test-FolderOrWarn -Path $Paths.OpenSpec -Label $OpenSpecFolder) {
        $changes = Get-OpenSpecChanges -OpenSpecPath $Paths.OpenSpec
        $baseline = Get-OpenSpecBaselineAndArchive -OpenSpecPath $Paths.OpenSpec
        Write-Host "OpenSpec-Changes aktiv      : $($changes.Count) (Baseline-Specs: $($baseline.Baseline.Count), archiviert: $($baseline.Archiv.Count))"
        foreach ($c in $changes) { Write-Host "  - $($c.Name): $($c.Stufe)" -ForegroundColor DarkGray }
    }
    if (Test-FolderOrWarn -Path $Paths.ExportArtefacts -Label $ExportArtefactsFolder) {
        $export = Get-ExportArtefactsOverview -ExportPath $Paths.ExportArtefacts -RepoRoot $Paths.Root
        if ($export) { Write-Host "Export-Artefakte            : $($export.TotalDateien) Dateien in $($export.Gruppen.Count) Ordnern (ohne gitignorierte)" }
    }
}

function Show-IngestHistory {
    Write-SectionHeader 'Ingest-Historie'
    if (-not (Test-FolderOrWarn -Path $Paths.MemIndex -Label $MemIndexFolder)) { return }
    $history = Get-IngestHistory -MemIndexPath $Paths.MemIndex
    if ($history.Count -eq 0) { Write-Host 'Keine ingest-Eintraege in log.md gefunden.'; return }
    $history | Format-Table -Wrap -AutoSize | Out-String | Write-Host
}

function Show-Stakeholders {
    Write-SectionHeader 'Stakeholder'
    if (-not (Test-FolderOrWarn -Path $Paths.MemIndex -Label $MemIndexFolder)) { return }
    $stakeholders = Get-Stakeholders -MemIndexPath $Paths.MemIndex
    if ($stakeholders.Count -eq 0) { Write-Host '02_Stakeholder.md nicht gefunden oder keine Tabelle erkannt.'; return }
    $stakeholders | Format-Table -Wrap -AutoSize | Out-String | Write-Host
}

function Show-RequirementsNodeLevel {
    Write-SectionHeader 'Requirements - Node-Ebene Quellen'
    if (-not (Test-FolderOrWarn -Path $Paths.MemIndex -Label $MemIndexFolder)) { return }
    $requirements = Get-AllRequirements -MemIndexPath $Paths.MemIndex
    $mapping = Get-QuelldokumentMapping -MemIndexPath $Paths.MemIndex
    $nodeSources = @{}
    foreach ($m in $mapping) {
        foreach ($n in $m.Nodes) {
            if (-not $nodeSources.ContainsKey($n)) { $nodeSources[$n] = New-Object System.Collections.Generic.List[string] }
            if (-not $m.IsDerived) { $nodeSources[$n].Add($m.SourcePattern) }
        }
    }
    $rows = foreach ($r in $requirements) {
        $sources = if ($nodeSources.ContainsKey($r.Node)) { ($nodeSources[$r.Node] | Select-Object -Unique) -join ', ' } else { '' }
        [pscustomobject]@{ ID = $r.ID; Kind = $r.Kind; Titel = $r.Title; Node = $r.Node; NodeQuellen = $sources }
    }
    $rows | Format-Table -Wrap -AutoSize | Out-String | Write-Host
}

function Show-TraceabilityComparison {
    Write-SectionHeader 'Requirements - Traceability-Vergleich (Node- vs. ID-Ebene)'
    if (-not (Test-FolderOrWarn -Path $Paths.MemIndex -Label $MemIndexFolder)) { return }
    $cmp = Get-TraceabilityComparison -MemIndexPath $Paths.MemIndex
    if (-not $cmp) { Write-Host 'Keine Requirements gefunden.'; return }
    Write-Host "Requirements gesamt         : $($cmp.Total)"
    Write-Host "Node-Ebene (00_INDEX-Mapping): $($cmp.NodeMatchCount)/$($cmp.Total) rueckverfolgbar"
    Write-Host "ID-Ebene (heuristisch, log.md-Scan, best effort): $($cmp.IdMatchCount)/$($cmp.Total) mit direktem ID-Treffer"
    Write-Host "Verhaeltnis ID-Ebene / Node-Ebene: $($cmp.RatioPercent) %"
    Write-Host ''
    $cmp.Rows | Format-Table -Wrap -AutoSize | Out-String | Write-Host
}

function Show-IngestCoverage {
    Write-SectionHeader 'Ingest-Abdeckung Client-Docs'
    if (-not (Test-FolderOrWarn -Path $Paths.MemIndex -Label $MemIndexFolder)) { return }
    if (-not (Test-FolderOrWarn -Path $Paths.InputDocs -Label $InputDocsFolder)) { return }
    $coverage = Get-IngestCoverage -MemIndexPath $Paths.MemIndex -InputDocsPath $Paths.InputDocs
    if ($coverage.Total -eq 0) { Write-Host 'Keine Dateien im Input-Docs-Ordner gefunden.'; return }
    Write-Host "Gesamt Client-Docs             : $($coverage.Total)"
    Write-Host "Bewusst ignoriert              : $($coverage.Ignored.Count) (Duplikate/aktuell nicht wichtig, siehe 00_INDEX-Mapping)"
    Write-Host "Relevant (Gesamt - ignoriert)  : $($coverage.RelevantTotal)"
    Write-Host "Ingestet                       : $($coverage.Ingested.Count) ($($coverage.PercentIngested) % von relevant)"
    Write-Host "Nicht erfasst (Gap)            : $($coverage.NotTracked.Count)"
    if ($coverage.Ignored.Count -gt 0) {
        Write-Host ''
        Write-Host 'Bewusst ignorierte Dateien:' -ForegroundColor DarkGray
        $coverage.Ignored | ForEach-Object { Write-Host "  - $_" }
    }
    if ($coverage.NotTracked.Count -gt 0) {
        Write-Host ''
        Write-Host 'Noch nicht ingestete Dateien:' -ForegroundColor Yellow
        $coverage.NotTracked | ForEach-Object { Write-Host "  - $_" }
    }
}

function Show-AnalyseSprints {
    Write-SectionHeader 'Analyse-Sprints & Workstreams'
    if (-not (Test-FolderOrWarn -Path $Paths.AnalyseSprint -Label $AnalyseSprintFolder)) { return }
    $sprints = Get-AnalyseSprintFiles -AnalyseSprintPath $Paths.AnalyseSprint
    Write-Host "Analyse-Sprint-Dateien gesamt: $($sprints.Files.Count)"
    $sprints.Files | Sort-Object Datum | Format-Table Datum, Typ, Datei -AutoSize | Out-String | Write-Host
    Write-Host 'Erkannte Workstreams:' -ForegroundColor Yellow
    if ($sprints.Workstreams.Count -eq 0) { Write-Host '  (keine Workstream-Dateien gefunden)' }
    else { $sprints.Workstreams | Format-Table -AutoSize | Out-String | Write-Host }
    if ($sprints.Fortschritt.Count -gt 0) {
        Write-Host '_openspec-fortschritt/ Notizen:' -ForegroundColor Yellow
        $sprints.Fortschritt | ForEach-Object { Write-Host "  - $_" }
    }
}

function Show-OpenSpecStatus {
    Write-SectionHeader 'OpenSpec-Status'
    if (-not (Test-FolderOrWarn -Path $Paths.OpenSpec -Label $OpenSpecFolder)) { return }
    $changes = Get-OpenSpecChanges -OpenSpecPath $Paths.OpenSpec
    $baseline = Get-OpenSpecBaselineAndArchive -OpenSpecPath $Paths.OpenSpec
    if ($changes.Count -eq 0) { Write-Host 'Keine Changes unter openspec/changes gefunden.' }
    else { $changes | Select-Object Name, Proposal, Design, Specs, Tasks, Stufe | Format-Table -AutoSize | Out-String | Write-Host }
    Write-Host "Baseline-Specs (openspec/specs): $($baseline.Baseline.Count)"
    if ($baseline.Baseline.Count -gt 0) { $baseline.Baseline | ForEach-Object { Write-Host "  - $_" } }
    Write-Host "Archivierte Changes             : $($baseline.Archiv.Count)"
    if ($baseline.Archiv.Count -gt 0) { $baseline.Archiv | ForEach-Object { Write-Host "  - $_" } }
    if ($changes.Count -gt 0) {
        $answer = Read-Host 'Zusaetzlich npx openspec validate je Change ausfuehren? (j/N)'
        if ($answer -match '^[jJ]') {
            foreach ($c in $changes) { Invoke-OpenSpecValidate -OpenSpecPath $Paths.OpenSpec -ChangeName $c.Name }
        }
    }
}

function Show-ExportArtefacts {
    Write-SectionHeader 'Export-Artefakte'
    if (-not (Test-FolderOrWarn -Path $Paths.ExportArtefacts -Label $ExportArtefactsFolder)) { return }
    $overview = Get-ExportArtefactsOverview -ExportPath $Paths.ExportArtefacts -RepoRoot $Paths.Root
    if (-not $overview) { Write-Host 'Keine Export-Artefakte gefunden.'; return }
    Write-Host "Dateien gesamt (ohne gitignorierte): $($overview.TotalDateien)"
    if ($overview.RootDateien.Count -gt 0) {
        Write-Host 'Dateien im Root:' -ForegroundColor Yellow
        $overview.RootDateien | ForEach-Object { Write-Host "  - $_" }
    }
    $overview.Gruppen | Format-Table -AutoSize | Out-String | Write-Host
    $praesentationenPath = Join-Path $Paths.ExportArtefacts 'praesentationen'
    $decks = Get-SlidevDecks -PraesentationenPath $praesentationenPath
    if ($decks.Count -gt 0) {
        Write-Host 'Slidev-Praesentationen (Ordner mit slides.md):' -ForegroundColor Yellow
        $decks | Sort-Object Pfad | Format-Table Ordner, Pfad -AutoSize | Out-String | Write-Host
    }
}

# ===========================================================================
#  8. Vollstaendiger Report-Export (Markdown)
# ===========================================================================

function Export-FullReport {
    Write-SectionHeader 'Vollstaendigen Report exportieren'
    $timestamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $reportPath = Join-Path $Paths.Reports "status-report_$timestamp.md"
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("# Projekt-Status-Report")
    [void]$sb.AppendLine("Erstellt: $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
    [void]$sb.AppendLine('')

    if (Test-Path -LiteralPath $Paths.MemIndex) {
        [void]$sb.AppendLine('## Ingest-Historie')
        [void]$sb.AppendLine((ConvertTo-MarkdownTable -Objects (Get-IngestHistory -MemIndexPath $Paths.MemIndex)))

        [void]$sb.AppendLine('## Stakeholder')
        [void]$sb.AppendLine((ConvertTo-MarkdownTable -Objects (Get-Stakeholders -MemIndexPath $Paths.MemIndex)))

        [void]$sb.AppendLine('## Requirements - Node-Ebene Quellen')
        $requirements = Get-AllRequirements -MemIndexPath $Paths.MemIndex
        $mapping = Get-QuelldokumentMapping -MemIndexPath $Paths.MemIndex
        $nodeSources = @{}
        foreach ($m in $mapping) {
            foreach ($n in $m.Nodes) {
                if (-not $nodeSources.ContainsKey($n)) { $nodeSources[$n] = New-Object System.Collections.Generic.List[string] }
                if (-not $m.IsDerived) { $nodeSources[$n].Add($m.SourcePattern) }
            }
        }
        $reqRows = foreach ($r in $requirements) {
            $sources = if ($nodeSources.ContainsKey($r.Node)) { ($nodeSources[$r.Node] | Select-Object -Unique) -join ', ' } else { '' }
            [pscustomobject]@{ ID = $r.ID; Kind = $r.Kind; Titel = $r.Title; Node = $r.Node; NodeQuellen = $sources }
        }
        [void]$sb.AppendLine((ConvertTo-MarkdownTable -Objects $reqRows))

        [void]$sb.AppendLine('## Requirements - Traceability-Vergleich (Node- vs. ID-Ebene, heuristisch)')
        $cmp = Get-TraceabilityComparison -MemIndexPath $Paths.MemIndex
        if ($cmp) {
            [void]$sb.AppendLine("- Requirements gesamt: $($cmp.Total)")
            [void]$sb.AppendLine("- Node-Ebene rueckverfolgbar: $($cmp.NodeMatchCount)/$($cmp.Total)")
            [void]$sb.AppendLine("- ID-Ebene (heuristisch, best effort): $($cmp.IdMatchCount)/$($cmp.Total)")
            [void]$sb.AppendLine("- Verhaeltnis ID-Ebene / Node-Ebene: $($cmp.RatioPercent) %")
            [void]$sb.AppendLine('')
            [void]$sb.AppendLine((ConvertTo-MarkdownTable -Objects $cmp.Rows))
        }

        [void]$sb.AppendLine('## Ingest-Abdeckung Client-Docs')
        $coverage = Get-IngestCoverage -MemIndexPath $Paths.MemIndex -InputDocsPath $Paths.InputDocs
        if ($coverage.Total -gt 0) {
            [void]$sb.AppendLine("- Gesamt: $($coverage.Total), davon bewusst ignoriert: $($coverage.Ignored.Count) (Duplikate/aktuell nicht wichtig)")
            [void]$sb.AppendLine("- Relevant (Gesamt - ignoriert): $($coverage.RelevantTotal), Ingestet: $($coverage.Ingested.Count) ($($coverage.PercentIngested) %), Nicht erfasst: $($coverage.NotTracked.Count)")
            if ($coverage.NotTracked.Count -gt 0) {
                [void]$sb.AppendLine('')
                [void]$sb.AppendLine('Nicht erfasste Dateien:')
                foreach ($nt in $coverage.NotTracked) { [void]$sb.AppendLine("- $nt") }
            }
        }
        [void]$sb.AppendLine('')
    }

    if (Test-Path -LiteralPath $Paths.AnalyseSprint) {
        [void]$sb.AppendLine('## Analyse-Sprints & Workstreams')
        $sprints = Get-AnalyseSprintFiles -AnalyseSprintPath $Paths.AnalyseSprint
        [void]$sb.AppendLine((ConvertTo-MarkdownTable -Objects $sprints.Files))
        [void]$sb.AppendLine('### Workstreams')
        [void]$sb.AppendLine((ConvertTo-MarkdownTable -Objects $sprints.Workstreams))
    }

    if (Test-Path -LiteralPath $Paths.OpenSpec) {
        [void]$sb.AppendLine('## OpenSpec-Status')
        $changes = Get-OpenSpecChanges -OpenSpecPath $Paths.OpenSpec
        [void]$sb.AppendLine((ConvertTo-MarkdownTable -Objects ($changes | Select-Object Name, Proposal, Design, Specs, Tasks, Stufe)))
        $baseline = Get-OpenSpecBaselineAndArchive -OpenSpecPath $Paths.OpenSpec
        [void]$sb.AppendLine("- Baseline-Specs: $($baseline.Baseline -join ', ')")
        [void]$sb.AppendLine("- Archivierte Changes: $($baseline.Archiv -join ', ')")
        [void]$sb.AppendLine('')
    }

    if (Test-Path -LiteralPath $Paths.ExportArtefacts) {
        [void]$sb.AppendLine('## Export-Artefakte')
        $overview = Get-ExportArtefactsOverview -ExportPath $Paths.ExportArtefacts -RepoRoot $Paths.Root
        if ($overview) {
            [void]$sb.AppendLine("- Dateien gesamt (ohne gitignorierte): $($overview.TotalDateien)")
            [void]$sb.AppendLine((ConvertTo-MarkdownTable -Objects $overview.Gruppen))
        }
        $praesentationenPath = Join-Path $Paths.ExportArtefacts 'praesentationen'
        $decks = Get-SlidevDecks -PraesentationenPath $praesentationenPath
        if ($decks.Count -gt 0) {
            [void]$sb.AppendLine('### Slidev-Praesentationen (Ordner mit slides.md)')
            [void]$sb.AppendLine((ConvertTo-MarkdownTable -Objects ($decks | Sort-Object Pfad)))
        }
    }

    Write-FileUtf8NoBom -Path $reportPath -Content $sb.ToString()
    Write-Host "Report geschrieben nach: $reportPath" -ForegroundColor Green
}

# ===========================================================================
#  9. Interaktives Menue
# ===========================================================================

function Show-Menu {
    Write-Host ''
    Write-Host '=============================================' -ForegroundColor Cyan
    Write-Host ' Projekt-Status-Tool' -ForegroundColor Cyan
    Write-Host '=============================================' -ForegroundColor Cyan
    Write-Host " Projekt-Root: $($Paths.Root)"
    Write-Host ''
    Write-Host ' 1) High-Level Projekt-Status'
    Write-Host ' 2) Ingest-Historie (Client-Docs: was & wann)'
    Write-Host ' 3) Stakeholder-Liste'
    Write-Host ' 4) Requirements - Node-Ebene Quellen'
    Write-Host ' 5) Requirements - Traceability-Vergleich'
    Write-Host ' 6) Ingest-Abdeckung (%)'
    Write-Host ' 7) Analyse-Sprints & Workstreams'
    Write-Host ' 8) OpenSpec-Status'
    Write-Host ' 9) Export-Artefakte auflisten'
    Write-Host ' R) Vollstaendigen Report exportieren (Markdown)'
    Write-Host ' 0) Beenden'
}

# Nicht-interaktiver Einzelaufruf (z. B. durch /ingest-docs): fuehrt genau einen Menuepunkt aus
# und beendet, ohne das interaktive Menue je zu zeigen.
if ($Action -ne 'Menu') {
    switch ($Action) {
        'HighLevelStatus' { Show-HighLevelStatus }
        'IngestHistory' { Show-IngestHistory }
        'Stakeholders' { Show-Stakeholders }
        'RequirementsNodeLevel' { Show-RequirementsNodeLevel }
        'Traceability' { Show-TraceabilityComparison }
        'IngestCoverage' { Show-IngestCoverage }
        'AnalyseSprints' { Show-AnalyseSprints }
        'OpenSpecStatus' { Show-OpenSpecStatus }
        'ExportArtefacts' { Show-ExportArtefacts }
        'FullReport' { Export-FullReport }
    }
    return
}

do {
    Show-Menu
    $choice = Read-Host 'Auswahl'
    switch ($choice) {
        '1' { Show-HighLevelStatus }
        '2' { Show-IngestHistory }
        '3' { Show-Stakeholders }
        '4' { Show-RequirementsNodeLevel }
        '5' { Show-TraceabilityComparison }
        '6' { Show-IngestCoverage }
        '7' { Show-AnalyseSprints }
        '8' { Show-OpenSpecStatus }
        '9' { Show-ExportArtefacts }
        { $_ -in @('r', 'R') } { Export-FullReport }
        '0' { }
        default { Write-Warning "Ungueltige Auswahl: $choice" }
    }
} while ($choice -ne '0')
