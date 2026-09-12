#!/usr/bin/env python3
"""Purpose: Synthesize validated audit records without editing application code.
Inputs: Frozen track findings, independent dispositions and coverage recommendations.
Outputs: Canonical findings, complete register, repair/improvement CSVs and final coverage.
Side effects: Writes only this audit directory; no builds, network, credentials or Git.
"""
import collections
import csv
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REPORTS = ROOT / "reports"


# Chunk: Preserve original assertions alongside the independently validated disposition.
originals = [x for f in sorted(REPORTS.glob("track-*-findings.json")) for x in json.loads(f.read_text())]
validations = [x for n in [18, 19] for x in json.loads((REPORTS / f"{n}-dispositions.json").read_text())]
by_id = {x["id"]: x for x in validations}
assert len(originals) == len(by_id) == len(validations) == 77
assert {x["id"] for x in originals} == set(by_id)
register = []
for original in originals:
    finding = dict(original)
    finding["originalAssertion"] = original
    disposition = by_id[finding["id"]]
    finding.update(status=disposition["status"], severity=disposition["severity"])
    finding["validation"] = disposition
    finding["validatorDisposition"] = disposition["rationale"]
    finding["evidence"] = str(original["evidence"]) + " | Independent validation: " + str(disposition["evidence"])
    finding["provenance"] = "Fable source review, Codex independent validation" if int(finding["id"].split("-")[1]) <= 6 or finding["id"].startswith("RVA-11-") else "Codex continuation and independent validation"
    if disposition.get("duplicateOf"):
        finding["duplicateOf"] = disposition["duplicateOf"]
    register.append(finding)


