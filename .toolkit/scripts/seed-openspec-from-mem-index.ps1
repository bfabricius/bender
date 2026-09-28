<#
.SYNOPSIS
    Creates a reproducible OpenSpec seed package from a Memory Index.

.DESCRIPTION
    Drop this self-contained script into a project root after running
    install-openspec-sdd.ps1. It detects a Memory Index by its 00_INDEX.md,
    proposes relevant nodes, allows the selection to be changed interactively,
    and creates immutable input copies, a manifest, and a confirmed Copilot
    prompt below the local OpenSpec workspace.

.PARAMETER OpenSpecPath
    OpenSpec SDD workspace, absolute or relative to this script's folder.

.PARAMETER MemIndexPath
    Memory Index folder, absolute or relative to this script's folder.

.EXAMPLE
    ./seed-openspec-from-mem-index.ps1

.EXAMPLE
    ./seed-openspec-from-mem-index.ps1 -OpenSpecPath "tools/openspec-sdd" -MemIndexPath mem-index
#>
[CmdletBinding()]
param(
    [string]$OpenSpecPath,
    [string]$MemIndexPath
)

$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot

$excludedNames = @('00_INDEX.md', 'log.md', '_client-input-inventory.md')
$seedTopicPattern = '(?i)(requirement|anforder|spec(ification)?|use[ -]?case|persona|user[ -]?flow|workflow|constraint|vorgab|architecture|architektur|key[ -]?management|schl(ü|u)ssel|object[ -]?model|objekt[ -]?modell|data[ -]?model|datenmodell|conflict|konflikt|glossar|terminolog|scope|projektkontext|project[ -]?context|governance|open[ -]?question|offene[ -]?frage|risk|risik)'

function Read-YesNo {
    param([string]$Prompt, [bool]$DefaultYes = $true)

    $defaultHint = if ($DefaultYes) { 'J/n' } else { 'j/N' }
    do {
        $answer = (Read-Host "$Prompt [$defaultHint]").Trim()
        if ([string]::IsNullOrWhiteSpace($answer)) { return $DefaultYes }
        if ($answer -match '^(j|ja|y|yes)$') { return $true }
        if ($answer -match '^(n|nein|no)$') { return $false }
        Write-Warning 'Bitte j oder n eingeben.'
    } while ($true)
}

function Resolve-ProjectPath {
    param([string]$Path)

    $candidate = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $projectRoot $Path }
    return [System.IO.Path]::GetFullPath($candidate)
}

function Test-OpenSpecInstallation {
    param([string]$Path)

    return (Test-Path -LiteralPath $Path -PathType Container) -and
        (Test-Path -LiteralPath (Join-Path $Path 'openspec') -PathType Container) -and
        (Test-Path -LiteralPath (Join-Path $Path '.openspec-sdd-install.json') -PathType Leaf)
}

function Select-OpenSpecPath {
    param([string]$SuppliedPath)

    if ($SuppliedPath) {
        $resolved = Resolve-ProjectPath $SuppliedPath
        if (-not (Test-OpenSpecInstallation $resolved)) {
            throw "Keine gueltige OpenSpec-SDD-Installation gefunden: $resolved. Bitte zuerst ./install-openspec-sdd.ps1 ausfuehren."
        }
        return $resolved
    }

    $suggested = Join-Path $projectRoot 'openspec-sdd'
    if (Test-OpenSpecInstallation $suggested) {
        Write-Host "==> Gefundene OpenSpec-SDD-Installation: $suggested" -ForegroundColor Green
        if (Read-YesNo 'Diese Installation verwenden?' $true) { return $suggested }
    }

    do {
        $customPath = Read-Host 'Pfad zur OpenSpec-SDD-Installation eingeben (absolut oder relativ zum Projekt-Root)'
        if ([string]::IsNullOrWhiteSpace($customPath)) {
            Write-Warning 'Es wurde kein Pfad angegeben.'
            continue
        }
        $resolved = Resolve-ProjectPath $customPath
        if (Test-OpenSpecInstallation $resolved) { return $resolved }
        Write-Warning "Keine gueltige OpenSpec-SDD-Installation: $resolved"
    } while ($true)
}

function Find-MemoryIndexes {
    Get-ChildItem -Path $projectRoot -Recurse -File -Filter '00_INDEX.md' -ErrorAction SilentlyContinue |
        Where-Object {
            $_.FullName -notmatch '\\.git\\' -and
            $_.FullName -notmatch '\\openspec-sdd\\' -and
            $_.FullName -notmatch '\\node_modules\\' -and
            $_.FullName -notmatch '\\export-artefacts\\'
        } |
        Sort-Object { $_.DirectoryName.Length }
}

