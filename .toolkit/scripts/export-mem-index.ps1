<#
.SYNOPSIS
    Portables Export-Tooling fuer Memory Indexe (Flat Markdown ZIP oder
    Quartz Static Site).

.DESCRIPTION
    Ein einzelnes, self-contained Skript. Es wird in den Root-Ordner eines
    aehnlich aufgebauten Mandats gelegt und von dort ausgefuehrt. Es erkennt
    den Wiki-Ordner (Ordner mit 00_INDEX.md) automatisch und exportiert ihn
    wahlweise als:

      - Flat Markdown : ZIP des gesamten Wiki-Ordners -> export-artefacts/
      - Quartz        : statische Website + Zero-Dependency-Kundenpaket
                        -> export-artefacts/

    Alle Hilfsartefakte (Quartz-Config, lokaler Webserver, Launcher) werden
    zur Laufzeit aus dem Skript selbst erzeugt - es sind keine Begleitdateien
    noetig. Der Memory Index wird NIE veraendert (nur gelesen/kopiert).

    Es werden KEINE LLM-Tokens verbraucht - reiner Node-/Git-/PowerShell-Build.

.PARAMETER MemIndexPath
    Pfad zum Wiki-Ordner relativ zum Skript-Root. Ueberschreibt den
    Auto-Detect. Nuetzlich, wenn der Wiki-Ordner nicht eindeutig auffindbar
    ist oder statt des erkannten Ordners ein anderer (z. B. der ganze
    Container) exportiert werden soll.

.PARAMETER ExportType
    'Flat' oder 'Quartz'. Ohne Angabe fragt das Skript interaktiv nach.

.PARAMETER Title
    Seitentitel der Quartz-Website. Default: aus dem Skript-Root-Ordnernamen
    abgeleitet.

.PARAMETER IncludeDeepDives
    Quartz: bindet zusaetzlich alle Deep-Dive-Ordner (*-deepdive neben dem
    Wiki-Ordner) in dieselbe Website ein.

.PARAMETER Serve
    Quartz: startet einen lokalen Dev-Server mit Hot-Reload statt zu bauen.

.PARAMETER Port
    Port fuer den Dev-Server (nur mit -Serve). Default: 8080

.PARAMETER Reinstall
    Loescht die zwischengespeicherte Quartz-Installation und klont neu.

.EXAMPLE
    ./export-mem-index.ps1
    Fragt den Export-Typ ab und exportiert den auto-erkannten Wiki-Ordner.

.EXAMPLE
    ./export-mem-index.ps1 -ExportType Flat
    Erzeugt direkt ein Markdown-ZIP in export-artefacts/.

.EXAMPLE
    ./export-mem-index.ps1 -ExportType Quartz -IncludeDeepDives
    Baut Haupt-Index + Deep-Dives als eine verlinkte Website + Kundenpaket.

.EXAMPLE
    ./export-mem-index.ps1 -MemIndexPath "mem-indexed/01_mem-index-terradata" -ExportType Quartz
    Nutzt einen explizit angegebenen Wiki-Ordner.
