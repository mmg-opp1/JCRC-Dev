"""
Turn a UAT test script from Markdown into a Word document testers can actually use.

The testers are fundraisers, not developers - they will not open a .md file, and they need to
type answers into the document and sign it. So this is not a generic Markdown converter; it is
built around the shape these scripts have:

  - Any EMPTY table cell is an answer box. It gets light shading and a minimum height so there
    is somewhere obvious to type. This is the whole reason for a purpose-built converter: a
    generic one produces hairline-thin empty cells that look like a rendering fault.
  - A table whose header row is blank is a form, not data, so its header row is dropped.
  - Blockquotes carry the "what worries us" charter framing, so they are indented and italic
    rather than styled as quotations.

Usage:  python md_to_docx.py <input.md> [output.docx]

Jason Ott, 2026-08-21.
"""
import re
import sys
from pathlib import Path

from docx import Document
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor

BODY_FONT = "Calibri"
ANSWER_SHADE = "FBFBF8"      # barely-there warm grey: reads as "type here", prints clean
LABEL_SHADE = "F2F2F2"
ACCENT = RGBColor(0x1F, 0x38, 0x64)
ANSWER_MIN_HEIGHT = Pt(34)
FREEFORM_MIN_HEIGHT = Pt(150)   # a table that is ALL empty is an open "anything else" box


# --------------------------------------------------------------------------- low-level helpers
def shade_cell(cell, hex_fill):
    """Word has no cell-background API, so the shading element goes in by hand."""
    tc_pr = cell._tc.get_or_add_tcPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear")
    shd.set(qn("w:color"), "auto")
    shd.set(qn("w:fill"), hex_fill)
    tc_pr.append(shd)


def set_row_height(row, height):
    tr_pr = row._tr.get_or_add_trPr()
    tr_height = OxmlElement("w:trHeight")
    tr_height.set(qn("w:val"), str(int(height.twips)))
    tr_height.set(qn("w:hRule"), "atLeast")
    tr_pr.append(tr_height)


def add_page_numbers(section):
    """Footer of the form 'Page N of M'. Field codes have to be built element by element."""
    p = section.footer.paragraphs[0]
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.add_run("Page ").font.size = Pt(9)

    def field(instr):
        r = p.add_run()
        fld_begin = OxmlElement("w:fldChar")
        fld_begin.set(qn("w:fldCharType"), "begin")
        instr_el = OxmlElement("w:instrText")
        instr_el.set(qn("xml:space"), "preserve")
        instr_el.text = instr
        fld_end = OxmlElement("w:fldChar")
        fld_end.set(qn("w:fldCharType"), "end")
        r._r.append(fld_begin)
        r._r.append(instr_el)
        r._r.append(fld_end)
        r.font.size = Pt(9)

    field("PAGE")
    p.add_run(" of ").font.size = Pt(9)
    field("NUMPAGES")



BULLET_RE = re.compile(r"^[-*]\s+(.*)$")
NUMBER_RE = re.compile(r"^\d+\.\s+(.*)$")


def starts_new_block(line):
    """True if this line begins a new block rather than continuing the previous paragraph.

    The subtlety that matters: a wrapped line beginning "**accepts it**" is a continuation, not
    a bullet. Requiring the space after - or * is what separates a list marker from bold or a
    stray dash.
    """
    return bool(
        line.startswith(("#", "|", ">", "☐"))
        or BULLET_RE.match(line)
        or NUMBER_RE.match(line)
        or re.match(r"^-{3,}$", line)
    )


def gather_continuation(lines, i):
    """Collect the wrapped remainder of a list item: indented lines that start no new block."""
    chunk = []
    while i < len(lines):
        nxt = lines[i]
        if not nxt.strip() or not nxt.startswith((" ", "	")):
            break
        if starts_new_block(nxt.strip()):
            break
        chunk.append(nxt.strip())
        i += 1
    return chunk, i


