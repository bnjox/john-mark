# John Mark Mobile App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an internal Android/iPhone Flutter app that streams foreground microphone audio to Deepgram and displays stable, precision-first scripture matches from a selected bundled translation.

**Architecture:** Flutter owns capture, the direct Deepgram WebSocket, deterministic on-device matching, session coordination, and UI. A Dart build tool converts supplied FSB/XML files into one read-only SQLite asset; sermon audio and text remain memory-only.

**Tech Stack:** Flutter 3.47.5, Dart 3.13.4, `record` 7.1.1, `sqflite` 2.4.4, `sqlite3` 3.6.0, `xml` 7.0.1, `path` 1.9.1, `path_provider` 2.1.6, `shared_preferences` 2.5.5, `wakelock_plus` 1.8.0, Deepgram Nova-3, Flutter Test.

**Spec:** `docs/superpowers/specs/2026-09-24-mobile-scripture-listener-design.md`

## Global Constraints

- Support Android and iPhone from one Flutter codebase; listening is foreground-only.
- Use Deepgram Nova-3 monolingual English through a direct WebSocket.
- Inject `DEEPGRAM_API_KEY` using `--dart-define`; never commit or log it. Extraction from the private binary is an accepted risk.
- Never persist or log sermon audio, transcript, passage history, or session history.
- Ignore private Bible inputs and generated licensed `assets/bibles.db` in Git.
- Search only the translation selected before listening.
- Match explicit references and close quotations only; no embeddings, LLM, or broad paraphrase inference.
- Prefer no result over a weak result; show one featured passage and at most three alternatives.
- Bound audio/text buffers. On connection loss, discard queued audio and resume from current speech without replay.
- Backgrounding stops and clears the session.
- Keep automated tests lean; validate device-only behavior manually.
- Use `ChangeNotifier`, `ListenableBuilder`, and manual constructor injection; do not add Provider, Riverpod, GetIt, Freezed, a router, or a separate use-case layer.
- Add an abstraction only at an actual external boundary: SQLite, microphone capture, and Deepgram. Do not wrap the Deepgram adapter in another repository.
- Base layout decisions on `LayoutBuilder` constraints, never device type or orientation checks.

## Review Focus

- Unknown FSB/XML structures fail with a source location rather than silently dropping verses (Task 2).
- Short wording shared by many verses does not force a result (Task 3).
- Concurrent Start/Stop/background events never duplicate or leak capture (Task 5).
- Repeated/out-of-order Deepgram messages never duplicate finalized text (Tasks 4–5).
- Network/auth failures discard queued audio and never replay stale speech (Task 5).

## File map

- `lib/core/`: immutable shared types.
- `lib/features/bible/`: bundled database lookup and quote candidate retrieval.
- `lib/features/matching/`: normalization, reference parsing, lexical scoring, stability.
- `lib/features/transcription/`: microphone and Deepgram adapters.
- `lib/features/session/`: bounded lifecycle and reconnect coordination.
- `lib/features/listener/`: one operator screen, scripture panel, and passage sheet; one-use UI pieces remain private widgets.
- `tool/bibles/`: FSB/XML conversion into SQLite.
- `tool/evaluate.dart`: private calibration runner.
- `docs/operations/`: internal release and acceptance instructions.

---

### Task 1: Application contracts and baseline

**Files:**
- Modify: `.gitignore`, `pubspec.yaml`, `lib/main.dart`
- Create: `assets/.gitkeep`, `lib/app.dart`, `lib/core/models.dart`
- Replace: `test/widget_test.dart`

**Interfaces:**
- Produces: `JohnMarkApp`, `SessionPhase`, `ConfidenceBand`, `Translation`, `ScriptureReference`, `Passage`, `MatchCandidate`, `MatchUpdate`, `TranscriptUpdate`, `ListenerViewState`.

- [ ] **Step 1: Initialize Git and preserve the baseline**

```bash
git init
git add .
git commit -m "chore: initialize Flutter application"
```

- [ ] **Step 2: Pin dependencies**

Set `pubspec.yaml` runtime dependencies to `path: 1.9.1`, `path_provider: 2.1.6`, `record: 7.1.1`, `shared_preferences: 2.5.5`, `sqflite: 2.4.4`, `wakelock_plus: 1.8.0`, and `xml: 7.0.1`; add `sqlite3: 3.6.0` under dev dependencies. Declare `assets/`, create `assets/.gitkeep`, then run `flutter pub get`.

- [ ] **Step 3: Protect private files**

Append:

```gitignore
/private/bibles/
/private/evaluation/
/assets/bibles.db
*.env
```

