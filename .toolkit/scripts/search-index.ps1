<#
.SYNOPSIS
    Interaktive Volltext-Suche (REPL) ueber den gesamten Memory-Index (kein LLM/AI, reine
    Regex-/Fuzzy-String-Suche). Portables, self-contained, read-only PowerShell-Skript.

.DESCRIPTION
    Baut beim Start einen In-Memory-Volltext-Suchindex ueber alle Markdown-Dateien unter
    mem-index/ (Pflicht) sowie - falls vorhanden - analyse-sprint/ und openspec-sdd/ auf:
      - Pro Datei werden alle Zeilen tokenisiert (Woerter), inkl. laufendem Token-Index und
        der zuletzt gesehenen Ueberschrift ("Section") je Zeile.
      - Ein invertierter Index (Wort -> Fundstellen) erlaubt O(1)-Exaktsuche.
      - Ein nach Wortlaenge gebuckettes Vokabular erlaubt Fuzzy-Suche (Damerau-Levenshtein),
        ohne bei jeder Anfrage das gesamte Vokabular durchsuchen zu muessen - das Verfahren
        skaliert damit auch fuer groessere Memory-Indizes.

    Danach startet eine interaktive Such-Schleife (REPL): 1-n Stichwoerter eintippen
    (Leerzeichen-getrennt). Bei mehreren Stichwoertern zaehlt ein Treffer nur, wenn alle
    Stichwoerter in genau dieser Reihenfolge in derselben Datei vorkommen (nicht zwingend auf
    derselben Zeile). Die Suche ist case-insensitive und toleriert einfache Tippfehler
    (fehlender/vertauschter/falscher Buchstabe).

    Die Treffer werden als scrollbare Liste angezeigt. Mit den Pfeiltasten (hoch/runter) kann
    zwischen den Treffern gewechselt werden; der aktuell ausgewaehlte Treffer wird hervorgehoben
    und zeigt mehr Zeilen Kontext rund um die Fundstelle. Enter/Esc fuehrt zurueck zur Such-
    Eingabe, "q" beendet das Skript.

.PARAMETER ProjectRoot
    Wurzelordner des Projekts. Default: Ordner, in dem dieses Skript liegt.

.PARAMETER MemIndexFolder
    Name des Memory-Index-Ordners relativ zu ProjectRoot (Pflicht-Quelle). Default: "mem-index".

.PARAMETER AnalyseSprintFolder
    Name des Analyse-Sprint-Ordners relativ zu ProjectRoot. Nur einbezogen, falls vorhanden.
    Default: "analyse-sprint".

.PARAMETER OpenSpecFolder
    Name des OpenSpec-SDD-Ordners relativ zu ProjectRoot. Nur einbezogen, falls vorhanden.
    Default: "openspec-sdd".

.EXAMPLE
    ./search-index.ps1
    Baut den Volltext-Index auf und startet die interaktive Suche.
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot = $PSScriptRoot,
    [string]$MemIndexFolder = 'mem-index',
    [string]$AnalyseSprintFolder = 'analyse-sprint',
    [string]$OpenSpecFolder = 'openspec-sdd'
)

$ErrorActionPreference = 'Stop'

$Paths = [ordered]@{
    Root          = $ProjectRoot
    MemIndex      = Join-Path $ProjectRoot $MemIndexFolder
    AnalyseSprint = Join-Path $ProjectRoot $AnalyseSprintFolder
    OpenSpec      = Join-Path $ProjectRoot $OpenSpecFolder
}

# ===========================================================================
#  1. Datei-/Pfad-Hilfsfunktionen (Konvention wie in glossar-suche.ps1)
# ===========================================================================