# ------------------------------------------------------------------------------ inline markup
INLINE = re.compile(r"(\*\*.+?\*\*|\*[^*]+?\*|`[^`]+?`|\[[^\]]+?\]\([^)]+?\))")


def add_inline(paragraph, text):
    """Render **bold**, *italic*, `code` and [links](url) into runs."""
    for part in INLINE.split(text):
        if not part:
            continue
        if part.startswith("**") and part.endswith("**"):
            paragraph.add_run(part[2:-2]).bold = True
        elif part.startswith("*") and part.endswith("*") and len(part) > 2:
            paragraph.add_run(part[1:-1]).italic = True
        elif part.startswith("`") and part.endswith("`"):
            r = paragraph.add_run(part[1:-1])
            r.font.name = "Consolas"
            r.font.size = Pt(10)
        elif part.startswith("["):
            m = re.match(r"\[([^\]]+?)\]\(([^)]+?)\)", part)
            if m:
                # Testers are reading on paper as often as on screen, so show the label and let
                # the URL live in the plan document rather than cluttering the form.
                r = paragraph.add_run(m.group(1))
                r.font.color.rgb = RGBColor(0x1F, 0x38, 0x64)
                r.underline = True
            else:
                paragraph.add_run(part)
        else:
            paragraph.add_run(part)


# ------------------------------------------------------------------------------- table parsing
def split_row(line):
    line = line.strip()
    if line.startswith("|"):
        line = line[1:]
    if line.endswith("|"):
        line = line[:-1]
    return [c.strip() for c in line.split("|")]


def is_divider(line):
    return bool(re.match(r"^\s*\|?[\s:|-]+\|[\s:|-]*$", line)) and "-" in line


def emit_table(doc, rows):
    """rows[0] is the header. A blank header means this is a form, so the header is dropped."""
    header = rows[0]
    has_header = any(c.strip() for c in header)
    body = rows if has_header else rows[1:]
    if not body:
        return

    cols = max(len(r) for r in body)
    # A table with no text anywhere is not a form with labels - it is an open writing space, and
    # a two-line-high sliver does not invite anyone to write in it.
    freeform = not any(c.strip() for r in body for c in r)
    table = doc.add_table(rows=0, cols=cols)
    table.style = "Table Grid"
    table.alignment = WD_TABLE_ALIGNMENT.CENTER

    for i, row_cells in enumerate(body):
        row = table.add_row()
        is_header_row = has_header and i == 0
        row_is_answerable = False

        for j in range(cols):
            text = row_cells[j] if j < len(row_cells) else ""
            cell = row.cells[j]
            para = cell.paragraphs[0]
            para.paragraph_format.space_before = Pt(3)
            para.paragraph_format.space_after = Pt(3)
            add_inline(para, text)

            for run in para.runs:
                run.font.name = BODY_FONT
                run.font.size = Pt(10)
                if is_header_row:
                    run.bold = True

            if is_header_row:
                shade_cell(cell, LABEL_SHADE)
            elif not text.strip():
                # An empty cell is somewhere a tester writes. Make that unmistakable.
                shade_cell(cell, ANSWER_SHADE)
                row_is_answerable = True
            elif cols == 2 and j == 0:
                shade_cell(cell, LABEL_SHADE)

        if row_is_answerable:
            set_row_height(row, FREEFORM_MIN_HEIGHT if freeform else ANSWER_MIN_HEIGHT)

    if cols == 2 and not freeform:
        for row in table.rows:
            row.cells[0].width = Inches(2.6)
            row.cells[1].width = Inches(3.7)

    doc.add_paragraph()


