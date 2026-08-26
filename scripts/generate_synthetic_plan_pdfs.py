#!/usr/bin/env python3
"""Generate importable, synthetic care-plan fixtures for the PaceBack demo."""

from __future__ import annotations

import json
from pathlib import Path

from reportlab.lib.colors import HexColor
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import inch
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, PageBreak


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "benchmark" / "synthetic_clinician_plans.json"
OUTPUT = ROOT / "output" / "pdf"

DISPLAY_NAMES = {
    "synthetic_child_school": "Synthetic Child School Support Plan",
    "synthetic_teen_school": "Synthetic Teen School Support Plan",
    "synthetic_adult_work": "Synthetic Adult Work Support Plan",
    "synthetic_older_adult": "Synthetic Older-Adult Support Plan",
}


def page_decoration(canvas, document) -> None:
    width, height = letter
    canvas.saveState()
    canvas.setFillColor(HexColor("#173A55"))
    canvas.rect(0, height - 0.38 * inch, width, 0.38 * inch, stroke=0, fill=1)
    canvas.setFillColor(HexColor("#FFFFFF"))
    canvas.setFont("Helvetica-Bold", 9)
    canvas.drawString(0.62 * inch, height - 0.24 * inch, "PACEBACK SYNTHETIC DEMO FIXTURE")
    canvas.setFillColor(HexColor("#58636B"))
    canvas.setFont("Helvetica", 8)
    canvas.drawString(0.62 * inch, 0.42 * inch, "No real person. Not a medical order, diagnosis, treatment plan, or clearance.")
    canvas.drawRightString(width - 0.62 * inch, 0.42 * inch, f"Page {document.page}")
    canvas.restoreState()


def build_plan(plan: dict, warning: str) -> Path:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    output_path = OUTPUT / f"{plan['plan_id'].replace('_', '-')}.pdf"
    styles = getSampleStyleSheet()
    title = ParagraphStyle(
        "PaceBackTitle",
        parent=styles["Title"],
        fontName="Helvetica-Bold",
        fontSize=22,
        leading=27,
        textColor=HexColor("#173A55"),
        alignment=TA_LEFT,
        spaceAfter=14,
    )
    label = ParagraphStyle(
        "PaceBackLabel",
        parent=styles["Heading2"],
        fontName="Helvetica-Bold",
        fontSize=11,
        leading=14,
        textColor=HexColor("#217075"),
        spaceAfter=8,
    )
    body = ParagraphStyle(
        "PaceBackBody",
        parent=styles["BodyText"],
        fontName="Helvetica",
        fontSize=12,
        leading=18,
        textColor=HexColor("#1F2A30"),
        spaceAfter=12,
    )
    warning_style = ParagraphStyle(
        "PaceBackWarning",
        parent=body,
        backColor=HexColor("#FFF4E8"),
        borderColor=HexColor("#BF7338"),
        borderWidth=1,
        borderPadding=10,
        textColor=HexColor("#603817"),
        spaceAfter=18,
    )

    document = SimpleDocTemplate(
        str(output_path),
        pagesize=letter,
        rightMargin=0.72 * inch,
        leftMargin=0.72 * inch,
        topMargin=0.78 * inch,
        bottomMargin=0.78 * inch,
        title=DISPLAY_NAMES[plan["plan_id"]],
        author="PaceBack Contributors",
        subject="Entirely synthetic hackathon import fixture",
    )
    story = []
    for index, page in enumerate(plan["pages"]):
        if index:
            story.append(PageBreak())
        story.extend(
            [
                Paragraph(DISPLAY_NAMES[plan["plan_id"]], title),
                Paragraph(f"Age-scope fixture: {plan['age_scope'].replace('_', ' ')}", label),
                Paragraph(warning, warning_style),
                Spacer(1, 0.12 * inch),
                Paragraph(f"Synthetic page-cited item {page['page']}", label),
                Paragraph(page["text"], body),
                Spacer(1, 0.18 * inch),
                Paragraph(
                    "Import workflow: PaceBack must treat this text as an unconfirmed extraction. "
                    "A profile owner, parent, guardian, or authorized caregiver must review each item "
                    "before it can enter the local evidence index.",
                    body,
                ),
            ]
        )
    document.build(story, onFirstPage=page_decoration, onLaterPages=page_decoration)
    return output_path


def main() -> None:
    data = json.loads(SOURCE.read_text(encoding="utf-8"))
    paths = [build_plan(plan, data["warning"]) for plan in data["plans"]]
    for path in paths:
        print(path)


if __name__ == "__main__":
    main()