# Chunk: Apply supervisor scope corrections; original wording remains auditable above.
corrections = {
    "RVA-02-008": {
        "expected": "An editor should preserve unrelated newer visit data or reject a conflicting stale draft. The native visit-editor rerender behavior still needs a focused UI reproduction.",
        "smallestFix": "If reproduced, rebase form-owned visit edits on the latest visit or introduce an explicit stable conflict baseline. Do not assume the separate record editor already guards stale whole-value saves.",
    },
    "RVA-03-007": {
        "title": "Closed evidence gap: native optimization and provider checks executed in stage one",
        "actual": "The saved stage-one runner executed the existing regression harness and real native-client/local-server integration. The original missing-execution assertion is superseded.",
        "smallestFix": "No repair for this closed evidence gap; retain the successful run evidence.",
    },
    "RVA-06-002": {
        "title": "Closed evidence gap: current Swift signatures match all browser fixture goldens",
        "actual": "The Codex unchanged-production harness emitted all three browser golden signatures successfully; browser tests also pass against them.",
        "smallestFix": "No repair for this closed evidence gap; keep cross-platform signature verification with future contract changes.",
    },
    "RVA-05-005": {
        "title": "Rejected claim: native player does not remap AVAudioPlayer initialization errors to missing or damaged",
        "actual": "The missing-file guard has its own message. AVAudioPlayer initialization throws directly and the catch publishes that error's localized description. Cross-device codec behavior remains unverified separately.",
        "smallestFix": "No repair justified by this rejected error-remapping claim. Verify actual supported/unsupported formats on the target devices before changing messaging.",
    },
    "RVA-11-001": {
        "smallestFix": "Carry the existing persistent-volume requirement for call receipts into completed deployment configuration and verify receipts survive process recreation and redeploy. An absolute-path policy is optional hardening and does not itself establish durability.",
        "regressionCheck": "Persist a synthetic uncertain/completed call receipt, recreate the deployed process or container using its configured persistent volume, then replay/poll the same owner/request and assert no new dial. Use a fake provider; do not place a real call for this test.",
    },
    "RVA-11-005": {
        "title": "Remaining evidence gap: complete native booking and recording UI journeys have not run",
        "trigger": "Before claiming native workflow readiness, execute the remaining simulation, normal relaunch repair, reviewed submission/uncertain outcome and interactive navigation paths.",
        "actual": "The new production-state harness executes delayed call polling, stale owner publication and failed startup repair. It does not execute the complete booking simulation, normal successful relaunch repair, live submission UI or complete native recording journey.",
        "impact": "These unexecuted native workflow paths remain a verification gap; existing production state checks and browser captures are acknowledged rather than erased.",
        "smallestFix": "Run the remaining synthetic native booking/recording journeys with controlled provider transport and targeted UI checks; retain hardware/real-provider cases as separate gates until exercised.",
    },
    "RVA-04-004": {
        "regressionCheck": "While summarization is in flight, assert either that the brief action is disabled with clear busy context or that attempting it produces the chosen visible retry notice. After completion the action must generate a brief normally.",
    },
    "RVA-04-005": {
        "title": "Native record editor can replace a newly saved AI summary with its stale draft",
        "file": "apps/ios/Reva/Features/Records/RecordEditorView.swift", "line": 62,
        "requirementIDs": ["D05", "E04"],
        "trigger": "Open a record editor, let a summary request finish for that unchanged record, then save only a notes/title edit from the open form.",
        "actual": "The @State record draft is saved as a whole value, replacing the current summary and provenance with its older values.",
        "expected": "A notes/title-only record edit preserves a newer saved summary and its provenance; a deliberate source text edit invalidates derived data explicitly.",
        "impact": "A newly generated summary can be lost. The original report's visit-editor arm was not independently reproduced and is excluded from this confirmed defect.",
        "smallestFix": "At save time load the current record and apply only form-owned fields. Preserve its current summary/model unless source text actually changed. Reject conflicting source edits explicitly.",
        "regressionCheck": "Keep an editor draft open while a provider summary arrives; save a notes-only edit and assert the latest summary/model survive. Separately check changed source text invalidates summary/page mapping deliberately.",
    },
    "RVA-02-002": {
        "smallestFix": "Bound excerpts at a complete line or safe token boundary. Disclose truncation outside the exact quoted-source field, preserving exact substring citations and full original text. Apply equivalent native/browser rules.",
        "regressionCheck": "Exercise numeric value, unit, dose, negation and Unicode boundaries at the cap. Verify the quoted field is an exact complete source span and omission is visibly disclosed separately. Include the saved 100 mg-to-10 reproduction.",
    },
    "RVA-02-005": {
        "smallestFix": "Restrict fixture-wrapper removal to explicitly synthetic, recognized fixtures, or move fixture metadata outside source text. Preserve all ordinary uploaded content; do not infer demo provenance from a Source date header.",
    },
    "RVA-05-004": {
        "title": "Native mixed PDF pages can skip raster text when a short embedded header passes the OCR threshold",
        "smallestFix": "Detect incomplete embedded-text coverage or raster content and run bounded OCR on affected pages. Preserve page provenance and require review when completeness cannot be established. Merely increasing the character threshold is insufficient.",
    },
    "RVA-07-001": {
        "smallestFix": "Detect raster content or uncertain embedded-text coverage, OCR affected pages within existing budgets, and surface a page warning when completeness is uncertain. Preserve the original and avoid duplicate merged text. Do not rely on a larger character threshold alone.",
    },
    "RVA-07-002": {
        "title": "Failed browser import saves leave unused attachment keys and retries allocate new keys",
        "impact": "Failed snapshot CAS can leave unreferenced original keys; retries allocate new keys. Snapshot consistency is preserved. Physical byte duplication and quota exhaustion were not measured.",
    },
    "RVA-16-001": {
        "title": "Vercel setup guide specifies conflicting project roots with different deployment configurations",
        "impact": "A deployer can choose different build/routing/security behavior depending on which README instruction is followed. This source review does not identify the cause of the user's hosted 404.",
    },
}
for finding in register:
    finding.update(corrections.get(finding["id"], {}))
    if finding["id"] == "RVA-02-008":
        finding.pop("duplicateOf", None)
        finding["supervisorCorrection"] = "Retain this visit-editor candidate separately: canonical RVA-04-005 is narrowed to the record editor, so the unverified visit arm is not a duplicate of that confirmed scope."