#>
[CmdletBinding()]
param(
    [string]$MemIndexPath,
    [ValidateSet('Flat', 'Quartz')]
    [string]$ExportType,
    [string]$Title,
    [switch]$IncludeDeepDives,
    [switch]$Serve,
    [int]$Port = 8080,
    [switch]$Reinstall
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$workRoot = Join-Path $here '.mem-index-export'   # gecachte Quartz-Installation
$quartzDir = Join-Path $workRoot 'quartz'
$contentDir = Join-Path $quartzDir 'content'
$artefactDir = Join-Path $here 'export-artefacts'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# ===========================================================================
#  Hilfsfunktionen
# ===========================================================================

# Tiefe Verzeichnisse long-path-sicher loeschen (node_modules + OneDrive-Pfad
# sprengen MAX_PATH; Remove-Item scheitert). robocopy-Mirror-Trick: ein leeres
# Verzeichnis ueber das Ziel spiegeln loescht beliebig tiefe Strukturen.
function Remove-DirRobust([string]$Target) {
    if (-not (Test-Path $Target)) { return }
    $empty = Join-Path $env:TEMP ("empty_" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $empty | Out-Null
    robocopy $empty $Target /MIR /NFL /NDL /NJH /NJS /NC /NS /NP | Out-Null
    Remove-Item $Target -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $empty -Recurse -Force -ErrorAction SilentlyContinue
}

# Titel aus einem Ordnernamen ableiten: Datums-/Zahlpraefixe strippen,
# Trennzeichen zu Leerzeichen, Title-Case.
function Get-TitleFromName([string]$name) {
    $t = $name
    $t = $t -replace '^\d{6,8}[_-]', ''          # 260107_ / 20260107_
    $t = $t -replace '^\d{4}-\d{2}-\d{2}[_-]', '' # 2026-01-07_
    $t = $t -replace '^\d+[_-]', ''               # 01_
    $t = $t -replace '[_-]+', ' '
    $t = $t.Trim()
    if (-not $t) { $t = $name }
    return (Get-Culture).TextInfo.ToTitleCase($t.ToLower())
}

# Kurzes Temp-Arbeitsverzeichnis erzeugen (MAX_PATH-/OneDrive-Umgehung).
function New-TempDir([string]$prefix) {
    $p = Join-Path $env:TEMP ($prefix + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $p -Force | Out-Null
    return $p
}

# ===========================================================================
#  1. Wiki-Ordner bestimmen (Auto-Detect oder -MemIndexPath)
# ===========================================================================

if ($MemIndexPath) {
    $candidate = if ([System.IO.Path]::IsPathRooted($MemIndexPath)) {
        $MemIndexPath
    } else {
        Join-Path $here $MemIndexPath
    }
    if (-not (Test-Path $candidate -PathType Container)) {
        throw "Angegebener MemIndexPath existiert nicht: $candidate"
    }
    $SourceDir = (Resolve-Path $candidate).Path
    if (-not (Test-Path (Join-Path $SourceDir '00_INDEX.md'))) {
        Write-Warning "Im angegebenen Ordner wurde keine 00_INDEX.md gefunden - fahre trotzdem fort."
    }
} else {
    Write-Host "==> Suche Wiki-Ordner (enthaelt 00_INDEX.md) unterhalb von:" -ForegroundColor Cyan
    Write-Host "    $here" -ForegroundColor Cyan
    $indexHits = Get-ChildItem -Path $here -Recurse -File -Filter '00_INDEX.md' -ErrorAction SilentlyContinue |
        Where-Object {
            $_.FullName -notmatch '\\\.obsidian\\' -and
            $_.FullName -notmatch '\\\.git\\' -and
            $_.FullName -notmatch '\\\.mem-index-export\\' -and
            $_.FullName -notmatch '\\export-artefacts\\'
        } |
        Sort-Object { $_.FullName.Length }   # kuerzester Pfad = wahrscheinlichster Haupt-Index
    if (-not $indexHits) {
        throw "Kein Wiki-Ordner mit 00_INDEX.md gefunden. Bitte -MemIndexPath angeben."
    }
    if ($indexHits.Count -gt 1) {
        Write-Warning "Mehrere 00_INDEX.md gefunden. Verwende den mit dem kuerzesten Pfad:"
        $indexHits | ForEach-Object { Write-Host "      $($_.DirectoryName)" -ForegroundColor DarkGray }
        Write-Warning "Bei Bedarf den gewuenschten Ordner explizit via -MemIndexPath angeben."
    }
    $SourceDir = $indexHits[0].DirectoryName
}

Write-Host "==> Wiki-Ordner: $SourceDir" -ForegroundColor Green

# Titel ableiten (falls nicht gesetzt): aus Skript-Root-Ordnernamen
if (-not $Title) {
    $Title = Get-TitleFromName (Split-Path $here -Leaf)
}

# ===========================================================================
#  2. Export-Typ bestimmen (Parameter oder interaktiver Prompt)
# ===========================================================================

if (-not $ExportType) {
    Write-Host ""
    Write-Host "Export-Typ waehlen:" -ForegroundColor Cyan
    Write-Host "  [1] Flat Markdown  (ZIP des Wiki-Ordners)"
    Write-Host "  [2] Quartz         (statische Website + Kundenpaket)"
    do {
        $choice = Read-Host "Auswahl (1/2)"
    } while ($choice -notin @('1', '2'))
    $ExportType = if ($choice -eq '1') { 'Flat' } else { 'Quartz' }
}
Write-Host "==> Export-Typ: $ExportType" -ForegroundColor Green

if (-not (Test-Path $artefactDir)) {
    New-Item -ItemType Directory -Path $artefactDir -Force | Out-Null
}

# ===========================================================================
#  ZWEIG A - Flat Markdown (ZIP)
# ===========================================================================

if ($ExportType -eq 'Flat') {
    $wikiName = Split-Path $SourceDir -Leaf
    $stamp = Get-Date -Format 'yyyy-MM-dd'
    $zipPath = Join-Path $artefactDir "${wikiName}_$stamp.zip"

    # Inhalt long-path-sicher in kurzes Temp spiegeln (ohne .obsidian/.git),
    # dann zippen. Compress-Archive scheitert sonst an tiefen OneDrive-Pfaden.
    $tmp = New-TempDir 'flat_'
    $stage = Join-Path $tmp $wikiName
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    Write-Host "==> Kopiere Wiki-Inhalt (ohne .obsidian/.git) ..." -ForegroundColor Yellow
    robocopy $SourceDir $stage /E /XD .obsidian .git /NFL /NDL /NJH /NJS /NC /NS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy (Wiki -> Temp) fehlgeschlagen (Code $LASTEXITCODE)." }

    $tmpZip = Join-Path $tmp "${wikiName}_$stamp.zip"
    Write-Host "==> Erzeuge ZIP ..." -ForegroundColor Yellow
    Compress-Archive -Path $stage -DestinationPath $tmpZip -Force

    if (Test-Path $zipPath) { Remove-Item -Force $zipPath }
    Move-Item $tmpZip $zipPath -Force
    Remove-DirRobust $tmp

    $zipSize = [math]::Round((Get-Item $zipPath).Length / 1MB, 2)
    Write-Host ""
    Write-Host "==> Fertig. Flat-Markdown-ZIP ($zipSize MB):" -ForegroundColor Green
    Write-Host "    $zipPath" -ForegroundColor Green
    return
}

# ===========================================================================
#  ZWEIG B - Quartz Static Site
# ===========================================================================

# --- B1. Quartz installieren (nur beim ersten Lauf) ------------------------
if ($Reinstall -and (Test-Path $quartzDir)) {
    Write-Host "==> Entferne vorhandene Quartz-Installation ..." -ForegroundColor Yellow
    Remove-DirRobust $quartzDir
}
if (-not (Test-Path $quartzDir)) {
    if (-not (Test-Path $workRoot)) { New-Item -ItemType Directory -Path $workRoot -Force | Out-Null }
    # git und npm schreiben ihren Fortschritt nach stderr. Unter
    # $ErrorActionPreference='Stop' kann PowerShell diese stderr-Ausgabe - v. a.
    # wenn der Output umgeleitet/geloggt wird (2>&1) - als terminierenden Fehler
    # werten, obwohl der Befehl erfolgreich war. Deshalb hier lokal auf
    # 'Continue' schalten und den Erfolg ausschliesslich am Exit-Code messen.
    $prevEA = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        Write-Host "==> Klone Quartz (stabiler v4-Branch) ..." -ForegroundColor Yellow
        git clone --depth 1 --branch v4 https://github.com/jackyzha0/quartz.git $quartzDir 2>&1 | Write-Host
        if ($LASTEXITCODE -ne 0) {
            Remove-DirRobust $quartzDir
            throw "git clone fehlgeschlagen (Code $LASTEXITCODE). Ist git installiert und Internet verfuegbar?"
        }
        Push-Location $quartzDir
        try {
            Write-Host "==> Installiere npm-Abhaengigkeiten ..." -ForegroundColor Yellow
            npm install 2>&1 | Write-Host
            if ($LASTEXITCODE -ne 0) { throw "npm install fehlgeschlagen (Code $LASTEXITCODE)." }
        } finally { Pop-Location }
    } finally { $ErrorActionPreference = $prevEA }
}

# --- B2. Quartz-Konfiguration erzeugen (jeder Lauf, idempotent) ------------
$titleEscaped = $Title.Replace('"', '\"')
$quartzConfig = @'
import { QuartzConfig } from "./quartz/cfg"
import * as Plugin from "./quartz/plugins"

/**
 * Quartz 4 Konfiguration - vom portablen Export-Skript erzeugt.
 * Siehe https://quartz.jzhao.xyz/configuration fuer Details.
 */
const config: QuartzConfig = {
  configuration: {
    pageTitle: "__TITLE__",
    pageTitleSuffix: "",
    enableSPA: true,
    enablePopovers: true,
    analytics: null,
    locale: "de-DE",
    baseUrl: "localhost:8080",
    ignorePatterns: ["private", "templates", ".obsidian"],
    defaultDateType: "modified",
    theme: {
      fontOrigin: "googleFonts",
      cdnCaching: true,
      typography: {
        header: "Schibsted Grotesk",
        body: "Source Sans Pro",
        code: "IBM Plex Mono",
      },
      colors: {
        lightMode: {
          light: "#faf8f8",
          lightgray: "#e5e5e5",
          gray: "#b8b8b8",
          darkgray: "#4e4e4e",
          dark: "#2b2b2b",
          secondary: "#284b63",
          tertiary: "#84a59d",
          highlight: "rgba(143, 159, 169, 0.15)",
          textHighlight: "#fff23688",
        },
        darkMode: {
          light: "#161618",
          lightgray: "#393639",
          gray: "#646464",
          darkgray: "#d4d4d4",
          dark: "#ebebec",
          secondary: "#7b97aa",
          tertiary: "#84a59d",
          highlight: "rgba(143, 159, 169, 0.15)",
          textHighlight: "#b3aa0288",
        },
      },
    },
  },
  plugins: {
    transformers: [
      Plugin.FrontMatter(),
      Plugin.CreatedModifiedDate({
        priority: ["frontmatter", "git", "filesystem"],
      }),
      Plugin.SyntaxHighlighting({
        theme: {
          light: "github-light",
          dark: "github-dark",
        },
        keepBackground: false,
      }),
      Plugin.ObsidianFlavoredMarkdown({ enableInHtmlEmbed: false }),
      Plugin.GitHubFlavoredMarkdown(),
      Plugin.TableOfContents(),
      Plugin.CrawlLinks({ markdownLinkResolution: "shortest" }),
      Plugin.Description(),
      Plugin.Latex({ renderEngine: "katex" }),
    ],
    filters: [Plugin.RemoveDrafts()],
    emitters: [
      Plugin.AliasRedirects(),
      Plugin.ComponentResources(),
      Plugin.ContentPage(),
      Plugin.FolderPage(),
      Plugin.TagPage(),
      Plugin.ContentIndex({
        enableSiteMap: true,
        enableRSS: true,
      }),
      Plugin.Assets(),
      Plugin.Static(),
      Plugin.Favicon(),
      Plugin.NotFoundPage(),
      // CustomOgImages muss aktiv bleiben: Head.tsx importiert den
      // Emitter-Namen. Auskommentieren bricht den Build.
      Plugin.CustomOgImages(),
    ],
  },
}

export default config
'@
$quartzConfig = $quartzConfig.Replace('__TITLE__', $titleEscaped)
[System.IO.File]::WriteAllText((Join-Path $quartzDir 'quartz.config.ts'), $quartzConfig, $utf8NoBom)
Write-Host "==> quartz.config.ts erzeugt (Titel: '$Title', Locale de-DE)." -ForegroundColor Green

# --- B3. Inhalte in den content-Ordner kopieren ---------------------------
Write-Host "==> Kopiere Wiki-Nodes in content/ ..." -ForegroundColor Yellow
if (Test-Path $contentDir) { Remove-Item -Recurse -Force $contentDir }
New-Item -ItemType Directory -Path $contentDir | Out-Null

$prefix = $SourceDir.TrimEnd('\') + '\'
Get-ChildItem -Path $SourceDir -Recurse -File |
    Where-Object { $_.FullName -notmatch '\\\.obsidian\\' -and $_.FullName -notmatch '\\\.git\\' } |
    ForEach-Object {
        $rel = $_.FullName.Substring($prefix.Length)
        $dest = Join-Path $contentDir $rel
        $destParent = Split-Path $dest -Parent
        if (-not (Test-Path $destParent)) { New-Item -ItemType Directory -Path $destParent -Force | Out-Null }
        Copy-Item $_.FullName $dest -Force
    }

# Startseite aus 00_INDEX.md erzeugen
$indexSource = Join-Path $SourceDir '00_INDEX.md'
if (Test-Path $indexSource) {
    Copy-Item $indexSource (Join-Path $contentDir 'index.md') -Force
    Write-Host "==> Startseite aus 00_INDEX.md erzeugt." -ForegroundColor Green
} else {
    Write-Warning "00_INDEX.md nicht gefunden - keine dedizierte Startseite gesetzt."
}

# --- B4. Deep-Dive-Indexe einbinden (optional, generisch) ------------------
# Jeder Deep-Dive-Ordner (*-deepdive neben dem Wiki-Ordner) enthaelt oft
# gleichnamige Dateien (00_INDEX.md, 00_Synthese_Kernfragen.md). In EINER
# Quartz-Website waeren die Wikilinks dadurch mehrdeutig. Deshalb werden die
# Kopien (nie die Quelle!) eindeutig umbenannt und die betroffenen Links
# gezielt umgeschrieben. Slug/Title werden generisch aus dem Ordnernamen
# abgeleitet (keine hardcodierte Tabelle).
$buildContentDir = $null   # $null => Standard-Build aus quartz/content
$buildTempRoot = $null
if ($IncludeDeepDives) {
    $memRoot = Split-Path $SourceDir -Parent
    $ddFolders = Get-ChildItem -Path $memRoot -Directory |
        Where-Object { $_.Name -like '*-deepdive' } |
        Sort-Object Name
    if (-not $ddFolders) {
        Write-Warning "Keine *-deepdive-Ordner in $memRoot gefunden."
    }

    $slugByFolder = @{}   # Ordnername -> Slug (fuer spaetere Verweis-Umschreibung)
    $rnodeRename = @{}     # alter R-Node-Basisname (mit Datum) -> neuer (gekuerzter)

    # Kurzes Temp-Arbeitsverzeichnis (MAX_PATH-Umgehung)
    $buildTempRoot = New-TempDir 'qzc_'
    $buildContentDir = Join-Path $buildTempRoot 'content'
    New-Item -ItemType Directory -Path $buildContentDir -Force | Out-Null

    # Bereits kopierten Haupt-Index (inkl. index.md) uebernehmen (long-path-sicher)
    robocopy $contentDir $buildContentDir /E /NFL /NDL /NJH /NJS /NC /NS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy (Haupt-Index -> Temp) fehlgeschlagen (Code $LASTEXITCODE)." }

    $ddRoot = Join-Path $buildContentDir 'Deep-Dives'
    foreach ($dd in $ddFolders) {
        # Slug (URL-Ordner) generisch ableiten: numer. Praefix + '-deepdive' strippen.
        $slug = $dd.Name -replace '^\d+[_-]', '' -replace '-deepdive$', ''
        if (-not $slug) { $slug = $dd.Name }
        $ddTitle = Get-TitleFromName $slug
        $slugByFolder[$dd.Name] = $slug

        Write-Host "==> Deep-Dive: $($dd.Name) -> Deep-Dives/$slug ('$ddTitle') ..." -ForegroundColor Yellow
        $destFolder = Join-Path $ddRoot $slug
        New-Item -ItemType Directory -Path $destFolder -Force | Out-Null

        # Dateien kopieren (ohne .obsidian/.git) - robocopy ist long-path-sicher
        robocopy $dd.FullName $destFolder /E /XD .obsidian .git /NFL /NDL /NJH /NJS /NC /NS /NP | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "robocopy ($($dd.Name) -> Temp) fehlgeschlagen (Code $LASTEXITCODE)." }

        # R-Node-Dateinamen kuerzen: fuehrendes Datum entfernen (260706_R2_... -> R2_...)
        # UND bei Bedarf laengenbegrenzen (MAX_PATH: Quartz erzeugt zusaetzlich
        # "<name>-og-image.webp", +14 Zeichen). Cap = 52 - len(slug).
        $cap = 52 - $slug.Length
        Get-ChildItem -Path $destFolder -File -Filter '*.md' | ForEach-Object {
            if ($_.Name -match '^(\d{6}_(R\d.*))\.md$') {
                $oldBase = $Matches[1]
                $newBase = $Matches[2]
                if ($newBase.Length -gt $cap -and $cap -gt 8) {
                    $cut = $newBase.Substring(0, $cap)
                    $lastDash = $cut.LastIndexOf('-')
                    $newBase = if ($lastDash -ge 8) { $cut.Substring(0, $lastDash) } else { $cut }
                }
                $rnodeRename[$oldBase] = $newBase
                Move-Item $_.FullName (Join-Path $destFolder ($newBase + '.md')) -Force
            }
        }

        # Ordner-Index -> index.md (liefert Ordner-Anzeigenamen); Synthese eindeutig benennen
        $idxNew = Join-Path $destFolder 'index.md'
        $idxOld = Join-Path $destFolder '00_INDEX.md'
        if (Test-Path $idxOld) { Move-Item $idxOld $idxNew -Force }
        $synOld = Join-Path $destFolder '00_Synthese_Kernfragen.md'
        $synNew = Join-Path $destFolder ("$slug-synthese.md")
        if (Test-Path $synOld) { Move-Item $synOld $synNew -Force }

        # Frontmatter-'title' in die Ordner-index.md -> Ordnername im Explorer/Breadcrumb
        if (Test-Path $idxNew) {
            $itext = [System.IO.File]::ReadAllText($idxNew)
            if ($itext -match '(?s)^\uFEFF?---\r?\n') {
                if ($itext -match '(?m)^title:.*$') {
                    $itext = [regex]::Replace($itext, '(?m)^title:.*$', "title: `"$ddTitle`"", 1)
                } else {
                    $itext = [regex]::Replace($itext, '(\uFEFF?---\r?\n)', "`$1title: `"$ddTitle`"`r`n", 1)
                }
            } else {
                $itext = "---`r`ntitle: `"$ddTitle`"`r`n---`r`n`r`n" + $itext
            }
            [System.IO.File]::WriteAllText($idxNew, $itext, $utf8NoBom)
        }

        # DD-interne, kontextabhaengige Wikilinks umschreiben (Synthese + eigener Index)
        Get-ChildItem -Path $destFolder -Recurse -File -Filter *.md | ForEach-Object {
            $text = [System.IO.File]::ReadAllText($_.FullName)
            $orig = $text
            $text = $text.Replace('[[00_Synthese_Kernfragen', "[[$slug-synthese")
            if ($_.FullName -ieq $idxNew) {
                # Ordner-Index: Rueckverweis auf den Haupt-Index (Root).
                $text = $text.Replace('[[00_INDEX]] (Haupt-Index)', '[[index|Haupt-Index]]')
                $text = $text.Replace('[[00_INDEX]]', '[[index|Haupt-Index]]')
            } else {
                # Uebrige DD-Dateien: Rueckverweis auf den eigenen Ordner-Index (voller Pfad).
                $text = $text.Replace('[[00_INDEX]]', "[[Deep-Dives/$slug/index|$ddTitle]]")
            }
            if ($text -ne $orig) { [System.IO.File]::WriteAllText($_.FullName, $text, $utf8NoBom) }
        }
    }

    # Globale Umschreibung ueber ALLE Inhalte (Haupt-Index + Deep-Dives):
    #  a) Datums-Praefix in R-Node-Verweisen entfernen (Wiki- UND Markdown-Links)
    #  b) Deep-Dive-Markdown-Links -> Wikilinks (loesen sich lageunabhaengig auf)
    Get-ChildItem -Path $buildContentDir -Recurse -File -Filter *.md | ForEach-Object {
        $text = [System.IO.File]::ReadAllText($_.FullName)
        $orig = $text
        foreach ($k in $rnodeRename.Keys) { $text = $text.Replace($k, $rnodeRename[$k]) }
        foreach ($f in $slugByFolder.Keys) {
            $slug = $slugByFolder[$f]
            $fe = [regex]::Escape($f)
            $text = [regex]::Replace($text, "\[([^\]]+)\]\((?:\.\./)+$fe/00_INDEX\.md\)", "[[Deep-Dives/$slug/index|`$1]]")
            $text = [regex]::Replace($text, "\[([^\]]+)\]\((?:\.\./)+$fe/(R\d[^)]*?)\.md\)", "[[`$2|`$1]]")
            $text = [regex]::Replace($text, "\[([^\]]+)\]\((?:\.\./)+$fe/\)", "[[Deep-Dives/$slug/index|`$1]]")
        }
        if ($text -ne $orig) { [System.IO.File]::WriteAllText($_.FullName, $text, $utf8NoBom) }
    }
    Write-Host "==> Deep-Dives unter content/Deep-Dives/<slug>/ eingebunden." -ForegroundColor Green
}

# --- B5. Bauen oder Serven -------------------------------------------------
$publicDir = Join-Path $artefactDir 'public'
Push-Location $quartzDir
try {
    $dirArgs = @()
    if ($buildContentDir) { $dirArgs = @('--directory', $buildContentDir) }
    if ($Serve) {
        Write-Host "==> Starte Dev-Server auf http://localhost:$Port ..." -ForegroundColor Cyan
        node --no-deprecation quartz/bootstrap-cli.mjs build @dirArgs --serve --port $Port
    } else {
        # In kurzes Temp bauen (MAX_PATH-/OneDrive-sicher), dann robocopy nach public/.
        # Quartz macht vor jedem Build ein rmdir auf den Output-Ordner; unter OneDrive
        # sperrt der Sync einzelne Dateien -> EBUSY. robocopy /R:5 /W:2 wartet Sperren aus.
        $buildOut = New-TempDir 'qzp_'
        Write-Host "==> Baue statische Website (Temp, MAX_PATH-/OneDrive-sicher) ..." -ForegroundColor Cyan
        # node kann Warnungen nach stderr schreiben; unter 'Stop' + Umleitung sonst
        # faelschlich terminierend. Lokal 'Continue' + Exit-Code pruefen.
        $prevEA = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            node --no-deprecation quartz/bootstrap-cli.mjs build @dirArgs --output $buildOut 2>&1 | Write-Host
            if ($LASTEXITCODE -ne 0) { throw "Quartz-Build fehlgeschlagen (Code $LASTEXITCODE)." }
        } finally { $ErrorActionPreference = $prevEA }

        Write-Host "==> Spiegle Ergebnis nach $publicDir ..." -ForegroundColor Cyan
        if (-not (Test-Path $publicDir)) { New-Item -ItemType Directory -Path $publicDir -Force | Out-Null }
        robocopy $buildOut $publicDir /MIR /R:5 /W:2 /NFL /NDL /NJH /NJS /NC /NS /NP | Out-Null
        if ($LASTEXITCODE -ge 8) {
            throw "robocopy (Temp -> $publicDir) fehlgeschlagen (Code $LASTEXITCODE). Sperrt OneDrive oder ein laufender Server den Ordner 'public'?"
        }
        Remove-DirRobust $buildOut
        Write-Host "==> Statische Website liegt in: $publicDir" -ForegroundColor Green
    }
} finally {
    Pop-Location
    if ($buildTempRoot -and (-not $Serve)) { Remove-DirRobust $buildTempRoot }
}

