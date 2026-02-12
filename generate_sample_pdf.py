#!/usr/bin/env python3
"""
generate_sample_pdf.py
======================
Creates a synthetic financial report PDF at  data/sample_financial_report.pdf .

The PDF contains three distinct content types that NVIngest should recognise:
  1. Narrative text  (paragraphs about the quarter)
  2. A data table    (quarterly revenue, net income, EPS)
  3. A bar-chart     (drawn with ReportLab graphics)

Run:
    pip install reportlab
    python generate_sample_pdf.py
"""

from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import inch
from reportlab.platypus import (
    SimpleDocTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
    PageBreak,
    Image,
)
from reportlab.graphics.shapes import Drawing, Rect, String
from reportlab.graphics import renderPDF
from reportlab.graphics.charts.barcharts import VerticalBarChart
from reportlab.lib.enums import TA_CENTER, TA_JUSTIFY

# ── Output path ──────────────────────────────────────────────────────────────
OUTPUT_DIR = Path(__file__).parent / "data"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
OUTPUT_PDF = OUTPUT_DIR / "sample_financial_report.pdf"

# ── Financial data (ground-truth for the "aha" query) ────────────────────────
COMPANY = "Acme Corp"
YEAR = 2024
QUARTERLY_DATA = [
    # (Quarter, Revenue $M, Net Income $M, EPS $)
    ("Q1 2024", 2_105, 312, 1.56),
    ("Q2 2024", 2_498, 389, 1.95),
    ("Q3 2024", 2_847, 456, 2.28),
    ("Q4 2024", 3_102, 521, 2.61),
]


def build_styles():
    """Return custom paragraph styles."""
    styles = getSampleStyleSheet()
    styles.add(ParagraphStyle(
        name="CoverTitle",
        parent=styles["Title"],
        fontSize=28,
        leading=34,
        alignment=TA_CENTER,
        spaceAfter=20,
    ))
    styles.add(ParagraphStyle(
        name="CoverSubtitle",
        parent=styles["Heading2"],
        fontSize=16,
        alignment=TA_CENTER,
        textColor=colors.HexColor("#555555"),
        spaceAfter=40,
    ))
    styles.add(ParagraphStyle(
        name="BodyJustified",
        parent=styles["BodyText"],
        alignment=TA_JUSTIFY,
        fontSize=11,
        leading=15,
        spaceAfter=12,
    ))
    styles.add(ParagraphStyle(
        name="SectionHead",
        parent=styles["Heading2"],
        fontSize=16,
        spaceAfter=10,
        spaceBefore=20,
    ))
    styles.add(ParagraphStyle(
        name="TableCaption",
        parent=styles["Normal"],
        fontSize=10,
        alignment=TA_CENTER,
        textColor=colors.HexColor("#666666"),
        spaceBefore=6,
        spaceAfter=16,
    ))
    return styles


def cover_page(styles):
    """Return flowables for the cover page."""
    elements = []
    elements.append(Spacer(1, 2 * inch))
    elements.append(Paragraph(f"{COMPANY}", styles["CoverTitle"]))
    elements.append(Paragraph(
        f"Quarterly Earnings Report &mdash; Fiscal Year {YEAR}",
        styles["CoverSubtitle"],
    ))
    elements.append(Spacer(1, 0.5 * inch))
    elements.append(Paragraph(
        "Prepared for Investors and Analysts<br/>"
        "Published: January 15, 2025",
        styles["CoverSubtitle"],
    ))
    elements.append(PageBreak())
    return elements


def narrative_section(styles):
    """Return flowables for the narrative text section."""
    elements = []
    elements.append(Paragraph("Executive Summary", styles["SectionHead"]))
    elements.append(Paragraph(
        f"{COMPANY} delivered record-breaking results in fiscal year {YEAR}, "
        "driven by strong demand across our cloud computing and enterprise "
        "AI product lines. Total annual revenue reached $10,552 million, "
        "representing year-over-year growth of 34%. The company continued to "
        "invest in next-generation GPU architectures and expanded its data "
        "centre footprint in three new regions.",
        styles["BodyJustified"],
    ))
    elements.append(Paragraph(
        "Third-quarter performance was particularly notable, with revenue of "
        "$2,847 million and net income of $456 million. This was driven by "
        "a 42% increase in data-centre revenue and the successful launch of "
        "our new inference acceleration platform. Earnings per share for Q3 "
        "came in at $2.28, exceeding consensus estimates by $0.12.",
        styles["BodyJustified"],
    ))
    elements.append(Paragraph(
        "Looking ahead, management expects continued momentum in Q1 2025, "
        "with revenue guidance of $3,300 &ndash; $3,500 million. The company "
        "announced a $2 billion share repurchase programme and increased its "
        "quarterly dividend by 15%.",
        styles["BodyJustified"],
    ))
    elements.append(Spacer(1, 0.3 * inch))
    return elements