- [ ] **Step 4: Write the failing smoke test**

```dart
await tester.pumpWidget(const JohnMarkApp(home: Text('Ready')));
expect(find.text('John Mark'), findsOneWidget);
expect(find.text('Ready'), findsOneWidget);
```

Run: `flutter test test/widget_test.dart`  
Expected: FAIL because `JohnMarkApp` does not exist.

- [ ] **Step 5: Add exact shared contracts**

```dart
enum SessionPhase { ready, connecting, listening, silence, reconnecting, delayed, stopped, permissionDenied, serviceError }
enum ConfidenceBand { high, possible }
class Translation { const Translation({required this.id, required this.name}); final String id; final String name; }
class ScriptureReference { const ScriptureReference({required this.book, required this.chapter, required this.startVerse, required this.endVerse}); final int book, chapter, startVerse, endVerse; }
class Passage { const Passage({required this.reference, required this.label, required this.text}); final ScriptureReference reference; final String label, text; }
class MatchCandidate { const MatchCandidate({required this.passage, required this.score, required this.band, required this.explicitReference}); final Passage passage; final double score; final ConfidenceBand band; final bool explicitReference; }
class MatchUpdate { const MatchUpdate({this.featured, this.alternatives = const []}); final MatchCandidate? featured; final List<MatchCandidate> alternatives; }
class TranscriptUpdate { const TranscriptUpdate({this.finalized = '', this.interim = ''}); final String finalized, interim; }
class ListenerViewState { const ListenerViewState({this.phase = SessionPhase.ready, this.translation, this.transcript = const TranscriptUpdate(), this.matches = const MatchUpdate(), this.elapsed = Duration.zero, this.message, this.resultIsStale = false}); final SessionPhase phase; final Translation? translation; final TranscriptUpdate transcript; final MatchUpdate matches; final Duration elapsed; final String? message; final bool resultIsStale; }
```

- [ ] **Step 6: Replace the demo shell**

Create a dark Material 3 `JohnMarkApp` titled “John Mark” with a required `home`. Replace `main.dart` with `WidgetsFlutterBinding.ensureInitialized()` and a temporary centered Ready screen.

- [ ] **Step 7: Verify and commit**

```bash
dart format lib test
flutter analyze
flutter test test/widget_test.dart
git add .gitignore pubspec.yaml pubspec.lock assets/.gitkeep lib test/widget_test.dart
git commit -m "refactor: establish scripture listener contracts"
```

---

### Task 2: Bible conversion and repository

**Files:**
- Create: `tool/bibles/{model,fsb_parser,xml_parser,builder}.dart`, `tool/build_bibles.dart`
- Create: `lib/features/bible/{bible_repository,sqlite_bible_repository}.dart`
- Create: `test/fixtures/bibles/minimal.fsb`, `minimal-zefania.xml`, `test/bible_builder_test.dart`

**Interfaces:**
- Consumes: FreeShow FSB `name`, `books[].number/name`, `chapters[].number`, `verses[].number/endNumber/text`; Zefania `XMLBIBLE/BIBLEBOOK/CHAPTER/VERS`.
- Produces: `BibleBuilder.build(List<File>, String)` and repository methods `translations`, `passage`, `context`, `quoteCandidates`, `close`.

- [ ] **Step 1: Add synthetic fixtures and failing tests**

Use fictional wording for John 3:15–17 in both formats. Import `../tool/bibles/builder.dart` directly from the test, build both into a temporary DB, and assert two translations and more than six generated passages. Feed book 99 and assert `FormatException`.

Run: `flutter test test/bible_builder_test.dart`  
Expected: FAIL because `BibleBuilder` does not exist.

- [ ] **Step 2: Implement strict parsers**

Define `SourceBible`, `SourceBook`, `SourceChapter`, `SourceVerse`. Reject duplicate IDs, books outside 1–66, duplicate chapters/verse starts, non-positive numbers, empty text, reversed ranges, and unsupported extensions. Errors include file plus JSON path/XML element. Slug translation names to lowercase ASCII IDs and fail on collisions.

- [ ] **Step 3: Build deterministic SQLite output**

Create a temporary file, insert canonical-sorted rows in one transaction, `VACUUM`, set `user_version=1`, then atomically rename. Schema:

