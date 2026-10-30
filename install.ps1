<#
.SYNOPSIS
    Installs (or updates) the mandate-toolkit (bender) into a project folder - as plain files,
    without any git history or .git folder.

.DESCRIPTION
    Downloads the current state of a branch (default: main) as a zip archive from GitHub and
    copies only the toolkit payload into the target folder:

      bootstrap-wizard.ps1
      .toolkit/

    The archive contains no .git folder, so the target folder is never turned into (or nested
    with) a clone of the toolkit repo. If the target folder is part of the project's own git
    repository, the toolkit files simply become regular files of that repository.

    Re-running the script updates an existing installation: `.toolkit/` is replaced completely
    (it is toolkit-owned), `bootstrap-wizard.ps1` is overwritten. Nothing else in the target
    folder is touched.

.PARAMETER TargetDir
    Project folder to install into. Default: current directory. Created if missing.

.PARAMETER Branch
    Branch of the toolkit repo to install. Default: main.

.PARAMETER RunWizard
    Start bootstrap-wizard.ps1 in the target folder after the installation.

.EXAMPLE
    # One-liner (installs into the current directory):
    irm https://raw.githubusercontent.com/bfabricius/bender/main/install.ps1 | iex

.EXAMPLE
    # One-liner with parameters:
    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/bfabricius/bender/main/install.ps1))) -TargetDir C:\Projekte\mein-mandat -RunWizard

.EXAMPLE
    ./install.ps1 -TargetDir ..\mein-mandat
#>
[CmdletBinding()]
param(
    [string]$TargetDir = (Get-Location).Path,
    [string]$Branch = 'main',
    [switch]$RunWizard
)

$ErrorActionPreference = 'Stop'
$repo       = 'bfabricius/bender'
$archiveUrl = "https://github.com/$repo/archive/refs/heads/$Branch.zip"

# Windows PowerShell 5.1 does not enable TLS 1.2 by default.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

function Get-ToolkitVersion {
    param([string]$ToolkitDir)
    $versionFile = Join-Path $ToolkitDir 'toolkit-version.json'
    if (-not (Test-Path -LiteralPath $versionFile)) { return $null }
    try { return (Get-Content -LiteralPath $versionFile -Raw -Encoding UTF8 | ConvertFrom-Json).version } catch { return $null }
}

if (-not (Test-Path -LiteralPath $TargetDir)) {
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
}
$TargetDir = (Resolve-Path -LiteralPath $TargetDir).Path

$targetToolkit = Join-Path $TargetDir '.toolkit'
$targetWizard  = Join-Path $TargetDir 'bootstrap-wizard.ps1'
$oldVersion    = Get-ToolkitVersion -ToolkitDir $targetToolkit

Write-Host "mandate-toolkit ($repo@$Branch) -> $TargetDir" -ForegroundColor Cyan

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("bender-install-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
try {
    $zipPath = Join-Path $tempDir 'toolkit.zip'
    Write-Host "  Download: $archiveUrl" -ForegroundColor DarkGray
    Invoke-WebRequest -Uri $archiveUrl -OutFile $zipPath -UseBasicParsing

    $extractDir = Join-Path $tempDir 'extract'
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractDir -Force

    # GitHub archives contain a single top-level folder "<repo>-<branch>/".
    $srcRoot = Get-ChildItem -LiteralPath $extractDir -Directory | Select-Object -First 1
    if (-not $srcRoot) { throw "Archiv ist leer oder unerwartet aufgebaut: $archiveUrl" }
    $srcToolkit = Join-Path $srcRoot.FullName '.toolkit'
    $srcWizard  = Join-Path $srcRoot.FullName 'bootstrap-wizard.ps1'
    if (-not (Test-Path -LiteralPath $srcToolkit) -or -not (Test-Path -LiteralPath $srcWizard)) {
        throw "Archiv enthaelt kein .toolkit/ bzw. bootstrap-wizard.ps1 - falscher Branch? ($Branch)"
    }

    # Defensive: never carry git metadata or build caches into the project.
    Get-ChildItem -LiteralPath $srcToolkit -Recurse -Force -Directory |
        Where-Object { $_.Name -in @('.git', '__pycache__') } |
        Sort-Object { $_.FullName.Length } -Descending |
        Remove-Item -Recurse -Force

    if (Test-Path -LiteralPath $targetToolkit) {
        Remove-Item -LiteralPath $targetToolkit -Recurse -Force
    }
    Copy-Item -LiteralPath $srcToolkit -Destination $targetToolkit -Recurse -Force
    Copy-Item -LiteralPath $srcWizard -Destination $targetWizard -Force
} finally {
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

$newVersion = Get-ToolkitVersion -ToolkitDir $targetToolkit
if ($oldVersion) {
    Write-Host "  Toolkit aktualisiert: $oldVersion -> $newVersion" -ForegroundColor Green
} else {
    Write-Host "  Toolkit installiert: $newVersion" -ForegroundColor Green
}

if (Get-Command git -ErrorAction SilentlyContinue) {
    # Local 'Continue': under 'Stop', Windows PowerShell 5.1 turns git's stderr into a terminating error.
    $ErrorActionPreference = 'Continue'
    $repoTop = & git -C $TargetDir rev-parse --show-toplevel 2>$null
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -eq 0 -and $repoTop) {
        Write-Host "  Teil des Projekt-Repos: $repoTop (keine verschachtelte .git angelegt)" -ForegroundColor DarkGray
    }
}

if ($RunWizard) {
    & $targetWizard
} else {
    Write-Host ''
    Write-Host 'Naechster Schritt:' -ForegroundColor Cyan
    Write-Host "  cd `"$TargetDir`"; ./bootstrap-wizard.ps1"
}