if ($Serve) { return }

# --- B6. Zero-Dependency-Kundenpaket schnueren -----------------------------
# serve-local.ps1 + START-<Name>.bat + LIESMICH.txt (aus eingebetteten
# Vorlagen) neben site/ (= Kopie von public/) zusammenstellen und zippen.
Write-Host "==> Schnuere Zero-Dependency-Kundenpaket ..." -ForegroundColor Cyan

$serveLocalTemplate = @'
<#
.SYNOPSIS
    Lokaler Webserver fuer __TITLE__ - ohne Zusatzsoftware.
.DESCRIPTION
    Startet einen kleinen Webserver (reines PowerShell/.NET, kein Python oder
    Node noetig) und oeffnet die Website im Standardbrowser.
.PARAMETER Port
    Startport (wird bei Belegung automatisch hochgezaehlt). Default: 8080
.PARAMETER Root
    Ordner mit der Website. Default: ./site neben diesem Skript.
#>
param(
    [int]$Port = 8080,
    [string]$Root
)

$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Join-Path $PSScriptRoot 'site' }
if (-not (Test-Path $Root)) { Write-Error "Website-Ordner nicht gefunden: $Root"; exit 1 }
$Root = (Resolve-Path $Root).Path
$rootWithSep = $Root.TrimEnd('\') + '\'

$mime = @{
    '.html' = 'text/html; charset=utf-8';        '.htm' = 'text/html; charset=utf-8'
    '.css'  = 'text/css; charset=utf-8';          '.js'  = 'text/javascript; charset=utf-8'
    '.mjs'  = 'text/javascript; charset=utf-8';   '.json' = 'application/json; charset=utf-8'
    '.svg'  = 'image/svg+xml';                    '.png' = 'image/png'
    '.jpg'  = 'image/jpeg';                       '.jpeg' = 'image/jpeg'
    '.gif'  = 'image/gif';                        '.webp' = 'image/webp'
    '.avif' = 'image/avif';                       '.ico' = 'image/x-icon'
    '.woff' = 'font/woff';                        '.woff2' = 'font/woff2'
    '.ttf'  = 'font/ttf';                         '.otf' = 'font/otf'
    '.xml'  = 'application/xml; charset=utf-8';   '.txt' = 'text/plain; charset=utf-8'
    '.map'  = 'application/json';                 '.csv' = 'text/csv; charset=utf-8'
    '.pdf'  = 'application/pdf'
}

function Resolve-RequestPath([string]$target) {
    $p = $target.Split('?')[0]
    try { $p = [System.Uri]::UnescapeDataString($p) } catch {}
    $p = $p.TrimStart('/')
    if ([string]::IsNullOrWhiteSpace($p)) { return (Join-Path $Root 'index.html') }
    $candidate = Join-Path $Root $p
    $full = [System.IO.Path]::GetFullPath($candidate)
    if (-not ($full.StartsWith($rootWithSep, [StringComparison]::OrdinalIgnoreCase) -or $full -eq $Root)) {
        return $null
    }
    if (Test-Path $full -PathType Leaf) { return $full }
    if (Test-Path "$full.html" -PathType Leaf) { return "$full.html" }
    if (Test-Path $full -PathType Container) {
        $idx = Join-Path $full 'index.html'
        if (Test-Path $idx -PathType Leaf) { return $idx }
    }
    return $null
}

$listener = $null
for ($i = 0; $i -lt 25; $i++) {
    try {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
        $listener.Start()
        break
    } catch { $Port++; $listener = $null }
}
if (-not $listener) { Write-Error "Kein freier Port gefunden."; exit 1 }

$url = "http://localhost:$Port/"
Write-Host ""
Write-Host "  __TITLE__ laeuft auf:  $url" -ForegroundColor Green
Write-Host "  Zum Beenden dieses Fenster schliessen (oder Strg+C)." -ForegroundColor Yellow
Write-Host ""
Start-Process $url

function Send-Response($stream, [int]$code, [string]$status, [string]$contentType, [byte[]]$body, [bool]$headOnly) {
    $head = "HTTP/1.1 $code $status`r`nContent-Type: $contentType`r`nContent-Length: $($body.Length)`r`nCache-Control: no-cache`r`nConnection: close`r`n`r`n"
    $hb = [System.Text.Encoding]::ASCII.GetBytes($head)
    $stream.Write($hb, 0, $hb.Length)
    if (-not $headOnly) { $stream.Write($body, 0, $body.Length) }
    $stream.Flush()
}

try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        try {
            $stream = $client.GetStream()
            $reader = [System.IO.StreamReader]::new($stream)
            $requestLine = $reader.ReadLine()
            if (-not $requestLine) { continue }
            while (($line = $reader.ReadLine()) -ne $null -and $line -ne '') { }

            $parts = $requestLine.Split(' ')
            $method = $parts[0]
            $target = if ($parts.Length -ge 2) { $parts[1] } else { '/' }
            $headOnly = ($method -eq 'HEAD')

            if ($method -ne 'GET' -and $method -ne 'HEAD') {
                $b = [System.Text.Encoding]::UTF8.GetBytes('Method Not Allowed')
                Send-Response $stream 405 'Method Not Allowed' 'text/plain; charset=utf-8' $b $false
                continue
            }

            $file = Resolve-RequestPath $target
            if ($file) {
                $bytes = [System.IO.File]::ReadAllBytes($file)
                $ext = [System.IO.Path]::GetExtension($file).ToLowerInvariant()
                $ct = $mime[$ext]; if (-not $ct) { $ct = 'application/octet-stream' }
                Send-Response $stream 200 'OK' $ct $bytes $headOnly
            } else {
                $nf = Join-Path $Root '404.html'
                if (Test-Path $nf) {
                    $bytes = [System.IO.File]::ReadAllBytes($nf)
                    Send-Response $stream 404 'Not Found' 'text/html; charset=utf-8' $bytes $headOnly
                } else {
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes('404 Not Found')
                    Send-Response $stream 404 'Not Found' 'text/plain; charset=utf-8' $bytes $headOnly
                }
            }
        } catch {
        } finally {
            $client.Close()
        }
    }
} finally {
    $listener.Stop()
}
'@

