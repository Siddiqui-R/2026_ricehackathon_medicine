#!/usr/bin/env python3
"""Verify explicit database mode fails closed against an unreachable loopback port.

Purpose: Prove database startup failure is bounded, redacted, and never falls back to local storage.
Inputs: An already-built RevaAPI executable and the deliberately unreachable loopback port 1.
Outputs: A PASS message or assertion/timeout describing a violated startup boundary.
Side effects: Launches one child process with synthetic credentials and a temporary data directory.
Cleanup: subprocess.run owns process completion/timeout and TemporaryDirectory removes test files.
This does not connect to a configured account or modify a real PostgreSQL database.
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

# --- Replace inherited storage settings with one deliberately failing synthetic configuration ---
root = Path(__file__).resolve().parents[1]
environment = {key: value for key, value in os.environ.items()
               if not key.startswith("REVA_") and key != "DATABASE_URL"}
with tempfile.TemporaryDirectory(prefix="reva-postgres-failure-") as directory:
    environment.update(
        REVA_STORAGE="postgres",
        REVA_TOKENS=json.dumps({"startup-test-token-123456789": "synthetic-owner"}),
        DATABASE_URL="postgres://synthetic:never-log-this-password@127.0.0.1:1/reva_test?sslmode=disable",
        REVA_ALLOW_INSECURE_LOCAL_POSTGRES="true", REVA_DATA_DIRECTORY=directory)
    # --- Bound total startup time outside the server's own acquisition deadline ---
    started = time.monotonic()
    result = subprocess.run([str(root / ".build/debug/RevaAPI")], env=environment,
                            capture_output=True, timeout=27)
    # --- Assert the failure contract without printing the synthetic credential ---
    output = (result.stdout + result.stderr).decode()
    assert result.returncode != 0, "Expected PostgreSQL startup failure"
    assert "No local fallback" in output, output
    assert "never-log-this-password" not in output, "Credential appeared in output"
    assert not list(Path(directory).iterdir()), "Unexpected local fallback data"
    print(f"PASS: PostgreSQL unreachable exits {result.returncode} in {time.monotonic() - started:.1f}s; credentials redacted; no local files")
