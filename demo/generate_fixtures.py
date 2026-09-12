#!/usr/bin/env python3
"""SYNTHETIC DEMO ONLY. Generate Reva's fictional sources and app fixtures.

No private data, external service, model inference, or clinical advice is used.
Requires reportlab, pypdf, Pillow. Run from any working directory.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
from datetime import date, datetime
from pathlib import Path
from xml.sax.saxutils import escape

from PIL import Image, ImageDraw, ImageFilter, ImageFont
from pypdf import PdfReader
from reportlab import rl_config
from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.utils import ImageReader
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import Paragraph

ROOT = Path(__file__).resolve().parent.parent
DEMO = ROOT / "demo"
SOURCES = DEMO / "sources"
RESOURCES = ROOT / "apps/ios/Reva/Resources"
QA = DEMO / "qa"
LABEL = "SYNTHETIC DEMO - FICTIONAL MEDICAL RECORD"
DISCLAIMER = "Invented for Reva software demonstration. Not a real patient record or medical advice."
PATIENT = "Jordan Avery (Synthetic)"
DOB = "1991-04-16"
UPLOAD = "2026-09-12T14:00:00Z"
PROFILE_ID = "demo-profile-jordan-avery"
PRIMARY_ID = "demo-visit-primary-20260915"
ORTHO_ID = "demo-visit-orthopedics-20260917"
PAST_ID = "demo-visit-primary-20260908"
TEAL = colors.HexColor("#0A5B6C")
INK = colors.HexColor("#1C3036")
MUTED = colors.HexColor("#4A6268")
SKY = colors.HexColor("#E1ECEE")
GOLD = colors.HexColor("#C8A07D")
rl_config.invariant = 1


def rid(suffix: str) -> str:
    return "demo-record-" + suffix


def source(suffix: str, ext: str = "pdf") -> str:
    return "reva-synthetic-" + suffix + "." + ext


# Source facts are authored here once. PDF record text is extracted from the
# final PDF bytes, so content and page boundaries cannot drift independently.
DOCUMENTS = [
    dict(id=rid("history"), title="Medication, allergy and health history", kind="Notes",
         provider="Sample Grove Primary Care (Fictional)", date="2026-09-01",
         tags=["medications", "allergy", "penicillin", "asthma", "primary care", "active context"],
         filename=source("health-history"),
         summary="Demo summary: Penicillin-associated rash is documented. The medication list records albuterol inhaler and cetirizine use. Intermittent asthma is part of the fictional history.",
         pages=[[("Purpose", "Medication and allergy reconciliation for the fictional patient's shared visit history."),
                 ("Allergy", "Penicillin: rash reported in childhood. This record does not describe the original reaction or a formal allergy test."),
                 ("Medications reported on September 1", "Albuterol inhaler, 90 mcg per actuation: as-needed use is documented in the existing medication list. Cetirizine, 10 mg: patient-reported seasonal use. No new prescription or change is documented here."),
                 ("Medical history", "Intermittent asthma. Prior right tibial fracture repair in 2019 with retained hardware. A separate right distal fibula fracture occurred on August 22, 2026."),
                 ("Patient context", "The patient wants appointment summaries that keep prior documentation separate from current questions. This list reflects information recorded on September 1 and may require reconciliation at the next visit.")]]),
    dict(id=rid("tibia-procedure"), title="Prior right tibia fixation and implant record", kind="Procedure",
         provider="Sample Harbor Orthopedics (Fictional)", date="2019-04-18",
         tags=["orthopedics", "right leg", "tibia", "fracture", "implant", "hardware", "nail", "procedure"],
         filename=source("tibia-procedure-2019"),
         summary="Demo summary: A right tibial shaft fracture was repaired in 2019 with an intramedullary nail and locking screws. The implant inventory is on page 2. This source does not document subsequent imaging or hardware removal.",
         pages=[[("Procedure record", "Date of procedure: April 18, 2019. Documented indication: right tibial shaft fracture following a recreational fall. Procedure: intramedullary fixation of the right tibia."),
                 ("Operative summary", "The fictional operative record describes placement of a tibial intramedullary nail with proximal and distal locking screws. The implant inventory appears on page 2."),
                 ("Immediate documentation", "The operative record describes placement of the nail and locking screws during this encounter. It does not contain a later healing assessment or hardware-removal procedure."),
                 ("Source scope", "This operation concerns the right tibial shaft fracture described above. The procedure date and implant inventory are preserved for later comparison with other lower-leg records.")],
                [("Implant inventory - historical source", "Implant location: RIGHT TIBIA. Device category: intramedullary tibial nail. Retained components documented: one nail and proximal and distal locking screws. Placement date: April 18, 2019."),
                 ("Device identification", "Manufacturer, model, material, and serial or lot numbers are intentionally not supplied in this synthetic dataset. No imaging-compatibility conclusion can be made from this inventory."),
                 ("Inventory scope", "This page records the components placed during the same operation as page 1. It does not record subsequent imaging, hardware removal, or repeat surgery."),
                 ("Source boundary", "These are invented historical details for testing source retrieval across dates and PDF pages. An operative inventory alone does not describe a later clinical course.")]]),
    dict(id=rid("fibula-injury"), title="Right distal fibula fracture - initial assessment", kind="Notes",
         provider="Sample Harbor Orthopedics (Fictional)", date="2026-08-22",
         tags=["orthopedics", "right leg", "distal fibula", "fracture", "ankle", "injury", "follow-up"],
         filename=source("fibula-injury-2026"),
         summary="Demo summary: An August 22 fall led to a documented right distal fibula fracture. The note records a walking boot and an orthopedic follow-up plan; prior right tibial hardware is a separate historical event.",
         pages=[[("Reason for encounter", "Right ankle and lower-leg discomfort after a missed step on August 22, 2026. The patient reported swelling and reduced walking comfort."),
                 ("Documented assessment", "The source note records a right distal fibula fracture after review of initial radiographs. It also records the patient's prior right tibial nail from a 2019 tibial fracture repair."),
                 ("Care already documented", "The encounter note states that a walking boot was supplied and follow-up with orthopedics was arranged. This demo document does not add activity, weight-bearing, or treatment instructions."),
                 ("Questions carried forward", "The patient wants to discuss walking comfort, interval imaging, and whether the prior tibial hardware affects how the new injury is assessed."),
                 ("Source boundary", "This is the initial assessment of the 2026 fibula injury. It is not the 2019 tibial operation and does not document a new implant.")]]),
    dict(id=rid("leg-imaging"), title="Right lower-leg follow-up radiology report", kind="Imaging",
         provider="Sample Harbor Imaging (Fictional)", date="2026-08-29",
         tags=["orthopedics", "right leg", "tibia", "fibula", "fracture", "imaging", "hardware", "x-ray"],
         filename=source("leg-imaging"),
         summary="Demo summary: The August 29 radiology report describes an unchanged distal fibula fracture alignment and intact prior tibial nail and locking screws. It is a written report; no diagnostic radiograph is included.",
         pages=[[("Examination", "RIGHT TIBIA AND FIBULA, two views. Examination date: August 29, 2026. Comparison: August 22, 2026 study described in the injury encounter."),
                 ("Clinical history", "Follow-up after a right distal fibula fracture. Remote right tibial fixation in 2019."),
                 ("Findings", "The described distal fibula fracture remains visible with no interval change in alignment on the provided comparison. An intramedullary nail and locking screws are present in the right tibia. The hardware is described as intact on this examination."),
                 ("Impression", "Documented distal fibula fracture with unchanged alignment. Remote tibial fixation hardware remains in place. Clinical follow-up is referenced in the encounter record."),
                 ("Source boundary", "This synthetic written report has no attached radiographic images and cannot be used to interpret an actual image or establish healing status beyond the text above.")]]),
    dict(id=rid("labs"), title="Laboratory results for symptom review", kind="Labs",
         provider="Sample Grove Laboratory (Fictional)", date="2026-09-07",
         tags=["primary care", "labs", "nausea", "palpitations", "CBC", "metabolic", "TSH"],
         filename=source("laboratory-results"),
         summary="Demo summary: September 7 results list hemoglobin 13.4 g/dL, sodium 139 mmol/L, potassium 4.1 mmol/L, creatinine 0.82 mg/dL, glucose 94 mg/dL, and TSH 1.62 mIU/L. Values are synthetic and do not establish the cause of symptoms.",
         pages=[[("Collection context", "Collected September 7, 2026 at 08:15 America/Chicago. Reason documented in the order: review of intermittent nausea and palpitations. Fasting status was not recorded."),
                 ("Reported values", "Hemoglobin: 13.4 g/dL\nWhite blood cells: 6.2 x 10^9/L\nPlatelets: 248 x 10^9/L\nSodium: 139 mmol/L\nPotassium: 4.1 mmol/L\nCreatinine: 0.82 mg/dL\nGlucose: 94 mg/dL\nThyroid-stimulating hormone (TSH): 1.62 mIU/L"),
                 ("Documentation limits", "The fictional source does not supply laboratory-specific reference intervals, prior trend values, or a diagnostic interpretation. These invented numbers are included to test faithful transcription of values and units."),
                 ("Discussion context", "The patient plans to review what these results can and cannot clarify alongside the symptom diary and medication list at primary care.")]]),
    dict(id=rid("ecg"), title="Resting ECG note for palpitation review", kind="Notes",
         provider="Sample Grove Primary Care (Fictional)", date="2026-09-07",
         tags=["primary care", "palpitations", "ECG", "heart", "rhythm", "nausea"],
         filename=source("resting-ecg-note"),
         summary="Demo summary: A September 7 resting ECG note records sinus rhythm at 82 beats per minute. The patient did not report a racing-heart episode during the recorded examination; a single note does not explain intermittent symptoms.",
         pages=[[("Reason for test", "Patient-reported intermittent palpitations, described as brief racing-heart sensations, sometimes with nausea."),
                 ("Reported examination", "Resting ECG obtained September 7, 2026. The fictional clinician's note states sinus rhythm at 82 beats per minute. The patient did not report a typical racing-heart episode while the ECG was obtained."),
                 ("Context and limits", "This file is a written encounter note, not an ECG tracing. The note does not establish the cause of intermittent symptoms or exclude events occurring outside the recorded examination."),
                 ("Patient question", "What information about the timing and duration of episodes would make the next discussion more useful?")]]),
    dict(id=rid("ear-infection"), title="Resolved minor right-ear infection", kind="Notes",
         provider="Sample Maple Walk-In Clinic (Fictional)", date="2025-11-04",
         tags=["ear", "otitis", "resolved", "unrelated episode"],
         filename=source("resolved-ear-infection"),
         summary="Demo summary: A November 2025 follow-up note documents resolution of a minor right-ear infection and no ongoing ear complaint. This unrelated past episode is included to demonstrate relevance filtering.",
         pages=[[("Follow-up reason", "Review after a minor right-ear infection documented the preceding week. This is a standalone fictional episode."),
                 ("Recorded outcome", "The patient reported that the ear discomfort had resolved. The follow-up note records no ongoing ear complaint and no further ear-related appointment in this dataset."),
                 ("Record scope", "This note is limited to the resolved ear complaint described above."),
                 ("Demonstration purpose", "The record intentionally represents a less relevant historical episode. It should remain searchable and available when a user explicitly chooses to include it in visit preparation.")]]),
]

ASTHMA_BODY = """SYNTHETIC DEMO - FICTIONAL MEDICAL RECORD
Asthma history and medication context
Jordan Avery (Synthetic) | DOB: 1991-04-16
Source: Sample Grove Primary Care (Fictional)
Source date: 2026-05-12

