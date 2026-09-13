# Mobile experience

The iPhone app remains native SwiftUI. It is not a web wrapper.

For hackathon judging, open `/mobile` on the web deployment (or `http://127.0.0.1:5173/mobile` during development). It runs the actual `/demo` app inside a phone-sized viewport, including navigation, profile editors, preparation, and recording controls. On a phone, the outer frame disappears. This preview follows future web changes automatically; it does not emulate SwiftUI, the iPhone camera, or iOS permissions.

The native app now includes:

- Sign up and login against `https://revamed.health`, with the same password requirements as the website. The session token is kept in the device Keychain.
- Separate local storage for each personal account and demo persona; personal accounts start with empty medical records.
- Automatic account sync with conflict recovery, retention of edits made during uploads, and source-file transfer. Hosted originals and audio use the same 3 MiB chunks and 16 MiB file limit as the website. Offline edits stay on the device and retry when connected.
- Overview, Records, and Profile tabs. The avatar contains settings and sign out; demo workspaces also offer account switching.
- A compact medical profile with section-specific editors, report citations, and automatic AI updates that preserve corrections.
- A visit preparation form with optional concerns and three questions, a concise AI brief, source links, and PDF sharing.
- Standalone appointment recording with required consent, pause/resume, saved recordings, transcription, and AI summaries. Existing document scanning, importing, symptom entry, and visit history remain available.

Native recordings pause when the app leaves the foreground. Connected transcription and AI require configured server services. Live provider calls and physical-device microphone behavior are not covered by the simulator checks.

## Build and verify

Regenerate the Xcode project after adding Swift source files:

```sh
python3 scripts/generate_project.py
swift test
python3 scripts/check_native_repairs.py
xcodebuild -project Reva.xcodeproj -scheme Reva \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Open `Reva.xcodeproj` to install a signed build on an iPhone. An already installed native app receives interface changes only after rebuilding and reinstalling or distributing a new build. `/mobile` is served with the web deployment; native changes do not require publishing a separate web app.

Verification for this update: core/auth/profile/merge tests, isolated native state and audio recovery checks, full iPhone simulator compilation, native menu/profile/preparation/consent inspection, web production build, and production route tests. Real account deletion, password changes, and paid AI calls were tested with fake transports only.
