#!/usr/bin/env python3
"""Check real provider route registration with every provider deliberately unconfigured.

Purpose: Verify real HTTP provider wiring and fail-closed unconfigured responses without paid requests.
Inputs: An already-built RevaAPI executable and an available loopback port.
Outputs: Assertions for discovery, four authenticated routes, three 503 responses, and removed calling endpoints.
Side effects: Starts a temporary local server, sends synthetic HTTP requests, and removes its process/data afterward.
Isolation: All provider, database, and Reva configuration is removed before private test settings are supplied.
"""
import io
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
import wave

from test_client_server import BINARY, ROOT, stop


# --- Require the built server and strip provider configuration ---
def main():
    if not BINARY.is_file():
        raise SystemExit("Build the API first: python3 scripts/run_server.py --build")
    environment = {key: value for key, value in os.environ.items()
                   if not key.startswith(("GEMINI_", "OPENAI_", "ELEVENLABS_", "REVA_")) and key != "DATABASE_URL"}
    token = secrets.token_urlsafe(32)
    server = None
    with tempfile.TemporaryDirectory(prefix="reva-provider-http-") as temporary:
        with socket.socket() as reservation:
            reservation.bind(("127.0.0.1", 0))
            port = reservation.getsockname()[1]
        base_url = f"http://127.0.0.1:{port}"
        data_directory = Path(temporary) / "state"
        environment.update(REVA_STORAGE="local", REVA_HOST="127.0.0.1", REVA_PORT=str(port),
                           REVA_DATA_DIRECTORY=str(data_directory),
                           REVA_TOKENS=json.dumps({token: "synthetic-provider-smoke"}))

        # --- Send raw or JSON HTTP requests while retaining expected error responses ---
        def request(method, path, body=None, authorized=True, extra_headers=None):
            headers = {"Authorization": "Bearer " + token} if authorized else {}
            headers.update(extra_headers or {})
            if isinstance(body, dict):
                headers["Content-Type"] = "application/json"
                body = json.dumps(body).encode()
            req = urllib.request.Request(base_url + path, data=body, headers=headers, method=method)
            try:
                response = urllib.request.urlopen(req, timeout=5)
            except urllib.error.HTTPError as error:
                response = error
            with response:
                return response.status, response.read()

        # --- Own the isolated server process and bounded readiness wait ---
        with open(Path(temporary) / "server.log", "w+") as log:
            try:
                server = subprocess.Popen([str(BINARY)], cwd=ROOT / "server", env=environment,
                                          stdout=log, stderr=log, start_new_session=True)
                for _ in range(150):
                    if server.poll() is not None:
                        raise RuntimeError("Server exited before readiness.")
                    try:
                        if request("GET", "/health", authorized=False)[0] == 200:
                            break
                    except OSError:
                        pass
                    time.sleep(0.05)
                else:
                    raise RuntimeError("Provider smoke server did not become ready.")

                # --- Verify exact public discovery keys without exposing the token ---
                status, raw = request("GET", "/v1/providers")
                assert status == 200, (status, raw)
                configuration = json.loads(raw)
                assert set(configuration) == {"gemini", "transcription"}
                for name in ("gemini", "transcription"):
                    assert set(configuration[name]) == {"configured", "model"}
                    assert configuration[name]["configured"] is False
                    assert isinstance(configuration[name]["model"], str) and configuration[name]["model"]
                assert token.encode() not in raw

                # --- Build valid synthetic inputs so configuration gates are tested deliberately ---
                summary = {"recordID": "synthetic-record", "title": "Synthetic source", "text": "This is a fictional provider smoke document."}
                preparation = {"visit": {"id": "synthetic-visit", "type": "Primary care", "concern": "Review fictional source",
                                          "goal": "Organize discussion questions", "questions": []},
                               "records": [{"id": "synthetic-record", "title": "Synthetic source", "date": "2026-09-12",
                                            "text": "Fictional source for a disabled-provider test.", "summary": "Fictional source", "version": 1}]}
                audio = io.BytesIO()
                with wave.open(audio, "wb") as wav:
                    wav.setnchannels(1)
                    wav.setsampwidth(2)
                    wav.setframerate(8000)
                    wav.writeframes(b"\x00\x00" * 80)
                audio_headers = {"Content-Type": "audio/wav", "X-Filename": "Synthetic silence.wav"}
                posts = [("/v1/ai/summarize", summary, {}), ("/v1/ai/prepare", preparation, {}),
                         ("/v1/audio/transcribe", audio.getvalue(), audio_headers)]

                # --- Require authentication consistently across all four provider routes ---
                for method, path, body, extra in [("GET", "/v1/providers", None, {})] + [
                                                       ("POST", path, body, extra) for path, body, extra in posts]:
                    status, _ = request(method, path, body, authorized=False, extra_headers=extra)
                    assert status == 401, f"Unauthenticated {method} {path}: expected 401, got {status}"

                # --- Unconfigured operations must return safe errors ---
                for path, body, extra in posts:
                    status, raw = request("POST", path, body, extra_headers=extra)
                    assert status == 503, f"Unconfigured POST {path}: expected 503, got {status}: {raw!r}"
                    error = json.loads(raw)
                    assert error["error"] is True and isinstance(error["reason"], str) and error["reason"]
                    assert token.encode() not in raw
                # Retired calling endpoints must remain absent, even for authenticated requests.
                for method, path, body in [("POST", "/v1/booking/call", {}),
                                           ("GET", "/v1/booking/call/synthetic-call", None)]:
                    status, _ = request(method, path, body)
                    assert status == 404, f"Retired endpoint is still registered: {method} {path}"
                print("PASS: real HTTP provider status, four route auth checks, three unconfigured 503 responses, and retired calling routes return 404; no provider credentials.")
            # --- Preserve local diagnostics, then stop only the owned server ---
            except BaseException:
                log.flush()
                log.seek(0)
                print("Local server diagnostic:\n" + log.read(), file=sys.stderr)
                raise
            finally:
                stop(server)


# --- Turn termination into the same cleanup path as interruption ---
if __name__ == "__main__":
    def interrupted(_signal, _frame):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, interrupted)
    try:
        main()
    except KeyboardInterrupt:
        raise SystemExit(130)
