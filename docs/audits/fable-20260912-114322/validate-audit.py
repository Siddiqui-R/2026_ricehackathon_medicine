#!/usr/bin/env python3
"""Purpose: Check final audit identity, coverage, references and machine-readable consistency.
Inputs: Completed audit artifacts and the frozen source snapshot.
Outputs: validation-result.json and concise console result; assertions fail on inconsistency.
Side effects: Writes only the audit validation result. No application execution or mutation.
"""
import csv
import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent

# Chunk: Verify every requirement and incoming finding has exactly one final disposition.
findings = json.loads((ROOT / "findings.json").read_text())
register = json.loads((ROOT / "finding-register.json").read_text())
coverage = list(csv.DictReader((ROOT / "reports/coverage.csv").open()))
backlog = list(csv.DictReader((ROOT / "repair-backlog.csv").open()))
requirements = re.findall(r"\*\*([A-N][0-9]{2})\*\*", (ROOT / "checklist.md").read_text())
assert len(requirements) == len(set(requirements)) == len(coverage) == 67
assert set(requirements) == {x["requirement_id"] for x in coverage}
assert all(x["status"] in {"Pass", "Defect", "Unverified", "WIP", "Deferred", "Not applicable"} for x in coverage)
assert all("pending" not in x["reviewer"] for x in coverage)
assert len(findings) == len({x["id"] for x in findings}) == 74
assert len(register) == len({x["id"] for x in register}) == 77
confirmed = {x["id"] for x in findings if x["status"] == "confirmed"}
assert len(confirmed) == len(backlog) == 23
assert confirmed == {x["id"] for x in backlog}
assert all(x["validatorDisposition"] != "pending" for x in findings)
assert sum(bool(x.get("duplicateOf")) for x in register) == 3
assert next(x for x in findings if x["id"] == "RVA-02-008")["status"] == "candidate"
assert next(x for x in findings if x["id"] == "RVA-04-005")["file"].endswith("RecordEditorView.swift")

# Chunk: Verify frozen source and the exact production files compiled by the reproduction.
manifest = json.loads((ROOT / "snapshot-manifest.json").read_text())
frozen = Path(manifest["snapshotPath"])
for name, expected in manifest["fileSHA256"].items():
    assert hashlib.sha256((frozen / name).read_bytes()).hexdigest() == expected, name
assert hashlib.sha256((frozen / ".audit-source-delta.patch").read_bytes()).hexdigest() == manifest["patchSHA256"]
compiled = json.loads((ROOT / "evidence/codex-takeover/provider-context-production-hashes.json").read_text())
assert len(compiled) == 13
assert all(manifest["fileSHA256"][name] == digest for name, digest in compiled.items())
for finding in findings:
    assert set(finding["requirementIDs"]) <= set(requirements)
    if finding["status"] == "confirmed":
        source = frozen / finding["file"]
        assert source.is_file(), str(source)
        assert 1 <= finding["line"] <= len(source.read_text().splitlines()), finding["id"]

# Chunk: Validate published navigation and serialized artifacts without fetching external URLs.
links = 0
for filename in ["FINAL-REPORT.md", "AUDIT-LOG.md", "reports/17b-codex-evidence-adjudication.md", "reports/18-validator.md", "reports/19-validator.md"]:
    doc = ROOT / filename
    text = doc.read_text()
    assert text.count("```") % 2 == 0, filename
    for target in re.findall(r"\[[^\]]*\]\(([^)]+)\)", text):
        if target.startswith(("http:", "https:", "#")):
            continue
        target = target.split("#", 1)[0]
        if not target: continue
        assert (doc.parent / target).exists(), (filename, target)
        links += 1
json_files = list(ROOT.rglob("*.json"))
for file in json_files:
    json.loads(file.read_text())
result = {"checkedAt": datetime.now(timezone.utc).isoformat(), "result": "PASS",
          "requirements": 67, "incomingFindings": 77, "canonicalFindings": 74,
          "confirmedRepairs": 23, "frozenSourceHashes": len(manifest["fileSHA256"]),
          "productionReproHashes": 13, "localLinks": links, "jsonFilesParsed": len(json_files),
          "scope": "Audit artifact consistency and source identity; not an additional application test suite."}
(ROOT / "validation-result.json").write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps(result, indent=2))
