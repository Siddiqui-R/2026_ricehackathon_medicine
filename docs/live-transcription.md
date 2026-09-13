# Live recording captions

The browser recorder shows a muted live transcript beneath its recording controls, including in the `/mobile` web preview. This does not add streaming to the installed native SwiftUI recorder.

Start recording remains behind the doctor/everyone-present consent step. Audio from that same microphone stream is converted to mono PCM16 in an AudioWorklet and streamed to ElevenLabs Scribe v2 Realtime. Pausing, hiding the page, stopping, discarding, or leaving the workspace releases live capture; resume opens a fresh session. Navigating within the workspace preserves recording and captions.

The authenticated `POST /v1/audio/realtime-token` endpoint returns a temporary, single-use credential. Both the Vercel API and Swift server support it. Set `ELEVENLABS_API_KEY` on the server; the Swift server additionally requires private provider access. No new secret belongs in Vite or browser storage. Production CSP allows the fixed `wss://api.elevenlabs.io` destination. Unconfigured providers, dropped connections, or unsupported audio capture leave the original recording available and show a quiet unavailable message.

Live captions are an ephemeral preview. Saving still processes the original audio into the final timestamped transcript and summary, preserving existing review and speaker behavior. This uses **both** realtime and saved-audio transcription, with separate summary usage. Provider costs are listed on the [ElevenLabs API pricing page](https://elevenlabs.io/pricing/api).

Notes keep their allotted space. A light edge fade and small directional chevron appear only when content extends above or below the viewport; the editor retains native keyboard scrolling and a thin scrollbar.

Validation uses synthetic audio and mocked provider/token responses: PCM encoding, startup buffering, interim/final events, consented recorder lifecycle, pause/resume, late responses after discard, bounded network failures, authenticated routes, and notes overflow. Desktop and phone-sized browser layouts are inspected separately. A real provider stream and a physical microphone session still need a consented end-to-end check.

Provider contracts: [client-side streaming](https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/realtime/client-side-streaming), [WebSocket reference](https://elevenlabs.io/docs/api-reference/speech-to-text/v-1-speech-to-text-realtime), [single-use tokens](https://elevenlabs.io/docs/api-reference/tokens/create).