function Select-MemoryIndexPath {
    param([string]$SuppliedPath)

    if ($SuppliedPath) {
        $resolved = Resolve-ProjectPath $SuppliedPath
        if (-not (Test-Path -LiteralPath (Join-Path $resolved '00_INDEX.md') -PathType Leaf)) {
            throw "Im angegebenen Memory-Index wurde keine 00_INDEX.md gefunden: $resolved"
        }
        return $resolved
    }

    $hits = @(Find-MemoryIndexes)
    if ($hits.Count -gt 0) {
        $suggested = $hits[0].DirectoryName
        Write-Host "==> Vorgeschlagener Memory Index: $suggested" -ForegroundColor Cyan
        if ($hits.Count -gt 1) {
            Write-Warning 'Mehrere Memory Indexe wurden gefunden:'
            $hits | ForEach-Object { Write-Host "    $($_.DirectoryName)" -ForegroundColor DarkGray }
        }
        if (Read-YesNo 'Vorgeschlagenen Memory Index verwenden?' $true) { return $suggested }
    } else {
        Write-Warning 'Unterhalb des Projekt-Roots wurde kein Memory Index mit 00_INDEX.md gefunden.'
    }

    do {
        $customPath = Read-Host 'Pfad zum Memory Index eingeben (absolut oder relativ zum Projekt-Root)'
        if ([string]::IsNullOrWhiteSpace($customPath)) {
            Write-Warning 'Es wurde kein Pfad angegeben.'
            continue
        }
        $resolved = Resolve-ProjectPath $customPath
        if (Test-Path -LiteralPath (Join-Path $resolved '00_INDEX.md') -PathType Leaf) { return $resolved }
        Write-Warning "Keine 00_INDEX.md gefunden: $resolved"
    } while ($true)
}

function Read-NodeNumbers {
    param([string]$Text, [int]$Maximum)

    $numbers = New-Object System.Collections.Generic.List[int]
    foreach ($part in ($Text -split '[,;\s]+')) {
        if ([string]::IsNullOrWhiteSpace($part)) { continue }
        if ($part -match '^(\d+)-(\d+)$') {
            $start = [int]$matches[1]
            $end = [int]$matches[2]
            if ($start -gt $end) { throw "Ungueltiger Bereich: $part" }
            foreach ($number in $start..$end) {
                if ($number -lt 1 -or $number -gt $Maximum) { throw "Nummer ausserhalb des Bereichs: $number" }
                if (-not $numbers.Contains($number)) { [void]$numbers.Add($number) }
            }
        } elseif ($part -match '^\d+$') {
            $number = [int]$part
            if ($number -lt 1 -or $number -gt $Maximum) { throw "Nummer ausserhalb des Bereichs: $number" }
            if (-not $numbers.Contains($number)) { [void]$numbers.Add($number) }
        } else {
            throw "Ungueltige Eingabe: $part"
        }
    }
    return $numbers.ToArray()
}

function Get-InitialSeedNodeNames {
    param([System.IO.FileInfo[]]$Nodes)

    $recommended = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($node in $Nodes) {
        $documentTitle = ''
        try {
            $documentTitle = Get-Content -LiteralPath $node.FullName -TotalCount 40 -ErrorAction Stop |
                Where-Object { $_ -match '^#\s+' } |
                Select-Object -First 1
        } catch {
            Write-Warning "Node konnte fuer die Vorauswahl nicht gelesen werden: $($node.Name)"
        }
        if ($node.Name -match $seedTopicPattern -or $documentTitle -match $seedTopicPattern) {
            [void]$recommended.Add($node.Name)
        }
    }

    if ($recommended.Count -eq 0) {
        Write-Warning 'Keine inhaltlich passenden Nodes automatisch erkannt. Alle Nodes werden zur Auswahl vorausgewaehlt.'
        foreach ($node in $Nodes) { [void]$recommended.Add($node.Name) }
    }
    $recommended | ForEach-Object { [string]$_ }
}

