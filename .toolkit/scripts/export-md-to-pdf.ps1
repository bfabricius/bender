<#
.SYNOPSIS
    Portables MD -> PDF Export-Tooling fuer Mandats-Projekte.

.DESCRIPTION
    Ein einzelnes, self-contained Skript. Es wird in den Root-Ordner eines
    Mandats gelegt und von dort ausgefuehrt. Es rendert Markdown-Dateien in
    schoen gestylte PDFs (ein PDF pro .md-Datei) nach:

        export-artefacts/pdf/

    Rendering laeuft ueber den bereits installierten Edge- bzw. Chrome-Browser
    im Headless-Modus (Chrome DevTools Protocol, Page.printToPDF). Es wird KEIN
    Chromium heruntergeladen und es werden KEINE LLM-Tokens verbraucht.

    - Kopfzeile : Mandatsname (aus mem-index/00_INDEX.md abgeleitet) + Dokumenttitel
    - Fusszeile : Seite X / Y  +  Exportdatum
    - Styling   : Clean/Business (serifenlos, dezent), gestylte Headings,
                  Tabellen, Code, Blockquotes und Obsidian-Callouts.

    Markdown wird mit 'marked' (client-seitig im Browser) gerendert. marked.min.js
    wird einmalig in den Cache-Ordner .pdf-export/ geladen -> danach offline.

    Der Quell-Markdown wird NIE veraendert (nur gelesen).

.PARAMETER Source
    Optional. Ein oder mehrere Pfade (Datei oder Ordner). Ohne Angabe fragt das
    Skript interaktiv, welche Dateien exportiert werden sollen.

.PARAMETER Title
    Optional. Mandatsname fuer die Kopfzeile. Ueberschreibt den Auto-Detect aus
    mem-index/00_INDEX.md bzw. dem Root-Ordnernamen.

.PARAMETER OutDir
    Optional. Zielordner fuer die PDFs. Default: export-artefacts/pdf.

.PARAMETER Reinstall
    Loescht die zwischengespeicherte marked.min.js und laedt sie neu.

.EXAMPLE
    ./export-md-to-pdf.ps1
    Fragt interaktiv, welche Markdown-Dateien exportiert werden sollen.

.EXAMPLE
    ./export-md-to-pdf.ps1 -Source mem-index
    Exportiert alle .md-Dateien im Ordner mem-index/.

.EXAMPLE
    ./export-md-to-pdf.ps1 -Source mem-index/01_Projektkontext.md -Title "RichnerStutz"
    Exportiert eine einzelne Datei mit explizitem Mandatsnamen.
