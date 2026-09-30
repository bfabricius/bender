<#
.SYNOPSIS
    Baut den interaktiven Master-Schedule-Web-Editor (master-schedule-editor.html).

.DESCRIPTION
    Liest mem-index/09_Master-Schedule.json und erzeugt eine einzelne, self-contained
    HTML-Datei (master-schedule-editor.html) im Projekt-Root: Gantt-artige Zeitachse
    (Lanes/Arbeitspakete/Meilensteine), FTE-pro-Kalenderwoche-Ableitung, Filter (Arbeitsstrom,
    Datumsbereich), Bearbeiten (Arbeitspakete/Lanes/Meilensteine/Projekt-Rahmendaten),
    Speichern (Download `master-schedule-changes.json`, danach `./apply-master-schedule-changes.ps1`
    ausfuehren), "Aktuelle Daten neu laden" (Datei-Picker + Bestaetigung) sowie Export als PNG/PDF
    (nur die aktuell gefilterte Ansicht).

    `html2canvas` und `jsPDF` werden einmalig in den Cache-Ordner .schedule-export/ geladen und
    direkt in die generierte HTML-Datei eingebettet -> das Ergebnis ist vollstaendig offline-faehig
    (kein CDN-Zugriff beim Oeffnen der Datei noetig).

    Der Memory-Index wird von diesem Skript nur GELESEN, nie geschrieben. Aenderungen aus dem
    Editor werden erst durch `./apply-master-schedule-changes.ps1` (nach Bestaetigung) uebernommen.

.PARAMETER ProjectRoot
    Wurzelordner des Mandats. Default: Ordner, in dem dieses Skript liegt.

.PARAMETER MemIndexFolder
    Name des Memory-Index-Ordners relativ zu ProjectRoot. Default: "mem-index".

.PARAMETER Reinstall
    Loescht die zwischengespeicherten html2canvas/jsPDF-Bibliotheken und laedt sie neu.

.EXAMPLE
    ./build-master-schedule-editor.ps1
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot = $PSScriptRoot,
    [string]$MemIndexFolder = 'mem-index',
    [switch]$Reinstall
)

$ErrorActionPreference = 'Stop'

$MemIndexPath = Join-Path $ProjectRoot $MemIndexFolder
$JsonPath = Join-Path $MemIndexPath '09_Master-Schedule.json'
$OutPath = Join-Path $ProjectRoot 'master-schedule-editor.html'
$CacheDir = Join-Path $ProjectRoot '.schedule-export'

if (-not (Test-Path -LiteralPath $JsonPath)) {
    throw "Kein Master-Schedule gefunden: $JsonPath. Zuerst ./schedule-wizard.ps1 ausfuehren (oder Copilot-Chat: /pflege-master-schedule)."
}

function Get-MandateName {
    param([string]$ProjectRoot)
    $configPath = Join-Path $ProjectRoot 'mandate.config.json'
    if (Test-Path -LiteralPath $configPath) {
        try {
            $cfg = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($cfg.projectName) { return [string]$cfg.projectName }
        } catch {
            # ignore, fall through to folder-name fallback
        }
    }
    return (Split-Path -Leaf $ProjectRoot)
}

function Get-CachedLibrary {
    param([string]$Name, [string]$Url, [string]$CacheDir, [switch]$Reinstall)
    $path = Join-Path $CacheDir $Name
    if ($Reinstall -and (Test-Path -LiteralPath $path)) { Remove-Item -LiteralPath $path -Force }
    if (-not (Test-Path -LiteralPath $path)) {
        if (-not (Test-Path -LiteralPath $CacheDir)) { New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null }
        Write-Host "==> Lade $Name (einmalig) ..." -ForegroundColor Yellow
        try {
            Invoke-WebRequest -Uri $Url -OutFile $path -UseBasicParsing
        } catch {
            throw "$Name konnte nicht geladen werden ($Url). Fuer den ersten Lauf ist eine Internetverbindung noetig. Details: $($_.Exception.Message)"
        }
    }
    return (Get-Content -LiteralPath $path -Raw)
}

$mandateName = Get-MandateName -ProjectRoot $ProjectRoot
$scheduleRaw = Get-Content -LiteralPath $JsonPath -Raw -Encoding UTF8
# Validate only - the raw text (not a re-serialized copy) is embedded so the browser sees
# exactly the on-disk JSON shape.
$null = $scheduleRaw | ConvertFrom-Json

$html2canvasJs = Get-CachedLibrary -Name 'html2canvas.min.js' -Url 'https://cdn.jsdelivr.net/npm/html2canvas@1.4.1/dist/html2canvas.min.js' -CacheDir $CacheDir -Reinstall:$Reinstall
$jsPdfJs = Get-CachedLibrary -Name 'jspdf.umd.min.js' -Url 'https://cdn.jsdelivr.net/npm/jspdf@2.5.1/dist/jspdf.umd.min.js' -CacheDir $CacheDir -Reinstall:$Reinstall
Write-Host '==> html2canvas/jsPDF bereit (Cache: .schedule-export/)' -ForegroundColor Green

