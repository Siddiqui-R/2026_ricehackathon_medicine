"""Build the teammate packet and editable Markdown from one factual content source.

Requires reportlab; run with the bundled Codex Python runtime or an environment
that already has reportlab. The baseline is a documented snapshot, not live Git.

Purpose: Maintain matching readable PDF and editable Markdown handoff artifacts from the authored page definitions.
Inputs: The fixed baseline/content below, ReportLab, and the installed macOS Arial font files.
Outputs: output/pdf/reva-project-overview-packet.pdf and docs/project-overview-packet.md.
Side effects: Registers fonts at import and overwrites both artifacts when main runs.
Boundary: Worktree/status prose is a dated authored snapshot. Regeneration does not inspect Git or refresh its facts.
"""
from pathlib import Path
from html import escape
import re

from reportlab.pdfgen.canvas import Canvas
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak, Flowable
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.colors import HexColor, black, white
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont

# --- Artifact destinations, dated baseline, palette, and font registration ---
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "output/pdf/reva-project-overview-packet.pdf"
MD = ROOT / "docs/project-overview-packet.md"
BASE = "d0af1df"
REPO = "https://github.com/Siddiqui-R/2026_ricehackathon_medicine"
WIDTH = 516
TEAL, SKY, IVORY, GOLD = map(HexColor, ["#0A5B6C", "#E1ECEE", "#FAF4F4", "#C8A07D"])
MUTED, BORDER = HexColor("#49565B"), HexColor("#D9D9D9")
FONTS = Path("/System/Library/Fonts/Supplemental")
for key, file in [("Arial", "Arial.ttf"), ("Arial-Bold", "Arial Bold.ttf"), ("Arial-Italic", "Arial Italic.ttf")]:
    pdfmetrics.registerFont(TTFont(key, str(FONTS / file)))
pdfmetrics.registerFontFamily("Arial", normal="Arial", bold="Arial-Bold", italic="Arial-Italic", boldItalic="Arial-Bold")

# --- Shared typography for PDF prose, code, and comparison tables ---
styles = {
    "body": ParagraphStyle("body", fontName="Arial", fontSize=10, leading=14.2, textColor=black, spaceAfter=9),
    "small": ParagraphStyle("small", fontName="Arial", fontSize=8.7, leading=12.1, textColor=MUTED, spaceAfter=7),
    "title": ParagraphStyle("title", fontName="Arial-Bold", fontSize=29, leading=33, textColor=black, spaceAfter=14),
    "h1": ParagraphStyle("h1", fontName="Arial-Bold", fontSize=22, leading=27, textColor=black, spaceAfter=12),
    "h2": ParagraphStyle("h2", fontName="Arial-Bold", fontSize=12.5, leading=16, textColor=black, spaceBefore=9, spaceAfter=7),
    "cell": ParagraphStyle("cell", fontName="Arial", fontSize=9.1, leading=12.4, textColor=black),
    "head": ParagraphStyle("head", fontName="Arial-Bold", fontSize=9.1, leading=12.4, textColor=black),
    "code": ParagraphStyle("code", fontName="Courier", fontSize=8.3, leading=11.7, textColor=black, spaceAfter=9),
}

# --- Escape source text before applying the limited inline presentation markup ---
def rich(s):
    s = escape(s)
    s = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", s)
    s = re.sub(r"`([^`]+)`", r'<font name="Courier">\1</font>', s)
    return s.replace("\n", "<br/>")

def para(text, style="body"):
    return Paragraph(rich(text), styles[style])

