#!/usr/bin/env python3
"""Check real provider route registration with every provider deliberately unconfigured."""
from datetime import datetime, timedelta, timezone
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

                status, raw = request("GET", "/v1/providers")
                assert status == 200, (status, raw)
                configuration = json.loads(raw)
                assert set(configuration) == {"gemini", "transcription", "booking", "liveCallsEnabled"}
                for name in ("gemini", "transcription", "booking"):
                    assert set(configuration[name]) == {"configured", "model"}
                    assert configuration[name]["configured"] is False
                    assert isinstance(configuration[name]["model"], str) and configuration[name]["model"]
                assert configuration["liveCallsEnabled"] is False
                assert token.encode() not in raw

                summary = {"recordID": "synthetic-record", "title": "Synthetic source", "text": "This is a fictional provider smoke document."}
                preparation = {"visit": {"id": "synthetic-visit", "type": "Primary care", "concern": "Review fictional source",
                                          "goal": "Organize discussion questions", "questions": []},
                               "records": [{"id": "synthetic-record", "title": "Synthetic source", "date": "2026-09-12",
                                            "text": "Fictional source for a disabled-provider test.", "summary": "Fictional source", "version": 1}]}
                future = datetime.now(timezone.utc) + timedelta(days=7)
                call = {"requestID": "synthetic-call", "clinic": "Fictional clinic", "phone": "+12025550100",
                        "reason": "Disabled-provider smoke only; no call is made", "patientName": "Synthetic Patient",
                        "earliest": future.isoformat(timespec="seconds").replace("+00:00", "Z"),
                        "latest": (future + timedelta(days=1)).isoformat(timespec="seconds").replace("+00:00", "Z"),
                        "timeZone": "UTC", "preferences": "No real call", "consent": True}
                audio = io.BytesIO()
                with wave.open(audio, "wb") as wav:
                    wav.setnchannels(1)
                    wav.setsampwidth(2)
                    wav.setframerate(8000)
                    wav.writeframes(b"\x00\x00" * 80)
                audio_headers = {"Content-Type": "audio/wav", "X-Filename": "Synthetic silence.wav"}
                posts = [("/v1/ai/summarize", summary, {}), ("/v1/ai/prepare", preparation, {}),
                         ("/v1/audio/transcribe", audio.getvalue(), audio_headers), ("/v1/booking/call", call, {})]

                for method, path, body, extra in [("GET", "/v1/providers", None, {}),
                                                   ("GET", "/v1/booking/call/synthetic-call", None, {})] + [
                                                       ("POST", path, body, extra) for path, body, extra in posts]:
                    status, _ = request(method, path, body, authorized=False, extra_headers=extra)
                    assert status == 401, f"Unauthenticated {method} {path}: expected 401, got {status}"

                for path, body, extra in posts:
                    status, raw = request("POST", path, body, extra_headers=extra)
                    assert status == 503, f"Unconfigured POST {path}: expected 503, got {status}: {raw!r}"
                    error = json.loads(raw)
                    assert error["error"] is True and isinstance(error["reason"], str) and error["reason"]
                    assert token.encode() not in raw
                assert not (data_directory / "voice-call-receipts").exists(), "Disabled call created a receipt unexpectedly"
                print("PASS: real HTTP provider status, all six route auth checks, and four unconfigured 503 responses; no provider credentials or outbound calls.")
            except BaseException:
                log.flush()
                log.seek(0)
                print("Local server diagnostic:\n" + log.read(), file=sys.stderr)
                raise
            finally:
                stop(server)


if __name__ == "__main__":
    def interrupted(_signal, _frame):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, interrupted)
    try:
        main()
    except KeyboardInterrupt:
        raise SystemExit(130)