# ---------------------------------------------------------------------------------- main build
def convert(md_path, docx_path):
    lines = Path(md_path).read_text(encoding="utf-8").splitlines()

    doc = Document()
    style = doc.styles["Normal"]
    style.font.name = BODY_FONT
    style.font.size = Pt(11)
    style.paragraph_format.space_after = Pt(8)
    style.paragraph_format.line_spacing = 1.08

    for section in doc.sections:
        section.top_margin = Inches(0.8)
        section.bottom_margin = Inches(0.8)
        section.left_margin = Inches(0.9)
        section.right_margin = Inches(0.9)
        add_page_numbers(section)

    i = 0
    while i < len(lines):
        raw = lines[i]
        line = raw.strip()

        # ---- table
        if line.startswith("|") and i + 1 < len(lines) and is_divider(lines[i + 1]):
            rows = [split_row(line)]
            i += 2
            while i < len(lines) and lines[i].strip().startswith("|"):
                rows.append(split_row(lines[i]))
                i += 1
            emit_table(doc, rows)
            continue

        # ---- horizontal rule: a section break between scenarios
        if re.match(r"^-{3,}$", line):
            p = doc.add_paragraph()
            p.paragraph_format.space_before = Pt(2)
            p.paragraph_format.space_after = Pt(2)
            pbdr = OxmlElement("w:pBdr")
            bottom = OxmlElement("w:bottom")
            bottom.set(qn("w:val"), "single")
            bottom.set(qn("w:sz"), "6")
            bottom.set(qn("w:color"), "D0D0D0")
            pbdr.append(bottom)
            p._p.get_or_add_pPr().append(pbdr)
            i += 1
            continue

        # ---- headings
        m = re.match(r"^(#{1,4})\s+(.*)$", line)
        if m:
            level = len(m.group(1))
            text = m.group(2)
            h = doc.add_heading("", level=min(level, 4))
            add_inline(h, text)
            for run in h.runs:
                run.font.name = BODY_FONT
                run.font.color.rgb = ACCENT
                run.font.size = Pt({1: 20, 2: 15, 3: 12.5, 4: 11.5}[min(level, 4)])
            i += 1
            continue

        # ---- blockquote (the charter worries)
        if line.startswith(">"):
            chunk = []
            while i < len(lines) and lines[i].strip().startswith(">"):
                chunk.append(lines[i].strip().lstrip(">").strip())
                i += 1
            p = doc.add_paragraph()
            p.paragraph_format.left_indent = Inches(0.3)
            p.paragraph_format.space_before = Pt(6)
            add_inline(p, " ".join(c for c in chunk if c))
            for run in p.runs:
                run.italic = True
                run.font.size = Pt(10.5)
            i += 1 if not chunk else 0
            continue

        # ---- bullets
        m = BULLET_RE.match(line)
        if m:
            i += 1
            rest, i = gather_continuation(lines, i)
            p = doc.add_paragraph(style="List Bullet")
            p.paragraph_format.space_after = Pt(4)
            add_inline(p, " ".join([m.group(1)] + rest))
            continue

        # ---- numbered
        m = NUMBER_RE.match(line)
        if m:
            i += 1
            rest, i = gather_continuation(lines, i)
            p = doc.add_paragraph(style="List Number")
            p.paragraph_format.space_after = Pt(4)
            add_inline(p, " ".join([m.group(1)] + rest))
            continue

        # ---- checkbox line outside a table
        if line.startswith("☐"):
            p = doc.add_paragraph()
            p.paragraph_format.left_indent = Inches(0.25)
            add_inline(p, line)
            i += 1
            continue

        # ---- blank
        if not line:
            i += 1
            continue

        # ---- paragraph: join wrapped lines
        chunk = [line]
        i += 1
        while i < len(lines):
            nxt = lines[i].strip()
            if not nxt or starts_new_block(nxt):
                break
            chunk.append(nxt)
            i += 1
        p = doc.add_paragraph()
        add_inline(p, " ".join(chunk))

    doc.save(docx_path)
    return docx_path


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    src = Path(sys.argv[1])
    dst = Path(sys.argv[2]) if len(sys.argv) > 2 else src.with_suffix(".docx")
    out = convert(src, dst)
    print(f"wrote {out}")
