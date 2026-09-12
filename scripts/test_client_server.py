#!/usr/bin/env python3
"""Run real native URLSession tests against a temporary local Vapor process.

Purpose: Run the native ServerClient against a real isolated API instead of a mocked URLSession.
Inputs: Installed Xcode Swift toolchain, built RevaAPI, checked-in fixtures, and an available loopback port.
Outputs: The opt-in LiveServerTests result plus sanitized local-server diagnostics on failure.
Side effects: Builds/runs Swift tests, starts a local child server, and writes temporary synthetic owner data.
Cleanup: Owned process groups are stopped on normal completion, failure, or termination. No provider routes are used.
"""
import json
import os
from pathlib import Path
import secrets
import signal
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

# --- Repository-local binary and explicit Xcode toolchain prerequisites ---
ROOT = Path(__file__).resolve().parents[1]
BINARY = ROOT / "server/.build/debug/RevaAPI"
SWIFT = Path("/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift")


# --- Stop an owned process group, escalating only after the grace period ---
def stop(process):
    if process is None or process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
        process.wait(timeout=8)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait(timeout=5)
    except ProcessLookupError:
        process.wait(timeout=5)


# --- Create isolated local configuration and synthetic owner tokens ---
def main():
    if not BINARY.is_file():
        raise SystemExit("Build the backend first: cd server && swift build -j 6")
    if not SWIFT.is_file():
        raise SystemExit("Expected the installed Xcode Swift toolchain under /Applications/Xcode.app.")
    base_environment = {key: value for key, value in os.environ.items()
                        if not key.startswith("REVA_") and key != "DATABASE_URL"}
    base_environment["DEVELOPER_DIR"] = "/Applications/Xcode.app/Contents/Developer"
    token = secrets.token_urlsafe(32)
    other_token = secrets.token_urlsafe(32)
    server = test = None
    with tempfile.TemporaryDirectory(prefix="reva-client-server-") as temporary:
        with socket.socket() as reservation:
            reservation.bind(("127.0.0.1", 0))
            port = reservation.getsockname()[1]
        base_url = f"http://127.0.0.1:{port}"
        environment = dict(base_environment, REVA_STORAGE="local", REVA_HOST="127.0.0.1", REVA_PORT=str(port),
                           REVA_DATA_DIRECTORY=str(Path(temporary) / "state"),
                           REVA_TOKENS=json.dumps({token: "synthetic-client-owner", other_token: "synthetic-other-owner"}))
        with open(Path(temporary) / "server.log", "w+") as log:
            try:
                # --- Wait for the real local storage health endpoint before running the native client ---
                server = subprocess.Popen([str(BINARY)], cwd=ROOT / "server", env=environment,
                                          stdout=log, stderr=log, start_new_session=True)
                for _ in range(150):
                    if server.poll() is not None:
                        raise RuntimeError("Local server exited before readiness.")
                    try:
                        with urllib.request.urlopen(base_url + "/health", timeout=1) as response:
                            health = json.load(response)
                            if response.status == 200 and health.get("status") == "ok" and health.get("storage") == "local":
                                break
                    except (OSError, ValueError):
                        pass
                    time.sleep(0.05)
                else:
                    raise RuntimeError("Temporary localhost server did not become ready.")
                # --- Opt in to only LiveServerTests against this temporary server ---
                test_environment = dict(base_environment, REVA_RUN_LIVE_CLIENT_TESTS="1", REVA_LIVE_TEST_URL=base_url,
                                        REVA_LIVE_TEST_TOKEN=token, REVA_LIVE_TEST_OTHER_TOKEN=other_token)
                print("Running native URLSession integration against a temporary localhost Vapor server.", flush=True)
                test = subprocess.Popen([str(SWIFT), "test", "-j", "6", "--filter", "LiveServerTests"],
                                        cwd=ROOT, env=test_environment, start_new_session=True)
                code = test.wait(timeout=300)
                if code:
                    raise RuntimeError(f"LiveServerTests failed with exit status {code}.")
                print("PASS: native ServerClient ↔ real local Vapor API; temporary server and data will be removed.", flush=True)
            # --- Report local diagnostics and release both child process groups ---
            except BaseException:
                log.flush()
                log.seek(0)
                diagnostic = log.read()
                if diagnostic:
                    print("Local server diagnostic:\n" + diagnostic, file=sys.stderr)
                raise
            finally:
                stop(test)
                stop(server)


# --- Route termination through deterministic child-process cleanup ---
if __name__ == "__main__":
    def interrupted(_signal, _frame):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, interrupted)
    try:
        main()
    except KeyboardInterrupt:
        raise SystemExit(130)