# --- Draw the three bounded stack, worktree, and record-memory diagrams ---
class Diagram(Flowable):
    def __init__(self, kind):
        super().__init__(); self.kind = kind; self.width = WIDTH
        self.height = {"stack": 257, "worktrees": 171, "memory": 168}[kind]

    def draw(self):
        c = self.canv
        def box(x,y,w,h,title,body="",fill=SKY):
            c.setFillColor(fill); c.setStrokeColor(TEAL); c.setLineWidth(.7)
            c.roundRect(x,y,w,h,7,stroke=1,fill=1)
            title_style = ParagraphStyle("node", fontName="Arial-Bold", fontSize=9.7, leading=12, alignment=1, textColor=TEAL)
            p=Paragraph(escape(title),title_style); _,hh=p.wrap(w-14,h); p.drawOn(c,x+7,y+h-10-hh)
            if body:
                p=Paragraph(escape(body).replace("\n","<br/>"),ParagraphStyle("nodebody",fontName="Arial",fontSize=8.5,leading=11,alignment=1,textColor=black))
                _,hh=p.wrap(w-14,h); p.drawOn(c,x+7,y+9)
        def arrow(x1,y1,x2,y2):
            import math
            c.setStrokeColor(TEAL); c.setFillColor(TEAL); c.setLineWidth(1)
            c.line(x1,y1,x2,y2)
            a=math.atan2(y2-y1,x2-x1); path=c.beginPath(); path.moveTo(x2,y2)
            path.lineTo(x2-5*math.cos(a-.45),y2-5*math.sin(a-.45))
            path.lineTo(x2-5*math.cos(a+.45),y2-5*math.sin(a+.45)); path.close(); c.drawPath(path,fill=1,stroke=0)
        if self.kind=="stack":
            box(0,190,516,62,"SwiftUI iPhone app", "Summary  |  Records and symptoms  |  Visits  |  Medical profile")
            arrow(125,190,125,170); arrow(387,190,387,170)
            box(0,108,248,62,"On device", "AppStore + Codable models\nAtomic JSON, original files, OCR and audio")
            box(268,108,248,62,"Swift API server", "URLSession -> HTTPS -> Vapor\nPrivate bearer identity and validated routes")
            arrow(392,108,392,84)
            box(0,12,160,72,"Gemini", "Document summaries\nVisit overview and selection", GOLD)
            box(178,12,160,72,"Whisper and calling", "OpenAI transcription\nElevenLabs + Twilio", GOLD)
            box(356,12,160,72,"Server storage", "Local owner files OR\nPostgreSQL via PostgresNIO", GOLD)
            c.setStrokeColor(TEAL); c.line(80,95,436,95); c.line(392,108,392,95)
            arrow(80,95,80,84); arrow(258,95,258,84)
        elif self.kind=="worktrees":
            box(148,106,220,59,"Shared Git history", "One repository; separate checkouts")
            for center in [82,258,434]:
                c.setStrokeColor(TEAL); c.line(258,106,258,92); c.line(82,92,434,92); arrow(center,92,center,78)
            box(0,4,164,74,"main", "Current integration\nd0af1df", SKY)
            box(176,4,164,74,"review/implementation", "Historical review + pending patch\neb2ec3a", IVORY)
            box(352,4,164,74,"review/final", "Historical API review report\nd9ec87c", IVORY)
        elif self.kind=="memory":
            box(0,107,160,55,"Documents", "Import -> OCR/text review")
            box(178,107,160,55,"Symptoms", "User observation + local time")
            box(356,107,160,55,"Visit memories", "Audio/transcript -> saved text")
            for center in [80,258,436]: arrow(center,107,center,87)
            c.setStrokeColor(TEAL); c.line(80,87,436,87); arrow(258,87,258,69)
            box(81,5,354,64,"Versioned MedicalRecords", "Search + relevant selection + exact source quotes\nVisitReport -> review -> PDF export")

# --- Page-content helpers shared by the PDF and Markdown renderers ---
pages = []
def page(title, subtitle=None, cover=False):
    p=[]; pages.append(p); p.append(("title" if cover else "h1", title))
    if subtitle: p.append(("small",subtitle))
    return p
def t(p,headers,rows,widths): p.append(("table",headers,rows,widths))
def b(p,text): p.append(("body",text))
def h(p,text): p.append(("h2",text))

# --- Authored handoff content at the declared baseline ---
p=page("Reva project overview packet", "Team handoff | September 12 2026 | Code baseline d0af1df", True)
b(p,"Reva is a native iPhone MVP that brings records, symptom observations and visit memories together to prepare a useful conversation with a clinician. This packet explains the current code, the local worktrees, team ownership, and how data moves through the app and optional services.")
b(p,"**The local demo is working.** Provider adapters are implemented and tested with mocks; credentials, live provider checks and the optional Tiger database still require setup. No production web app or MyChart connection is included.")
p.append(("diagram","stack"))
p.append(("small","Sky nodes describe implemented app/server components. Gold nodes identify configurable service or storage boundaries; live activation is separate from implementation."))
h(p,"How to use this packet")
t(p,["Pages","What you will find"],[["2-3","Existing worktrees, branch safety and three-person ownership"],["4-5","Data relationships, workflow behavior and feature status"],["6-7","Connectors, configuration, running the project and evidence"]],[55,461])
b(p,"The phone saves locally first. Server sync is an explicit transfer; AI and call requests are separate operations. Provider secrets belong on the server. The app never talks directly to PostgreSQL.")
p.append(("small", "Repository: " + REPO + "\nProduct domain: revamed.health. This packet does not claim a deployed site."))