# Embed everything (libraries + JSON) as base64 rather than raw source text. A JS string literal
# can only ever contain the base64 alphabet [A-Za-z0-9+/=], which cannot form "</script" or
# "<!--" in any byte configuration - this is immune to script-tag-breakout regardless of what
# byte sequences the payloads contain. Escaping only the literal "</script" substring (tried
# first) was NOT sufficient in practice: jsPDF's own source contains this sequence as part of an
# HTML template string used for its window/new-tab PDF-preview output mode, and re-embedding the
# raw (still broken) source from a stale cached .js file reproduced the same failure - base64
# sidesteps the whole class of issue instead of chasing individual dangerous substrings.
function ConvertTo-Base64Utf8 {
    param([string]$Text)
    return [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Text))
}
$html2canvasB64 = ConvertTo-Base64Utf8 -Text $html2canvasJs
$jsPdfB64 = ConvertTo-Base64Utf8 -Text $jsPdfJs
$scheduleB64 = ConvertTo-Base64Utf8 -Text $scheduleRaw

# ===========================================================================
#  HTML-Template
# ===========================================================================

$htmlTemplate = @'
<!doctype html>
<html lang="de">
<head>
<meta charset="utf-8">
<title>Master-Schedule - %%MANDATE%%</title>
<style>
  * { box-sizing: border-box; }
  body { font-family: Segoe UI, Arial, sans-serif; margin: 1.2rem; color: #222; }
  h1 { margin-bottom: 0.1rem; }
  #meta { color: #555; margin-bottom: 0.8rem; font-size: 0.85rem; }
  .toolbar { display: flex; flex-wrap: wrap; gap: 0.6rem; align-items: flex-end; background: #fafafa;
    border: 1px solid #ddd; border-radius: 6px; padding: 0.6rem 0.9rem; margin-bottom: 0.8rem; }
  .toolbar .group { display: flex; flex-direction: column; gap: 0.2rem; font-size: 0.8rem; }
  .toolbar .grp-title { font-weight: 600; }
  .toolbar .lane-checks { display: flex; flex-wrap: wrap; gap: 0.4rem; max-width: 360px; }
  .toolbar button { padding: 0.35rem 0.7rem; cursor: pointer; border: 1px solid #99a; border-radius: 4px;
    background: #eef; }
  .toolbar button:hover { background: #dde6f2; }
  .toolbar input[type=date] { padding: 0.25rem; }
  #chart-scroll { overflow-x: auto; border: 1px solid #ddd; border-radius: 6px; margin-bottom: 1rem; background: #fff; }
  #chart-inner { position: relative; }
  .chart-header { position: relative; height: 26px; border-bottom: 1px solid #ccc; background: #f4f7fb; }
  .tick { position: absolute; top: 0; bottom: 0; border-left: 1px solid #e2e6ec; font-size: 0.68rem;
    color: #667; padding-left: 3px; white-space: nowrap; }
  .lane-row { position: relative; height: 40px; border-bottom: 1px solid #eee; }
  .lane-row:nth-child(even) { background: #fbfcfe; }
  .lane-label { position: sticky; left: 0; z-index: 3; display: inline-block; background: inherit; }
  .wp-bar { position: absolute; top: 6px; height: 26px; border-radius: 4px; font-size: 0.72rem; color: #fff;
    overflow: hidden; white-space: nowrap; padding: 4px 6px; cursor: pointer; box-shadow: 0 1px 2px rgba(0,0,0,.25); }
  .milestone-line { position: absolute; top: 0; bottom: 0; width: 0; border-left: 2px dashed #9333ea; z-index: 2; }
  .milestone-label { position: absolute; top: -20px; font-size: 0.68rem; color: #9333ea; white-space: nowrap;
    transform: translateX(-50%); }
  .today-line { position: absolute; top: 0; bottom: 0; width: 0; border-left: 2px solid #2563eb; z-index: 4; }
  .progress-marker { position: absolute; top: 3px; width: 0; height: 34px; border-left: 3px solid #dc2626; z-index: 5; }
  #lane-names { position: relative; }
  .lane-name-cell { height: 40px; display: flex; flex-direction: column; justify-content: center;
    padding: 0 0.5rem; border-bottom: 1px solid #eee; font-size: 0.78rem; }
  .lane-name-cell b { font-size: 0.82rem; }
  .chart-flex { display: flex; }
  #lane-names { flex: 0 0 180px; border-right: 1px solid #ccc; background: #fafcff; }
  #lane-names .chart-header { background: #eef2f8; }
  table.fte { border-collapse: collapse; font-size: 0.8rem; margin-bottom: 1rem; }
  table.fte th, table.fte td { border: 1px solid #ddd; padding: 0.25rem 0.5rem; text-align: right; }
  table.fte th:first-child, table.fte td:first-child { text-align: left; }
  table.fte tr.total { font-weight: 600; background: #eef2f8; }
  .legend { display: flex; gap: 1rem; font-size: 0.78rem; margin-bottom: 0.6rem; align-items: center; }
  .legend span.swatch { display: inline-block; width: 0.8rem; height: 0.8rem; border-radius: 2px; margin-right: 0.25rem; vertical-align: -1px; }
  #modal-overlay { position: fixed; inset: 0; background: rgba(0,0,0,.4); display: none; align-items: center;
    justify-content: center; z-index: 50; }
  #modal-box { background: #fff; border-radius: 8px; padding: 1rem 1.2rem; min-width: 320px; max-width: 90vw;
    max-height: 85vh; overflow: auto; }
  #modal-box h3 { margin-top: 0; }
  #modal-box label { display: block; font-size: 0.82rem; margin: 0.5rem 0 0.15rem; }
  #modal-box input, #modal-box select, #modal-box textarea { width: 100%; padding: 0.3rem 0.4rem; }
  #modal-actions { margin-top: 0.9rem; display: flex; gap: 0.5rem; justify-content: flex-end; }
  details.instructions { background: #f4f7fb; border: 1px solid #cdd8e6; border-radius: 6px; padding: 0.5rem 1rem; margin-bottom: 0.8rem; }
  details.instructions summary { cursor: pointer; font-weight: 600; }
</style>
</head>
<body>
<h1>Master-Schedule - %%MANDATE%%</h1>
<div id="meta">Generiert: %%GENERATED%%</div>

<details class="instructions">
<summary>Anleitung</summary>
<ol>
  <li><b>Filtern:</b> Arbeitsstrom-Checkboxen und Von/Bis-Datum kombinieren sich (UND). Wirkt auf Zeitachse, FTE-Tabelle und Exporte.</li>
  <li><b>Bearbeiten:</b> auf ein Arbeitspaket klicken zum Bearbeiten/Loeschen. "+ Arbeitspaket", "+ Arbeitsstrom", "+ Meilenstein", "Projekt-Rahmendaten" oeffnen je ein Formular.</li>
  <li><b>Speichern:</b> laedt <code>master-schedule-changes.json</code> herunter (nach Bestaetigung). Datei in den Projekt-Root legen und <code>./apply-master-schedule-changes.ps1</code> ausfuehren, um den Memory-Index zu aktualisieren.</li>
  <li><b>Aktuelle Daten neu laden:</b> waehlt die aktuelle <code>mem-index/09_Master-Schedule.json</code> von der Festplatte aus (Datei-Dialog) und ersetzt nach Bestaetigung den aktuellen Bearbeitungsstand (ungespeicherte Aenderungen gehen sonst verloren).</li>
  <li><b>Export:</b> "Als PNG/PDF exportieren" erfasst exakt die aktuell gefilterte Zeitachsen-Ansicht.</li>
</ol>
</details>

<div class="legend">
  <span><span class="swatch" style="background:#9ca3af"></span>To Do</span>
  <span><span class="swatch" style="background:#f59e0b"></span>In Progress</span>
  <span><span class="swatch" style="background:#22c55e"></span>Done</span>
  <span><span class="swatch" style="background:#2563eb"></span>Heute</span>
  <span><span class="swatch" style="background:#dc2626"></span>Fortschritt je Lane</span>
  <span><span class="swatch" style="background:#9333ea"></span>Meilenstein</span>
</div>

<div class="toolbar">
  <div class="group">
    <span class="grp-title">Arbeitsstrom</span>
    <div class="lane-checks" id="lane-filter"></div>
  </div>
  <div class="group">
    <span class="grp-title">Von</span>
    <input type="date" id="filter-from">
  </div>
  <div class="group">
    <span class="grp-title">Bis</span>
    <input type="date" id="filter-to">
  </div>
  <div class="group">
    <span class="grp-title">&nbsp;</span>
    <button id="btn-clear-filter">Filter zuruecksetzen</button>
  </div>
  <div class="group">
    <span class="grp-title">&nbsp;</span>
    <button id="btn-edit-project">Projekt-Rahmendaten</button>
  </div>
  <div class="group">
    <span class="grp-title">&nbsp;</span>
    <button id="btn-add-milestone">+ Meilenstein</button>
  </div>
  <div class="group">
    <span class="grp-title">&nbsp;</span>
    <button id="btn-add-lane">+ Arbeitsstrom</button>
  </div>
  <div class="group">
    <span class="grp-title">&nbsp;</span>
    <button id="btn-save">Speichern</button>
  </div>
  <div class="group">
    <span class="grp-title">&nbsp;</span>
    <button id="btn-refresh">Aktuelle Daten neu laden</button>
    <input type="file" id="refresh-file-input" accept="application/json,.json" style="display:none">
  </div>
  <div class="group">
    <span class="grp-title">&nbsp;</span>
    <button id="btn-export-png">Als PNG exportieren</button>
  </div>
  <div class="group">
    <span class="grp-title">&nbsp;</span>
    <button id="btn-export-pdf">Als PDF exportieren</button>
  </div>
</div>

<div id="chart-scroll">
  <div class="chart-flex">
    <div id="lane-names"></div>
    <div id="chart-inner"></div>
  </div>
</div>

<h2>Ressourcen: FTE pro Kalenderwoche</h2>
<div id="fte-container"></div>

<div id="modal-overlay">
  <div id="modal-box"></div>
</div>

<script>
// Libraries + data are embedded as base64 (JS string literals can only ever contain the base64
// alphabet [A-Za-z0-9+/=], which cannot form "</script" or "<!--" in any byte configuration - so
// this is immune to script-tag-breakout regardless of what byte sequences the payloads contain,
// unlike embedding raw source directly (jsPDF's own source contains a literal "</script"
// sequence in its window/new-tab PDF-preview HTML template, which broke earlier versions of
// this generator that inlined it as-is).
function decodeUtf8Base64(b64) {
  var bytes = Uint8Array.from(atob(b64), function (c) { return c.charCodeAt(0); });
  return new TextDecoder('utf-8').decode(bytes);
}
function injectClassicScript(src) {
  var s = document.createElement('script');
  s.text = src;
  document.head.appendChild(s);
}
injectClassicScript(decodeUtf8Base64('%%HTML2CANVAS_B64%%'));
injectClassicScript(decodeUtf8Base64('%%JSPDF_B64%%'));

var INITIAL_SCHEDULE = JSON.parse(decodeUtf8Base64('%%SCHEDULE_B64%%'));
var PRIORITY_OPTIONS = ['Must', 'Should', 'Could', "Won't"];
var STATUS_OPTIONS = ['To Do', 'In Progress', 'Done'];
var STATUS_COLORS = { 'To Do': '#9ca3af', 'In Progress': '#f59e0b', 'Done': '#22c55e' };
var PX_PER_DAY = 9;

var state = { schedule: null, filter: { laneIds: null, fromDate: '', toDate: '' } };

function cloneSchedule(s) { return JSON.parse(JSON.stringify(s)); }

// ---- date helpers (UTC to avoid timezone drift on plain yyyy-MM-dd dates) ----
function parseISO(s) {
  var p = s.split('-').map(Number);
  return new Date(Date.UTC(p[0], p[1] - 1, p[2]));
}
function toISO(d) { return d.toISOString().slice(0, 10); }
function addDays(d, n) { var r = new Date(d); r.setUTCDate(r.getUTCDate() + n); return r; }
function isWeekday(d) { var w = d.getUTCDay(); return w !== 0 && w !== 6; }
function countWeekdaysInRange(startISO, endISO) {
  var s = parseISO(startISO), e = parseISO(endISO), c = 0;
  for (var d = s; d <= e; d = addDays(d, 1)) { if (isWeekday(d)) c++; }
  return Math.max(c, 1);
}
function getISOWeek(date) {
  var d = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  var dayNum = d.getUTCDay() || 7;
  d.setUTCDate(d.getUTCDate() + 4 - dayNum);
  var yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  var weekNo = Math.ceil((((d - yearStart) / 86400000) + 1) / 7);
  return { year: d.getUTCFullYear(), week: weekNo };
}

function getAllWorkPackages(schedule) {
  var all = [];
  schedule.lanes.forEach(function (l) { l.workPackages.forEach(function (w) { all.push(w); }); });
  return all;
}
function getNextId(items, prefix) {
  var max = 0;
  items.forEach(function (it) {
    var m = /^([A-Za-z]+)(\d+)$/.exec(it.id || '');
    if (m && m[1] === prefix) { max = Math.max(max, parseInt(m[2], 10)); }
  });
  return prefix + (max + 1);
}

// ---- filter helpers ----
function visibleLanes() {
  var s = state.schedule;
  if (!state.filter.laneIds) return s.lanes;
  return s.lanes.filter(function (l) { return state.filter.laneIds.indexOf(l.id) !== -1; });
}
function computeRange() {
  var s = state.schedule;
  var dates = [];
  if (s.project.startDate) dates.push(parseISO(s.project.startDate));
  if (s.project.endDate) dates.push(parseISO(s.project.endDate));
  s.milestones.forEach(function (m) { if (m.date) dates.push(parseISO(m.date)); });
  getAllWorkPackages(s).forEach(function (w) { dates.push(parseISO(w.startDate)); dates.push(parseISO(w.endDate)); });
  if (!dates.length) { var t = new Date(); dates = [t, addDays(t, 30)]; }
  var min = new Date(Math.min.apply(null, dates));
  var max = new Date(Math.max.apply(null, dates));
  if (state.filter.fromDate) min = parseISO(state.filter.fromDate);
  if (state.filter.toDate) max = parseISO(state.filter.toDate);
  return { start: addDays(min, -2), end: addDays(max, 2) };
}

// The "aktuelles Arbeitspaket" per lane: first (by start date) package whose status != Done;
// if all are Done, the last one by end date. Progress line sits at its left edge unless it is
// itself Done, in which case it sits at its right edge (whole lane complete up to there).
function currentWorkPackageMarker(lane) {
  if (!lane.workPackages.length) return null;
  var sorted = lane.workPackages.slice().sort(function (a, b) { return parseISO(a.startDate) - parseISO(b.startDate); });
  var current = sorted.find(function (w) { return w.status !== 'Done'; });
  if (current) return { wp: current, edge: 'left' };
  var lastDone = sorted.slice().sort(function (a, b) { return parseISO(a.endDate) - parseISO(b.endDate); }).pop();
  return { wp: lastDone, edge: 'right' };
}

// ---- rendering ----
function renderAll() {
  renderLaneFilter();
  renderChart();
  renderFte();
}

function renderLaneFilter() {
  var el = document.getElementById('lane-filter');
  el.innerHTML = '';
  state.schedule.lanes.forEach(function (l) {
    var id = 'lf-' + l.id;
    var checked = !state.filter.laneIds || state.filter.laneIds.indexOf(l.id) !== -1;
    var label = document.createElement('label');
    var cb = document.createElement('input');
    cb.type = 'checkbox'; cb.checked = checked; cb.id = id;
    cb.addEventListener('change', function () {
      var all = state.schedule.lanes.map(function (x) { return x.id; });
      var current = state.filter.laneIds ? state.filter.laneIds.slice() : all.slice();
      if (cb.checked) { if (current.indexOf(l.id) === -1) current.push(l.id); }
      else { current = current.filter(function (x) { return x !== l.id; }); }
      state.filter.laneIds = (current.length === all.length) ? null : current;
      renderChart(); renderFte();
    });
    label.appendChild(cb);
    label.appendChild(document.createTextNode(' ' + l.name));
    el.appendChild(label);
  });
}

function renderChart() {
  var lanes = visibleLanes();
  var range = computeRange();
  var totalDays = Math.max(1, Math.round((range.end - range.start) / 86400000));
  var width = totalDays * PX_PER_DAY;

  var namesEl = document.getElementById('lane-names');
  var innerEl = document.getElementById('chart-inner');
  namesEl.innerHTML = '';
  innerEl.innerHTML = '';
  innerEl.style.width = width + 'px';

  var namesHeader = document.createElement('div');
  namesHeader.className = 'chart-header';
  namesEl.appendChild(namesHeader);

  var header = document.createElement('div');
  header.className = 'chart-header';
  header.style.width = width + 'px';
  var cursor = new Date(range.start);
  while (cursor <= range.end) {
    if (cursor.getUTCDate() === 1 || cursor.getTime() === range.start.getTime()) {
      var tick = document.createElement('div');
      tick.className = 'tick';
      tick.style.left = (Math.round((cursor - range.start) / 86400000) * PX_PER_DAY) + 'px';
      tick.textContent = cursor.toLocaleDateString('de-CH', { year: 'numeric', month: 'short' });
      header.appendChild(tick);
    }
    cursor = addDays(cursor, 1);
  }
  innerEl.appendChild(header);

  lanes.forEach(function (lane) {
    var nameCell = document.createElement('div');
    nameCell.className = 'lane-name-cell';
    var b = document.createElement('b'); b.textContent = lane.id + ' - ' + lane.name;
    var owner = document.createElement('span'); owner.textContent = 'Owner: ' + (lane.owner || '-');
    nameCell.appendChild(b); nameCell.appendChild(owner);
    namesEl.appendChild(nameCell);

    var row = document.createElement('div');
    row.className = 'lane-row';
    row.style.width = width + 'px';

    lane.workPackages.forEach(function (wp) {
      var s = parseISO(wp.startDate), e = parseISO(wp.endDate);
      if (e < range.start || s > range.end) return;
      var left = Math.round((s - range.start) / 86400000) * PX_PER_DAY;
      var w = Math.max(PX_PER_DAY, Math.round((e - s) / 86400000 + 1) * PX_PER_DAY);
      var bar = document.createElement('div');
      bar.className = 'wp-bar';
      bar.style.left = left + 'px';
      bar.style.width = w + 'px';
      bar.style.background = STATUS_COLORS[wp.status] || '#666';
      bar.title = wp.id + ': ' + wp.name + ' [' + wp.priority + ', ' + wp.effortPT + ' PT, ' + wp.status + ']';
      bar.textContent = wp.name;
      bar.addEventListener('click', function () { openWorkPackageForm(lane, wp); });
      row.appendChild(bar);
    });

    var marker = currentWorkPackageMarker(lane);
    if (marker) {
      var mw = marker.wp;
      var mDate = marker.edge === 'left' ? parseISO(mw.startDate) : parseISO(mw.endDate);
      if (mDate >= range.start && mDate <= range.end) {
        var pm = document.createElement('div');
        pm.className = 'progress-marker';
        pm.style.left = (Math.round((mDate - range.start) / 86400000) * PX_PER_DAY + (marker.edge === 'right' ? PX_PER_DAY : 0)) + 'px';
        row.appendChild(pm);
      }
    }

    innerEl.appendChild(row);
  });

  state.schedule.milestones.forEach(function (m) {
    if (!m.date) return;
    var d = parseISO(m.date);
    if (d < range.start || d > range.end) return;
    var line = document.createElement('div');
    line.className = 'milestone-line';
    line.style.left = (Math.round((d - range.start) / 86400000) * PX_PER_DAY) + 'px';
    var lbl = document.createElement('div');
    lbl.className = 'milestone-label';
    lbl.style.left = line.style.left;
    lbl.textContent = m.id + ': ' + m.name;
    innerEl.appendChild(line);
    innerEl.appendChild(lbl);
  });

  var today = new Date();
  var todayUtc = new Date(Date.UTC(today.getFullYear(), today.getMonth(), today.getDate()));
  if (todayUtc >= range.start && todayUtc <= range.end) {
    var tl = document.createElement('div');
    tl.className = 'today-line';
    tl.style.left = (Math.round((todayUtc - range.start) / 86400000) * PX_PER_DAY) + 'px';
    innerEl.appendChild(tl);
  }

  var totalHeight = header.offsetHeight + lanes.length * 40;
  innerEl.style.minHeight = totalHeight + 'px';
}

function renderFte() {
  var lanes = visibleLanes();
  var range = computeRange();
  var weeks = [];
  var seen = {};
  var cursor = new Date(range.start);
  while (cursor <= range.end) {
    var iw = getISOWeek(cursor);
    var key = iw.year + '-W' + (iw.week < 10 ? '0' : '') + iw.week;
    if (!seen[key]) {
      seen[key] = true;
      weeks.push({ key: key, label: 'KW' + (iw.week < 10 ? '0' : '') + iw.week + ' ' + iw.year });
    }
    cursor = addDays(cursor, 7);
  }

  var container = document.getElementById('fte-container');
  if (!weeks.length || !lanes.length) { container.innerHTML = '<em>Keine Daten fuer die aktuelle Auswahl.</em>'; return; }

  var byLane = {};
  var totals = {};
  weeks.forEach(function (w) { totals[w.key] = 0; });
  lanes.forEach(function (lane) {
    byLane[lane.id] = {};
    weeks.forEach(function (w) { byLane[lane.id][w.key] = 0; });
    lane.workPackages.forEach(function (wp) {
      var wpStart = parseISO(wp.startDate), wpEnd = parseISO(wp.endDate);
      var dailyRate = wp.effortPT / countWeekdaysInRange(wp.startDate, wp.endDate);
      weeks.forEach(function (w) {
        var iw = w.key.split('-W');
        var yr = parseInt(iw[0], 10), wn = parseInt(iw[1], 10);
        var jan4 = new Date(Date.UTC(yr, 0, 4));
        var mondayW1 = addDays(jan4, -(((jan4.getUTCDay() || 7) - 1)));
        var weekStart = addDays(mondayW1, (wn - 1) * 7);
        var weekEnd = addDays(weekStart, 6);
        var s = wpStart > weekStart ? wpStart : weekStart;
        var e = wpEnd < weekEnd ? wpEnd : weekEnd;
        if (s > e) return;
        var overlap = 0;
        for (var d = s; d <= e; d = addDays(d, 1)) { if (isWeekday(d)) overlap++; }
        var fte = (overlap * dailyRate) / 5;
        byLane[lane.id][w.key] += fte;
        totals[w.key] += fte;
      });
    });
  });

  var html = '<table class="fte"><thead><tr><th>Lane</th>';
  weeks.forEach(function (w) { html += '<th>' + w.label + '</th>'; });
  html += '</tr></thead><tbody>';
  lanes.forEach(function (lane) {
    html += '<tr><td>' + lane.id + ' - ' + lane.name + '</td>';
    weeks.forEach(function (w) { html += '<td>' + byLane[lane.id][w.key].toFixed(2) + '</td>'; });
    html += '</tr>';
  });
  html += '<tr class="total"><td>Gesamt</td>';
  weeks.forEach(function (w) { html += '<td>' + totals[w.key].toFixed(2) + '</td>'; });
  html += '</tr></tbody></table>';
  container.innerHTML = html;
}

// ---- modal forms ----
function closeModal() { document.getElementById('modal-overlay').style.display = 'none'; }
function openModal(title, bodyEl, onSave, onDelete) {
  var box = document.getElementById('modal-box');
  box.innerHTML = '';
  var h = document.createElement('h3'); h.textContent = title; box.appendChild(h);
  box.appendChild(bodyEl);
  var actions = document.createElement('div'); actions.id = 'modal-actions';
  if (onDelete) {
    var del = document.createElement('button'); del.textContent = 'Loeschen';
    del.addEventListener('click', function () {
      if (!confirm('Wirklich loeschen?')) return;
      if (onDelete() === false) return;
      closeModal(); renderAll();
    });
    actions.appendChild(del);
  }
  var cancel = document.createElement('button'); cancel.textContent = 'Abbrechen';
  cancel.addEventListener('click', closeModal);
  var save = document.createElement('button'); save.textContent = 'Speichern';
  save.addEventListener('click', function () { if (onSave()) { closeModal(); renderAll(); } });
  actions.appendChild(cancel); actions.appendChild(save);
  box.appendChild(actions);
  document.getElementById('modal-overlay').style.display = 'flex';
}
function field(labelText, inputEl) {
  var wrap = document.createElement('div');
  var l = document.createElement('label'); l.textContent = labelText;
  wrap.appendChild(l); wrap.appendChild(inputEl);
  return wrap;
}
function selectEl(options, value) {
  var s = document.createElement('select');
  options.forEach(function (o) { var opt = document.createElement('option'); opt.value = o; opt.textContent = o; if (o === value) opt.selected = true; s.appendChild(opt); });
  return s;
}

function openProjectForm() {
  var body = document.createElement('div');
  var name = document.createElement('input'); name.value = state.schedule.project.name || '';
  var start = document.createElement('input'); start.type = 'date'; start.value = state.schedule.project.startDate || '';
  var end = document.createElement('input'); end.type = 'date'; end.value = state.schedule.project.endDate || '';
  body.appendChild(field('Projektname', name));
  body.appendChild(field('Startdatum', start));
  body.appendChild(field('Enddatum', end));
  openModal('Projekt-Rahmendaten', body, function () {
    state.schedule.project.name = name.value;
    state.schedule.project.startDate = start.value;
    state.schedule.project.endDate = end.value;
    return true;
  });
}

function openMilestoneForm(milestone) {
  var body = document.createElement('div');
  var name = document.createElement('input'); name.value = milestone ? milestone.name : '';
  var date = document.createElement('input'); date.type = 'date'; date.value = milestone ? milestone.date : '';
  var desc = document.createElement('textarea'); desc.value = milestone ? (milestone.description || '') : '';
  body.appendChild(field('Name', name));
  body.appendChild(field('Datum', date));
  body.appendChild(field('Beschreibung (optional)', desc));
  openModal(milestone ? 'Meilenstein bearbeiten' : 'Meilenstein hinzufuegen', body, function () {
    if (!name.value || !date.value) { alert('Name und Datum sind Pflichtfelder.'); return false; }
    if (milestone) { milestone.name = name.value; milestone.date = date.value; milestone.description = desc.value; }
    else {
      var id = getNextId(state.schedule.milestones, 'M');
      state.schedule.milestones.push({ id: id, name: name.value, date: date.value, description: desc.value });
    }
    return true;
  }, milestone ? function () {
    state.schedule.milestones = state.schedule.milestones.filter(function (m) { return m !== milestone; });
  } : null);
}

function openLaneForm(lane) {
  var body = document.createElement('div');
  var name = document.createElement('input'); name.value = lane ? lane.name : '';
  var owner = document.createElement('input'); owner.value = lane ? lane.owner : '';
  body.appendChild(field('Name', name));
  body.appendChild(field('Owner', owner));
  openModal(lane ? 'Arbeitsstrom bearbeiten' : 'Arbeitsstrom hinzufuegen', body, function () {
    if (!name.value) { alert('Name ist Pflichtfeld.'); return false; }
    if (lane) { lane.name = name.value; lane.owner = owner.value; }
    else {
      var id = getNextId(state.schedule.lanes, 'L');
      state.schedule.lanes.push({ id: id, name: name.value, owner: owner.value, workPackages: [] });
    }
    return true;
  }, lane ? function () {
    if (lane.workPackages.length && !confirm('Dieser Arbeitsstrom enthaelt ' + lane.workPackages.length + ' Arbeitspaket(e) - diese werden mitgeloescht. Fortfahren?')) { return false; }
    state.schedule.lanes = state.schedule.lanes.filter(function (l) { return l !== lane; });
  } : null);
}

function openWorkPackageForm(lane, wp) {
  var body = document.createElement('div');
  var name = document.createElement('input'); name.value = wp ? wp.name : '';
  var start = document.createElement('input'); start.type = 'date'; start.value = wp ? wp.startDate : '';
  var end = document.createElement('input'); end.type = 'date'; end.value = wp ? wp.endDate : '';
  var prio = selectEl(PRIORITY_OPTIONS, wp ? wp.priority : 'Should');
  var effort = document.createElement('input'); effort.type = 'number'; effort.min = '0'; effort.step = '0.5';
  effort.value = wp ? wp.effortPT : '1';
  var status = selectEl(STATUS_OPTIONS, wp ? wp.status : 'To Do');
  body.appendChild(field('Name', name));
  body.appendChild(field('Startdatum', start));
  body.appendChild(field('Enddatum', end));
  body.appendChild(field('Prioritaet', prio));
  body.appendChild(field('Aufwand (PT)', effort));
  body.appendChild(field('Status', status));
  openModal((wp ? 'Arbeitspaket bearbeiten' : 'Arbeitspaket hinzufuegen') + ' - ' + lane.id + ' ' + lane.name, body, function () {
    if (!name.value || !start.value || !end.value) { alert('Name, Start- und Enddatum sind Pflichtfelder.'); return false; }
    if (start.value > end.value) { alert('Startdatum muss vor oder gleich Enddatum liegen.'); return false; }
    var effortNum = parseFloat(effort.value) || 0;
    if (wp) {
      wp.name = name.value; wp.startDate = start.value; wp.endDate = end.value;
      wp.priority = prio.value; wp.effortPT = effortNum; wp.status = status.value;
    } else {
      var id = getNextId(getAllWorkPackages(state.schedule), 'WP');
      lane.workPackages.push({ id: id, name: name.value, startDate: start.value, endDate: end.value, priority: prio.value, effortPT: effortNum, status: status.value });
    }
    return true;
  }, wp ? function () {
    lane.workPackages = lane.workPackages.filter(function (w) { return w !== wp; });
  } : null);
}

// ---- toolbar wiring ----
document.getElementById('btn-edit-project').addEventListener('click', openProjectForm);
document.getElementById('btn-add-milestone').addEventListener('click', function () { openMilestoneForm(null); });
document.getElementById('btn-add-lane').addEventListener('click', function () { openLaneForm(null); });
document.getElementById('filter-from').addEventListener('change', function (e) { state.filter.fromDate = e.target.value; renderChart(); renderFte(); });
document.getElementById('filter-to').addEventListener('change', function (e) { state.filter.toDate = e.target.value; renderChart(); renderFte(); });
document.getElementById('btn-clear-filter').addEventListener('click', function () {
  state.filter = { laneIds: null, fromDate: '', toDate: '' };
  document.getElementById('filter-from').value = '';
  document.getElementById('filter-to').value = '';
  renderAll();
});

document.getElementById('btn-save').addEventListener('click', function () {
  if (!confirm('Aenderungen als master-schedule-changes.json herunterladen? Diese Datei danach in den Projekt-Root legen und ./apply-master-schedule-changes.ps1 ausfuehren, um den Memory-Index zu aktualisieren.')) return;
  var blob = new Blob([JSON.stringify(state.schedule, null, 2)], { type: 'application/json' });
  var a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = 'master-schedule-changes.json';
  a.click();
});

document.getElementById('btn-refresh').addEventListener('click', function () {
  document.getElementById('refresh-file-input').click();
});
document.getElementById('refresh-file-input').addEventListener('change', function (e) {
  var file = e.target.files[0];
  e.target.value = '';
  if (!file) return;
  if (!confirm('Nicht gespeicherte Aenderungen gehen verloren - aktuelle Daten aus "' + file.name + '" trotzdem neu laden?')) return;
  var reader = new FileReader();
  reader.onload = function (ev) {
    try {
      var parsed = JSON.parse(ev.target.result);
      state.schedule = cloneSchedule(parsed);
      state.filter = { laneIds: null, fromDate: '', toDate: '' };
      document.getElementById('filter-from').value = '';
      document.getElementById('filter-to').value = '';
      renderAll();
    } catch (err) {
      alert('Datei konnte nicht als JSON gelesen werden: ' + err.message);
    }
  };
  reader.readAsText(file);
});

function downloadCanvas(canvas, filename, asPdf) {
  if (asPdf) {
    var jsPDFCtor = window.jspdf.jsPDF;
    var doc = new jsPDFCtor({ orientation: canvas.width >= canvas.height ? 'landscape' : 'portrait', unit: 'px', format: [canvas.width, canvas.height] });
    doc.addImage(canvas.toDataURL('image/png'), 'PNG', 0, 0, canvas.width, canvas.height);
    doc.save(filename);
  } else {
    canvas.toBlob(function (blob) {
      var a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = filename;
      a.click();
    });
  }
}
document.getElementById('btn-export-png').addEventListener('click', function () {
  html2canvas(document.getElementById('chart-scroll')).then(function (canvas) { downloadCanvas(canvas, 'master-schedule.png', false); });
});
document.getElementById('btn-export-pdf').addEventListener('click', function () {
  html2canvas(document.getElementById('chart-scroll')).then(function (canvas) { downloadCanvas(canvas, 'master-schedule.pdf', true); });
});
document.getElementById('modal-overlay').addEventListener('click', function (e) { if (e.target.id === 'modal-overlay') closeModal(); });

state.schedule = cloneSchedule(INITIAL_SCHEDULE);
renderAll();
</script>
</body>
</html>
'@

$html = $htmlTemplate.
    Replace('%%MANDATE%%', $mandateName).
    Replace('%%GENERATED%%', (Get-Date -Format 'yyyy-MM-dd HH:mm')).
    Replace('%%HTML2CANVAS_B64%%', $html2canvasB64).
    Replace('%%JSPDF_B64%%', $jsPdfB64).
    Replace('%%SCHEDULE_B64%%', $scheduleB64)

$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText([System.IO.Path]::GetFullPath($OutPath), $html, $enc)
Write-Host "==> Master-Schedule-Editor geschrieben: $OutPath" -ForegroundColor Green