function Read-TextFileLines {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    return [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)
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

# ===========================================================================
#  2. Scope-Ermittlung: welche Ordner/Dateien werden durchsucht
# ===========================================================================

function Get-SearchScopeFiles {
    param([hashtable]$Paths)

    if (-not (Test-Path -LiteralPath $Paths.MemIndex -PathType Container)) {
        throw "Memory-Index-Ordner nicht gefunden: $($Paths.MemIndex)"
    }

    $scopeFolders = @([pscustomobject]@{ Label = 'mem-index'; Path = $Paths.MemIndex })
    if (Test-Path -LiteralPath $Paths.AnalyseSprint -PathType Container) {
        $scopeFolders += [pscustomobject]@{ Label = 'analyse-sprint'; Path = $Paths.AnalyseSprint }
    }
    if (Test-Path -LiteralPath $Paths.OpenSpec -PathType Container) {
        $scopeFolders += [pscustomobject]@{ Label = 'openspec-sdd'; Path = $Paths.OpenSpec }
    }

    # Generischer Ausschluss versteckter Ordner (.git, .vscode, ...) und node_modules, damit das
    # Skript auch in anderen/fremden Projekten unauffaellig bleibt.
    $excludePattern = '[\\/]\.[^\\/]+[\\/]|[\\/]node_modules[\\/]'

    $files = New-Object System.Collections.Generic.List[object]
    foreach ($scope in $scopeFolders) {
        $mdFiles = Get-ChildItem -LiteralPath $scope.Path -Filter '*.md' -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch $excludePattern }
        foreach ($f in $mdFiles) {
            $files.Add([pscustomobject]@{
                FullPath = $f.FullName
                RelPath  = (Get-RelativePathString -BasePath $Paths.Root -FullPath $f.FullName)
                Scope    = $scope.Label
            })
        }
    }
    return $files
}

# ===========================================================================
#  3. Index-Aufbau: Tokenisierung, invertierter Index, Vokabular nach Laenge
# ===========================================================================

$Script:WordRegex    = [regex]'[\p{L}\p{Nd}_]+'
$Script:HeadingRegex = '^#{1,6}\s+(.*)$'

$Script:FileLinesCache    = @{}
$Script:OccurrencesByWord = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[object]]]::new()
$Script:VocabularyByLength = [System.Collections.Generic.Dictionary[int, System.Collections.Generic.List[string]]]::new()
$Script:VocabularySeen     = [System.Collections.Generic.HashSet[string]]::new()

function Add-VocabularyWord {
    param([string]$WordLower)
    if ($Script:VocabularySeen.Add($WordLower)) {
        $len = $WordLower.Length
        if (-not $Script:VocabularyByLength.ContainsKey($len)) {
            $Script:VocabularyByLength[$len] = New-Object System.Collections.Generic.List[string]
        }
        $Script:VocabularyByLength[$len].Add($WordLower)
    }
}

function New-FullTextIndex {
    param([System.Collections.Generic.List[object]]$Files)

    foreach ($file in $Files) {
        $lines = Read-TextFileLines -Path $file.FullPath
        if ($lines.Count -eq 0) { continue }
        $Script:FileLinesCache[$file.RelPath] = $lines

        $currentSection = $file.RelPath
        $tokenIndex = 0
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            $headingMatch = [regex]::Match($line, $Script:HeadingRegex)
            if ($headingMatch.Success) {
                $currentSection = $headingMatch.Groups[1].Value.Trim()
            }

            foreach ($tm in $Script:WordRegex.Matches($line)) {
                $word = $tm.Value
                $wordLower = $word.ToLowerInvariant()
                Add-VocabularyWord -WordLower $wordLower

                if (-not $Script:OccurrencesByWord.ContainsKey($wordLower)) {
                    $Script:OccurrencesByWord[$wordLower] = New-Object System.Collections.Generic.List[object]
                }
                $Script:OccurrencesByWord[$wordLower].Add([pscustomobject]@{
                    File       = $file.RelPath
                    Line       = $i + 1
                    Section    = $currentSection
                    TokenIndex = $tokenIndex
                    Word       = $word
                })
                $tokenIndex++
            }
        }
    }
}

# ===========================================================================
#  4. Fuzzy-Matching: Damerau-Levenshtein mit Laengen-Bucket-Pruning
# ===========================================================================

# Distanz-Obergrenze skaliert mit Wortlaenge: kurze Woerter sehr strikt, laengere toleranter.
function Get-MaxEditDistance {
    param([int]$Length)
    if ($Length -lt 3) { return 0 }
    elseif ($Length -lt 7) { return 1 }
    else { return 2 }
}