# --- Historical checkout inventory and team ownership guidance ---
p=page("Existing worktrees", "Inventory inspected at d0af1df before this documentation update")
b(p,"A Git worktree is a separate folder with its own branch, checked-out files and uncommitted changes, sharing one repository's commit history. Worktrees support parallel editing on one machine. They are not separate services, environments deployed to users, or copies that sync automatically.")
p.append(("diagram","worktrees"))
t(p,["Checkout and branch","Observed state","Relationship"],[
 ["Reva\nmain","Clean integration checkout at d0af1df; matches the local origin/main tracking ref.","Current baseline"],
 [".worktrees/implementation-review\nreview/implementation","eb2ec3a; 2 modified tracked files and 2 untracked review reports. Nothing staged.","6 commits behind baseline main"],
 [".worktrees/final-review\nreview/final","d9ec87c; 1 untracked API review report. No tracked modifications or staged changes.","4 commits behind baseline main"],
],[180,239,97])
p.append(("small","All paths above are relative to /Users/tempadmin/Documents/Reva except the root label Reva. This documentation commit will advance main beyond the inventory baseline."))
h(p,"What the review folders contain")
b(p,"The implementation-review patch changes the older AppStore.swift and UI/RecordsView.swift layout: source versions, metadata-edit preservation, summary labels and PDF page navigation. Its pending diff is 55 insertions and 14 deletions. Reports are 02-implementation.md and 03-targeted-revision.md. The final-review folder holds mvp-api-contract-review.md.")
b(p,"**Preserve these folders as review evidence.** Neither review branch has commits absent from main. Their uncommitted content targets older code, while main already contains integrated fixes and later features. Compare any useful idea against current code; do not merge or copy either folder wholesale.")

p=page("Working as a three person team")
b(p,"Separation is by folders and focused AppStore extensions inside one iPhone target. The suggested feature branches below do not exist yet. Create them from the same agreed main checkpoint when the team is ready. One teammate also acts as integration captain; that is a coordination role, not a fourth developer.")
t(p,["Owner","Primary files","Suggested branch"],[
 ["1  Records and preparation","Features/Records and Features/Preparation; AppStore +Records, +Symptoms, +Visits; document import, scan and PDF adapters.","mvp/records-preparation"],
 ["2  Booking and visit memory","Features/Visits; AppStore +Bookings and +Recordings; Device/AudioServices.swift.","mvp/visit-memory"],
 ["3  Server and providers","server/**: HTTP routes, Gemini/voice adapters, local/Postgres stores, migrations, server tests and setup.","mvp/server-providers"],
 ["Integration captain","Core shared models/DTOs, shared UI/theme, Medical profile, root navigation, provider/sync state, scripts, project file and contracts.","Integrates into main"],
],[109,278,129])
p.append(("small","App paths begin at apps/ios/Reva/. Core/SymptomEntry.swift is owned with records; shared Models.swift and ReportEngine.swift changes still need coordination."))
h(p,"Proposed worktree setup")
b(p,"From a clean integration checkout, agree a base SHA and branch names first. The following creates sibling feature folders; it does not alter the retained review worktrees.")
p.append(("code", "git fetch origin\ngit status --short\ngit pull --ff-only origin main\nreva_base=$(git rev-parse HEAD)\ngit worktree add -b mvp/records-preparation \\\n  ../Reva-records-preparation \"$reva_base\"\ngit worktree add -b mvp/visit-memory \\\n  ../Reva-visit-memory \"$reva_base\"\ngit worktree add -b mvp/server-providers \\\n  ../Reva-server-providers \"$reva_base\""))
h(p,"How changes come back together")
b(p,"Each person edits only their assigned checkout, makes small commits and sends the captain the SHA, changed files, tests and any contract change. The captain reviews and merges one branch at a time, resolves shared edits deliberately, regenerates the Xcode project when needed, checks the integrated build and pushes main.")
b(p,"On separate computers, use separate clones and exchange pushed commits. Keep one owner for simulator verification on a shared Mac: two checkouts using the same app bundle can overwrite the same demo state. Worktrees reduce file conflicts; they do not coordinate shared DTOs, build outputs or runtime data for you.")