canonical = [x for x in register if "duplicateOf" not in x]
for finding in canonical:
    finding["aliases"] = [x["id"] for x in register if x.get("duplicateOf") == finding["id"]]
    for duplicate in register:
        if duplicate.get("duplicateOf") == finding["id"]:
            finding["requirementIDs"] = sorted(set(finding["requirementIDs"]) | set(duplicate["requirementIDs"]))
(ROOT / "finding-register.json").write_text(json.dumps(register, indent=2) + "\n")
(ROOT / "findings.json").write_text(json.dumps(canonical, indent=2) + "\n")


# Chunk: Rank concrete repairs and retain suggestions outside the defect queue.
priority = ["RVA-10-001", "RVA-02-002", "RVA-02-005", "RVA-05-004", "RVA-07-001", "RVA-05-001", "RVA-04-005", "RVA-08-001", "RVA-03-001", "RVA-05-008", "RVA-05-002", "RVA-04-001", "RVA-16-001", "RVA-14-001"]
def ranking(x):
    return (priority.index(x["id"]) if x["id"] in priority else 100 + int(x["severity"][1]), x["id"])
def owner(x):
    if x["id"].startswith(("RVA-07-", "RVA-08-", "RVA-14-")):
        return "B: Browser and accessibility"
    if x["id"].startswith(("RVA-09-", "RVA-11-", "RVA-12-", "RVA-13-", "RVA-16-")):
        return "C: Server and release integration"
    return "A: Native and domain"
fields = ["rank", "id", "severity", "title", "owner", "file", "line", "trigger", "smallest_fix", "regression_check", "dependency_and_coordination", "evidence", "status"]
def write_queue(name, status):
    rows = sorted([x for x in canonical if x["status"] == status], key=ranking)
    with (ROOT / name).open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        for rank, x in enumerate(rows, 1):
            coordination = "Independent focused commit in assigned owner's worktree; rebase before review."
            if x["id"].startswith("RVA-02-"):
                coordination = "A owns native ReportEngine; coordinate equivalent browser domain change with B and preserve signature goldens. Serialize changes to the same domain file."
            elif x["id"] in ["RVA-03-001", "RVA-04-001", "RVA-10-001"]:
                coordination = "A owns shared AppStore integration. Land connection guards before adjacent startup/order edits; preserve source/version protections."
            elif x["id"].startswith("RVA-16-"):
                coordination = "C owns deployment/build contract. Review against a completed account checkpoint before hosting verification; do not sweep concurrent WIP into this repair."
            writer.writerow(dict(rank=rank, id=x["id"], severity=x["severity"], title=x["title"], owner=owner(x), file=x["file"], line=x["line"], trigger=x["trigger"], smallest_fix=x["smallestFix"], regression_check=x["regressionCheck"], dependency_and_coordination=coordination, evidence=x["evidence"], status=status))
    return rows
repairs = write_queue("repair-backlog.csv", "confirmed")
improvements = write_queue("improvements.csv", "suggestion")


# Chunk: Finish every checklist disposition while retaining unmet execution gates explicitly.
with (REPORTS / "coverage-draft.csv").open() as stream:
    coverage = list(csv.DictReader(stream))