# Iterative Damerau-Levenshtein-Distanz (mit Transposition), Laengen-Vorfilter + Zeilen-Abbruch
# sobald die minimal moegliche Distanz einer Zeile bereits $MaxDistance ueberschreitet.
function Get-EditDistance {
    param([string]$A, [string]$B, [int]$MaxDistance)
    $lenA = $A.Length
    $lenB = $B.Length
    if ([Math]::Abs($lenA - $lenB) -gt $MaxDistance) { return $MaxDistance + 1 }

    $prev2 = New-Object 'int[]' ($lenB + 1)
    $prev  = New-Object 'int[]' ($lenB + 1)
    $curr  = New-Object 'int[]' ($lenB + 1)
    for ($j = 0; $j -le $lenB; $j++) { $prev[$j] = $j }

    for ($i = 1; $i -le $lenA; $i++) {
        $curr[0] = $i
        $rowMin = $curr[0]
        for ($j = 1; $j -le $lenB; $j++) {
            $cost = if ($A[$i - 1] -eq $B[$j - 1]) { 0 } else { 1 }
            $del = $prev[$j] + 1
            $ins = $curr[$j - 1] + 1
            $sub = $prev[$j - 1] + $cost
            $val = [Math]::Min([Math]::Min($del, $ins), $sub)
            if ($i -gt 1 -and $j -gt 1 -and $A[$i - 1] -eq $B[$j - 2] -and $A[$i - 2] -eq $B[$j - 1]) {
                $val = [Math]::Min($val, $prev2[$j - 2] + 1)
            }
            $curr[$j] = $val
            if ($val -lt $rowMin) { $rowMin = $val }
        }
        if ($rowMin -gt $MaxDistance) { return $MaxDistance + 1 }
        $prev2 = $prev.Clone()
        $prev = $curr.Clone()
    }
    return $prev[$lenB]
}

# Liefert alle Fundstellen eines Stichworts: exakte Treffer + (skaliert) fuzzy Treffer, nur ueber
# die nach Laenge passenden Vokabular-Buckets gescannt statt ueber das gesamte Vokabular.
function Get-KeywordMatches {
    param([string]$Keyword)

    $keywordLower = $Keyword.ToLowerInvariant()
    $maxDist = Get-MaxEditDistance -Length $keywordLower.Length
    $matchedWords = New-Object System.Collections.Generic.List[object]

    if ($Script:OccurrencesByWord.ContainsKey($keywordLower)) {
        $matchedWords.Add([pscustomobject]@{ Word = $keywordLower; MatchType = 'Exakt'; Distance = 0 })
    }

    if ($maxDist -gt 0) {
        $minLen = [Math]::Max(1, $keywordLower.Length - $maxDist)
        $maxLen = $keywordLower.Length + $maxDist
        for ($len = $minLen; $len -le $maxLen; $len++) {
            if (-not $Script:VocabularyByLength.ContainsKey($len)) { continue }
            foreach ($candidate in $Script:VocabularyByLength[$len]) {
                if ($candidate -eq $keywordLower) { continue }
                $dist = Get-EditDistance -A $keywordLower -B $candidate -MaxDistance $maxDist
                if ($dist -le $maxDist) {
                    $matchedWords.Add([pscustomobject]@{ Word = $candidate; MatchType = 'Fuzzy'; Distance = $dist })
                }
            }
        }
    }

    $occurrences = New-Object System.Collections.Generic.List[object]
    foreach ($mw in $matchedWords) {
        foreach ($occ in $Script:OccurrencesByWord[$mw.Word]) {
            $occurrences.Add([pscustomobject]@{
                File       = $occ.File
                Line       = $occ.Line
                Section    = $occ.Section
                TokenIndex = $occ.TokenIndex
                Word       = $occ.Word
                MatchType  = $mw.MatchType
                Distance   = $mw.Distance
            })
        }
    }
    return @($occurrences | Sort-Object File, TokenIndex)
}

# ===========================================================================
#  5. Reihenfolge-Suche ueber mehrere Stichwoerter (Scope: ganze Datei, beliebiger Abstand)
# ===========================================================================

function Find-FirstOccurrenceAfter {
    param([object[]]$SortedOccurrences, [int]$AfterTokenIndex)
    $lo = 0
    $hi = $SortedOccurrences.Count - 1
    $result = $null
    while ($lo -le $hi) {
        $mid = [int](($lo + $hi) / 2)
        if ($SortedOccurrences[$mid].TokenIndex -gt $AfterTokenIndex) {
            $result = $SortedOccurrences[$mid]
            $hi = $mid - 1
        }
        else {
            $lo = $mid + 1
        }
    }
    return $result
}