# --- Current domain interactions, feature status, and API setup ---
p=page("Data and component interactions")
p.append(("diagram","memory"))
h(p,"From a source to a visit brief")
b(p,"Files and photos enter through native pickers. PDFKit reads embedded PDF text; Vision performs OCR and VisionKit supplies camera scanning on supported iPhones. The user reviews the extracted wording and date. Reva preserves the original file, saves a record, and produces a local excerpt. If connected AI is enabled, it can replace that summary with a labeled Gemini result.")
b(p,"Preparation uses visit type, concern, goal and pinned records. Locally, ReportEngine matches terms and context against titles, tags, summaries and full text. Connected preparation submits readable record candidates to Gemini for an overview, questions and source IDs. The client validates IDs, retains pins and creates exact source excerpts locally. This is currently a record scan, not a vector database or embeddings pipeline.")
t(p,["Object","Purpose and connection"],[
 ["PatientProfile","Persistent identity, allergies, medications, conditions, procedures and care notes. Quick-reference information; currently excluded from the records-only preparation input. Profile name is used in configured call requests."],
 ["MedicalRecord + SymptomEntry","Searchable source text, summary, original file reference, status and version. Optional structured symptom fields retain occurrence time/zone and the user's observations."],
 ["Visit + VisitReport","Appointment goal, notes, questions and pins; generated sections reference source record IDs, versions and original pages where known."],
 ["VisitRecording + BookingRequest","Transcript segments/audio and saved-memory backlinks; separate booking state, stable call request identity and provider outcome."],
],[150,366])
b(p,"AppStore writes a complete AppSnapshot through LocalRepository using an atomic JSON replacement and one backup. Original files are separate. Record changes alter source versions/signatures, so old briefs become stale; user questions and notes remain authoritative. Late AI responses cannot silently replace edits made while the request was running.")

p=page("Functionality and current status")
t(p,["Feature","What a user can do","Status"],[
 ["Summary","See the next visit, add records/visits, log symptoms, open Medical profile, and jump from Recent records to the full Records tab.","Local"],
 ["Medical profile","View/edit persistent health details and open Settings from the gear. Empty fields remain Not provided.","Local"],
 ["Documents and OCR","Import PDF/text/images, review or correct extraction, search/filter, preview originals and edit source metadata.","Local; camera needs device check"],
 ["Symptom log","Create/edit dated User symptom entries with optional severity, duration, details, triggers and what helped.","Local"],
 ["Visit preparation","Match relevant records, pin sources, keep personal questions, regenerate stale briefs, open cited pages and share a PDF.","Local; Gemini mode needs setup"],
 ["Audio and visit memory","Record with consent, pause outside foreground, play saved audio, correct transcript words and retain a linked memory.","Native flow; live speech needs setup"],
 ["Clinic booking","Run a labeled simulation, or review/consent to a configured outbound call and check its status/transcript.","Simulation local; live calls need setup"],
 ["Server sync","Explicitly push/pull a snapshot and its attachments, with owner identity and revision conflict handling.","Local server verified; hosting needed remotely"],
],[112,296,108])
h(p,"Two workflows to keep distinct")
b(p,"**Recording:** consent -> capture original audio -> explicit transcription -> Whisper segments with relative timestamps -> review/correct -> saved memory record. The fictional sample transcript is separate and is never attached to new microphone audio. Whisper output uses generic speaker labels; diarization is not implemented.")
b(p,"**Calling:** review the clinic, number, reason and window -> explicit consent -> persist call intent on the server -> ElevenLabs agent dials through its imported Twilio number -> manually check status and transcript. Stable request IDs and durable receipts prevent automatic redial after an uncertain outcome. Call completion does not confirm an appointment; the user updates the visit after clinic confirmation.")
h(p,"Outside the current MVP")
b(p,"No MyChart connection, browser wrapper, custom password encryption, local Whisper integration or Google Speech-to-Text adapter is built. OCR and AI output remain reviewable; perfect extraction is not promised. Production deployment and medical-data compliance have not been established.")

