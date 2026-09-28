<#
.SYNOPSIS
    Optionales Pre-Processing-Tool: extrahiert Klartext aus DOCX/PPTX/PDF fuer den /ingest-docs Slash-Agent.

.DESCRIPTION
    Wird typischerweise vom /ingest-docs Slash-Agent aufgerufen, wenn ein Dokument sich beim
    direkten Lesen als schwer auswertbar erweist (z. B. rohes DOCX/PPTX-Binaerformat oder ein PDF
    ohne direkt extrahierbaren Text). Schreibt pro Quelldatei eine .txt-Datei unter
    .ingest-tools/extracted/ (Pfad wird relativ zu InputDocsFolder gespiegelt, damit
    input_client-docs/ selbst unveraendert bleibt und die Ingest-Abdeckungs-Diffs in
    project-status.ps1 nicht verfaelscht werden).

    DOCX/PPTX: reines .NET (ZipFile + XML), keine externe Abhaengigkeit noetig - beide Formate
    benennen ihre Text-Run-Elemente lediglich "t" (w:t bzw. a:t, unterschiedlicher Namespace), ein
    namespace-unabhaengiger Zugriff ueber den lokalen Elementnamen deckt daher beide Formate ab.

    PDF: benoetigt "pdftotext" (Poppler) auf PATH oder unter .ingest-tools/poppler/. Pandoc kann
    KEIN PDF als Eingabeformat lesen (nur als Ausgabeformat via LaTeX) und ist daher hierfuer
    technisch keine Option - deshalb wird ausschliesslich Poppler unterstuetzt. Ohne pdftotext
    werden PDF-Dateien uebersprungen (mit Hinweis); mit -InstallMissingTool wird bei Bedarf ein
    aktuelles Poppler-fuer-Windows-Release (ueber die GitHub-Releases-API, kein fest verdrahteter
    Download-Link) nach .ingest-tools/poppler/ geladen und von dort verwendet - nie systemweit
    installiert, nie git-getrackt.

.PARAMETER Path
    Ein oder mehrere Pfade (Datei oder Ordner). Ordner werden rekursiv nach .docx/.pptx/.pdf
    durchsucht.

.PARAMETER ProjectRoot
    Wurzelordner des Mandats. Default: Ordner, in dem dieses Skript liegt.

.PARAMETER InputDocsFolder
    Name des Client-Input-Ordners relativ zu ProjectRoot, dient nur zur Ableitung des relativen
    Zielpfads unter .ingest-tools/extracted/. Default: "input_client-docs".

.PARAMETER OutDir
    Zielordner fuer die extrahierten .txt-Dateien. Default: ".ingest-tools/extracted".

.PARAMETER InstallMissingTool
    Erlaubt den einmaligen Download von Poppler (pdftotext) nach .ingest-tools/poppler/, falls
    weder PATH noch ein frueherer lokaler Download eine PDF-Textextraktion erlauben.

.EXAMPLE
    ./convert-docs-to-text.ps1 -Path input_client-docs\akquise-beistellungen
    Extrahiert Text aus allen DOCX/PPTX/PDF-Dateien in diesem Ordner.

.EXAMPLE
    ./convert-docs-to-text.ps1 -Path "input_client-docs\foo.pdf" -InstallMissingTool
    Laedt bei Bedarf Poppler lokal nach und extrahiert den Text der PDF-Datei.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$Path,
    [string]$ProjectRoot = $PSScriptRoot,
    [string]$InputDocsFolder = 'input_client-docs',
    [string]$OutDir,
    [switch]$InstallMissingTool
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

if (-not $OutDir) { $OutDir = Join-Path $ProjectRoot '.ingest-tools/extracted' }
$inputDocsPath = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot $InputDocsFolder))
$popplerDir = Join-Path $ProjectRoot '.ingest-tools/poppler'

# ===========================================================================
#  Hilfsfunktionen
# ===========================================================================