DOCUMENTED HISTORY
Intermittent asthma appears in the fictional health history. The encounter note
records an albuterol inhaler on the existing medication list. No hospital stay
or acute respiratory complaint is documented in this particular encounter.

PATIENT-REPORTED MEDICATION CONTEXT
Albuterol inhaler, 90 mcg per actuation: as-needed use documented in the source
medication list. Cetirizine, 10 mg: seasonal use reported by the patient.
This note does not introduce a new medicine or change an existing instruction.

SOURCE BOUNDARY
This note gives historical context for medication reconciliation. It contains
no attribution of symptoms to a medicine and no separate symptom assessment.

Invented for Reva software demonstration. Not a real patient record or medical advice.
"""

DIARY_TEXT = """SYNTHETIC DEMO - FICTIONAL MEDICAL RECORD
Patient symptom diary
Jordan Avery (Synthetic) | DOB: 1991-04-16
Source: Patient-authored sample (Fictional)
Week ending: September 7, 2026

Entry date: September 0[unclear], 2026
The final date digit is obscured in this synthetic scan.

PATIENT OBSERVATIONS
Morning: brief racing-heart sensation while sitting after breakfast.
Estimated duration: about 2 minutes. Nausea at the same time.
Afternoon: another brief racing-heart sensation while at a desk.
Exact start and stop times were not written down.