#>
[CmdletBinding()]
param(
    [string[]]$Source,
    [string]$Title,
    [string]$OutDir,
    [switch]$Reinstall
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$cacheDir = Join-Path $here '.pdf-export'
$markedPath = Join-Path $cacheDir 'marked.min.js'
$markedUrl = 'https://cdn.jsdelivr.net/npm/marked/marked.min.js'
if (-not $OutDir) { $OutDir = Join-Path $here 'export-artefacts/pdf' }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# Ordner, die bei der rekursiven Markdown-Suche ausgeschlossen werden.
$excludeDirs = @('.git', '.obsidian', 'node_modules', '.mem-index-export',
    '.pdf-export', 'export-artefacts')

# ===========================================================================
#  Hilfsfunktionen
# ===========================================================================

# Titel aus einem Datei-/Ordnernamen ableiten: Datums-/Zahlpraefixe strippen,
# Trennzeichen zu Leerzeichen, Title-Case.
function Get-TitleFromName([string]$name) {
    $t = $name
    $t = $t -replace '^\d{6,8}[_-]', ''            # 260107_ / 20260107_
    $t = $t -replace '^\d{4}-\d{2}-\d{2}[_-]', ''  # 2026-01-07_
    $t = $t -replace '^\d+[_-]', ''                # 01_
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

# Alle relevanten .md-Dateien unterhalb von $here einsammeln (gefiltert).
function Get-AllMarkdown {
    Get-ChildItem -Path $here -Recurse -File -Filter '*.md' -ErrorAction SilentlyContinue |
        Where-Object {
            $rel = $_.FullName.Substring($here.Length).TrimStart('\', '/')
            $parts = $rel -split '[\\/]'
            -not ($parts | Where-Object { $excludeDirs -contains $_ })
        } |
        Sort-Object FullName
}

# ===========================================================================
#  1. Mandatsname bestimmen
# ===========================================================================

function Get-MandateName {
    # Bevorzugt aus mem-index/00_INDEX.md: H1 der Form "# Titel - Mandat".
    $indexHits = Get-ChildItem -Path $here -Recurse -File -Filter '00_INDEX.md' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\(\.git|export-artefacts|\.pdf-export)\\' } |
        Sort-Object { $_.FullName.Length }
    if ($indexHits) {
        $h1 = Get-Content -LiteralPath $indexHits[0].FullName -TotalCount 30 -Encoding UTF8 |
            Where-Object { $_ -match '^\#\s+\S' } | Select-Object -First 1
        if ($h1) {
            $text = ($h1 -replace '^\#\s+', '').Trim()
            # Teil nach dem letzten Gedankenstrich (Halbgeviert/Bindestrich) = Mandat.
            if ($text -match '[\u2013\u2014-]\s*([^\u2013\u2014-]+)$') {
                $cand = $Matches[1].Trim()
                if ($cand) { return $cand }
            }
            if ($text) { return $text }
        }
    }
    # Fallback: Root-Ordnername.
    return (Get-TitleFromName (Split-Path $here -Leaf))
}

if (-not $Title) { $Title = Get-MandateName }
Write-Host "==> Mandat: $Title" -ForegroundColor Green

# ===========================================================================
#  2. Browser finden (Edge oder Chrome) - sonst sauberer Abbruch
# ===========================================================================

function Find-Browser {
    $candidates = @()
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)) {
        if (-not $base) { continue }
        $candidates += Join-Path $base 'Microsoft\Edge\Application\msedge.exe'
        $candidates += Join-Path $base 'Google\Chrome\Application\chrome.exe'
    }
    foreach ($exe in @('msedge.exe', 'chrome.exe')) {
        foreach ($root in @('HKLM:', 'HKCU:')) {
            $key = "$root\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$exe"
            if (Test-Path $key) {
                $val = (Get-ItemProperty -Path $key -ErrorAction SilentlyContinue).'(default)'
                if ($val) { $candidates += $val }
            }
        }
    }
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return (Resolve-Path $c).Path }
    }
    return $null
}

$browser = Find-Browser
if (-not $browser) {
    throw "Kein Browser gefunden. Dieses Skript benoetigt Microsoft Edge oder " +
          "Google Chrome (headless PDF-Druck). Bitte einen der beiden Browser " +
          "installieren und erneut ausfuehren."
}
Write-Host "==> Browser: $browser" -ForegroundColor Green

# ===========================================================================
#  3. marked.min.js sicherstellen (einmalig cachen -> danach offline)
# ===========================================================================

if ($Reinstall -and (Test-Path $markedPath)) { Remove-Item $markedPath -Force }
if (-not (Test-Path $markedPath)) {
    if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
    Write-Host "==> Lade marked.min.js (einmalig) ..." -ForegroundColor Yellow
    try {
        Invoke-WebRequest -Uri $markedUrl -OutFile $markedPath -UseBasicParsing
    }
    catch {
        throw "marked.min.js konnte nicht geladen werden ($markedUrl). " +
              "Fuer den ersten Lauf ist eine Internetverbindung noetig. Details: $($_.Exception.Message)"
    }
}
$markedJs = Get-Content -LiteralPath $markedPath -Raw
Write-Host "==> Markdown-Engine bereit (Cache: .pdf-export/marked.min.js)" -ForegroundColor Green

# ===========================================================================
#  4. Quell-Dateien bestimmen (Parameter oder interaktiver Prompt)
# ===========================================================================

function Resolve-Sources([string[]]$paths) {
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($p in $paths) {
        $full = if ([System.IO.Path]::IsPathRooted($p)) { $p } else { Join-Path $here $p }
        if (Test-Path $full -PathType Container) {
            Get-ChildItem -Path $full -Recurse -File -Filter '*.md' |
                Sort-Object FullName | ForEach-Object { $result.Add($_.FullName) }
        }
        elseif (Test-Path $full -PathType Leaf) {
            $result.Add((Resolve-Path $full).Path)
        }
        else {
            Write-Warning "Pfad nicht gefunden, uebersprungen: $p"
        }
    }
    return $result
}

