"""Exportiert ein .drawio-Diagramm als PNG/SVG/PDF über die draw.io-Desktop-CLI (falls installiert).

Aufruf: python export_drawio.py <diagramm.drawio> [png|svg|pdf]
Ergebnis liegt neben der Quelldatei. Ohne installierte CLI: Hinweis und Exit-Code 2
(dann das Diagramm manuell in draw.io öffnen: Datei > Exportieren als).
"""
import os
import shutil
import subprocess
import sys

CANDIDATES = [
    shutil.which("drawio"),
    shutil.which("draw.io"),
    os.path.expandvars(r"%ProgramFiles%\draw.io\draw.io.exe"),
    os.path.expandvars(r"%LocalAppData%\Programs\draw.io\draw.io.exe"),
    "/Applications/draw.io.app/Contents/MacOS/draw.io",
]


def main(src, fmt="png"):
    exe = next((c for c in CANDIDATES if c and os.path.exists(c)), None)
    if not exe:
        print("draw.io-CLI nicht gefunden – Export manuell in draw.io (Datei > Exportieren als).")
        return 2
    out = os.path.splitext(src)[0] + "." + fmt
    cmd = [exe, "-x", "-f", fmt, "-b", "20", "-o", out, src]
    if fmt == "png":
        cmd[1:1] = ["--scale", "2"]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print(res.stderr or res.stdout)
        return 1
    print(f"Exportiert: {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "png"))
