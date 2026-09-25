# Scripture Listener

Scripture Listener is an internal Android/iPhone Flutter app for a live sermon
operator. It streams foreground microphone audio to Deepgram Nova-3, searches
the selected bundled Bible translation on-device, and displays precision-first
explicit-reference or close-quotation matches.

## Architecture and privacy

Flutter owns microphone capture, the direct Deepgram WebSocket, deterministic
matching, bounded session coordination, and the responsive operator screen.
Build-time Dart tooling converts licensed FSB/XML sources into one read-only
SQLite asset. The matcher prefers no result over a weak result and displays one
featured passage plus at most three alternatives.

Sermon audio, transcripts, passage history, and session history are held in
bounded memory only and are not intentionally persisted or logged. Audio is
sent to Deepgram for transcription. The selected translation preference and
the bundled Bible database are the only relevant local persistence.

## Prerequisites

- Flutter 3.47.5 / Dart 3.13.4
- Android SDK; macOS and Xcode for iOS release builds
- Legally licensed Bible source files under `private/bibles/`
- Private NDJSON evaluation fixtures under `private/evaluation/`
- A restricted Deepgram key in the `DEEPGRAM_API_KEY` environment variable

Private inputs, `assets/bibles.db`, environment files, and credentials are
ignored by Git. A key supplied with `--dart-define` remains extractable from a
compiled mobile binary; internal distribution accepts that risk and rotation
requires a newly built and redistributed app.

## Local setup

Create `.env` at the repository root. It is ignored by Git:

```dotenv
DEEPGRAM_API_KEY='your-restricted-deepgram-key'
```

Load it into the current shell without printing the value:

```bash
set -a
. ./.env
set +a
test -n "$DEEPGRAM_API_KEY"
```

The app does not read `.env` at runtime. Every `flutter run` or `flutter build`
command must inject the loaded value with
`--dart-define=DEEPGRAM_API_KEY="$DEEPGRAM_API_KEY"`.

Install dependencies and generate the private Bible asset:

```bash
flutter pub get
dart run tool/build_bibles.dart private/bibles/NKJV.fsb private/bibles/KJV.xml --output assets/bibles.db
```

List connected targets and run locally:

```bash
flutter devices
flutter run -d <device-id> --dart-define=DEEPGRAM_API_KEY="$DEEPGRAM_API_KEY"
```

Android requires the Android SDK and a complete JDK with `javac`. iPhone runs
and builds require macOS, Xcode, and configured signing.

## Evaluate and build

After loading `.env` as above:

```bash
dart run tool/evaluate.dart --database assets/bibles.db --fixtures private/evaluation/sermons.ndjson
flutter test
flutter analyze
flutter build apk --release --dart-define=DEEPGRAM_API_KEY="$DEEPGRAM_API_KEY"
flutter build ios --release --dart-define=DEEPGRAM_API_KEY="$DEEPGRAM_API_KEY"
```

The evaluator reads one JSON object per line with `translation`, nullable
`expected`, and either one `transcript` matcher window or explicit ordered
`windows`:

```json
{"translation":"nkjv","transcript":"John chapter three verse sixteen","expected":"John 3:16"}
{"translation":"nkjv","windows":["first rolling window","next rolling window"],"expected":"John 3:16"}
```

A `transcript` is evaluated exactly once. Each `windows` entry is passed to the
matcher once, in order, and should contain the rolling text exactly as the live
session would present it. The evaluator prints aggregate metrics only and never
prints transcript or verse text.

Audio delivery awaits one `dart:io` WebSocket `addStream` call per frame. This
bounds the controller to one in-flight transport write plus its 64-frame queue;
completion means the local transport accepted the frame, not that Deepgram
acknowledged it over the network.

## Operations

- [Internal release workflow](docs/operations/internal-release.md)
- [Release acceptance checklist](docs/operations/acceptance-checklist.md)
- [Product design](docs/superpowers/specs/2026-09-24-mobile-scripture-listener-design.md)
