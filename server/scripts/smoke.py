#!/usr/bin/env python3
"""Real localhost HTTP/restart smoke test using temporary synthetic data only.

Purpose: Check authentication, owner separation, exact bytes, revisions, and restart durability.
Inputs: An already-built server/.build/debug/RevaAPI executable and an available loopback port.
Outputs: A PASS message, or an assertion/timeout when the real server contract differs.
Side effects: Starts/restarts one local child server and writes synthetic temporary storage/logs.
Cleanup: The main scenario stops its child in finally and removes its temporary directory.
No provider endpoints are invoked. This is separate from the opt-in live database test.
"""
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

# --- Fixed executable and synthetic owner fixtures ---
ROOT = Path(__file__).resolve().parents[1]
BINARY = ROOT / ".build/debug/RevaAPI"
TOKEN_A = "smoke-owner-a-token-123456789"
TOKEN_B = "smoke-owner-b-token-123456789"
SNAPSHOT = {"schemaVersion": 1, "profile": {"id": "owner-b", "name": "Synthetic smoke patient"},
            "records": [], "visits": [], "bookings": [], "recordings": []}


def main():
    # --- Isolate storage, choose loopback, and replace inherited storage/owner settings ---
    with tempfile.TemporaryDirectory(prefix="reva-http-smoke-") as temporary:
        with socket.socket() as reservation:
            reservation.bind(("127.0.0.1", 0))
            port = reservation.getsockname()[1]
        base = f"http://127.0.0.1:{port}"
        environment = {key: value for key, value in os.environ.items()
                       if not key.startswith("REVA_") and key != "DATABASE_URL"}
        environment.update(REVA_STORAGE="local", REVA_HOST="127.0.0.1", REVA_PORT=str(port),
                           REVA_DATA_DIRECTORY=str(Path(temporary) / "state"),
                           REVA_TOKENS=json.dumps({TOKEN_A: "owner-a", TOKEN_B: "owner-b"}))

        # --- Preserve raw bytes and expose negative HTTP responses to assertions ---
        def request(method, path, body=None, token=TOKEN_A, extra=None):
            headers = {"Authorization": f"Bearer {token}"} if token else {}
            headers.update(extra or {})
            if isinstance(body, dict):
                headers["Content-Type"] = "application/json"
                body = json.dumps(body).encode()
            req = urllib.request.Request(base + path, body, headers, method=method)
            try:
                response = urllib.request.urlopen(req, timeout=5)
            except urllib.error.HTTPError as error:
                response = error
            with response:
                return response.status, dict(response.headers), response.read()

        # --- Own the child process and wait a bounded time for real HTTP readiness ---
        with open(Path(temporary) / "server.log", "w+") as log:
            def start():
                process = subprocess.Popen([str(BINARY)], cwd=ROOT, env=environment, stdout=log, stderr=log)
                for _ in range(100):
                    if process.poll() is not None:
                        raise AssertionError("Server exited before becoming ready")
                    try:
                        if request("GET", "/health", token=None)[0] == 200:
                            return process
                    except OSError:
                        pass
                    time.sleep(0.05)
                process.terminate()
                process.wait(timeout=5)
                raise AssertionError("Server did not become ready")

            process = start()
            try:
                # --- Authentication, compare-and-swap ownership, and original attachment bytes ---
                assert request("GET", "/v1/state", token=None)[0] == 401
                assert request("PUT", "/v1/state", {"baseRevision": 0, "snapshot": SNAPSHOT})[0] == 200
                assert request("GET", "/v1/state", token=TOKEN_B)[0] == 404
                assert request("PUT", "/v1/state", {"baseRevision": 0, "snapshot": SNAPSHOT})[0] == 409
                source = b"\x00\xff\x80Synthetic exact attachment bytes\r\n"
                assert request("PUT", "/v1/attachments/source", source,
                               extra={"Content-Type": "application/pdf", "X-Filename": "Synthetic source.pdf"})[0] == 204
                assert request("GET", "/v1/attachments/source")[2] == source
                assert request("GET", "/v1/attachments/source", token=TOKEN_B)[0] == 404
                # --- Restart against the same directory, then verify deletion tombstones ---
                process.terminate()
                process.wait(timeout=5)
                process = start()
                assert json.loads(request("GET", "/v1/state")[2]) == {"revision": 1, "snapshot": SNAPSHOT}
                assert request("GET", "/v1/attachments/source")[2] == source
                assert json.loads(request("DELETE", "/v1/state")[2]) == {"revision": 2}
                status, response_headers, _ = request("GET", "/v1/state")
                assert status == 404 and response_headers.get("X-State-Revision", response_headers.get("x-state-revision")) == "2"
                assert request("GET", "/v1/attachments/source")[0] == 404
                assert request("PUT", "/v1/state", {"baseRevision": 1, "snapshot": SNAPSHOT})[0] == 409
                assert request("PUT", "/v1/state", {"baseRevision": 2, "snapshot": SNAPSHOT})[0] == 200
            finally:
                # --- Release only the process created by this script ---
                if process.poll() is None:
                    process.terminate()
                process.wait(timeout=5)
    print("PASS: real HTTP auth, owner isolation, conflict, bytes, process restart, deletion and tombstone checks")


if __name__ == "__main__":
    main()