function Select-MemoryNodes {
    param([System.IO.FileInfo[]]$Nodes)

    $selectedNumbers = @{}
    $initialNames = @(Get-InitialSeedNodeNames $Nodes)
    for ($index = 0; $index -lt $Nodes.Count; $index++) {
        if ($Nodes[$index].Name -in $initialNames) {
            $selectedNumbers[$index + 1] = $true
        }
    }

    do {
        Write-Host ''
        Write-Host 'Memory-Index-Nodes fuer den OpenSpec-Seed:' -ForegroundColor Cyan
        for ($index = 0; $index -lt $Nodes.Count; $index++) {
            $nodeNumber = $index + 1
            $marker = if ($selectedNumbers.ContainsKey($nodeNumber)) { 'x' } else { ' ' }
            $category = if ($selectedNumbers.ContainsKey($nodeNumber)) { 'Vorschlag' } else { 'Optional' }
            Write-Host ('  [{0}] {1,2}. {2} ({3})' -f $marker, ($index + 1), $Nodes[$index].Name, $category)
        }
        Write-Host '  Befehle: a <Nummern> hinzufuegen, e <Nummern> entfernen, f fertig, q abbrechen' -ForegroundColor DarkGray
        $command = (Read-Host 'Auswahl').Trim()
        if ($command -match '^(f|fertig)$') {
            if ($selectedNumbers.Count -eq 0) {
                Write-Warning 'Mindestens ein Node muss ausgewaehlt sein.'
                continue
            }
            return @($Nodes | ForEach-Object -Begin { $index = 0 } -Process {
                $index++
                if ($selectedNumbers.ContainsKey($index)) { $_ }
            })
        }
        if ($command -match '^(q|abbrechen)$') { throw 'Vom Benutzer abgebrochen.' }
        if ($command -match '^(a|add)\s+(.+)$') {
            $numberInput = $matches[2]
            try {
                $addedNodes = @()
                $nodeNumbers = @(Read-NodeNumbers -Text $numberInput -Maximum $Nodes.Count)
                Write-Host "Verarbeite Node-Nummern: $($nodeNumbers -join ', ')" -ForegroundColor DarkGray
                foreach ($nodeNumber in $nodeNumbers) {
                    $nodeName = $Nodes[$nodeNumber - 1].Name
                    if (-not $selectedNumbers.ContainsKey($nodeNumber)) {
                        $selectedNumbers[$nodeNumber] = $true
                        $addedNodes += $nodeName
                    }
                }
                if ($addedNodes.Count -gt 0) {
                    Write-Host "Hinzugefuegt: $($addedNodes -join ', ')" -ForegroundColor Green
                } else {
                    Write-Host 'Alle angegebenen Nodes waren bereits ausgewaehlt.' -ForegroundColor Yellow
                }
            } catch { Write-Warning $_.Exception.Message }
            continue
        }
        if ($command -match '^(e|entfernen|remove)\s+(.+)$') {
            $numberInput = $matches[2]
            try {
                $removedNodes = @()
                $nodeNumbers = @(Read-NodeNumbers -Text $numberInput -Maximum $Nodes.Count)
                Write-Host "Verarbeite Node-Nummern: $($nodeNumbers -join ', ')" -ForegroundColor DarkGray
                foreach ($nodeNumber in $nodeNumbers) {
                    $nodeName = $Nodes[$nodeNumber - 1].Name
                    if ($selectedNumbers.ContainsKey($nodeNumber)) {
                        [void]$selectedNumbers.Remove($nodeNumber)
                        $removedNodes += $nodeName
                    }
                }
                if ($removedNodes.Count -gt 0) {
                    Write-Host "Entfernt: $($removedNodes -join ', ')" -ForegroundColor Green
                } else {
                    Write-Host 'Keine der angegebenen Nodes war ausgewaehlt.' -ForegroundColor Yellow
                }
            } catch { Write-Warning $_.Exception.Message }
            continue
        }
        Write-Warning 'Ungueltiger Befehl.'
    } while ($true)
}

