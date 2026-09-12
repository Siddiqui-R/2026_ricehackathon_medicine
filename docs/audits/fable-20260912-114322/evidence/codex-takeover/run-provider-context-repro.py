#!/usr/bin/env python3
"""Compile unchanged frozen production sources with a synthetic provider transport double."""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
from datetime import datetime, timezone

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
FROZEN = ROOT / ".worktrees/fable-audit-20260912-114322"
FILES = ["Core/Models.swift", "Core/SymptomEntry.swift", "Core/LocalRepository.swift",
         "Core/ProviderContracts.swift", "Core/ReportEngine.swift", "Core/BookingEngine.swift",
         "State/AppStore.swift", "State/AppStore+Records.swift", "State/AppStore+Visits.swift",
         "State/AppStore+Providers.swift", "State/AppStore+AI.swift", "State/AppStore+Bookings.swift",
         "State/AppStore+LiveCalls.swift"]
sources = [FROZEN / "apps/ios/Reva" / f for f in FILES]
manifest = {str(f.relative_to(FROZEN)): hashlib.sha256(f.read_bytes()).hexdigest() for f in sources}
(HERE / "provider-context-production-hashes.json").write_text(json.dumps(manifest, indent=2) + "\n")
with tempfile.TemporaryDirectory(prefix="reva-provider-audit-", dir="/private/tmp") as tmp:
    binary = str(Path(tmp) / "repro")
    command = ["/usr/bin/xcrun", "swiftc", "-swift-version", "5", "-parse-as-library", "-module-cache-path", str(Path(tmp) / "modules"), *map(str, sources), str(HERE / "ProviderContextRepro.swift"), "-o", binary]
    result = subprocess.run(command, capture_output=True, text=True)
    output = "Compiler exit: " + str(result.returncode) + "\n" + result.stdout + result.stderr
    if result.returncode == 0:
        run = subprocess.run([binary, str(FROZEN / "demo/seed.json"), tmp], capture_output=True, text=True)
        output += "Run exit: " + str(run.returncode) + "\n" + run.stdout + run.stderr
        result = run
    evidence = HERE / "provider-context-repro.txt"
    if evidence.exists():
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
        (HERE / ("provider-context-prior-" + stamp + ".txt")).write_text(evidence.read_text())
    evidence.write_text(output)
    print(output)
    raise SystemExit(result.returncode)
