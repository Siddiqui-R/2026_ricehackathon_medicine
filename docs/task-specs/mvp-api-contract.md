# Current provider API contract

Updated for appointment recording and removal of calling. Provider secrets remain on the server; every `/v1` route below requires an authenticated owner. Private static tokens and account sessions are supported. Provider configuration flags are not live credential probes.

## Discovery and Gemini

`GET /v1/providers` → `{gemini:{configured:Bool,model:String},transcription:{configured:Bool,model:String}}`.

`POST /v1/ai/summarize` accepts `{recordID:String,title:String,text:String}` and returns `{summary:String,model:String}`. JSON body limit 256 KiB; source text maximum 120,000 UTF-8 bytes; summary maximum 8,000 UTF-8 bytes. Records and full timestamped appointment transcripts use this endpoint. Appointment summaries preserve stated instructions, follow-ups, numbers, negation and uncertainty without inventing speaker roles or medical advice. Oversized input is rejected, never silently truncated.

`POST /v1/ai/prepare` accepts `{visit:{id,type,concern,goal,questions},records:[{id,title,date,text,summary,version}]}` and returns `{overview,questions,selectedRecordIDs,model}`. JSON body limit 1 MiB; 100 candidates, 500,000 combined source/summary bytes, 20 questions. Returned selected IDs must uniquely resolve to supplied candidates. Clients build source citations from originals.

## Appointment audio

`POST /v1/audio/transcribe` accepts raw saved audio (maximum 16 MiB) with `Content-Type` and `X-Filename`. It returns `{text,segments:[{id,speaker,start,end,text}],model}`. Whisper `whisper-1` supplies recording-relative times. Generic speaker labels do not claim diarization. Clients preserve audio and let the user review/correct transcript words.

Before recording, clients display **Get your doctor’s consent and permission from everyone present before recording.** Explicit confirmation gates capture and browser upload/save. Transcript and summary operations are explicit actions. New audio never receives unrelated demo text.

The clients persist optional `VisitRecording.aiSummary`, `aiSummaryModel`, and `aiSummaryGeneratedAt`. Existing `summary` remains personal notes. Transcript changes invalidate AI output, stale provider responses are rejected, and saved memory retains full transcript source and the original recording backlink.

## Configuration and errors

Active provider variables: `GEMINI_API_KEY`, `GEMINI_MODEL`, `OPENAI_API_KEY`, `OPENAI_TRANSCRIPTION_MODEL=whisper-1`. Server URL/token are configured in native Settings; web account requests use their session. Missing configuration or provider errors preserve local state and return explicit failures. All provider tests use intercepted synthetic transports unless a separate live check is authorized.

Calling routes and ElevenLabs configuration are removed. `POST /v1/booking/call` and `GET /v1/booking/call/:requestID` return 404. The historical `bookings` snapshot array remains inert so existing data can still decode and sync. No destructive migration removes it.