function Find-OrderedHits {
    param([object[]]$KeywordOccurrenceLists)

    if ($KeywordOccurrenceLists.Count -eq 1) {
        $hits = New-Object System.Collections.Generic.List[object]
        foreach ($occ in $KeywordOccurrenceLists[0]) { $hits.Add(@($occ)) }
        return $hits
    }

    $byFilePerKeyword = @()
    foreach ($list in $KeywordOccurrenceLists) {
        $grouped = @{}
        foreach ($occ in $list) {
            if (-not $grouped.ContainsKey($occ.File)) { $grouped[$occ.File] = New-Object System.Collections.Generic.List[object] }
            $grouped[$occ.File].Add($occ)
        }
        $byFilePerKeyword += , $grouped
    }

    $commonFiles = @($byFilePerKeyword[0].Keys)
    for ($k = 1; $k -lt $byFilePerKeyword.Count; $k++) {
        $commonFiles = @($commonFiles | Where-Object { $byFilePerKeyword[$k].ContainsKey($_) })
    }

    $hits = New-Object System.Collections.Generic.List[object]
    foreach ($file in $commonFiles) {
        $perKeywordSorted = @()
        foreach ($grouped in $byFilePerKeyword) {
            $perKeywordSorted += , @($grouped[$file] | Sort-Object TokenIndex)
        }

        foreach ($startOcc in $perKeywordSorted[0]) {
            $chain = New-Object System.Collections.Generic.List[object]
            $chain.Add($startOcc)
            $prevTokenIndex = $startOcc.TokenIndex
            $complete = $true
            for ($k = 1; $k -lt $perKeywordSorted.Count; $k++) {
                $next = Find-FirstOccurrenceAfter -SortedOccurrences $perKeywordSorted[$k] -AfterTokenIndex $prevTokenIndex
                if ($null -eq $next) { $complete = $false; break }
                $chain.Add($next)
                $prevTokenIndex = $next.TokenIndex
            }
            if ($complete) { $hits.Add(@($chain.ToArray())) }
        }
    }
    return $hits
}

# ===========================================================================
#  6. Treffer-Aufbereitung (Hit-Records) + Kontext-Auszug (lazy, nur bei Anzeige)
# ===========================================================================

function New-HitRecord {
    param([object[]]$Chain)

    $anchor = $Chain[0]
    $totalDistance = ($Chain | Measure-Object -Property Distance -Sum).Sum
    $isExact = -not ($Chain | Where-Object { $_.MatchType -eq 'Fuzzy' })
    $allLines = @($Chain | ForEach-Object { $_.Line } | Sort-Object -Unique)

    [pscustomobject]@{
        Node          = $anchor.File
        Section       = $anchor.Section
        PrimaryLine   = $anchor.Line
        AllLines      = $allLines
        MatchedWords  = @($Chain | ForEach-Object { $_.Word })
        IsExact       = [bool]$isExact
        TotalDistance = $totalDistance
    }
}

function Get-ContextExcerpt {
    param([object]$Hit, [int]$Radius)

    $lines = $Script:FileLinesCache[$Hit.Node]
    if (-not $lines) { return @() }
    $start = [Math]::Max(0, $Hit.PrimaryLine - 1 - $Radius)
    $end = [Math]::Min($lines.Count - 1, $Hit.PrimaryLine - 1 + $Radius)

    $result = New-Object System.Collections.Generic.List[string]
    for ($i = $start; $i -le $end; $i++) {
        $lineNum = $i + 1
        $marker = if ($lineNum -eq $Hit.PrimaryLine) { '>' } else { ' ' }
        $result.Add("$marker $lineNum| $($lines[$i].Trim())")
    }
    return $result.ToArray()
}

function Invoke-MemIndexSearch {
    param([string[]]$Keywords)

    $perKeywordOccurrences = @()
    foreach ($kw in $Keywords) {
        $occ = Get-KeywordMatches -Keyword $kw
        if ($occ.Count -eq 0) { return @() }
        $perKeywordOccurrences += , $occ
    }

    $chains = Find-OrderedHits -KeywordOccurrenceLists $perKeywordOccurrences
    $hits = @($chains | ForEach-Object { New-HitRecord -Chain $_ })
    $sorted = @($hits | Sort-Object @{Expression = 'IsExact'; Descending = $true }, TotalDistance, Node, PrimaryLine)

    # Mehrere Token-Treffer auf derselben Zeile(-nkombination) (z. B. "fundaro-fundaro-x") sollen
    # nicht als separate Treffer erscheinen - je Datei+Zeilen-Kombination nur den besten behalten.
    return @($sorted | Group-Object { "$($_.Node)|$($_.AllLines -join ',')" } | ForEach-Object { $_.Group[0] })
}

# ===========================================================================
#  7. Interaktive Trefferliste mit Pfeiltasten-Navigation
# ===========================================================================

