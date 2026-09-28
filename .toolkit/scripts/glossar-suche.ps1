<#
.SYNOPSIS
    Schnelle lokale Glossar-/ID-Suche fuer den Memory-Index (kein LLM/AI, reine String-/Regex-Suche).

.DESCRIPTION
    Portables, self-contained, read-only PowerShell-Skript nach dem Muster von project-status.ps1.
    Baut beim Start einen In-Memory-Suchindex aus drei Quellgruppen auf:
      1. SSOT-Glossar (mem-index/14_Glossar.md) - Begriff/Definition/Quelle-Tabellen.
      2. Strukturierte ID-Eintraege in allen anderen mem-index/*.md Dateien - erkannt ueber drei
         generische Muster (Tabellenzeile, Ueberschrift, Bullet-Punkt), nicht ueber fest verdrahtete
         Dateinamen/Spalten, damit neue Nodes/IDs automatisch mit erfasst werden.
      3. Arbeitsdefinitionen aus den "## 9. Glossar"-Abschnitten der Analyse-Sprint-Grundlagen-
         Dokumente (analyse-sprint/*.md) - klar als nicht-verbindlich gelabelt (SSOT bleibt 14_Glossar.md).

    Danach startet eine interaktive Such-Schleife (REPL): Suchbegriff/Abkuerzung/ID eintippen,
    sofort alle Treffer sehen (case-insensitive, exakte Treffer zuerst, dann Teilstring-Treffer).
    "exit" / "q" / "quit" beendet die Schleife.

.PARAMETER ProjectRoot
    Wurzelordner des Mandats. Default: Ordner, in dem dieses Skript liegt.

.PARAMETER MemIndexFolder
    Name des Memory-Index-Ordners relativ zu ProjectRoot. Default: "mem-index".

.PARAMETER AnalyseSprintFolder
    Name des Analyse-Sprint-Ordners relativ zu ProjectRoot. Default: "analyse-sprint".

.EXAMPLE
    ./glossar-suche.ps1
    Baut den Index auf und startet die interaktive Suche.
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot = $PSScriptRoot,
    [string]$MemIndexFolder = 'mem-index',
    [string]$AnalyseSprintFolder = 'analyse-sprint'
)

$ErrorActionPreference = 'Stop'

# Nicht-ASCII-Zeichen als Zeichencode statt Literal (siehe project-status.ps1-Konvention) - vermeidet
# Codepage-Probleme beim Lesen dieses Skripts unter Windows PowerShell 5.1 ohne BOM.
$Script:EmDash = [char]0x2014

$Paths = [ordered]@{
    Root          = $ProjectRoot
    MemIndex      = Join-Path $ProjectRoot $MemIndexFolder
    AnalyseSprint = Join-Path $ProjectRoot $AnalyseSprintFolder
}

# ===========================================================================
#  1. Markdown-Hilfsfunktionen (uebernommen aus project-status.ps1)
# ===========================================================================

function Read-TextFileLines {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    return [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)
}

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

# .NET Framework (Windows PowerShell 5.1) kennt kein [System.IO.Path]::GetRelativePath - eigene
# einfache Implementierung fuer den Fall, dass $FullPath unterhalb von $BasePath liegt.
function Get-RelativePathString {
    param([string]$BasePath, [string]$FullPath)
    $baseFull = [System.IO.Path]::GetFullPath($BasePath).TrimEnd('\', '/')
    $targetFull = [System.IO.Path]::GetFullPath($FullPath)
    if ($targetFull.StartsWith($baseFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        $rel = $targetFull.Substring($baseFull.Length).TrimStart('\', '/')
    }
    else {
        $rel = $targetFull
    }
    return ($rel -replace '\\', '/')
}

# Entfernt umschliessende Markdown-Bold-Sternchen ("**Text**" -> "Text").
function Remove-BoldMarkers {
    param([string]$Text)
    if (-not $Text) { return $Text }
    return ($Text.Trim() -replace '^\*\*(.*)\*\*$', '$1').Trim()
}

# ===========================================================================
#  2. Regex-Muster fuer ID-Erkennung (F-01, K-01, ST-01, T-VP-01, FA-05, UC-01, SE-02a, ...)
# ===========================================================================

$Script:IdPattern = '^([A-Z]{1,4}(?:-[A-Z]{1,4})?-\d{1,3}[a-z]?)$'
$Script:IdPatternLoose = '[A-Z]{1,4}(?:-[A-Z]{1,4})?-\d{1,3}[a-z]?'

# ===========================================================================
#  3. Quelle 1: SSOT-Glossar (mem-index/14_Glossar.md)
# ===========================================================================

function Get-SsotGlossarEntries {
    param([string]$FilePath, [string]$RelativePath)
    $entries = @()
    $lines = Read-TextFileLines -Path $FilePath
    if ($lines.Count -eq 0) { return $entries }
    foreach ($table in (Get-AllMarkdownTables -Lines $lines)) {
        $headerNames = @($table.HeaderLine.Trim('|') -split '\|' | ForEach-Object { $_.Trim() })
        if ($headerNames.Count -lt 2) { continue }
        if ($headerNames[0] -notmatch 'Begriff') { continue }
        foreach ($row in $table.Rows) {
            $props = $row.PSObject.Properties.Name
            $term = Remove-BoldMarkers -Text $row.($props[0])
            if (-not $term) { continue }
            $definition = if ($props.Count -gt 1) { $row.($props[1]) } else { '' }
            $quelle = if ($props.Count -gt 2) { $row.($props[2]) } else { '' }
            $entries += [pscustomobject]@{
                Id           = $null
                Term         = $term
                Definition   = $definition
                Xrefs        = (Get-WikiLinks -Text $quelle)
                SourceFile   = $RelativePath
                SourceLabel  = 'SSOT'
            }
        }
    }
    return $entries
}

# ===========================================================================
#  4. Quelle 2: Strukturierte ID-Eintraege in allen anderen mem-index/*.md Dateien
#     Drei generische Erkennungsmuster, unabhaengig von Dateiname/Spaltennamen.
# ===========================================================================

# Muster A: Tabellenzeile, deren erste Zelle exakt einer ID entspricht (Wert, nicht Spaltenname).
function Get-IdTableRowEntries {
    param([string[]]$Lines, [string]$RelativePath)
    $entries = @()
    foreach ($table in (Get-AllMarkdownTables -Lines $Lines)) {
        foreach ($row in $table.Rows) {
            $props = $row.PSObject.Properties.Name
            if ($props.Count -lt 2) { continue }
            $idCandidate = Remove-BoldMarkers -Text $row.($props[0])
            if ($idCandidate -notmatch $Script:IdPattern) { continue }
            $title = if ($props.Count -gt 1) { $row.($props[1]) } else { '' }
            $rest = @()
            for ($j = 2; $j -lt $props.Count; $j++) {
                $val = $row.($props[$j])
                if ($val) { $rest += "$($props[$j]): $val" }
            }
            $definition = if ($rest.Count -eq 1 -and $props.Count -eq 3) { $row.($props[2]) } else { $rest -join ' | ' }
            $entries += [pscustomobject]@{
                Id           = $idCandidate
                Term         = $title
                Definition   = $definition
                Xrefs        = @()
                SourceFile   = $RelativePath
                SourceLabel  = 'ID-Tabelle'
            }
        }
    }
    return $entries
}

# Muster B: "### ID -- Titel [`Tag`]" Ueberschrift, gefolgt von Bullet-/Fliesstext bis zur naechsten
# Ueberschrift. Erfasst z. B. K-01 (13_Offene-Konflikte.md), UC-/FA-/NFA-/OP-xx (03b_HighLevel-*.md).
function Get-IdHeaderEntries {
    param([string[]]$Lines, [string]$RelativePath)
    $entries = @()
    $headerRegex = '^###\s+(' + $Script:IdPatternLoose + ')\s+' + [regex]::Escape($Script:EmDash) + '\s+(.+?)\s*(?:`[^`]*`)?\s*$'
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $m = [regex]::Match($Lines[$i], $headerRegex)
        if (-not $m.Success) { continue }
        $id = $m.Groups[1].Value
        $title = $m.Groups[2].Value.Trim()
        $bodyLines = @()
        for ($j = $i + 1; $j -lt $Lines.Count; $j++) {
            if ($Lines[$j] -match '^#{2,3}\s') { break }
            $t = $Lines[$j].Trim()
            if ($t) { $bodyLines += ($t -replace '^-\s*', '') }
        }
        $body = $bodyLines -join ' | '
        if ($body.Length -gt 400) { $body = $body.Substring(0, 400) + "... (gekuerzt, Volltext: $RelativePath)" }
        $entries += [pscustomobject]@{
            Id           = $id
            Term         = $title
            Definition   = $body
            Xrefs        = (Get-WikiLinks -Text $body)
            SourceFile   = $RelativePath
            SourceLabel  = 'ID-Tabelle'
        }
    }
    return $entries
}

# Muster C: "- **ID Titel** (Typ): Definition" bzw. "- **ID Titel:** Definition" Bullet-Zeile.
# Erfasst z. B. ST-01/02/03, SE-02a/02b (12_Objektmodell.md).
function Get-IdBulletEntries {
    param([string[]]$Lines, [string]$RelativePath)
    $entries = @()
    $bulletRegex = '^\s*-\s+\*\*(' + $Script:IdPatternLoose + ')\s*([^*]*?)\*\*\s*(?:\(([^)]*)\))?\s*:?\s*(.*)$'
    foreach ($line in $Lines) {
        $m = [regex]::Match($line, $bulletRegex)
        if (-not $m.Success) { continue }
        $id = $m.Groups[1].Value
        $title = $m.Groups[2].Value.Trim()
        $typeHint = $m.Groups[3].Value.Trim()
        $definition = $m.Groups[4].Value.Trim()
        if ($typeHint) { $title = "$title ($typeHint)" }
        $entries += [pscustomobject]@{
            Id           = $id
            Term         = $title.Trim()
            Definition   = $definition
            Xrefs        = (Get-WikiLinks -Text $definition)
            SourceFile   = $RelativePath
            SourceLabel  = 'ID-Tabelle'
        }
    }
    return $entries
}

function Get-IdEntriesFromFile {
    param([string]$FilePath, [string]$RelativePath)
    $lines = Read-TextFileLines -Path $FilePath
    if ($lines.Count -eq 0) { return @() }
    $entries = @()
    $entries += Get-IdTableRowEntries -Lines $lines -RelativePath $RelativePath
    $entries += Get-IdHeaderEntries -Lines $lines -RelativePath $RelativePath
    $entries += Get-IdBulletEntries -Lines $lines -RelativePath $RelativePath
    return $entries
}

# ===========================================================================
#  5. Quelle 3: Arbeitsdefinitionen in Analyse-Sprint-Grundlagen-Dokumenten
# ===========================================================================

function Get-ArbeitsdefinitionEntries {
    param([string]$AnalyseSprintPath, [string]$ProjectRootPath)
    $entries = @()
    if (-not (Test-Path -LiteralPath $AnalyseSprintPath)) { return $entries }
    $files = Get-ChildItem -LiteralPath $AnalyseSprintPath -Filter '*.md' -File -ErrorAction SilentlyContinue
    foreach ($file in $files) {
        $lines = Read-TextFileLines -Path $file.FullName
        if ($lines.Count -eq 0) { continue }
        $glossarLineIdx = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^##\s+9\.\s+Glossar') { $glossarLineIdx = $i; break }
        }
        if ($glossarLineIdx -lt 0) { continue }
        $relPath = Get-RelativePathString -BasePath $ProjectRootPath -FullPath $file.FullName
        $tailLines = $lines[$glossarLineIdx..($lines.Count - 1)]
        foreach ($table in (Get-AllMarkdownTables -Lines $tailLines)) {
            foreach ($row in $table.Rows) {
                $props = $row.PSObject.Properties.Name
                if ($props.Count -lt 2) { continue }
                $term = $row.($props[0]).Trim()
                if (-not $term) { continue }
                $definition = if ($props.Count -eq 2) {
                    $row.($props[1])
                }
                else {
                    (1..($props.Count - 1) | ForEach-Object { $row.($props[$_]) }) -join ' - '
                }
                $entries += [pscustomobject]@{
                    Id           = $null
                    Term         = $term
                    Definition   = $definition
                    Xrefs        = @()
                    SourceFile   = $relPath
                    SourceLabel  = 'Arbeitsdefinition'
                }
            }
        }
    }
    return $entries
}

# ===========================================================================
#  6. Index-Aufbau
# ===========================================================================

function New-SearchIndex {
    param([hashtable]$Paths)
    $index = New-Object System.Collections.Generic.List[object]

    $glossarPath = Join-Path $Paths.MemIndex '14_Glossar.md'
    if (Test-Path -LiteralPath $glossarPath) {
        $glossarRel = Get-RelativePathString -BasePath $Paths.Root -FullPath $glossarPath
        foreach ($e in (Get-SsotGlossarEntries -FilePath $glossarPath -RelativePath $glossarRel)) {
            $index.Add($e)
        }
    }

    if (Test-Path -LiteralPath $Paths.MemIndex) {
        $memFiles = Get-ChildItem -LiteralPath $Paths.MemIndex -Filter '*.md' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne '14_Glossar.md' }
        foreach ($file in $memFiles) {
            $relPath = Get-RelativePathString -BasePath $Paths.Root -FullPath $file.FullName
            foreach ($e in (Get-IdEntriesFromFile -FilePath $file.FullName -RelativePath $relPath)) {
                $index.Add($e)
            }
        }
    }

    foreach ($e in (Get-ArbeitsdefinitionEntries -AnalyseSprintPath $Paths.AnalyseSprint -ProjectRootPath $Paths.Root)) {
        $index.Add($e)
    }

    return $index
}

# ===========================================================================
#  7. Suche
# ===========================================================================

function Find-IndexEntries {
    param([string]$Query, [System.Collections.Generic.List[object]]$Index)
    $q = $Query.Trim()
    if (-not $q) { return @() }

    $labelRank = @{ 'SSOT' = 0; 'ID-Tabelle' = 1; 'Arbeitsdefinition' = 2 }

    $exact = $Index | Where-Object {
        ($_.Id -and $_.Id -ieq $q) -or ($_.Term -and $_.Term -ieq $q)
    }
    $substring = $Index | Where-Object {
        (-not (($_.Id -and $_.Id -ieq $q) -or ($_.Term -and $_.Term -ieq $q))) -and (
            ($_.Id -and $_.Id -match [regex]::Escape($q)) -or
            ($_.Term -and $_.Term -match [regex]::Escape($q)) -or
            ($_.Definition -and $_.Definition -match [regex]::Escape($q))
        )
    }

    $exactSorted = @($exact | Sort-Object { $labelRank[$_.SourceLabel] }, SourceFile)
    $substringSorted = @($substring | Sort-Object { $labelRank[$_.SourceLabel] }, SourceFile)

    $result = New-Object System.Collections.Generic.List[object]
    foreach ($e in $exactSorted) { $result.Add([pscustomobject]@{ Entry = $e; MatchType = 'Exakt' }) }
    foreach ($e in $substringSorted) { $result.Add([pscustomobject]@{ Entry = $e; MatchType = 'Teilstring' }) }
    return $result
}

# ===========================================================================
#  8. Ausgabe
# ===========================================================================

function Show-SearchResults {
    param([System.Collections.Generic.List[object]]$Results, [string]$Query)

    if ($Results.Count -eq 0) {
        Write-Host "Kein Treffer fuer '$Query' in Glossar / ID-Eintraegen / Arbeitsdefinitionen." -ForegroundColor DarkYellow
        return
    }

    Write-Host ''
    foreach ($r in $Results) {
        $entry = $r.Entry
        $color = switch ($entry.SourceLabel) {
            'SSOT' { 'Green' }
            'ID-Tabelle' { 'Cyan' }
            'Arbeitsdefinition' { 'Yellow' }
            default { 'White' }
        }
        $labelTag = "[$($entry.SourceLabel)]"
        $namePart = if ($entry.Id) { "$($entry.Id) - $($entry.Term)" } else { $entry.Term }
        Write-Host "$labelTag $namePart" -ForegroundColor $color -NoNewline
        Write-Host " ($($r.MatchType))" -ForegroundColor DarkGray
        if ($entry.Definition) { Write-Host "    $($entry.Definition -replace '\*\*', '')" }
        Write-Host "    Quelle: $($entry.SourceFile)" -ForegroundColor DarkGray
        if ($entry.Xrefs -and $entry.Xrefs.Count -gt 0) {
            Write-Host "    Siehe auch: $($entry.Xrefs -join ', ')" -ForegroundColor DarkGray
        }
        Write-Host ''
    }
}

# ===========================================================================
#  9. Hauptprogramm: Index bauen + interaktive Suchschleife
# ===========================================================================

if (-not (Test-Path -LiteralPath $Paths.MemIndex)) {
    Write-Warning "Memory-Index-Ordner nicht gefunden: $($Paths.MemIndex)"
    return
}

Write-Host 'Baue Suchindex auf ...' -ForegroundColor DarkGray
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$SearchIndex = New-SearchIndex -Paths $Paths
$stopwatch.Stop()
Write-Host "Index bereit: $($SearchIndex.Count) Eintraege aus mem-index/ und analyse-sprint/ ($($stopwatch.ElapsedMilliseconds) ms)." -ForegroundColor DarkGray

Write-Host ''
Write-Host '=============================================' -ForegroundColor Cyan
Write-Host ' Glossar-/ID-Suche - Kaeppeli Digital Fundaro' -ForegroundColor Cyan
Write-Host '=============================================' -ForegroundColor Cyan
Write-Host 'Suchbegriff, Abkuerzung oder ID eingeben. "exit" / "q" zum Beenden.'

do {
    Write-Host ''
    $query = Read-Host 'Suche'
    if ([string]::IsNullOrWhiteSpace($query)) { continue }
    if ($query -in @('exit', 'q', 'quit')) { break }
    $results = Find-IndexEntries -Query $query -Index $SearchIndex
    Show-SearchResults -Results $results -Query $query
} while ($true)