```sql
CREATE TABLE translations (id TEXT PRIMARY KEY, name TEXT NOT NULL);
CREATE TABLE books (translation_id TEXT NOT NULL, number INTEGER NOT NULL, name TEXT NOT NULL, PRIMARY KEY (translation_id, number));
CREATE TABLE passages (id INTEGER PRIMARY KEY, translation_id TEXT NOT NULL, book_number INTEGER NOT NULL, chapter INTEGER NOT NULL, start_verse INTEGER NOT NULL, end_verse INTEGER NOT NULL, label TEXT NOT NULL, display_text TEXT NOT NULL, normalized_text TEXT NOT NULL, UNIQUE (translation_id, book_number, chapter, start_verse, end_verse));
CREATE TABLE passage_tokens (passage_id INTEGER NOT NULL, token TEXT NOT NULL, position INTEGER NOT NULL);
CREATE INDEX passage_tokens_lookup ON passage_tokens(token, passage_id);
CREATE INDEX passage_reference_lookup ON passages(translation_id, book_number, chapter, start_verse, end_verse);
```

Generate individual verses and consecutive two-/three-verse ranges.

- [ ] **Step 4: Add the CLI**

```bash
dart run tool/build_bibles.dart private/bibles/NKJV.fsb private/bibles/KJV.xml --output assets/bibles.db
```

Print translation names, counts, output path—never verse text.

- [ ] **Step 5: Implement the repository**

```dart
abstract interface class BibleRepository {
  Future<List<Translation>> translations();
  Future<Passage?> passage(String translationId, ScriptureReference reference);
  Future<Passage?> context(String translationId, ScriptureReference reference, {int before = 1, int after = 1});
  Future<List<Passage>> quoteCandidates(String translationId, List<String> tokens, {int limit = 40});
  Future<void> close();
}
```

Copy the bundled DB atomically to the app database directory on cold start, open read-only, and rank candidate rows by distinct requested token hits with SQL limit 40.

- [ ] **Step 6: Test malformed variants**

Missing FSB verse text and unsupported XML root must fail with file/location, never partial output.

- [ ] **Step 7: Verify and commit**

```bash
dart format tool lib/features/bible test/bible_builder_test.dart
flutter analyze
flutter test test/bible_builder_test.dart
git add tool lib/features/bible test/fixtures test/bible_builder_test.dart
git commit -m "feat: build and query bundled Bible database"
```

---

### Task 3: Reference and quotation matching

**Files:**
- Create: `lib/features/matching/{normalizer,book_aliases,reference_parser,quote_matcher,match_stabilizer,scripture_matcher}.dart`
- Create: `test/matching_test.dart`

**Interfaces:**
- Consumes: `BibleRepository`, finalized rolling text, translation ID.
- Produces: `ReferenceParser.parse`, `QuoteMatcher.match`, `MatchStabilizer.update`, `ScriptureMatcher.match(String)`.

- [ ] **Step 1: Write failing focused tests**

Cover “John three sixteen”, “First Corinthians thirteen four through seven”, ordinary “John spoke for three minutes”, exact and imperfect quotes, unrelated speech, translation isolation, distinct alternatives, and ambiguous “love one another” producing no featured result.

Run: `flutter test test/matching_test.dart`  
Expected: FAIL because matcher classes do not exist.

- [ ] **Step 2: Implement normalization/reference parsing**

Normalize case, apostrophes, punctuation, whitespace, number words through 150, and ordinal prefixes. Define explicit aliases for all 66 books; never fuzzy-match book names. Accept compact/chapter/verse/range forms and validate each parsed reference through the repository.

- [ ] **Step 3: Implement bounded scoring**

Use at most 12 significant tokens and 40 candidates. Reject quote windows below four significant tokens. Score:

```dart
final score = orderedCoverage * 0.55 + tokenJaccard * 0.30 + queryCoverage * 0.15;
```

Use LCS/candidate length, unique-token Jaccard, and matched significant query coverage respectively.

- [ ] **Step 4: Implement stability**

```dart
class MatchConfig {
  const MatchConfig({this.strongThreshold = 0.78, this.possibleThreshold = 0.68, this.replacementMargin = 0.06, this.confirmationWindows = 2});
  final double strongThreshold, possibleThreshold, replacementMargin;
  final int confirmationWindows;
}
```

Validated references score 1.0/High. Strong quotes may display immediately; Possible quotes require two windows. Weak candidates cannot replace stronger ones. Return no more than three distinct alternatives and suppress unchanged updates.

- [ ] **Step 5: Verify and commit**

```bash
dart format lib/features/matching test/matching_test.dart
flutter analyze
flutter test test/matching_test.dart
git add lib/features/matching test/matching_test.dart
git commit -m "feat: match spoken references and close quotations"
```

---

### Task 4: Microphone and Deepgram adapters

