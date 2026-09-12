# Two-hour MVP API implementation contract

Deadline14:28UTC September12. No live keys/calls; provider calls tested with mocks. Existing bearer middleware secures all /v1 routes. Provider hosts fixed, credentials server-only. POSTs are explicit user actions or enabled automatic document summarization after upload. Disable cleanly when unconfigured, return safe503 errors, never fall back silently.

## JSON wire shapes (client and server implement exactly)

GET /v1/providers => {gemini:{configured:Bool,model:String},transcription:{configured:Bool,model:String},booking:{configured:Bool,model:String},liveCallsEnabled:Bool}

POST /v1/ai/summarize {recordID:String,title:String,text:String} => {summary:String,model:String}

POST /v1/ai/prepare {visit:{id:String,type:String,concern:String,goal:String,questions:[String]},records:[{id:String,title:String,date:String,text:String,summary:String,version:Int}]} => {overview:String,questions:[String],selectedRecordIDs:[String],model:String}
Client preserves exact local source citations by generating quote sections from selected IDs; overview/questions are clearly labeled AI-generated/reviewable. Server validates selectedIDs against supplied candidates, size limits, JSON validity, nonempty summary. No model-generated page numbers or unvalidated quotes enter source references.

POST /v1/audio/transcribe with raw audio bytes, Content-Type audio/mp4|audio/m4a|audio/wav|audio/mpeg, X-Filename safe filename => {text:String,segments:[{id:String,start:Double,end:Double,speaker:String,text:String}],model:String}. Whisper1 verbose_json segment timestamps, speaker label 'Speaker' (no invented diarization).16MiB input max. Existing saved audio can be transcribed, sample cannot. Output offsets relative to audio. Failures preserve local state.

POST /v1/booking/call {requestID:String,clinic:String,phone:String,reason:String,earliest:String,latest:String,timeZone:String,preferences:String,patientName:String,consent:Bool} => {conversationID:String,status:String,provider:String}. Exact phone E164, explicit consent=true, environment REVA_ENABLE_LIVE_CALLS=true plus configured agent/number/key. ElevenLabs outbound Twilio endpoint using configured imported phone number. Do not autonomously confirm an appointment from a call's completion; user reviews conversation and enters/accepts actual time manually. Owner+requestID replay receipt must prevent duplicate outbound calls including uncertain/restarted attempts. Persist an intent before calling and fail closed on an uncertain receipt. No callbacks needed for MVP; polling.

GET /v1/booking/call/:requestID => {conversationID:String,status:String,provider:String,transcript:String}. Only owner can resolve own receipt; poll ElevenLabs conversation. Return bounded transcript/status, no false appointment booking.

## Ownership

Backend agent: server/Sources/RevaServer/Providers/Gemini*.swift, ProviderConfiguration.swift, ProviderRoutes.swift; register routes in HTTP.swift; make OwnerIdentity internal. Own server provider tests for Gemini/status, .env.example files + server provider README section. Coordinate VoiceServices from device_services agent via registerVoiceProviderRoutes(secured,configuration,...) minimal agreed interface.
Voice agent: server/Sources/RevaServer/Providers/Voice*.swift and voice tests only. Coordinate exact registration signature with backend; own reusable OpenAI Whisper and ElevenLabs adapters, durable call receipt. Do not edit HTTP.swift, Configuration.swift, app files or shared examples.
Primary: native Core/ProviderClient.swift and State/AppStore+Providers.swift, native feature integration/settings, shared Models optional fields if needed, Xcode regeneration, final integration/build/UI and docs.
Documentation agent: docs/team-workflow.md, future feature work list. No code edits.

Read provider official docs using web; do not guess model names. Keep Gemini model configurable with a documented currently-supported Flash default. Environment names: GEMINI_API_KEY, GEMINI_MODEL, OPENAI_API_KEY, OPENAI_TRANSCRIPTION_MODEL(defaultwhisper-1), ELEVENLABS_API_KEY, ELEVENLABS_AGENT_ID, ELEVENLABS_PHONE_NUMBER_ID, REVA_ENABLE_LIVE_CALLS. App server URL/token via Settings, no provider secrets on device.
