"""Bereinigt Metadaten eines .docx-Templates in-place und meldet Restrisiken.

Aufruf: python sanitize_docx.py <template.docx>

- Leert Dokument-Eigenschaften (Autor, zuletzt geaendert von, Titel, Thema, Stichwoerter,
  Kommentar, Kategorie, Inhaltsstatus).
- Meldet Kommentare, Aenderungsverfolgung (Einfuegungen/Loeschungen) und eingebettete Bilder.
  Diese werden NICHT automatisch entfernt - der User entscheidet.
"""
import re
import sys
import zipfile

from docx import Document


def report(path):
    with zipfile.ZipFile(path) as zf:
        names = zf.namelist()
        body = zf.read("word/document.xml").decode("utf-8", errors="ignore")
        comments = 0
        if "word/comments.xml" in names:
            xml = zf.read("word/comments.xml").decode("utf-8", errors="ignore")
            comments = len(re.findall(r"<w:comment\b", xml))
        images = [n for n in names if n.startswith("word/media/")]
    ins = len(re.findall(r"<w:ins\b", body))
    dele = len(re.findall(r"<w:del\b", body))
    print(f"Kommentare: {comments} | Einfuegungen: {ins} | Loeschungen: {dele} | Bilder: {len(images)}")
    if comments or ins or dele:
        print("WARNUNG: Kommentare/Aenderungsverfolgung enthalten - in Word pruefen/annehmen/entfernen.")
    for name in images:
        print(f"HINWEIS: eingebettetes Bild {name} - auf Kundenbezug pruefen.")


def main(path):
    sys.stdout.reconfigure(encoding="utf-8")
    doc = Document(path)
    props = doc.core_properties
    for attr in ("author", "last_modified_by", "title", "subject", "keywords", "comments", "category", "content_status"):
        setattr(props, attr, "")
    doc.save(path)
    print(f"Metadaten bereinigt: {path}")
    report(path)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