assert len(coverage) == 67 and len({x["requirement_id"] for x in coverage}) == 67
changes = {
    "B05": ("Defect", "Independent validators confirm recorder failure-state, stale editor and provider-publication defects. Production failure/publication paths need correction despite generally explicit errors and validation."),
    "C06": ("Unverified", "Validation/identity/version/optional fields have source and unit evidence. UTC-plus-zone wording is a readability suggestion after validation, not demonstrated time corruption. The complete native/browser entry-edit-reload journey remains unexecuted."),
    "D03": ("Defect", "Both independent validators confirm the mixed-page OCR omission from complete source branches. Runtime extraction of a mixed PDF remains unverified; source confirmation does not claim such execution."),
    "D04": ("Defect", "RVA-07-002 is independently confirmed P3: original attachment keys can be left unused by failed snapshot CAS and retries allocate new keys. Physical byte duplication/quota exhaustion is unmeasured. Native alert stacking remains a candidate."),
    "D06": ("Defect", "RVA-04-006 is independently source-confirmed: camera PDFs are classified Notes and omitted by the exact Scan filter, with no kind editor. Other browser search/filter paths were traced; native UI execution is not claimed."),
    "E02": ("Defect", "Specified implant/ear scenarios pass, but independent validation confirms generic goal/fixture terms can select the unrelated ear record for another supplied visit (RVA-02-004). Broader clinical relevance remains unverified."),
    "F05": ("Unverified", "Owner isolation/CAS/bytes/collision checks have evidence, but the full attachment/DB requirement is not closed. RVA-06-001 is a documented retention/capacity suggestion after validation, not a demonstrated corruption defect. Live PostgreSQL and large-file execution remain unverified."),
    "K01": ("Defect", "Main light UI uses all six approved heart roles and removes Appearance. Native PDF still hardcodes teal (canonical RVA-04-008); a small native caption pair also misses its stated contrast target (RVA-04-007)."),
    "N03": ("Pass", "Independent validators18/19 adjudicated all77 inputs on tracks they did not author. Three duplicate entries are merged, unsupported claims rejected or qualified, and focused unchanged-production reproductions independently inspected."),
    "N04": ("Pass", "Final report,74 canonical findings,77-entry provenance register,23 ranked repairs,improvements,67 dispositions,commands and evidence inventory delivered. Completion is audit delivery, not certification of unexecuted functionality."),
}
ids = {x["id"] for x in register}
aliases = {x["id"]: x["duplicateOf"] for x in register if x.get("duplicateOf")}
for row in coverage:
    if row["requirement_id"] in changes:
        row["status"], row["rationale"] = changes[row["requirement_id"]]
    used = [x.strip() for x in row["finding_ids"].split(";") if x.strip()]
    assert all(x in ids for x in used)
    row["finding_ids"] = "; ".join(dict.fromkeys(aliases.get(x, x) for x in used))
    if row["requirement_id"] == "K01": row["finding_ids"] = "RVA-04-007; RVA-04-008"
    if row["requirement_id"] == "N03": row["evidence"] = "reports/18-validator.md; reports/19-validator.md; finding-register.json"
    if row["requirement_id"] == "N04": row["evidence"] = "FINAL-REPORT.md; findings.json; repair-backlog.csv; reports/coverage.csv; evidence/codex-takeover/evidence-inventory.json"
    row["reviewer"] = "Codex coverage synthesis; tracks01–16; independent validators18/19; supervisor final adjudication"
with (REPORTS / "coverage.csv").open("w", newline="") as stream:
    writer = csv.DictWriter(stream, fieldnames=list(coverage[0]))
    writer.writeheader(); writer.writerows(coverage)
checklist = ROOT / "checklist.md"
checklist.write_text(checklist.read_text().replace("- [ ] **", "- [x] **"))
summary = {
    "inputFindings": len(register), "canonicalFindings": len(canonical),
    "duplicateEntries": len(register)-len(canonical),
    "canonicalStatuses": dict(collections.Counter(x["status"] for x in canonical)),
    "confirmedSeverity": dict(collections.Counter(x["severity"] for x in repairs)),
    "coverage": dict(collections.Counter(x["status"] for x in coverage)),
    "repairIDs": [x["id"] for x in repairs],
}
(ROOT / "audit-summary.json").write_text(json.dumps(summary, indent=2) + "\n")
print(json.dumps(summary, indent=2))
