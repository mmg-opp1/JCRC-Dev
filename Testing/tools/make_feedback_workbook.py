"""
Build the feedback spreadsheet that goes out with a test script.

The testers record findings here rather than filling in the document. Leaving a scenario out
means it worked, so there is no pass column and nothing to sign. The sheet only ever holds
things worth fixing, which also means the returned file IS the defect list, with no collation
step in between.

Design notes worth keeping:
  - The scenario column is a dropdown, so findings can be sorted and counted per scenario
    without anyone having to type a name consistently.
  - Severity is worded in plain language rather than Blocker/Major/Minor. The testers are
    fundraisers, and "stops me working" needs no glossary.
  - Rows are pre-formatted well past what anyone will use, so the sheet does not visibly run
    out and discourage a long answer.

Usage:  python make_feedback_workbook.py <script-name> <output.xlsx>

Jason Ott, 2026-08-21.
"""
import sys

from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter
from openpyxl.worksheet.datavalidation import DataValidation

ACCENT = "1F3864"
HEADER_FILL = PatternFill("solid", fgColor="1F3864")
BAND_FILL = PatternFill("solid", fgColor="F7F7FA")
THIN = Side(style="thin", color="C8C8D0")
BORDER = Border(left=THIN, right=THIN, top=THIN, bottom=THIN)

SEVERITY = ["Stops me working", "Workable, but needs fixing", "Small thing"]

COLUMNS = [
    ("Scenario", 34),
    ("What you were trying to do", 40),
    ("What you expected", 38),
    ("What actually happened", 44),
    ("How much does it matter?", 26),
    ("Your name", 16),
]

BOARD_SCENARIOS = [
    "Scenario 1: See who is on the board today",
    "Scenario 2: Add a new board member",
    "Scenario 3: Record a board meeting and take attendance",
    "Scenario 4: Put someone on a committee",
    "Scenario 5: Someone comes off the board",
    "Scenario 6: Report to leadership",
    "Part 2: Complicated board history",
    "Part 2: Commitment number",
    "Part 2: Break it, then fix it",
    "Part 2: Year boundary",
    "Part 2: My own scenario",
    "General / anything else",
]

ROWS = 60


def build(script_title, scenarios, out_path):
    wb = Workbook()
    ws = wb.active
    ws.title = "Feedback"

    # ---- title block
    ws["A1"] = f"{script_title}: feedback"
    ws["A1"].font = Font(bold=True, size=15, color=ACCENT)
    ws.merge_cells(start_row=1, start_column=1, end_row=1, end_column=len(COLUMNS))

    ws["A2"] = ("One row per thing worth raising. If a scenario worked the way you expect, "
                "leave it out. There is nothing to sign and no pass to record.")
    ws["A2"].font = Font(size=10, italic=True, color="555555")
    ws.merge_cells(start_row=2, start_column=1, end_row=2, end_column=len(COLUMNS))
    ws.row_dimensions[2].height = 18

    ws.row_dimensions[3].height = 6      # spacer

    # ---- header
    head = 4
    for i, (name, width) in enumerate(COLUMNS, start=1):
        c = ws.cell(row=head, column=i, value=name)
        c.font = Font(bold=True, color="FFFFFF", size=11)
        c.fill = HEADER_FILL
        c.alignment = Alignment(vertical="center", wrap_text=True)
        c.border = BORDER
        ws.column_dimensions[get_column_letter(i)].width = width
    ws.row_dimensions[head].height = 30

    # ---- body
    first, last = head + 1, head + ROWS
    for r in range(first, last + 1):
        ws.row_dimensions[r].height = 30
        for i in range(1, len(COLUMNS) + 1):
            c = ws.cell(row=r, column=i)
            c.border = BORDER
            c.alignment = Alignment(vertical="top", wrap_text=True)
            if (r - first) % 2 == 1:
                c.fill = BAND_FILL

    # ---- dropdowns, driven from a hidden sheet rather than inline lists.
    #
    # Inline lists are NOT safe here. Excel separates their options with commas, so
    # "Part 2: Break it, then fix it" and "Workable, but needs fixing" would each split into two
    # nonsense options; and the whole inline list is capped at 255 characters, which the scenario
    # list exceeds on its own. A range reference has neither limit.
    lists = wb.create_sheet("Lists")
    for r, value in enumerate(scenarios, start=1):
        lists.cell(row=r, column=1, value=value)
    for r, value in enumerate(SEVERITY, start=1):
        lists.cell(row=r, column=3, value=value)
    lists.sheet_state = "hidden"

    dv_scen = DataValidation(
        type="list", formula1=f"=Lists!$A$1:$A${len(scenarios)}", allow_blank=True)
    dv_scen.error = "Pick a scenario from the list, or choose General / anything else."
    dv_scen.errorTitle = "Not on the list"
    ws.add_data_validation(dv_scen)
    dv_scen.add(f"A{first}:A{last}")

    dv_sev = DataValidation(
        type="list", formula1=f"=Lists!$C$1:$C${len(SEVERITY)}", allow_blank=True)
    dv_sev.error = "Pick one of the three options."
    dv_sev.errorTitle = "Not on the list"
    ws.add_data_validation(dv_sev)
    dv_sev.add(f"E{first}:E{last}")

    ws.freeze_panes = ws.cell(row=first, column=1)
    ws.sheet_view.showGridLines = False
    ws.auto_filter.ref = f"A{head}:{get_column_letter(len(COLUMNS))}{last}"

    # Print setup. Excel's default splits six wide columns over several pages, so anyone who
    # prints this to work on paper gets one column per sheet.
    ws.page_setup.orientation = "landscape"
    ws.page_setup.fitToWidth = 1
    ws.page_setup.fitToHeight = 0
    ws.sheet_properties.pageSetUpPr.fitToPage = True
    ws.print_title_rows = f"{head}:{head}"
    ws.print_area = f"A1:{get_column_letter(len(COLUMNS))}{last}"

    wb.save(out_path)
    return out_path


if __name__ == "__main__":
    title = sys.argv[1] if len(sys.argv) > 1 else "Board Management"
    out = sys.argv[2] if len(sys.argv) > 2 else "Board_Management_Feedback.xlsx"
    print("wrote", build(title, BOARD_SCENARIOS, out))