$startBatTemplate = @'
@echo off
rem Startet den lokalen Webserver und oeffnet die Website im Browser.
title __TITLE__
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0serve-local.ps1"
echo.
echo Server beendet. Dieses Fenster kann geschlossen werden.
pause
'@

$liesmichTemplate = @'
========================================================================
  __TITLE__ (lokale Website)
========================================================================

SO STARTEN SIE DIE WEBSITE (Windows):

  1. Doppelklick auf:  __STARTBAT__
  2. Es oeffnet sich ein schwarzes Fenster und danach Ihr Browser
     mit der Website.
  3. Zum Beenden einfach das schwarze Fenster schliessen.

Falls Windows eine Sicherheitswarnung zeigt ("Ausfuehrung verhindert"):
  - Rechtsklick auf __STARTBAT__  ->  "Eigenschaften"
  - unten ggf. Haken bei "Zulassen" / "Entsperren" setzen  ->  OK
  - danach erneut doppelklicken.

------------------------------------------------------------------------
HINWEISE

  - Es wird KEINE zusaetzliche Software benoetigt (kein Python, kein Node).
  - Es werden KEINE Daten ins Internet gesendet - alles laeuft lokal auf
    Ihrem Rechner.
  - Die Inhalte liegen im Unterordner "site".

------------------------------------------------------------------------
ALTERNATIVE (Mac / Linux oder falls vorhanden):

  Im Ordner ein Terminal oeffnen und einen der Befehle ausfuehren:

    python -m http.server 8080 --directory site
    npx serve site

  Danach im Browser oeffnen:  http://localhost:8080