p=page("Technology and API connections")
t(p,["Technology","Role in this codebase"],[
 ["Swift and SwiftUI","One native iPhone target; iOS 18 minimum. Verified with Xcode 26.4, Swift 6.3 compiler and iOS 26.4 simulator. Generated app project uses Swift 5 language mode."],
 ["Apple frameworks","Combine state publication; Codable/JSON persistence; PDFKit, Vision, VisionKit, PhotosUI, QuickLook, AVFoundation, UIKit/CoreText and CryptoKit source signatures."],
 ["Vapor 4.122.1","Swift HTTP server and authenticated JSON/binary routes. URLSession is the app's transport. No third-party iPhone packages are required."],
 ["PostgresNIO 1.33.1","Optional PostgreSQL adapter: JSONB snapshots, BYTEA attachments and mutation audit. Local owner-file storage is the default. Live Tiger testing is pending."],
 ["Gemini Developer API","Default model in code: gemini-3.8-flash. Structured generateContent responses for summaries and preparation. GEMINI_MODEL can select an available model."],
 ["OpenAI and ElevenLabs","whisper-1 audio transcription; ElevenLabs Twilio outbound call and conversation polling APIs. Provider HTTP requests originate only from the server."],
],[152,364])
h(p,"Native to server route map")
t(p,["Route","Input and result"],[
 ["GET /v1/providers","Reports configured services/models and live-call flag; not a credential test."],
 ["POST /v1/ai/summarize","Record ID, title and text -> summary and model."],
 ["POST /v1/ai/prepare","Visit goals/questions + candidate records -> overview, questions, source IDs and model."],
 ["POST /v1/audio/transcribe","Raw audio + MIME/filename headers -> text, timestamped segments and model."],
 ["POST /v1/booking/call\nGET /v1/booking/call/:id","Reviewed stable request -> provider conversation/status; poll by local request ID."],
 ["GET/PUT/DELETE /v1/state\nPUT/GET/DELETE /v1/attachments/:id","Versioned snapshot exchange and separate original-file transfer."],
],[221,295])
b(p,"HTTPS is required except explicit loopback development. Private REVA_TOKENS enables paid provider access; the public demo token cannot do so. Provider keys stay server-side and the app's access token stays in memory for the session. Snapshot commits and attachment transfers are separate transactions, so a failed sync may leave already-copied files.")

p=page("Running and handing off the project")
h(p,"Local demo and optional API")
b(p,"Open Reva.xcodeproj, select Reva and an iPhone simulator, then Run. No API keys are needed. From the repository root, regenerate after source changes and start the optional server:")
p.append(("code", "python3 scripts/generate_project.py\npython3 scripts/run_server.py --build"))
b(p,"Simulator Settings: http://127.0.0.1:8080 and reva-local-demo-token. A physical phone needs a reachable HTTPS server; its loopback address does not refer to the Mac.")
t(p,["Connection","Configuration needed"],[
 ["Private service access","REVA_TOKENS mapping and the matching app access token"],
 ["Gemini","GEMINI_API_KEY; optional GEMINI_MODEL"],
 ["Whisper","OPENAI_API_KEY; OPENAI_TRANSCRIPTION_MODEL=whisper-1"],
 ["Calling","ELEVENLABS_API_KEY, ELEVENLABS_AGENT_ID, ELEVENLABS_PHONE_NUMBER_ID, REVA_ENABLE_LIVE_CALLS; configured agent and imported Twilio number"],
 ["PostgreSQL and receipts","REVA_STORAGE=postgres + DATABASE_URL. Keep REVA_DATA_DIRECTORY durable for call receipts even with PostgreSQL."],
],[129,387])
b(p,"Follow .env.example and server/.env.example. Root .env is empty and ignored. The launcher reads it without shell evaluation; exported values win. Keep keys out of commits. Discovery reports configuration, not credential validity.")
h(p,"Verification already recorded")
b(p,"Latest native follow-up: Xcode build passed; 43 root tests passed and one opt-in live-server test was skipped. The earlier server checkpoint recorded 29 passes and one live-PostgreSQL skip. These are separate recorded runs, not a newly rerun combined suite for this packet. Real local HTTP checks and simulator flows are documented; paid providers and a live database remain unverified.")
p.append(("code", "swift test -j 6\nswift test --package-path server -j 6\n# Build the server before the two HTTP checks below.\npython3 scripts/test_client_server.py\npython3 scripts/check_provider_api.py"))
h(p,"Where to go next")
b(p,"Assign owners and create agreed feature branches. Test configured providers with synthetic data. Verify signing, camera and microphone on a physical iPhone; use manual feedback for focused revisions.")
p.append(("small", "Source map at baseline d0af1df: docs/architecture.md; docs/team-workflow.md; docs/verification/profile-symptoms.md; docs/verification/README.md; docs/task-specs/mvp-api-contract.md; server/README.md; Core/Models.swift; Core/ProviderClient.swift; server/Package.resolved. All app-relative source paths start at apps/ios/Reva/."))