$files = @()
if ($Source) {
    $files = Resolve-Sources $Source
}
else {
    $allMd = @(Get-AllMarkdown)
    if (-not $allMd) { throw "Keine .md-Dateien im Projekt gefunden." }

    Write-Host ""
    Write-Host "Was soll exportiert werden?" -ForegroundColor Cyan
    Write-Host "  [1] Alle .md-Dateien im Projekt  ($($allMd.Count) Dateien)"
    Write-Host "  [2] Ein ganzer Ordner"
    Write-Host "  [3] Ein einzelnes File"
    Write-Host "  [4] Mehrere einzelne Files"
    do { $choice = Read-Host "Auswahl (1/2/3/4)" } while ($choice -notin @('1', '2', '3', '4'))

    switch ($choice) {
        '1' {
            $files = $allMd | ForEach-Object { $_.FullName }
        }
        '2' {
            $dirs = $allMd | ForEach-Object { $_.DirectoryName } |
                Sort-Object -Unique
            Write-Host ""
            Write-Host "Verfuegbare Ordner:" -ForegroundColor Cyan
            for ($i = 0; $i -lt $dirs.Count; $i++) {
                $rel = $dirs[$i].Substring($here.Length).TrimStart('\', '/')
                if (-not $rel) { $rel = '.' }
                $cnt = ($allMd | Where-Object { $_.DirectoryName -eq $dirs[$i] }).Count
                Write-Host ("  [{0}] {1}  ({2} .md)" -f ($i + 1), $rel, $cnt)
            }
            do {
                $sel = Read-Host "Ordner-Nummer"
                $ok = ($sel -match '^\d+$') -and ([int]$sel -ge 1) -and ([int]$sel -le $dirs.Count)
            } while (-not $ok)
            $chosen = $dirs[[int]$sel - 1]
            $files = $allMd | Where-Object { $_.DirectoryName -eq $chosen } |
                ForEach-Object { $_.FullName }
        }
        '3' {
            Write-Host ""
            Write-Host "Verfuegbare Dateien:" -ForegroundColor Cyan
            for ($i = 0; $i -lt $allMd.Count; $i++) {
                $rel = $allMd[$i].FullName.Substring($here.Length).TrimStart('\', '/')
                Write-Host ("  [{0}] {1}" -f ($i + 1), $rel)
            }
            do {
                $sel = Read-Host "Datei-Nummer"
                $ok = ($sel -match '^\d+$') -and ([int]$sel -ge 1) -and ([int]$sel -le $allMd.Count)
            } while (-not $ok)
            $files = @($allMd[[int]$sel - 1].FullName)
        }
        '4' {
            Write-Host ""
            Write-Host "Verfuegbare Dateien:" -ForegroundColor Cyan
            for ($i = 0; $i -lt $allMd.Count; $i++) {
                $rel = $allMd[$i].FullName.Substring($here.Length).TrimStart('\', '/')
                Write-Host ("  [{0}] {1}" -f ($i + 1), $rel)
            }
            do {
                $sel = Read-Host "Datei-Nummern (Komma-getrennt, z. B. 1,3,5)"
                $nums = $sel -split '[,\s]+' | Where-Object { $_ -match '^\d+$' } |
                    ForEach-Object { [int]$_ } |
                    Where-Object { $_ -ge 1 -and $_ -le $allMd.Count } |
                    Sort-Object -Unique
                $ok = $nums.Count -gt 0
            } while (-not $ok)
            $files = $nums | ForEach-Object { $allMd[$_ - 1].FullName }
        }
    }
}

$files = @($files | Select-Object -Unique)
if (-not $files -or $files.Count -eq 0) { throw "Keine Dateien zum Exportieren ausgewaehlt." }
Write-Host "==> $($files.Count) Datei(en) ausgewaehlt." -ForegroundColor Green

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

# ===========================================================================
#  5. HTML-Template (Clean/Business) - Platzhalter werden pro Datei ersetzt
# ===========================================================================

$htmlTemplate = @'
<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="utf-8">
<title>%%TITLE%%</title>
<style>
  * { box-sizing: border-box; }
  html, body { margin: 0; padding: 0; }
  body {
    font-family: "Segoe UI", system-ui, -apple-system, Arial, sans-serif;
    color: #23272e; line-height: 1.55; font-size: 10.75pt;
    -webkit-print-color-adjust: exact; print-color-adjust: exact;
  }
  h1, h2, h3, h4 { color: #1a3a5c; line-height: 1.25; margin: 1.2em 0 0.5em;
    break-after: avoid; page-break-after: avoid; }
  h1 { font-size: 20pt; border-bottom: 2px solid #1a3a5c; padding-bottom: .18em; margin-top: .2em; }
  h2 { font-size: 15pt; border-bottom: 1px solid #d0d7de; padding-bottom: .15em; }
  h3 { font-size: 12.5pt; }
  h4 { font-size: 11pt; color: #33506b; }
  p { margin: .55em 0; }
  a { color: #1a5fb4; text-decoration: none; }
  ul, ol { margin: .5em 0; padding-left: 1.5em; }
  li { margin: .2em 0; }
  hr { border: none; border-top: 1px solid #d0d7de; margin: 1.4em 0; }
  code { font-family: "Cascadia Code", "Consolas", monospace; font-size: .88em;
    background: #eef1f5; padding: .12em .35em; border-radius: 4px; }
  pre { background: #f6f8fa; border: 1px solid #d7dde5; border-radius: 6px;
    padding: .8em 1em; overflow: auto; break-inside: avoid; page-break-inside: avoid; }
  pre code { background: none; padding: 0; font-size: .85em; }
  blockquote { margin: .8em 0; padding: .1em 1em; border-left: 4px solid #cbd3dc;
    color: #56606b; background: #f7f9fb; border-radius: 0 4px 4px 0; }
  table { border-collapse: collapse; width: 100%; margin: .9em 0; font-size: .95em;
    break-inside: avoid; page-break-inside: avoid; }
  th, td { border: 1px solid #d0d7de; padding: 6px 10px; text-align: left; vertical-align: top; }
  th { background: #1a3a5c; color: #fff; font-weight: 600; }
  tr:nth-child(even) td { background: #f6f8fa; }
  img { max-width: 100%; }
  /* Obsidian-Callouts */
  blockquote.callout { border-left-width: 4px; border-radius: 6px; padding: .6em 1em;
    background: #eef2f7; border-color: #1a5fb4; }
  blockquote.callout .callout-title { display: block; font-weight: 700; margin-bottom: .3em;
    text-transform: uppercase; letter-spacing: .04em; font-size: .82em; }
  blockquote.callout-note, blockquote.callout-info, blockquote.callout-tip {
    background: #eaf2fb; border-color: #1a5fb4; }
  blockquote.callout-note .callout-title, blockquote.callout-info .callout-title,
  blockquote.callout-tip .callout-title { color: #1a5fb4; }
  blockquote.callout-important { background: #f5eefe; border-color: #8250df; }
  blockquote.callout-important .callout-title { color: #8250df; }
  blockquote.callout-warning, blockquote.callout-caution { background: #fff8e6; border-color: #bf8700; }
  blockquote.callout-warning .callout-title, blockquote.callout-caution .callout-title { color: #9a6a00; }
  blockquote.callout-danger, blockquote.callout-error, blockquote.callout-bug {
    background: #ffebe9; border-color: #cf222e; }
  blockquote.callout-danger .callout-title, blockquote.callout-error .callout-title,
  blockquote.callout-bug .callout-title { color: #cf222e; }
  blockquote.callout-success, blockquote.callout-check, blockquote.callout-done {
    background: #eaf7ee; border-color: #1a7f37; }
  blockquote.callout-success .callout-title, blockquote.callout-check .callout-title,
  blockquote.callout-done .callout-title { color: #1a7f37; }
</style>
<script>%%MARKED%%</script>
</head>
<body>
<article id="content"></article>
<script>
(function () {
  var b64 = "%%MDB64%%";
  var bytes = Uint8Array.from(atob(b64), function (c) { return c.charCodeAt(0); });
  var md = new TextDecoder("utf-8").decode(bytes);

  // Wiki-Links [[Ziel]] / [[Ziel|Alias]] -> Klartext entschaerfen
  md = md.replace(/\[\[([^\]|]+)(?:\|([^\]]+))?\]\]/g, function (m, target, alias) {
    return alias ? alias : target;
  });

  marked.setOptions({ gfm: true, breaks: false });
  document.getElementById("content").innerHTML = marked.parse(md);

  // Obsidian-Callouts: > [!TYPE] Titel  ->  farbige Box
  document.querySelectorAll("blockquote").forEach(function (bq) {
    var first = bq.querySelector("p");
    if (!first) return;
    var m = first.innerHTML.match(/^\s*\[!([A-Za-z]+)\]\s*(.*?)(<br\s*\/?>|$)/);
    if (!m) return;
    var type = m[1].toLowerCase();
    var title = (m[2] || "").trim();
    bq.classList.add("callout", "callout-" + type);
    var label = title ? title : m[1].charAt(0).toUpperCase() + m[1].slice(1).toLowerCase();
    first.innerHTML = first.innerHTML.replace(
      /^\s*\[![A-Za-z]+\]\s*(.*?)(<br\s*\/?>|$)/,
      '<span class="callout-title">' + label + '</span>'
    );
  });

  window.__ready = "%%NONCE%%";
})();
</script>
</body>
</html>
'@

# ===========================================================================
#  6. CDP-Infrastruktur (WebSocket zum Headless-Browser)
# ===========================================================================

function Get-FreePort {
    $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $l.Start()
    $p = $l.LocalEndpoint.Port
    $l.Stop()
    return $p
}

$script:cdpId = 0

function Send-CdpRaw($ws, [string]$json) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $seg = [System.ArraySegment[byte]]::new($bytes)
    $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true,
        [System.Threading.CancellationToken]::None).GetAwaiter().GetResult() | Out-Null
}

function Receive-CdpText($ws) {
    $buffer = New-Object byte[] 65536
    $ms = New-Object System.IO.MemoryStream
    do {
        $seg = [System.ArraySegment[byte]]::new($buffer)
        $res = $ws.ReceiveAsync($seg, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
        $ms.Write($buffer, 0, $res.Count)
    } while (-not $res.EndOfMessage)
    return [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
}

# Sendet ein CDP-Kommando und wartet auf die Antwort mit passender id.
function Invoke-Cdp($ws, [string]$method, $params, [string]$sessionId) {
    $script:cdpId++
    $myId = $script:cdpId
    $msg = @{ id = $myId; method = $method }
    if ($null -ne $params) { $msg.params = $params }
    if ($sessionId) { $msg.sessionId = $sessionId }
    $json = $msg | ConvertTo-Json -Depth 30 -Compress
    Send-CdpRaw $ws $json
    while ($true) {
        $text = Receive-CdpText $ws
        $obj = $text | ConvertFrom-Json
        if ($obj.id -eq $myId) {
            if ($obj.error) { throw "CDP-Fehler bei ${method}: $($obj.error.message)" }
            return $obj
        }
        # andernfalls: Event -> ignorieren (Readiness wird via Polling geprueft)
    }
}

# ===========================================================================
#  7. Browser starten + PDFs erzeugen
# ===========================================================================

$port = Get-FreePort
$userDataDir = New-TempDir 'pdfedge_'
$browserArgs = @(
    '--headless=new'
    '--disable-gpu'
    '--no-first-run'
    '--no-default-browser-check'
    '--disable-extensions'
    '--disable-background-networking'
    '--disable-sync'
    '--disable-component-update'
    '--hide-scrollbars'
    "--remote-debugging-port=$port"
    "--user-data-dir=$userDataDir"
    'about:blank'
)

Write-Host "==> Starte Headless-Browser (Port $port) ..." -ForegroundColor Yellow
$proc = Start-Process -FilePath $browser -ArgumentList $browserArgs -PassThru -WindowStyle Hidden

$ws = $null
$tempHtmlDir = New-TempDir 'pdfhtml_'
$made = 0
$usedNames = @{}

try {
    # WebSocket-Debugger-URL abfragen (mit Retry, bis der Browser bereit ist).
    $wsUrl = $null
    for ($i = 0; $i -lt 40; $i++) {
        try {
            $ver = Invoke-RestMethod -Uri "http://127.0.0.1:$port/json/version" -TimeoutSec 2
            if ($ver.webSocketDebuggerUrl) { $wsUrl = $ver.webSocketDebuggerUrl; break }
        }
        catch { Start-Sleep -Milliseconds 250 }
    }
    if (-not $wsUrl) { throw "Headless-Browser antwortet nicht am Debug-Port $port." }

    $ws = [System.Net.WebSockets.ClientWebSocket]::new()
    $ws.ConnectAsync([Uri]$wsUrl, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult() | Out-Null

    # Eine Seite (Target) anlegen und flach anbinden -> sessionId fuer Page-Kommandos.
    $t = Invoke-Cdp $ws 'Target.createTarget' @{ url = 'about:blank' } $null
    $targetId = $t.result.targetId
    $a = Invoke-Cdp $ws 'Target.attachToTarget' @{ targetId = $targetId; flatten = $true } $null
    $sessionId = $a.result.sessionId

    $stamp = Get-Date -Format 'dd.MM.yyyy'
    $safeTitle = $Title -replace '<', '&lt;' -replace '>', '&gt;'

    foreach ($file in $files) {
        $base = [System.IO.Path]::GetFileNameWithoutExtension($file)
        $docTitle = Get-TitleFromName $base

        # Eindeutigen PDF-Namen sichern (bei Namensgleichheit Parent voranstellen).
        $pdfName = $base
        if ($usedNames.ContainsKey($pdfName)) {
            $parent = Split-Path (Split-Path $file -Parent) -Leaf
            $pdfName = "${parent}_$base"
        }
        $usedNames[$pdfName] = $true
        $outPdf = Join-Path $OutDir "$pdfName.pdf"

        # HTML pro Datei bauen (marked + Markdown inline, keine Netzabhaengigkeit).
        $mdRaw = Get-Content -LiteralPath $file -Raw -Encoding UTF8
        $mdB64 = [Convert]::ToBase64String($utf8NoBom.GetBytes($mdRaw))
        $nonce = [guid]::NewGuid().ToString('N')

        $html = $htmlTemplate.
            Replace('%%TITLE%%', ($docTitle -replace '<', '&lt;' -replace '>', '&gt;')).
            Replace('%%MARKED%%', $markedJs).
            Replace('%%MDB64%%', $mdB64).
            Replace('%%NONCE%%', $nonce)

        $htmlFile = Join-Path $tempHtmlDir "$nonce.html"
        [System.IO.File]::WriteAllText($htmlFile, $html, $utf8NoBom)
        $fileUrl = ([Uri]$htmlFile).AbsoluteUri

        # Navigieren und auf fertiges Rendern warten (Nonce-Marker).
        Invoke-Cdp $ws 'Page.navigate' @{ url = $fileUrl } $sessionId | Out-Null
        $ready = $false
        for ($i = 0; $i -lt 80; $i++) {
            Start-Sleep -Milliseconds 60
            $ev = Invoke-Cdp $ws 'Runtime.evaluate' @{
                expression = "window.__ready === '$nonce'"; returnByValue = $true
            } $sessionId
            if ($ev.result.result.value -eq $true) { $ready = $true; break }
        }
        if (-not $ready) { Write-Warning "Render-Timeout: $base (fahre trotzdem fort)" }

        # Header/Footer-Templates (Chrome verlangt explizite font-size).
        $headerTpl = '<div style="font-size:8px;width:100%;padding:0 12mm;color:#8a94a0;' +
            'font-family:Segoe UI,Arial,sans-serif;display:flex;justify-content:space-between;">' +
            '<span>' + $safeTitle + '</span><span class="title"></span></div>'
        $footerTpl = '<div style="font-size:8px;width:100%;padding:0 12mm;color:#8a94a0;' +
            'font-family:Segoe UI,Arial,sans-serif;display:flex;justify-content:space-between;">' +
            '<span>' + $stamp + '</span>' +
            '<span>Seite <span class="pageNumber"></span> / <span class="totalPages"></span></span></div>'

        $pdf = Invoke-Cdp $ws 'Page.printToPDF' @{
            printBackground     = $true
            displayHeaderFooter = $true
            headerTemplate      = $headerTpl
            footerTemplate      = $footerTpl
            paperWidth          = 8.27
            paperHeight         = 11.69
            marginTop           = 0.6
            marginBottom        = 0.6
            marginLeft          = 0.6
            marginRight         = 0.6
            preferCSSPageSize   = $false
        } $sessionId

        [System.IO.File]::WriteAllBytes($outPdf, [Convert]::FromBase64String($pdf.result.data))
        $made++
        Write-Host ("  [OK] {0}  ->  {1}" -f $base, ("export-artefacts/pdf/$pdfName.pdf")) -ForegroundColor Green
    }
}
finally {
    if ($ws) {
        try {
            Invoke-Cdp $ws 'Browser.close' $null $null | Out-Null
        }
        catch { }
        try { $ws.Dispose() } catch { }
    }
    if ($proc -and -not $proc.HasExited) {
        try { $proc.Kill() } catch { }
    }
    if (Test-Path $tempHtmlDir) { Remove-Item $tempHtmlDir -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path $userDataDir) { Remove-Item $userDataDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ""
Write-Host "==> Fertig: $made PDF(s) in $OutDir" -ForegroundColor Cyan