========================================================================
'@

# Dateinamen des Starters aus dem Titel ableiten (dateisystem-tauglich)
$safeName = ($Title -replace '[^\w\-]+', '-').Trim('-')
if (-not $safeName) { $safeName = 'Website' }
$startBatName = "START-$safeName.bat"

$serveLocal = $serveLocalTemplate.Replace('__TITLE__', $Title)
$startBat = $startBatTemplate.Replace('__TITLE__', $Title)
$liesmich = $liesmichTemplate.Replace('__TITLE__', $Title).Replace('__STARTBAT__', $startBatName)

# Paket in kurzem Temp assemblieren (MAX_PATH), dann zippen
$pkgTmp = New-TempDir 'qzpkg_'
$pkgDir = Join-Path $pkgTmp $safeName
$siteDir = Join-Path $pkgDir 'site'
New-Item -ItemType Directory -Path $siteDir -Force | Out-Null

robocopy $publicDir $siteDir /MIR /NFL /NDL /NJH /NJS /NC /NS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy (public -> Paket) fehlgeschlagen (Code $LASTEXITCODE)." }

# ASCII fuer .bat (rem/echo), UTF-8 ohne BOM fuer .ps1 und .txt
[System.IO.File]::WriteAllText((Join-Path $pkgDir 'serve-local.ps1'), $serveLocal, $utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $pkgDir $startBatName), $startBat, (New-Object System.Text.ASCIIEncoding))
[System.IO.File]::WriteAllText((Join-Path $pkgDir 'LIESMICH.txt'), $liesmich, $utf8NoBom)

$stamp = Get-Date -Format 'yyyy-MM-dd'
$tmpZip = Join-Path $pkgTmp "${safeName}_Memory-Index_$stamp.zip"
Compress-Archive -Path $pkgDir -DestinationPath $tmpZip -Force

$zipPath = Join-Path $artefactDir (Split-Path $tmpZip -Leaf)
if (Test-Path $zipPath) { Remove-Item -Force $zipPath }
Move-Item $tmpZip $zipPath -Force
Remove-DirRobust $pkgTmp

$zipSize = [math]::Round((Get-Item $zipPath).Length / 1MB, 2)
Write-Host ""
Write-Host "==> Fertig." -ForegroundColor Green
Write-Host "    Statische Website : $publicDir" -ForegroundColor Green
Write-Host "    Kundenpaket ($zipSize MB): $zipPath" -ForegroundColor Green
Write-Host "    -> ZIP entpacken, '$startBatName' doppelklicken." -ForegroundColor Green
