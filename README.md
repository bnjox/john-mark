# John Mark

John Mark is an internal Android/iPhone Flutter app and live scripture companion
for a sermon operator. It streams foreground microphone audio to Deepgram
Nova-3, searches every bundled Bible translation on-device, and displays
explicit references, quotations, and paraphrases as scripture matches.

## Architecture and privacy

Flutter owns microphone capture, the direct Deepgram WebSocket, explicit
reference parsing, BGE-base ONNX inference, bounded session coordination, and
the responsive operator screen. Build-time tooling converts licensed FSB/XML
sources into one read-only SQLite asset and a validated int8 semantic index.
Explicit references resolve directly. Other speech is embedded on-device and
matched against the semantic index. The app displays one featured passage plus
at most three above-threshold alternatives.

Matching uses all bundled translations. Display text and surrounding context
use NKJV when bundled, otherwise a deterministic named fallback translation.
There is no operator translation selection or saved translation preference.
Missing, stale, or invalid semantic assets degrade safely to explicit-reference
matching rather than preventing listening.

Sermon audio, transcripts, passage history, and session history are held in
bounded memory only and are not intentionally persisted or logged. Audio is
sent to Deepgram for transcription. Semantic queries and vectors remain
on-device and are neither logged nor persisted. The bundled Bible database,
model, tokenizer, and semantic index are build assets, not session history.

## Prerequisites

- Flutter 3.47.5 / Dart 3.13.4
- `uv` with Python 3.12 or newer for semantic asset tooling
- Android SDK; macOS and Xcode for iOS 16+ release builds
- Legally licensed Bible source files under `private/bibles/`
- A restricted Deepgram key in the `DEEPGRAM_API_KEY` environment variable

Private inputs, `assets/bibles.db`, its generated manifest, environment files,
and credentials are ignored by Git. A key supplied with `--dart-define` remains
extractable from a compiled mobile binary; internal distribution accepts that
risk and rotation requires a newly built and redistributed app.

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

Install dependencies. The project owner must then verify the semantic tooling,
generate the private Bible database, fetch the pinned BGE-base-en-v1.5 model,
and generate its matching semantic index:

```bash
flutter pub get
uv run tool/test_semantic_tools.py
dart run tool/build_bibles.dart private/bibles/KJV.fsb private/bibles/NIV.fsb private/bibles/NKJV.fsb private/bibles/NLT.fsb --output assets/bibles.db
uv run tool/fetch_semantic_model.py
uv run tool/build_semantic_index.py --database assets/bibles.db --model private/models/bge-base-en-v1.5 --output assets/semantic/scripture_embeddings.bin
```

The fetch tool verifies the pinned revision, file sizes, and SHA-256 hashes
before atomically staging runtime assets. It also stages the upstream BGE model
card (`assets/semantic/README.md`) for attribution. BGE model-card licensing is
MIT; Bible and model attribution/distribution approval remains a release-owner
responsibility. Private model files and generated runtime semantic assets are
ignored by Git.

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
dart format --output=none --set-exit-if-changed tool lib test integration_test test_driver
flutter test
flutter analyze
flutter drive --profile --driver=test_driver/integration_test.dart --target=integration_test/semantic_performance_test.dart -d <android-device-id>
flutter build apk --release --dart-define=DEEPGRAM_API_KEY="$DEEPGRAM_API_KEY"
flutter build ios --release --dart-define=DEEPGRAM_API_KEY="$DEEPGRAM_API_KEY"
```

The corpus builder emits `assets/bibles.manifest.json` beside the compact
database. Keep both files together: the app uses the manifest to avoid copying
and validating an unchanged database on every launch. The profile integration
test measures exact BGE inference plus exhaustive index search on the selected
physical Android device. Also evaluate semantic quality, cold start, memory,
battery, and thermal behavior in owner-run profile sessions on representative
Android and iPhone devices because the ONNX runtime executes on-device.

Audio delivery awaits one `dart:io` WebSocket `addStream` call per frame. This
bounds the controller to one in-flight transport write plus its 64-frame queue;
completion means the local transport accepted the frame, not that Deepgram
acknowledged it over the network.

## Operations

- [Internal release workflow](docs/operations/internal-release.md)
- [Release acceptance checklist](docs/operations/acceptance-checklist.md)
- [Original product design](docs/superpowers/specs/2026-09-24-mobile-scripture-listener-design.md)