def financial_table(styles):
    """Return flowables for the quarterly financials table."""
    elements = []
    elements.append(Paragraph("Quarterly Financial Highlights", styles["SectionHead"]))

    # Build table data
    header = ["Quarter", "Revenue ($M)", "Net Income ($M)", "EPS ($)"]
    rows = [[q, f"{rev:,}", f"{ni:,}", f"{eps:.2f}"] for q, rev, ni, eps in QUARTERLY_DATA]
    # Annual totals row
    total_rev = sum(r[1] for r in QUARTERLY_DATA)
    total_ni = sum(r[2] for r in QUARTERLY_DATA)
    total_eps = sum(r[3] for r in QUARTERLY_DATA)
    rows.append(["FY 2024 Total", f"{total_rev:,}", f"{total_ni:,}", f"{total_eps:.2f}"])

    table_data = [header] + rows

    table = Table(table_data, colWidths=[1.6 * inch, 1.5 * inch, 1.6 * inch, 1.2 * inch])
    table.setStyle(TableStyle([
        # Header row
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#76B900")),  # NVIDIA green
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("FONTSIZE", (0, 0), (-1, 0), 11),
        ("ALIGN", (0, 0), (-1, 0), "CENTER"),
        ("BOTTOMPADDING", (0, 0), (-1, 0), 10),
        ("TOPPADDING", (0, 0), (-1, 0), 10),
        # Data rows
        ("FONTNAME", (0, 1), (-1, -1), "Helvetica"),
        ("FONTSIZE", (0, 1), (-1, -1), 10),
        ("ALIGN", (1, 1), (-1, -1), "RIGHT"),
        ("ALIGN", (0, 1), (0, -1), "LEFT"),
        ("BOTTOMPADDING", (0, 1), (-1, -1), 7),
        ("TOPPADDING", (0, 1), (-1, -1), 7),
        # Alternating row colours
        ("BACKGROUND", (0, 1), (-1, 1), colors.HexColor("#F5F5F5")),
        ("BACKGROUND", (0, 3), (-1, 3), colors.HexColor("#F5F5F5")),
        ("BACKGROUND", (0, 5), (-1, 5), colors.HexColor("#E8E8E8")),  # total row
        # Totals row bold
        ("FONTNAME", (0, -1), (-1, -1), "Helvetica-Bold"),
        # Grid
        ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#CCCCCC")),
        ("LINEBELOW", (0, 0), (-1, 0), 1.5, colors.HexColor("#333333")),
        ("LINEABOVE", (0, -1), (-1, -1), 1, colors.HexColor("#333333")),
    ]))

    elements.append(table)
    elements.append(Paragraph(
        f"Table 1: {COMPANY} Quarterly Financial Highlights, FY {YEAR}",
        styles["TableCaption"],
    ))
    return elements


def revenue_chart():
    """Return a Drawing flowable with a bar chart of quarterly revenue."""
    drawing = Drawing(450, 260)

    chart = VerticalBarChart()
    chart.x = 60
    chart.y = 40
    chart.width = 350
    chart.height = 180

    revenues = [r[1] for r in QUARTERLY_DATA]
    chart.data = [revenues]
    chart.categoryAxis.categoryNames = [r[0] for r in QUARTERLY_DATA]
    chart.categoryAxis.labels.fontName = "Helvetica"
    chart.categoryAxis.labels.fontSize = 9

    chart.valueAxis.valueMin = 0
    chart.valueAxis.valueMax = 3500
    chart.valueAxis.valueStep = 500
    chart.valueAxis.labels.fontName = "Helvetica"
    chart.valueAxis.labels.fontSize = 9

    chart.bars[0].fillColor = colors.HexColor("#76B900")  # NVIDIA green
    chart.bars[0].strokeColor = colors.HexColor("#5A8F00")
    chart.bars[0].strokeWidth = 0.5

    # Add value labels on top of each bar
    chart.barLabels.nudge = 10
    chart.barLabelFormat = "%d"
    chart.barLabels.fontName = "Helvetica-Bold"
    chart.barLabels.fontSize = 9

    drawing.add(chart)

    # Title for the chart
    title = String(225, 240, f"{COMPANY} Quarterly Revenue ($M) — FY {YEAR}",
                   textAnchor="middle", fontName="Helvetica-Bold", fontSize=11)
    drawing.add(title)

    return drawing


def build_pdf():
    """Assemble and write the PDF."""
    doc = SimpleDocTemplate(
        str(OUTPUT_PDF),
        pagesize=letter,
        leftMargin=inch,
        rightMargin=inch,
        topMargin=inch,
        bottomMargin=inch,
    )

    styles = build_styles()
    elements = []

    # Page 1 — Cover
    elements.extend(cover_page(styles))

    # Page 2 — Executive Summary (narrative text)
    elements.extend(narrative_section(styles))

    # Still on page 2 / page 3 — Financial Table
    elements.extend(financial_table(styles))

    elements.append(Spacer(1, 0.4 * inch))

    # Revenue Bar Chart
    elements.append(Paragraph("Revenue Trend", styles["SectionHead"]))
    elements.append(revenue_chart())
    elements.append(Paragraph(
        f"Figure 1: {COMPANY} Quarterly Revenue Trend, FY {YEAR}",
        styles["TableCaption"],
    ))

    # Build the PDF
    doc.build(elements)
    print(f"✅ Sample financial report created: {OUTPUT_PDF}")
    print(f"   File size: {OUTPUT_PDF.stat().st_size / 1024:.1f} KB")


if __name__ == "__main__":
    build_pdf()