function Show-InteractiveResults {
    param([object[]]$Hits, [string]$QueryText)

    $selected = 0
    $viewportSize = 10
    $viewportStart = 0

    while ($true) {
        if ($selected -lt $viewportStart) { $viewportStart = $selected }
        if ($selected -ge $viewportStart + $viewportSize) { $viewportStart = $selected - $viewportSize + 1 }
        $viewportEnd = [Math]::Min($Hits.Count - 1, $viewportStart + $viewportSize - 1)

        Clear-Host
        Write-Host "$($Hits.Count) Treffer fuer '$QueryText'" -ForegroundColor Cyan
        Write-Host ('=' * 70) -ForegroundColor DarkGray

        for ($i = $viewportStart; $i -le $viewportEnd; $i++) {
            $hit = $Hits[$i]
            $isSelected = ($i -eq $selected)
            $matchTag = if ($hit.IsExact) { 'exakt' } else { "fuzzy, Distanz $($hit.TotalDistance)" }
            $header = "[$($i + 1)/$($Hits.Count)] $($hit.Node) | $($hit.Section) | Zeile $($hit.AllLines -join ', ') ($matchTag)"

            if ($isSelected) {
                Write-Host $header -ForegroundColor Black -BackgroundColor Cyan
                $radius = 4
            }
            else {
                Write-Host $header -ForegroundColor White
                $radius = 1
            }

            $contextColor = if ($isSelected) { 'Yellow' } else { 'DarkGray' }
            foreach ($line in (Get-ContextExcerpt -Hit $hit -Radius $radius)) {
                Write-Host "    $line" -ForegroundColor $contextColor
            }
            Write-Host ''
        }

        Write-Host ('=' * 70) -ForegroundColor DarkGray
        Write-Host 'Pfeiltasten: Treffer wechseln | Enter/Esc: neue Suche | q: Beenden' -ForegroundColor DarkGray

        try {
            $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        }
        catch {
            Write-Warning 'Interaktive Tastatureingabe nicht verfuegbar (nicht-interaktives Terminal). Bitte in einem echten PowerShell-Terminal ausfuehren.'
            return 'quit'
        }

        switch ($key.VirtualKeyCode) {
            38 { if ($selected -gt 0) { $selected-- } }               # Pfeil hoch
            40 { if ($selected -lt $Hits.Count - 1) { $selected++ } } # Pfeil runter
            13 { return 'back' }                                      # Enter
            27 { return 'back' }                                      # Esc
            default {
                if ($key.Character -eq 'q' -or $key.Character -eq 'Q') { return 'quit' }
            }
        }
    }
}

# ===========================================================================
#  8. Hauptprogramm: Index bauen + interaktive Suchschleife
# ===========================================================================

if (-not (Test-Path -LiteralPath $Paths.MemIndex)) {
    Write-Warning "Memory-Index-Ordner nicht gefunden: $($Paths.MemIndex)"
    return
}

Write-Host 'Baue Volltext-Suchindex auf ...' -ForegroundColor DarkGray
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$scopeFiles = Get-SearchScopeFiles -Paths $Paths
New-FullTextIndex -Files $scopeFiles
$stopwatch.Stop()
$scopeLabels = ($scopeFiles | Select-Object -ExpandProperty Scope -Unique) -join ', '
Write-Host "Index bereit: $($scopeFiles.Count) Dateien ($scopeLabels), $($Script:OccurrencesByWord.Count) eindeutige Woerter ($($stopwatch.ElapsedMilliseconds) ms)." -ForegroundColor DarkGray

Write-Host ''
Write-Host '=============================================' -ForegroundColor Cyan
Write-Host ' Volltext-Suche - Memory-Index' -ForegroundColor Cyan
Write-Host '=============================================' -ForegroundColor Cyan
Write-Host '1-n Stichwoerter eingeben (Leerzeichen-getrennt).'
Write-Host 'Bei mehreren Stichwoertern muessen diese in genau dieser Reihenfolge in derselben'
Write-Host 'Datei vorkommen (case-insensitive, fuzzy bei einfachen Tippfehlern). "exit"/"q" zum Beenden.'

do {
    Write-Host ''
    $query = Read-Host 'Suche'
    if ([string]::IsNullOrWhiteSpace($query)) { continue }
    if ($query -in @('exit', 'q', 'quit')) { break }

    $keywords = @($query -split '\s+' | Where-Object { $_ })
    $results = Invoke-MemIndexSearch -Keywords $keywords

    if ($results.Count -eq 0) {
        Write-Host "Kein Treffer fuer '$query'." -ForegroundColor DarkYellow
        continue
    }

    $action = Show-InteractiveResults -Hits $results -QueryText $query
    if ($action -eq 'quit') { break }
} while ($true)

Write-Host ''
Write-Host 'Suche beendet.' -ForegroundColor DarkGray
