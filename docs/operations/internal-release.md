# Internal release workflow

This app is for controlled internal distribution. Run every command from the
repository root on the release commit. Private Bible sources, evaluation
fixtures, the generated database, and credentials must remain outside Git.

## Prerequisites

- Flutter 3.47.5 with Dart 3.13.4
- Android SDK and a configured Android release signing key
- For iOS: macOS, current Xcode, an Apple Developer team, and a registered
  bundle identifier/provisioning profile
- Bible source files the organization is legally entitled to copy and
  distribute in this app
- A restricted Deepgram API key supplied through the environment

Confirm the working tree and ignored private files before building:

```bash
set -a
. ./.env
set +a
git status --short --ignored
flutter --version
test -n "$DEEPGRAM_API_KEY"
```

Use a shell-compatible `.env` entry such as
`DEEPGRAM_API_KEY='your-restricted-key'`. The app does not load this file at
runtime; the release commands below inject the loaded value at compile time.

## Build and verify

Use these exact commands, replacing the example Bible filenames only when the
licensed source filenames differ:

```bash
dart run tool/build_bibles.dart private/bibles/NKJV.fsb private/bibles/KJV.xml --output assets/bibles.db
dart run tool/evaluate.dart --database assets/bibles.db --fixtures private/evaluation/sermons.ndjson
dart format --output=none --set-exit-if-changed tool lib test
flutter test
flutter analyze
flutter build apk --release --dart-define=DEEPGRAM_API_KEY="$DEEPGRAM_API_KEY"
flutter build ios --release --dart-define=DEEPGRAM_API_KEY="$DEEPGRAM_API_KEY"
```

The evaluator prints six aggregate values only. Store only those aggregate
values in the acceptance record; never copy transcript or verse text into
release notes, logs, tickets, or CI output.

The Android APK is written to `build/app/outputs/flutter-apk/app-release.apk`.
The unsigned/locally signed iOS application is under `build/ios/iphoneos/`;
distribution still requires the Xcode signing and archive steps below.

## iOS signing and internal distribution

1. On macOS, open `ios/Runner.xcworkspace` in Xcode (not the `.xcodeproj`).
2. Select the **Runner** target, then **Signing & Capabilities**.
3. Select the organization's Apple Developer team and the registered bundle
   identifier. Use **Automatically manage signing** unless the organization
   requires an explicitly supplied distribution certificate and provisioning
   profile.
4. Select **Any iOS Device (arm64)**, then choose **Product > Archive**.
5. In Organizer, choose **Distribute App**, then the approved internal method
   (TestFlight/Internal Testing, Ad Hoc, or Enterprise). Follow the signing
   prompts and retain the generated distribution logs with the release record.
6. Install the distributed artifact on a representative iPhone; a simulator
   build does not satisfy acceptance.

Do not export or commit signing certificates, private keys, provisioning
profiles, or the Deepgram key. Android signing credentials are likewise kept in
the organization's secret store and referenced by the local/CI Gradle signing
configuration.

## Credential and content risks

`--dart-define` prevents committing the Deepgram key, but it does **not** make
the key secret after compilation. A person with the APK or iOS application can
extract embedded strings or observe authenticated network use. This extraction
risk is accepted only for controlled internal distribution. Restrict the key by
project, quota, and provider permissions; monitor usage; do not reuse it for
other systems.

Key rotation requires a rebuild and redistribution:

1. Create a replacement restricted key and export it as `DEEPGRAM_API_KEY`.
2. Repeat the complete build, test, signing, and device acceptance workflow.
3. Distribute the replacement build.
4. Revoke the old key after required devices have moved to the new build.

The organization is responsible for legal ownership or a distribution license
for every bundled Bible translation. A technically valid source file is not
proof of permission. Confirm allowed territory, audience, attribution, and
distribution method with the rights holder before building. Record the legal
approval outside this repository. Never publish `assets/bibles.db` or private
source files as a source-control or CI artifact.

## Release decision

Complete [`acceptance-checklist.md`](acceptance-checklist.md) on the exact
signed artifacts. Do not release when any required item is unchecked, when the
agreed false-positive threshold is missed, or when legal/signing approval is
absent.