DETAILS TO CLARIFY
The entry does not record meal ingredients, caffeine quantity, or the time
of any inhaler use. It does not establish a cause for the symptoms.

PATIENT QUESTION
Which timing details would help make the follow-up conversation clearer?

REVIEW NEEDED
Confirm the obscured entry date. Do not infer its last digit.
Record date uses the legible week-ending date, September 7, 2026.

Invented for Reva software demonstration. Not a real patient record or medical advice.
SYNTHETIC SCAN | 1 page | no real patient data
"""

IMPORT_TEXT = """SYNTHETIC DEMO - FICTIONAL PATIENT PREPARATION NOTE
Jordan Avery (Synthetic) | Source date: 2026-09-12

ORTHOPEDIC VISIT PREPARATION
I want to bring the August 29 lower-leg imaging report and the older right
tibia implant inventory to the September 17 visit. My new injury is in the
distal fibula; the nail is from the tibia repair in 2019.

QUESTION TO ADD
Which changes in walking comfort should I describe when comparing this week
with the day of the injury?

This unseeded sample is intended for a manual import demonstration. It is
not a clinical recommendation or a real patient document.
"""


def paragraph(c: canvas.Canvas, content: str, x: float, y: float, width: float,
              font_size: float = 10.8, leading: float = 15, color=INK) -> float:
    style = ParagraphStyle("body", fontName="DemoSans", fontSize=font_size,
                           leading=leading, textColor=color, alignment=TA_LEFT,
                           spaceAfter=0)
    p = Paragraph(escape(content).replace("\n", "<br/>"), style)
    _, h = p.wrap(width, 1000)
    p.drawOn(c, x, y - h)
    return y - h


def create_pdf(doc: dict) -> None:
    path = SOURCES / doc["filename"]
    c = canvas.Canvas(str(path), pagesize=(612, 792), invariant=1, pageCompression=1)
    c.setTitle(LABEL + " | " + doc["title"])
    c.setAuthor("Reva Synthetic Fixture Generator")
    c.setSubject(DISCLAIMER)
    for index, sections in enumerate(doc["pages"], start=1):
        c.setFillColor(TEAL)
        c.rect(0, 748, 612, 44, fill=1, stroke=0)
        c.setFillColor(colors.white)
        c.setFont("DemoSansBold", 10)
        c.drawString(42, 766, LABEL)
        c.setFillColor(TEAL)
        c.setFont("DemoSansBold", 11)
        c.drawString(42, 720, "REVA / SYNTHETIC SOURCE LIBRARY")
        y = paragraph(c, doc["title"], 42, 698, 528, 22, 26, INK)
        c.setStrokeColor(GOLD)
        c.setLineWidth(2)
        c.line(42, y - 13, 570, y - 13)
        y -= 33
        y = paragraph(c, f"{PATIENT} | DOB: {DOB}", 42, y, 528, 10.2, 14, MUTED)
        y = paragraph(c, f"Source: {doc['provider']}\nSource date: {doc['date']}", 42, y - 5, 528, 10.2, 14, MUTED)
        y -= 23
        for heading, body in sections:
            c.setFillColor(TEAL)
            c.setFont("DemoSansBold", 10.8)
            c.drawString(42, y, heading.upper())
            y = paragraph(c, body, 42, y - 10, 528) - 21
        if y < 95:
            raise ValueError(f"Content overflows footer: {doc['filename']} page {index}: y={y}")
        c.setFillColor(SKY)
        c.rect(42, 54, 528, 32, fill=1, stroke=0)
        paragraph(c, DISCLAIMER, 51, 74, 510, 8.5, 11, MUTED)
        c.setFont("DemoSans", 8)
        c.setFillColor(MUTED)
        c.drawString(42, 35, "Synthetic source ID: " + doc["id"])
        c.drawRightString(570, 35, f"Page {index} of {len(doc['pages'])}")
        c.showPage()
    c.save()


def find_font(bold: bool = False) -> str:
    candidates = (["/System/Library/Fonts/Supplemental/Arial Bold.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"]
                  if bold else ["/System/Library/Fonts/Supplemental/Arial.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"])
    for candidate in candidates:
        if Path(candidate).exists():
            return candidate
    raise RuntimeError("Install Arial or DejaVu Sans to regenerate the synthetic scan.")


def create_diary() -> None:
    # A clean, high-resolution raster with one deliberately obscured date digit.
    # This is a generated document scan, not a captured patient document.
    im = Image.new("RGB", (1650, 2136), (248, 247, 242))
    d = ImageDraw.Draw(im)
    regular_path, bold_path = find_font(), find_font(True)
    body = ImageFont.truetype(regular_path, 28)
    small = ImageFont.truetype(regular_path, 23)
    bold = ImageFont.truetype(bold_path, 28)
    title = ImageFont.truetype(bold_path, 49)
    d.rectangle((70, 70, 1580, 162), fill=(10, 91, 108))
    d.text((102, 98), LABEL, font=bold, fill="white")
    d.text((102, 215), "Patient symptom diary", font=title, fill=(25, 42, 47))
    y = 310
    for line in [f"{PATIENT} | DOB: {DOB}", "Source: Patient-authored sample (Fictional)",
                 "Week ending: September 7, 2026"]:
        d.text((102, y), line, font=body, fill=(40, 48, 50))
        y += 48
    y += 18
    prefix = "Entry date: September 0"
    d.text((102, y), prefix, font=body, fill=(40, 48, 50))
    digit_x = round(102 + d.textlength(prefix, font=body))
    d.text((digit_x + 25, y), ", 2026", font=body, fill=(40, 48, 50))
    # The missing digit is intentionally unreadable; neither seed nor OCR should guess it.
    smudge = Image.new("RGBA", (31, 39), (0, 0, 0, 0))
    sd = ImageDraw.Draw(smudge)
    sd.text((1, 0), "5", font=body, fill=(70, 70, 70, 95))
    for dy in (9, 14, 20, 27):
        sd.line((0, dy, 29, dy + 5), fill=(74, 71, 65, 170), width=5)
    smudge = smudge.filter(ImageFilter.GaussianBlur(2.8))
    im.paste(smudge, (digit_x, y), smudge)
    y += 53
    d.text((102, y), "The final date digit is obscured in this synthetic scan.", font=small, fill=(76, 70, 60))
    sections = [
        ("PATIENT OBSERVATIONS", ["Morning: brief racing-heart sensation while sitting after breakfast.",
                                  "Estimated duration: about 2 minutes. Nausea at the same time.",
                                  "Afternoon: another brief racing-heart sensation while at a desk.",
                                  "Exact start and stop times were not written down."]),
        ("DETAILS TO CLARIFY", ["The entry does not record meal ingredients, caffeine quantity, or the time",
                                "of any inhaler use. It does not establish a cause for the symptoms."]),
        ("PATIENT QUESTION", ["Which timing details would help make the follow-up conversation clearer?"]),
        ("REVIEW NEEDED", ["Confirm the obscured entry date. Do not infer its last digit.",
                            "Record date uses the legible week-ending date, September 7, 2026."]),
    ]
    for heading, lines in sections:
        y += 92
        d.text((102, y), heading, font=bold, fill=(10, 91, 108))
        y += 52
        for line in lines:
            d.text((102, y), line, font=body, fill=(40, 48, 50))
            y += 45
    d.line((102, 1925, 1548, 1925), fill=(162, 183, 188), width=3)
    d.text((102, 1950), "Invented for Reva software demonstration.", font=small, fill=(65, 73, 75))
    d.text((102, 1987), "Not a real patient record or medical advice.", font=small, fill=(65, 73, 75))
    d.text((102, 2043), "SYNTHETIC SCAN | 1 page | no real patient data", font=small, fill=(65, 73, 75))
    im.save(SOURCES / source("symptom-diary-scan", "png"), optimize=False)
    scan_pdf = canvas.Canvas(str(SOURCES / source("symptom-diary-image-only")),
                             pagesize=(612, 792), invariant=1, pageCompression=1)
    scan_pdf.setTitle(LABEL + " | Image-only symptom diary")
    scan_pdf.setAuthor("Reva Synthetic Fixture Generator")
    scan_pdf.setSubject("Synthetic raster-only PDF; text requires actual OCR.")
    scan_pdf.drawImage(ImageReader(im), 0, 0, 612, 792)
    scan_pdf.save()


def record(doc: dict) -> dict:
    pages = [p.extract_text().strip() for p in PdfReader(SOURCES / doc["filename"]).pages]
    return dict(id=doc["id"], title=doc["title"], kind=doc["kind"], provider=doc["provider"],
                date=doc["date"], uploadedAt=UPLOAD, tags=doc["tags"],
                text="\n\n".join(pages), pageTexts=pages, summary=doc["summary"],
                sourceFilename=doc["filename"], mimeType="application/pdf", pageCount=len(pages),
                status="ready", notes="Synthetic source and authored demo summary. No AI service ran.",
                isDemo=True, version=1)


def make_seed() -> dict:
    records = [record(doc) for doc in DOCUMENTS]
    records.extend([
        dict(id=rid("asthma"), title="Asthma history and medication context", kind="Notes",
             provider="Sample Grove Primary Care (Fictional)", date="2026-05-12", uploadedAt=UPLOAD,
             tags=["asthma", "albuterol", "medications", "primary care", "history"],
             text=ASTHMA_BODY.strip(), pageTexts=[ASTHMA_BODY.strip()],
             summary="Demo summary: The May note documents intermittent asthma and existing albuterol and seasonal cetirizine use. It contains no attribution of symptoms to a medicine.",
             sourceFilename=source("asthma-context", "txt"), mimeType="text/plain", pageCount=1,
             status="ready", notes="Synthetic plain-text source and authored demo summary. No AI service ran.",
             isDemo=True, version=1),
        dict(id=rid("symptom-diary"), title="Nausea and palpitation diary - date needs review", kind="Scan",
             provider="Patient-authored sample (Fictional)", date="2026-09-07", uploadedAt=UPLOAD,
             tags=["primary care", "nausea", "palpitations", "symptom diary", "needs review"],
             text=DIARY_TEXT.strip(), pageTexts=[DIARY_TEXT.strip()],
             summary="Demo summary: A diary for the week ending September 7 describes two brief racing-heart sensations and nausea with the morning episode. The individual entry date is partly obscured and requires review.",
             sourceFilename=source("symptom-diary-scan", "png"), mimeType="image/png", pageCount=1,
             status="needsReview", notes="Synthetic scan with one deliberately obscured entry-date digit. Confirm the date; do not guess. Record date is the clearly printed week-ending date. Seed text is an authored reference transcription, not an OCR success claim.",
             isDemo=True, version=1),
    ])
    records.sort(key=lambda item: (item["date"], item["id"]), reverse=True)
    return dict(
        schemaVersion=1,
        profile=dict(id=PROFILE_ID, name=PATIENT, dateOfBirth=DOB, initials="JA",
                     allergies=["Penicillin - childhood rash reported (synthetic)"],
                     medications=["Albuterol inhaler, 90 mcg/actuation - existing as-needed use documented (synthetic)",
                                  "Cetirizine, 10 mg - seasonal use reported (synthetic)"],
                     conditions=["Intermittent asthma (synthetic)", "Right distal fibula fracture, August 2026 (synthetic)",
                                 "Prior right tibial fixation with retained hardware, 2019 (synthetic)"], isDemo=True),
        records=records,
        visits=[
            dict(id=PRIMARY_ID, title="Nausea and palpitation follow-up", type="Primary care",
                 provider="Dr. Morgan Ellis (Fictional)", clinic="Sample Grove Primary Care (Fictional)",
                 date="2026-09-15T09:00:00-05:00", timeZone="America/Chicago",
                 concern="Intermittent nausea and brief racing-heart sensations; I want to describe the timing clearly.",
                 goal="Review my symptom diary, current medications, September labs and ECG, and identify what information is still missing.",
                 questions=["Which details about episode timing and duration would be most useful to bring?",
                            "What can the existing laboratory results and ECG tell us, and what do they leave unresolved?",
                            "Should I bring a more complete record of meals, caffeine and the timing of my usual medicines?"],
                 pinnedRecordIDs=[], notes="Synthetic upcoming visit. The diary's individual entry date still needs confirmation.",
                 status="upcoming", report=None),
            dict(id=ORTHO_ID, title="Broken-leg follow-up", type="Orthopedics",
                 provider="Dr. Quinn Rowan (Fictional)", clinic="Sample Harbor Orthopedics (Fictional)",
                 date="2026-09-17T10:30:00-05:00", timeZone="America/Chicago",
                 concern="Follow-up of my August right distal fibula fracture, walking comfort, and prior right tibial hardware.",
                 goal="Review interval lower-leg imaging and the older tibial implant record, and prepare questions about recovery from the new fibula fracture.",
                 questions=["What does the comparison of my August imaging reports show?",
                            "How does the old right tibial nail relate to the assessment of this new fibula injury?",
                            "Which changes in walking comfort should I describe, and what recovery milestones should we discuss?"],
                 pinnedRecordIDs=[], notes="Synthetic upcoming visit. The old tibial fixation and new fibula fracture are separate events.",
                 status="upcoming", report=None),
            dict(id=PAST_ID, title="Initial symptom discussion", type="Primary care",
                 provider="Dr. Morgan Ellis (Fictional)", clinic="Sample Grove Primary Care (Fictional)",
                 date="2026-09-08T14:00:00-05:00", timeZone="America/Chicago",
                 concern="Discuss patient-reported brief palpitations and nausea.",
                 goal="Review existing source documents and organize unresolved questions before the follow-up visit.",
                 questions=["Which details were missing from my first symptom diary?"], pinnedRecordIDs=[],
                 notes="Completed synthetic visit associated with the optional text-only sample transcript. No audio was recorded.",
                 status="completed", report=None),
        ], bookings=[], recordings=[])


def make_recording() -> dict:
    utterances = [
        (0, 12, "Narrator (Synthetic)", "This is a fictional Reva demonstration transcript. No real patient conversation or recorded audio is represented."),
        (14, 34, "Jordan Avery - patient (Fictional)", "I wrote down two brief racing-heart sensations. I felt nauseated during the morning one. The exact entry date on my scan is smudged, so I need to confirm it."),
        (36, 55, "Dr. Morgan Ellis - clinician (Fictional)", "The diary is labeled for the week ending September seventh. We can keep that clear date separate from the entry date that is still uncertain."),
        (57, 77, "Jordan Avery - patient (Fictional)", "The current list includes my asthma inhaler and seasonal cetirizine. I did not record when I used them, or how much caffeine I had that day."),
        (79, 104, "Dr. Morgan Ellis - clinician (Fictional)", "We have the September seventh laboratory results and a resting ECG note. The ECG note says you did not feel a typical episode during that test. These documents do not establish why the episodes happened."),
        (106, 123, "Jordan Avery - patient (Fictional)", "For the next visit I want a clearer timeline, and I want to understand what the existing results leave unresolved."),
        (125, 151, "Dr. Morgan Ellis - clinician (Fictional)", "Our documented preparation items are to confirm the obscured date, bring the existing medication list, and organize the timing information you already have. We have not documented a diagnosis or a medication change in this sample conversation."),
        (153, 173, "Jordan Avery - patient (Fictional)", "I will review my notes and add the questions to the September fifteenth follow-up. The leg-fracture appointment is separate, so I will keep those preparation notes with orthopedics."),
        (175, 194, "Narrator (Synthetic)", "End of synthetic sample. Preparation items and unresolved questions come from the dialogue above. This text is not a treatment plan or a transcript of newly captured microphone audio."),
    ]
    return dict(id="demo-recording-primary-20260908", visitID=PAST_ID,
                title="Synthetic sample transcript - no audio", createdAt="2026-09-08T19:04:00Z",
                duration=196,
                segments=[dict(id=f"demo-segment-{i:02d}", speaker=speaker, start=start, end=end, text=text)
                          for i, (start, end, speaker, text) in enumerate(utterances, 1)],
                summary="Synthetic sample memory: Discussed nausea and brief palpitations with an uncertain diary date [demo-segment-02, demo-segment-03]. Reviewed existing medication context and missing timing details [demo-segment-04]. Existing laboratory and ECG notes did not establish a cause in this conversation [demo-segment-05]. Preparation items: confirm the obscured date, bring the existing medication list, and organize available timing information [demo-segment-07]. Questions remain for the September 15 follow-up [demo-segment-06, demo-segment-08]. No diagnosis or medication change was documented [demo-segment-07].",
                isSample=True, status="ready")


def make_expectations() -> dict:
    return dict(synthetic=True, description="Source-selection acceptance fixtures, not medical guidance.",
                schemaVersion=1, scenarios=[
                    dict(id="orthopedic-followup", visitID=ORTHO_ID,
                         mustInclude=[rid("history"), rid("tibia-procedure"), rid("fibula-injury"), rid("leg-imaging")],
                         mustExclude=[rid("ear-infection"), rid("labs"), rid("ecg"), rid("symptom-diary")],
                         mayInclude=[rid("asthma")],
                         sourceChecks=[dict(recordID=rid("tibia-procedure"), page=2, contains="Implant location: RIGHT TIBIA")],
                         rationale="The new distal fibula injury and old tibial implant share lower-leg imaging context; general medications/allergy context remains useful."),
                    dict(id="nausea-palpitations-primary-care", visitID=PRIMARY_ID,
                         mustInclude=[rid("history"), rid("symptom-diary"), rid("labs"), rid("ecg"), rid("asthma")],
                         mustExclude=[rid("ear-infection"), rid("leg-imaging"), rid("fibula-injury")],
                         mayInclude=[rid("tibia-procedure")],
                         sourceChecks=[dict(recordID=rid("labs"), page=1, contains="1.62 mIU/L")],
                         rationale="Symptom observations, test documentation and medication context matter. Old implant may be explicit history context but cannot be presented as the symptom cause."),
                ], pinningCase=dict(visitID=ORTHO_ID, pinRecordID=rid("ear-infection"), mustInclude=rid("ear-infection")),
                reviewCase=dict(recordID=rid("symptom-diary"), expectedStatus="needsReview",
                                uncertainField="individual symptom entry date",
                                sourceFilename=source("symptom-diary-scan", "png"),
                                knownDate="2026-09-07", knownDateMeaning="printed week-ending date",
                                expectedText="September 0[unclear], 2026",
                                forbiddenBehavior="Guessing the obscured digit or claiming OCR has been verified from the seeded reference transcription."))


def write_json(path: Path, value: dict) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def make_manifest(seed: dict) -> dict:
    mapping = {r["sourceFilename"]: r for r in seed["records"]}
    entries = []
    for path in sorted(SOURCES.iterdir()):
        r = mapping.get(path.name)
        related = rid("symptom-diary") if path.name == source("symptom-diary-image-only") else None
        entry = dict(filename=path.name, sha256=sha256(path), recordID=r["id"] if r else related,
                     mimeType={".pdf": "application/pdf", ".png": "image/png", ".txt": "text/plain"}[path.suffix],
                     bytes=path.stat().st_size, pageCount=len(PdfReader(path).pages) if path.suffix == ".pdf" else 1,
                     isSynthetic=True, isSeededSource=r is not None)
        if related:
            entry["note"] = "Raster-only alternate of the seeded diary; requires actual OCR on import."
        elif r is None:
            entry["note"] = "Unseeded preparation note for a distinct manual import."
        entries.append(entry)
    return dict(schemaVersion=1, synthetic=True, fixtureDate="2026-09-12",
                description=DISCLAIMER, profileID=PROFILE_ID, sources=entries)


def verify(seed: dict, recording: dict, manifest: dict, expectations: dict) -> dict:
    assert set(seed) == {"schemaVersion", "profile", "records", "visits", "bookings", "recordings"}
    assert seed["schemaVersion"] == 1 and seed["profile"]["isDemo"] is True
    date.fromisoformat(seed["profile"]["dateOfBirth"])
    records = {r["id"]: r for r in seed["records"]}
    visits = {v["id"]: v for v in seed["visits"]}
    assert len(records) == len(seed["records"]) == 9
    assert len(visits) == len(seed["visits"]) == 3
    assert len({r["sourceFilename"] for r in records.values()}) == 9
    for r in records.values():
        assert r["isDemo"] is True and r["version"] == 1
        assert r["kind"] in {"Notes", "Labs", "Imaging", "Procedure", "Scan", "Recording"}
        assert r["status"] in {"ready", "needsReview", "processing"}
        assert Path(r["sourceFilename"]).name == r["sourceFilename"]
        assert "SYNTHETIC DEMO" in r["text"] and r["summary"].startswith("Demo summary:")
        date.fromisoformat(r["date"])
        datetime.fromisoformat(r["uploadedAt"].replace("Z", "+00:00"))
        assert len(r["pageTexts"]) == r["pageCount"]
        if r["mimeType"] == "application/pdf":
            actual = [p.extract_text().strip() for p in PdfReader(SOURCES / r["sourceFilename"]).pages]
            assert actual == r["pageTexts"]
            assert r["text"] == "\n\n".join(actual)
        elif r["mimeType"] == "text/plain":
            assert r["text"] == (SOURCES / r["sourceFilename"]).read_text().strip()
    for v in visits.values():
        datetime.fromisoformat(v["date"])
        assert v["type"] in {"Primary care", "Orthopedics", "Cardiology", "Other"}
        assert v["status"] in {"upcoming", "completed"}
        assert set(v["pinnedRecordIDs"]) <= set(records)
    assert set(recording) == {"id", "visitID", "title", "createdAt", "duration", "segments", "summary", "isSample", "status"}
    assert recording["isSample"] is True and recording["visitID"] in visits
    assert visits[recording["visitID"]]["status"] == "completed"
    assert not seed["recordings"] and not seed["bookings"]
    datetime.fromisoformat(recording["createdAt"].replace("Z", "+00:00"))
    previous_end = 0
    assert len({s["id"] for s in recording["segments"]}) == len(recording["segments"])
    for segment in recording["segments"]:
        assert previous_end <= segment["start"] < segment["end"] <= recording["duration"]
        previous_end = segment["end"]
    for entry in manifest["sources"]:
        p = SOURCES / entry["filename"]
        assert entry["sha256"] == sha256(p)
        assert (RESOURCES / p.name).read_bytes() == p.read_bytes()
        assert entry["recordID"] is None or entry["recordID"] in records
    for scenario in expectations["scenarios"]:
        assert scenario["visitID"] in visits
        assert set(scenario["mustInclude"]).isdisjoint(scenario["mustExclude"])
        assert set(scenario["mustInclude"] + scenario["mustExclude"] + scenario["mayInclude"]) == set(records)
        for check in scenario["sourceChecks"]:
            assert check["contains"] in records[check["recordID"]]["pageTexts"][check["page"] - 1]
    scan_text = "".join(p.extract_text() for p in PdfReader(SOURCES / source("symptom-diary-image-only")).pages)
    assert not scan_text.strip(), "Image-only PDF unexpectedly has embedded text."
    assert records[rid("symptom-diary")]["status"] == "needsReview"
    for name in ["seed.json", "sample-transcript.json", "fixture-manifest.json", "expected-evidence.json"]:
        assert (DEMO / name).read_bytes() == (RESOURCES / name).read_bytes()
    return dict(synthetic=True, fixtureDate="2026-09-12", status="passed",
                recordCount=len(records), visitCount=len(visits), transcriptSegmentCount=len(recording["segments"]),
                sourceCount=len(manifest["sources"]), pdfCount=8, pdfPageCount=9,
                checks=["contract keys and enum/date types", "unique IDs and visit relationships", "source presence and flat names",
                        "PDF extraction matches JSON per page", "plain-text source matches JSON", "image-only PDF has no text layer",
                        "SHA-256 manifest", "byte-identical app resource copies", "recording-relative timestamp order and bounds",
                        "text-only sample belongs to completed visit", "expected evidence refers to real records and source pages",
                        "uncertain scan preserved as needsReview"],
                limits=["Fixture-level checks only; app relevance engine execution and native OCR are verified by app integration.",
                        "PDF visual inspection is recorded separately in the dataset task specification."])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify-only", action="store_true", help="Check current generated files without modifying them.")
    args = parser.parse_args()
    if args.verify_only:
        result = verify(*[json.loads((DEMO / name).read_text()) for name in
                          ["seed.json", "sample-transcript.json", "fixture-manifest.json", "expected-evidence.json"]])
        print(json.dumps(result, indent=2))
        return
    for path in (SOURCES, RESOURCES, QA):
        path.mkdir(parents=True, exist_ok=True)
    pdfmetrics.registerFont(TTFont("DemoSans", find_font()))
    pdfmetrics.registerFont(TTFont("DemoSansBold", find_font(True)))
    for doc in DOCUMENTS:
        create_pdf(doc)
    (SOURCES / source("asthma-context", "txt")).write_text(ASTHMA_BODY, encoding="utf-8")
    (SOURCES / source("import-preparation-note", "txt")).write_text(IMPORT_TEXT, encoding="utf-8")
    create_diary()
    seed, recording, expectations = make_seed(), make_recording(), make_expectations()
    manifest = make_manifest(seed)
    for name, value in [("seed.json", seed), ("sample-transcript.json", recording),
                        ("fixture-manifest.json", manifest), ("expected-evidence.json", expectations)]:
        write_json(DEMO / name, value)
        shutil.copyfile(DEMO / name, RESOURCES / name)
    for path in SOURCES.iterdir():
        shutil.copyfile(path, RESOURCES / path.name)
    verification = verify(seed, recording, manifest, expectations)
    write_json(QA / "verification.json", verification)
    print(f"Generated {len(seed['records'])} synthetic records, {len(seed['visits'])} visits, "
          f"{len(manifest['sources'])} importable sources; all fixture checks passed.")


if __name__ == "__main__":
    main()
