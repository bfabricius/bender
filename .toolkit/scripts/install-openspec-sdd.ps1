<#
.SYNOPSIS
    Installs and initializes a local OpenSpec SDD workspace.

.DESCRIPTION
    Drop this self-contained script into the root of a project and run it there.
    By default it initializes OpenSpec in ./openspec-sdd. The target is kept out
    of the parent Git repository by a confirmed .gitignore entry; this script
    never creates a nested Git repository.

.PARAMETER InstallPath
    Target folder, absolute or relative to the folder containing this script.

.PARAMETER PackageVersion
    OpenSpec npm package version. Defaults to latest.

.PARAMETER Tools
    Comma-separated OpenSpec AI-tool IDs. When omitted, the script asks which
    of the common tools to configure. Use all or none only deliberately.

.PARAMETER Language
    Language for newly created OpenSpec artifacts. Defaults to de.

.PARAMETER CopilotCloud
    Also create GitHub Copilot cloud coding-agent files.

.PARAMETER SkipGitIgnore
    Do not offer to add the target folder to the parent .gitignore.

.EXAMPLE
    ./install-openspec-sdd.ps1

.EXAMPLE
    ./install-openspec-sdd.ps1 -InstallPath "tools/openspec-sdd"

.EXAMPLE
    ./install-openspec-sdd.ps1 -Tools github-copilot -Language de

.EXAMPLE
    ./install-openspec-sdd.ps1 -Tools "github-copilot,claude,codex,cursor,cline"
#>
[CmdletBinding()]
param(
    [string]$InstallPath,
    [string]$PackageVersion = 'latest',
    [string]$Tools,
    [string]$Language = 'de',
    [switch]$CopilotCloud,
    [switch]$SkipGitIgnore
)

$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot

function Read-YesNo {
    param(
        [string]$Prompt,
        [bool]$DefaultYes = $true
    )

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

    $candidate = if ([System.IO.Path]::IsPathRooted($Path)) {
        $Path
    } else {
        Join-Path $projectRoot $Path
    }
    return [System.IO.Path]::GetFullPath($candidate)
}

function Select-OpenSpecTools {
    param([string]$SuppliedTools)

    if (-not [string]::IsNullOrWhiteSpace($SuppliedTools)) {
        return $SuppliedTools.Trim()
    }

    $commonTools = @(
        [pscustomobject]@{ Id = 'github-copilot'; Name = 'GitHub Copilot' },
        [pscustomobject]@{ Id = 'claude'; Name = 'Claude Code' },
        [pscustomobject]@{ Id = 'codex'; Name = 'Codex' },
        [pscustomobject]@{ Id = 'cursor'; Name = 'Cursor' },
        [pscustomobject]@{ Id = 'cline'; Name = 'Cline' }
    )

    Write-Host ''
    Write-Host 'KI-Tools fuer OpenSpec konfigurieren:' -ForegroundColor Cyan
    for ($index = 0; $index -lt $commonTools.Count; $index++) {
        Write-Host "  [$($index + 1)] $($commonTools[$index].Name) ($($commonTools[$index].Id))"
    }
    Write-Host '  Mehrere Nummern mit Komma trennen, z. B. 1,2,4.' -ForegroundColor DarkGray
    Write-Host '  Enter = GitHub Copilot; a = alle fuenf Tools.' -ForegroundColor DarkGray

    do {
        $answer = (Read-Host 'Auswahl').Trim()
        if ([string]::IsNullOrWhiteSpace($answer)) { return 'github-copilot' }
        if ($answer -match '^(a|alle|all)$') { return (($commonTools | ForEach-Object Id) -join ',') }
        try {
            $selected = New-Object System.Collections.Generic.List[string]
            foreach ($part in ($answer -split '[,;\s]+')) {
                if ($part -notmatch '^\d+$') { throw "Ungueltige Auswahl: $part" }
                $number = [int]$part
                if ($number -lt 1 -or $number -gt $commonTools.Count) { throw "Nummer ausserhalb des Bereichs: $number" }
                $toolId = $commonTools[$number - 1].Id
                if (-not $selected.Contains($toolId)) { $selected.Add($toolId) }
            }
            if ($selected.Count -gt 0) { return ($selected -join ',') }
        } catch {
            Write-Warning $_.Exception.Message
        }
    } while ($true)
}

function Test-PathInsideProject {
    param([string]$Path)

    $rootWithSeparator = $projectRoot.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    return $Path.StartsWith($rootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)
}

function Invoke-NpxOpenSpec {
    param([string[]]$Arguments)

    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & npx @Arguments 2>&1 | Write-Host
        if ($LASTEXITCODE -ne 0) {
            throw "OpenSpec-Befehl fehlgeschlagen (Exit-Code $LASTEXITCODE)."
        }
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }
}