function New-CopilotSeedPrompt {
    param([string]$SeedFolder, [System.IO.FileInfo[]]$Nodes)

    $nodeList = ($Nodes | ForEach-Object { "- $($_.Name)" }) -join "`r`n"
    return @"
# Copilot-Auftrag: OpenSpec aus kuratiertem Memory Index seeden

Arbeite im OpenSpec-Workspace. Die nachstehenden Markdown-Dateien sind die
einzige Faktenbasis fuer diesen initialen Seed. Lies sie vollstaendig und
erstelle danach einen konkreten ersten OpenSpec-Change mit nachvollziehbaren
Anforderungen und Akzeptanzkriterien.

Quellpaket: $SeedFolder

Ausgewaehlte Quellen:
$nodeList

Regeln:
- Uebernimm bestehende IDs (z. B. UC-, FA-, NFA-, OP-) zur Rueckverfolgbarkeit.
- Erfinde keine fachlichen Fakten. Fehlende Informationen, Konflikte und offene
  Fragen werden explizit als Annahme bzw. Klaerungspunkt festgehalten.
- Beruecksichtige Prioritaeten, harte Constraints, Sicherheits- und
  Datenschutzanforderungen sowie Abhaengigkeiten.
- Trenne Plattformanforderungen und Fachanwendungsanforderungen, wenn die
  Quellen dies nahelegen.
- Nutze die vorhandenen OpenSpec-Konventionen und erstelle keine Dateien
  ausserhalb des OpenSpec-Workspaces ohne vorherige Zustimmung.
- Gib vor dem Abschluss eine kurze Traceability-Zusammenfassung aus: Quelle,
  uebernommene Anforderungen, offene Punkte.
"@
}

Write-Host ''
Write-Host 'OpenSpec aus Memory Index seeden' -ForegroundColor Cyan
Write-Host "  Projekt-Root: $projectRoot"

try {
    $openSpecRoot = Select-OpenSpecPath $OpenSpecPath
    Write-Host "==> OpenSpec-Installation: $openSpecRoot" -ForegroundColor Green

    $memoryIndexRoot = Select-MemoryIndexPath $MemIndexPath
    Write-Host "==> Memory Index: $memoryIndexRoot" -ForegroundColor Green

    $nodes = @(Get-ChildItem -LiteralPath $memoryIndexRoot -File -Filter '*.md' |
        Where-Object { $_.Name -notin $excludedNames } |
        Sort-Object Name)
    if ($nodes.Count -eq 0) { throw 'Der Memory Index enthaelt keine waehbaren Markdown-Nodes.' }

    $selectedNodes = @(Select-MemoryNodes $nodes)
    $timestamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $seedRoot = Join-Path $openSpecRoot 'seed-input'
    $seedFolder = Join-Path $seedRoot $timestamp
    $prompt = New-CopilotSeedPrompt $seedFolder $selectedNodes

    Write-Host ''
    Write-Host 'Folgende Quellen werden als Seed-Paket kopiert:' -ForegroundColor Cyan
    $selectedNodes | ForEach-Object { Write-Host "  - $($_.FullName)" }
    Write-Host ''
    Write-Host 'Folgender Copilot-Auftrag wird gespeichert:' -ForegroundColor Cyan
    Write-Host '------------------------------------------------------------' -ForegroundColor DarkGray
    Write-Host $prompt
    Write-Host '------------------------------------------------------------' -ForegroundColor DarkGray
    if (-not (Read-YesNo "Seed-Paket unter '$seedFolder' erzeugen?" $false)) {
        Write-Host '==> Abgebrochen. Es wurden keine Seed-Dateien erstellt.' -ForegroundColor Yellow
        exit 0
    }

    New-Item -ItemType Directory -Path $seedFolder -Force | Out-Null
    $manifestNodes = @()
    foreach ($node in $selectedNodes) {
        $destination = Join-Path $seedFolder $node.Name
        Copy-Item -LiteralPath $node.FullName -Destination $destination -ErrorAction Stop
        $manifestNodes += [ordered]@{
            file = $node.Name
            sourceRelativePath = $node.Name
            sha256 = (Get-FileHash -LiteralPath $node.FullName -Algorithm SHA256).Hash
        }
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText((Join-Path $seedFolder 'COPILOT_SEED_PROMPT.md'), $prompt, $utf8NoBom)
    $manifest = [ordered]@{
        createdAt = (Get-Date).ToString('o')
        memoryIndex = $memoryIndexRoot
        openSpecWorkspace = $openSpecRoot
        nodes = $manifestNodes
    } | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText((Join-Path $seedFolder 'manifest.json'), $manifest + "`r`n", $utf8NoBom)

    Write-Host ''
    Write-Host "==> Seed-Paket erfolgreich erstellt ($($selectedNodes.Count) Nodes)." -ForegroundColor Green
    Write-Host "    Paket: $seedFolder" -ForegroundColor Green
    Write-Host '    Naechster Schritt: COPILOT_SEED_PROMPT.md im OpenSpec-Kontext an Copilot uebergeben.' -ForegroundColor Cyan
} catch {
    Write-Host ''
    Write-Host "==> Seeding fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}