# --- Markdown equivalents of the native PDF diagrams ---
DIAGRAM_MD = {
 "stack": "```mermaid\nflowchart TD\n  UI[SwiftUI iPhone app] --> LOCAL[AppStore and local JSON files]\n  UI --> API[URLSession to Vapor server]\n  API --> GEMINI[Gemini summaries and preparation]\n  API --> VOICE[Whisper and ElevenLabs with Twilio]\n  API --> STORE[Local files or PostgresNIO to PostgreSQL]\n```",
 "worktrees": "```mermaid\nflowchart TD\n  G[Shared Git history] --> MAIN[main at d0af1df]\n  G --> IMPLEMENT[review implementation at eb2ec3a]\n  G --> REVIEW[review final at d9ec87c]\n```",
 "memory": "```mermaid\nflowchart TD\n  DOC[Documents and OCR] --> RECORD[Versioned MedicalRecords]\n  SYM[Structured symptom entries] --> RECORD\n  AUDIO[Transcript memories] --> RECORD\n  RECORD --> PREP[Relevant selection and exact quotes]\n  PREP --> PDF[Visit report and PDF]\n```",
}

# --- Render repeated table headers and dated page furniture ---
def render_table(headers,rows,widths):
    cells=[[para(x,"head") for x in headers]]+[[para(x,"cell") for x in row] for row in rows]
    result=Table(cells,colWidths=widths,hAlign="LEFT",repeatRows=1)
    result.setStyle(TableStyle([
        ("BACKGROUND",(0,0),(-1,0),SKY),("GRID",(0,0),(-1,-1),.5,BORDER),
        ("VALIGN",(0,0),(-1,-1),"MIDDLE"),("LEFTPADDING",(0,0),(-1,-1),9),
        ("RIGHTPADDING",(0,0),(-1,-1),9),("TOPPADDING",(0,0),(-1,-1),7),
        ("BOTTOMPADDING",(0,0),(-1,-1),7),
    ]))
    return result

def footer(c,doc):
    c.saveState(); c.setFillColor(MUTED); c.setFont("Arial",8)
    c.drawString(48,765,"REVA  /  PROJECT OVERVIEW")
    c.drawRightString(564,765,"12 SEP 2026")
    c.setStrokeColor(BORDER); c.setLineWidth(.5); c.line(48,38,564,38)
    c.drawString(48,25,"Technical handoff  |  Code baseline "+BASE)
    c.drawRightString(564,25,str(doc.page)+" / "+str(len(pages)))
    c.restoreState()

# --- Serialize the same page definitions to PDF flowables and editable Markdown ---
def main():
    OUT.parent.mkdir(parents=True,exist_ok=True)
    story=[]; md=[]
    for index,items in enumerate(pages):
        if index: story.append(PageBreak()); md.append("\n---\n")
        for item in items:
            kind=item[0]
            if kind=="table":
                _,headers,rows,widths=item
                story += [render_table(headers,rows,widths),Spacer(1,10)]
                md += ["| "+" | ".join(headers)+" |","| "+" | ".join("---" for _ in headers)+" |"]
                md += ["| "+" | ".join(v.replace("\n","<br>") for v in row)+" |" for row in rows]
                md.append("")
            elif kind=="diagram":
                story += [Diagram(item[1]),Spacer(1,10)]; md += [DIAGRAM_MD[item[1]],""]
            else:
                story.append(para(item[1],kind))
                prefix={"title":"# ","h1":"## ","h2":"### "}.get(kind,"")
                md += [("```sh\n"+item[1]+"\n```") if kind=="code" else prefix+item[1],""]
    doc=SimpleDocTemplate(str(OUT),pagesize=(612,792),leftMargin=48,rightMargin=48,topMargin=48,bottomMargin=49,
                          title="Reva project overview packet",author="Reva project team",pageCompression=1)
    doc.build(story,onFirstPage=footer,onLaterPages=footer)
    MD.write_text("\n".join(md))
    print(OUT); print(MD)

if __name__=="__main__": main()