function Write-FileUtf8NoBom {
    param([string]$FilePath, [string]$Content)
    $full = [System.IO.Path]::GetFullPath($FilePath)
    $dir = [System.IO.Path]::GetDirectoryName($full)
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($full, $Content, $utf8NoBom)
}

# Zielpfad unter OutDir, gespiegelt relativ zu InputDocsFolder (oder nur Dateiname, falls die
# Quelle ausserhalb von InputDocsFolder liegt).
function Get-OutputPath {
    param([System.IO.FileInfo]$File)
    $full = $File.FullName
    if ($full.StartsWith($inputDocsPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        $rel = $full.Substring($inputDocsPath.Length).TrimStart('\', '/')
    }
    else {
        $rel = $File.Name
    }
    $rel = [System.IO.Path]::ChangeExtension($rel, '.txt')
    return Join-Path $OutDir $rel
}

function Resolve-InputFiles {
    param([string[]]$Paths)
    $files = @()
    foreach ($p in $Paths) {
        $full = if ([System.IO.Path]::IsPathRooted($p)) { $p } else { Join-Path $ProjectRoot $p }
        $full = [System.IO.Path]::GetFullPath($full)
        if (-not (Test-Path -LiteralPath $full)) {
            Write-Warning "Pfad nicht gefunden, wird uebersprungen: $p"
            continue
        }
        if ((Get-Item -LiteralPath $full).PSIsContainer) {
            $files += @(Get-ChildItem -LiteralPath $full -Recurse -File | Where-Object { $_.Extension -in '.docx', '.pptx', '.pdf' })
        }
        else {
            $files += Get-Item -LiteralPath $full
        }
    }
    return $files
}

# ===========================================================================
#  DOCX/PPTX - reines .NET, keine externe Abhaengigkeit
# ===========================================================================

function Get-OfficeXmlText {
    param([string]$ZipPath, [string]$EntryPattern)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        # Natuerliche Sortierung nach Ziffern im Dateinamen (slide2 vor slide10), damit PPTX-Folien
        # in Praesentations-Reihenfolge statt alphabetisch (slide1, slide10, slide2, ...) landen.
        $entries = $zip.Entries | Where-Object { $_.FullName -like $EntryPattern } | Sort-Object {
            $m = [regex]::Match($_.Name, '\d+')
            if ($m.Success) { [int]$m.Value } else { 0 }
        }
        $sb = New-Object System.Text.StringBuilder
        foreach ($entry in $entries) {
            $stream = $entry.Open()
            try {
                $xml = New-Object System.Xml.XmlDocument
                $xml.Load($stream)
                $nodes = $xml.SelectNodes("//*[local-name()='t']")
                foreach ($n in $nodes) { [void]$sb.AppendLine($n.InnerText) }
            }
            finally { $stream.Dispose() }
        }
        return $sb.ToString()
    }
    finally { $zip.Dispose() }
}

# ===========================================================================
#  PDF - benoetigt pdftotext (Poppler); Pandoc kann kein PDF lesen, daher keine Option hier
# ===========================================================================

function Find-PdfToText {
    $onPath = Get-Command 'pdftotext' -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    if (Test-Path -LiteralPath $popplerDir) {
        $local = Get-ChildItem -LiteralPath $popplerDir -Filter 'pdftotext.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($local) { return $local.FullName }
    }
    return $null
}

# Laedt das aktuelle Poppler-fuer-Windows-Release (oschwartz10612/poppler-windows, der
# gebraeuchliche Windows-Build dieses Open-Source-Projekts) ueber die GitHub-Releases-API - nie
# einen fest verdrahteten Versions-Link, damit das Skript nicht veraltet.
function Install-Poppler {
    Write-Host 'Lade aktuelles Poppler-fuer-Windows-Release (pdftotext) herunter...' -ForegroundColor Cyan
    $apiUrl = 'https://api.github.com/repos/oschwartz10612/poppler-windows/releases/latest'
    $release = Invoke-RestMethod -Uri $apiUrl -Headers @{ 'User-Agent' = 'kaeppeli-fundaro-ingest-docs' }
    $asset = $release.assets | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1
    if (-not $asset) { throw 'Kein Poppler-Zip-Release gefunden.' }
    if (-not (Test-Path -LiteralPath $popplerDir)) { New-Item -ItemType Directory -Path $popplerDir -Force | Out-Null }
    $zipPath = Join-Path $popplerDir $asset.name
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath
    Expand-Archive -LiteralPath $zipPath -DestinationPath $popplerDir -Force
    Remove-Item -LiteralPath $zipPath -Force
    $exe = Get-ChildItem -LiteralPath $popplerDir -Filter 'pdftotext.exe' -Recurse | Select-Object -First 1
    if (-not $exe) { throw 'pdftotext.exe nach dem Entpacken nicht gefunden.' }
    Write-Host "Poppler installiert nach: $($exe.FullName)" -ForegroundColor Green
    return $exe.FullName
}

# ===========================================================================
#  Hauptablauf
# ===========================================================================

$files = @(Resolve-InputFiles -Paths $Path)
if ($files.Count -eq 0) { Write-Warning 'Keine unterstuetzten Dateien (.docx/.pptx/.pdf) gefunden.'; return }

$pdftotextPath = $null
$results = @()
foreach ($file in $files) {
    $outPath = Get-OutputPath -File $file
    $text = $null
    # $skip statt "continue" im switch: "continue" innerhalb eines switch-Falls beendet nur den
    # switch selbst (PowerShell behandelt switch wie eine eigene Schleife), nicht die aeussere
    # foreach-Schleife - ohne dieses Flag wuerde die Warnung unten doppelt ausgegeben.
    $skip = $false
    try {
        switch ($file.Extension.ToLowerInvariant()) {
            '.docx' { $text = Get-OfficeXmlText -ZipPath $file.FullName -EntryPattern 'word/document.xml' }
            '.pptx' { $text = Get-OfficeXmlText -ZipPath $file.FullName -EntryPattern 'ppt/slides/slide*.xml' }
            '.pdf' {
                if (-not $pdftotextPath) { $pdftotextPath = Find-PdfToText }
                if (-not $pdftotextPath -and $InstallMissingTool) { $pdftotextPath = Install-Poppler }
                if (-not $pdftotextPath) {
                    Write-Warning "pdftotext (Poppler) nicht gefunden - '$($file.Name)' wird uebersprungen. Erneut mit -InstallMissingTool aufrufen, um Poppler lokal nach .ingest-tools/poppler/ zu laden."
                    $skip = $true
                }
                else {
                    $tmpTxt = [System.IO.Path]::GetTempFileName()
                    & $pdftotextPath -layout -enc 'UTF-8' $file.FullName $tmpTxt | Out-Null
                    $text = Get-Content -LiteralPath $tmpTxt -Raw -Encoding UTF8
                    Remove-Item -LiteralPath $tmpTxt -Force -ErrorAction SilentlyContinue
                }
            }
            default { Write-Warning "Nicht unterstuetztes Format, wird uebersprungen: $($file.FullName)"; $skip = $true }
        }
        if ($skip) { continue }
        if (-not $text) { Write-Warning "Kein Text extrahiert (leer): $($file.FullName)"; continue }
        Write-FileUtf8NoBom -FilePath $outPath -Content $text
        Write-Host "Extrahiert: $($file.Name) -> $outPath" -ForegroundColor Green
        $results += $outPath
    }
    catch {
        Write-Warning "Fehler bei '$($file.FullName)': $($_.Exception.Message)"
    }
}

Write-Host ''
Write-Host "Fertig. $($results.Count) Datei(en) extrahiert." -ForegroundColor Cyan
$results | ForEach-Object { Write-Host "  - $_" }