**Files:**
- Create: `lib/features/transcription/{transcription,deepgram_messages,deepgram_client,microphone_source}.dart`
- Create: `test/deepgram_messages_test.dart`
- Modify: Android manifest, iOS Info.plist

**Interfaces:**
- Produces: `AudioSource`, `TranscriptionClient`, `TranscriptionConnection`, `TranscriptionEvent`.

- [ ] **Step 1: Define contracts**

```dart
enum TranscriptionEventType { interim, finalized, disconnected, error }
class TranscriptionEvent { const TranscriptionEvent({required this.type, this.text = '', this.confidence, this.errorCode, this.eventId}); final TranscriptionEventType type; final String text; final double? confidence; final String? errorCode, eventId; }
abstract interface class AudioSource { Future<bool> hasPermission(); Future<Stream<Uint8List>> start(); Future<void> stop(); }
abstract interface class TranscriptionConnection { Stream<TranscriptionEvent> get events; void send(Uint8List audio); Future<void> close(); }
abstract interface class TranscriptionClient { Future<TranscriptionConnection> open({required List<String> keyterms}); }
```

- [ ] **Step 2: Write failing decoder tests**

Test interim, final, blank, repeated final `(start,duration,text)`, interim after final, and Error. Run `flutter test test/deepgram_messages_test.dart`; expect missing decoder failure.

- [ ] **Step 3: Implement decoder and client**

Decode only Results/Error, first alternative, bounded 100 finalized IDs, no raw payload logs. Read `String.fromEnvironment('DEEPGRAM_API_KEY')`; fail clearly when empty. Connect with authorization header and parameters `nova-3`, `en-US`, `linear16`, 16000 Hz, mono, interim, smart format, endpointing 300. Add URL-encoded keyterms below 500 tokens. Never expose key.

- [ ] **Step 4: Implement capture**

Use `AudioRecorder` with PCM16, 16kHz, mono, noise suppression, no file path. Reject duplicate Start until Stop.

- [ ] **Step 5: Configure platforms**

Android: `RECORD_AUDIO`, `INTERNET`, label John Mark. iOS: microphone usage text “John Mark uses the microphone to identify Bible passages during a live sermon.” Set display name; no background audio mode.

- [ ] **Step 6: Verify and commit**

```bash
dart format lib/features/transcription test/deepgram_messages_test.dart
flutter analyze
flutter test test/deepgram_messages_test.dart
git add lib/features/transcription test/deepgram_messages_test.dart android/app/src/main/AndroidManifest.xml ios/Runner/Info.plist
git commit -m "feat: add live Deepgram transcription adapters"
```

---

### Task 5: Bounded session controller

**Files:**
- Create: `lib/features/session/{bounded_audio_queue,session_controller}.dart`
- Create: `test/session_controller_test.dart`, `test/privacy_test.dart`

**Interfaces:**
- Consumes: audio, transcription, matcher, selected translation, lifecycle.
- Produces: `SessionController extends ChangeNotifier`, `state`, `start(Translation)`, `stop()`, `onAppBackgrounded()`.

- [ ] **Step 1: Write failing lifecycle tests**

Counting fakes verify concurrent Start opens once; concurrent Stop/background closes once; disconnect stops capture and never sends post-loss frames after reconnect; auth failure does not retry; repeated event IDs append once; recent transcript stays under 1,500 characters.

Run: `flutter test test/session_controller_test.dart`  
Expected: FAIL because controller does not exist.

- [ ] **Step 2: Implement bounded delivery**

Queue capacity 64; drop oldest when full; async take; clear on disconnect/Stop; never log frames.

- [ ] **Step 3: Implement lifecycle**

Serialize Start/Stop. Permission → Deepgram open → capture. Display interim, match finals only. Bound transcript to 1,500 characters. Clear frames/text/matches/timers/subscriptions/IDs on Stop.

- [ ] **Step 4: Implement reconnect**

On retryable loss: stop capture, clear queue, mark stale, retry at 1/2/4/8/15 seconds (15 repeated). Restart current capture after connect and clear stale after first new final. Never retry auth, invalid request, or quota errors.

- [ ] **Step 5: Add privacy check**

Run a fake session in a fresh temporary working directory, emit audio/text/matches, Stop, and assert directory remains empty.

- [ ] **Step 6: Verify and commit**

```bash
dart format lib/features/session test/session_controller_test.dart test/privacy_test.dart
flutter analyze
flutter test test/session_controller_test.dart test/privacy_test.dart
git add lib/features/session test/session_controller_test.dart test/privacy_test.dart
git commit -m "feat: coordinate bounded live listening sessions"
```

---