function Add-GitIgnoreEntry {
    param([string]$TargetPath)

    if (-not (Test-PathInsideProject $TargetPath)) {
        Write-Warning 'Ziel liegt ausserhalb des Projekt-Roots. .gitignore wird nicht angepasst.'
        return $false
    }

    $relativePath = $TargetPath.Substring($projectRoot.Length).TrimStart('\', '/') -replace '\\', '/'
    $entry = "$relativePath/"
    $gitIgnorePath = Join-Path $projectRoot '.gitignore'
    $currentContent = if (Test-Path -LiteralPath $gitIgnorePath) {
        [System.IO.File]::ReadAllText($gitIgnorePath)
    } else {
        ''
    }

    if ($currentContent -split "`r?`n" | Where-Object { $_.Trim() -eq $entry }) {
        Write-Host "==> .gitignore enthaelt bereits: $entry" -ForegroundColor Green
        return $true
    }

    Write-Host "==> Vorgesehener .gitignore-Eintrag: $entry" -ForegroundColor Yellow
    if (-not (Read-YesNo 'Lokalen OpenSpec-Ordner aus dem Hauptprojekt ausschliessen?' $true)) {
        Write-Warning 'OpenSpec wurde installiert, aber nicht zur .gitignore hinzugefuegt.'
        return $false
    }

    $append = if ([string]::IsNullOrWhiteSpace($currentContent)) {
        "# Local OpenSpec SDD workspace (managed by install-openspec-sdd.ps1)`r`n$entry`r`n"
    } else {
        "`r`n# Local OpenSpec SDD workspace (managed by install-openspec-sdd.ps1)`r`n$entry`r`n"
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($gitIgnorePath, $currentContent + $append, $utf8NoBom)
    Write-Host "==> .gitignore aktualisiert: $entry" -ForegroundColor Green
    return $true
}

Write-Host ''
Write-Host 'OpenSpec SDD installieren' -ForegroundColor Cyan
Write-Host "  Projekt-Root: $projectRoot"
$Tools = Select-OpenSpecTools $Tools

if ($InstallPath) {
    $targetPath = Resolve-ProjectPath $InstallPath
} else {
    $suggestedPath = Join-Path $projectRoot 'openspec-sdd'
    Write-Host "  Vorgeschlagenes Ziel: $suggestedPath" -ForegroundColor Cyan
    if (Read-YesNo 'Diesen Zielordner verwenden?' $true) {
        $targetPath = $suggestedPath
    } else {
        do {
            $customPath = Read-Host 'Alternativen Zielpfad eingeben (absolut oder relativ zum Projekt-Root)'
            if ([string]::IsNullOrWhiteSpace($customPath)) {
                Write-Warning 'Es wurde kein Zielpfad angegeben.'
                continue
            }
            $targetPath = Resolve-ProjectPath $customPath
            break
        } while ($true)
    }
}

Write-Host "  Gewaehltes Ziel: $targetPath" -ForegroundColor Cyan
if (Test-Path -LiteralPath $targetPath) {
    Write-Host ''
    Write-Host "==> Installation abgebrochen: Zielordner existiert bereits. Es wurde nichts veraendert: $targetPath" -ForegroundColor Red
    exit 1
}

foreach ($command in @('node', 'npm', 'npx')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Voraussetzung fehlt: '$command' wurde nicht im PATH gefunden. Bitte Node.js LTS inklusive npm installieren."
    }
}

Write-Host '==> Node.js- und npm-Voraussetzungen sind vorhanden.' -ForegroundColor Green
Write-Host "==> Initialisiere OpenSpec (@fission-ai/openspec@$PackageVersion) ..." -ForegroundColor Yellow
Write-Host "    KI-Tool: $Tools" -ForegroundColor Cyan
Write-Host "    Artefakt-Sprache: $Language" -ForegroundColor Cyan

$targetCreated = $false
try {
    New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
    $targetCreated = $true
    Push-Location $targetPath
    try {
        $initArguments = @(
            '--yes',
            "@fission-ai/openspec@$PackageVersion",
            'init',
            '--tools', $Tools,
            '--language', $Language,
            '--no-animation'
        )
        if ($CopilotCloud) {
            $initArguments += '--copilot-cloud'
        } else {
            $initArguments += '--no-copilot-cloud'
        }
        Invoke-NpxOpenSpec $initArguments
    } finally {
        Pop-Location
    }

    $nestedGit = Join-Path $targetPath '.git'
    if (Test-Path -LiteralPath $nestedGit) {
        throw "OpenSpec hat unerwartet ein verschachteltes Git-Repository erzeugt: $nestedGit. Installation wird nicht als gueltig akzeptiert."
    }

    $openSpecDirectory = Join-Path $targetPath 'openspec'
    if (-not (Test-Path -LiteralPath $openSpecDirectory -PathType Container)) {
        throw "Die erwartete OpenSpec-Struktur wurde nicht gefunden: $openSpecDirectory"
    }

    $marker = [ordered]@{
        package = '@fission-ai/openspec'
        version = $PackageVersion
        initializedAt = (Get-Date).ToString('o')
        initializedBy = 'install-openspec-sdd.ps1'
    } | ConvertTo-Json
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText((Join-Path $targetPath '.openspec-sdd-install.json'), $marker + "`r`n", $utf8NoBom)

    $gitIgnoreProtected = $false
    if (-not $SkipGitIgnore) {
        $gitIgnoreProtected = Add-GitIgnoreEntry $targetPath
    }

    Write-Host ''
    Write-Host '==> OpenSpec SDD erfolgreich initialisiert.' -ForegroundColor Green
    Write-Host "    Ziel: $targetPath" -ForegroundColor Green
    Write-Host "    Struktur: $openSpecDirectory" -ForegroundColor Green
    Write-Host "    Git-Schutz: $(if ($gitIgnoreProtected) { 'aktiv' } else { 'nicht aktiv' })" -ForegroundColor $(if ($gitIgnoreProtected) { 'Green' } else { 'Yellow' })
    Write-Host "    Naechster Schritt: ./seed-openspec-from-mem-index.ps1 -OpenSpecPath `"$targetPath`"" -ForegroundColor Cyan
} catch {
    Write-Host ''
    Write-Host "==> Installation fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red
    if ($targetCreated) {
        Write-Warning "Der angelegte Zielordner wurde aus Sicherheitsgruenden nicht automatisch geloescht: $targetPath"
    }
    exit 1
}