### Task 6: Operator interface and production wiring

**Files:**
- Create: `lib/features/listener/{listener_screen,scripture_panel,passage_sheet}.dart`
- Modify: `lib/app.dart`, `lib/main.dart`, `test/widget_test.dart`

**Interfaces:**
- Consumes: controller, repository, translations, view state.
- Produces: ready/listening UI, local alternative promotion, context sheet, lifecycle forwarding.

- [ ] **Step 1: Write the primary widget flow**

With fakes: render translations, Start, assert Listening, emit featured/alternative, assert both, Stop, assert Ready. In the same test, set the surface first to 390×844 and then 800×900 at text scale 2.0; both layouts must complete without overflow exceptions.

Run: `flutter test test/widget_test.dart`  
Expected: FAIL because `ListenerScreen` does not exist.

- [ ] **Step 2: Implement Ready and Listening**

Keep Ready, the listening header, and transcript as private widgets in `listener_screen.dart`; split only the reusable scripture panel and passage sheet. Ready shows status, translation, microphone, Start, and privacy disclosure. Disable Start without Bible/key; persist selected translation ID only. Listening renders status/time, featured card, three alternatives maximum, transcript, Stop. Use High/Possible, stale label on reconnect, and “Listening for scripture…” when empty.

- [ ] **Step 3: Add interactions and accessibility**

Alternative promotion is presentation-only. Featured tap opens `context(before:1, after:1)` sheet. Add semantic regions, 48dp targets, wrapping, and no fixed text heights. Use `LayoutBuilder`: below 600px, show scripture then transcript in one scrollable column; at 600px and above, use a two-column layout constrained to 1,000px. Do not inspect orientation or platform model. Forward non-resumed lifecycle to background stop. Enable wakelock only while listening.

- [ ] **Step 4: Wire production**

Open repository, construct Deepgram/audio/matcher/controller, and render ListenerScreen. Missing DB shows an error naming the build command without exposing paths/text.

- [ ] **Step 5: Verify and commit**

```bash
dart format lib test/widget_test.dart
flutter analyze
flutter test test/widget_test.dart
git add lib test/widget_test.dart
git commit -m "feat: add mobile scripture listener interface"
```

---

### Task 7: Calibration and internal release

**Files:**
- Create: `tool/evaluate.dart`, `docs/operations/internal-release.md`, `docs/operations/acceptance-checklist.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: private NDJSON fixtures/devices/Bibles/key.
- Produces: aggregate metrics, release instructions, acceptance record.

- [ ] **Step 1: Add evaluation CLI**

Read rows such as:

```json
{"translation":"nkjv","transcript":"John chapter three verse sixteen","expected":"John 3:16"}
{"translation":"nkjv","transcript":"ordinary sermon speech","expected":null}
```

Print aggregate total/top-one/top-four/false-positive/no-result/median-time only.

```bash
dart run tool/evaluate.dart --database assets/bibles.db --fixtures private/evaluation/sermons.ndjson
```

- [ ] **Step 2: Document release commands**

```bash
dart run tool/build_bibles.dart private/bibles/NKJV.fsb private/bibles/KJV.xml --output assets/bibles.db
flutter test
flutter analyze
flutter build apk --release --dart-define=DEEPGRAM_API_KEY="$DEEPGRAM_API_KEY"
flutter build ios --release --dart-define=DEEPGRAM_API_KEY="$DEEPGRAM_API_KEY"
```

Document macOS iOS signing, key extraction risk, legal ownership, and key rotation by rebuild.

- [ ] **Step 3: Run lean automation**

Run `flutter test` and `flutter analyze`; expect conversion, matching, decoder, session/privacy, and one widget flow to pass.

- [ ] **Step 4: Record manual acceptance**

Check Android/iPhone permission and Start/Stop; foreground wakelock; background stop; reconnect without replay; terminal bad-key error; selected-translation isolation; explicit/close quote results; no forced unrelated result; large text; 90-minute memory/battery/latency; no persisted session data; normal three-second result target.

- [ ] **Step 5: Calibrate**

Evaluate around initial 0.78/0.68/0.06 thresholds. Select the strictest values meeting the agreed false-positive rate while preserving representative matches. Record aggregate metrics only.

- [ ] **Step 6: Replace README and commit**

Document purpose, architecture, privacy, prerequisites, commands, and doc links, then:

```bash
git status --short --ignored
flutter test
flutter analyze
git add tool/evaluate.dart README.md docs/operations
git commit -m "docs: add internal release and acceptance workflow"
```

Expected: private inputs, DB, and credentials remain ignored.
