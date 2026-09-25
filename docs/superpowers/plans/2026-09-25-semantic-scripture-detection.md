# Semantic Scripture Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Detect explicit references, quotations, and paraphrased scripture across every bundled translation while always displaying canonical NKJV text without a translation dropdown.

**Architecture:** Replace the translation-bound matcher with a canonical-reference detection engine that combines explicit, cross-translation lexical, and guarded semantic evidence before resolving display text from NKJV. A lazily initialized on-device BGE-base ONNX service supplies semantic candidates from a generated, fingerprinted int8 index and degrades to lexical-only matching when assets are absent or invalid.

**Tech Stack:** Flutter 3.47.5, Dart 3.13.4, SQLite/sqflite, `flutter_onnxruntime` 1.8.4, ONNX Runtime 1.23.0 on mobile, Python 3.12 via `uv`, sentence-transformers 6.0.1, NumPy 2.5.3

**Spec:** `docs/superpowers/specs/2026-09-25-semantic-scripture-detection-design.md`

## Global Constraints

- Android and iPhone remain supported; raise the iOS deployment target from 15.0 to 16.0 as explicitly approved.
- Search every bundled translation, but resolve featured passages, alternatives, and context from NKJV; use a deterministic named fallback only when NKJV is absent.
- Keep semantic inference on-device and never persist or log sermon audio, transcript text, detected verse text, semantic queries, or vectors.
- Preserve precision-first ordering: explicit reference, strong lexical evidence, guarded semantic evidence, then no result.
- Semantic-only promotion requires an absolute threshold, a runner-up margin, and support from two consecutive finalized windows.
- Model/index failure must leave explicit and cross-translation lexical matching operational.
- Preserve the user's uncommitted changes in `tool/bibles/builder.dart`, `tool/bibles/fsb_parser.dart`, `test/bible_builder_test.dart`, and `test/fixtures/bibles/minimal.fsb`; this plan does not edit those files.
- Use `uv` for Python execution. Do not document direct `python` or `pip` workflows.
- The coding agent must not run Bible generation, model download, semantic-index generation, APK/IPA builds, or release scripts. Present commands to the owner and wait for results where required.
- Before implementation, load `flutter-apply-architecture-best-practices` for Tasks 1–7, `flutter-add-widget-test` for Task 8, and `performance-optimization` for Task 9.
- Add only the focused tests below; do not create redundant broad coverage.

## Review Focus

- `NKJV`, `nkjv`, spelled-out New King James, duplicate-looking names, and no NKJV must select the documented display translation; Task 1 pins these cases.
- Identical references from several translations must merge, while tied non-overlapping results remain suppressed; Task 2 pins both behaviors.
- Truncated, stale, wrong-model, wrong-dimension, and wrong-database indexes must never crash startup or silently produce matches; Task 3 pins each path.
- Slow semantic inference must remain coalesced, must not outlive Stop, and must not update a later session; Tasks 6 and 7 pin these boundaries.
- Common thematic language with ambiguous similarity must return no result unless threshold, winner margin, and consecutive-window support all pass; Task 6 pins each gate.

---

## File Structure

**New runtime units**

- `lib/features/bible/display_translation_resolver.dart` — deterministic NKJV/fallback choice.
- `lib/features/matching/detection_evidence.dart` — canonical evidence independent of display text.
- `lib/features/matching/lexical_evidence_matcher.dart` — all-translation retrieval and grouping.
- `lib/features/matching/scripture_detection_engine.dart` — evidence orchestration and display resolution.
- `lib/features/semantic/semantic_retriever.dart` — semantic port, status, metadata, and hits.
- `lib/features/semantic/semantic_index.dart` — binary validation and bounded search.
- `lib/features/semantic/bge_tokenizer.dart` — WordPiece and ONNX inputs.
- `lib/features/semantic/onnx_text_embedder.dart` — ONNX lifecycle and normalized embeddings.
- `lib/features/semantic/semantic_search_service.dart` — lazy initialization and failure isolation.

**New tooling and fixtures**

- `tool/fetch_semantic_model.py`, `tool/build_semantic_index.py`, `tool/semantic_index_format.py`, `tool/semantic_model_manifest.json`, `tool/test_semantic_tools.py`.
- `test/fixtures/semantic/tiny_index.bin` — synthetic, with no licensed text/model data.
- `assets/semantic/.gitkeep` — keeps an otherwise private asset directory present.

**Key modifications**

- `.gitignore`, `pubspec.yaml`, `pubspec.lock`, iOS deployment target, Android ProGuard.
- Bible repository, matching, controller, startup, listener UI, evaluator, focused tests, and release docs.
- Delete `lib/features/matching/scripture_matcher.dart` after all callers move.

---

### Task 1: Canonical Evidence and Display Translation

**Files:**
- Create: `lib/features/bible/display_translation_resolver.dart`
- Create: `lib/features/matching/detection_evidence.dart`
- Modify: `lib/core/models.dart`
- Modify: `lib/features/bible/bible_repository.dart`
- Modify: `lib/features/bible/sqlite_bible_repository.dart`
- Test: `test/matching_test.dart`

**Interfaces:**
- Consumes: existing `Translation`, `ScriptureReference`, `Passage`, and repository database access.
- Produces: `resolveDisplayTranslation`, `DetectionEvidence`, `EvidenceKind`, `SourcedPassage`, `quoteCandidatesAcrossTranslations`, and `fingerprint`.

- [ ] **Step 1: Write failing resolver and sourced-result tests**

```dart
test('prefers NKJV id, then full name, then deterministic fallback', () {
  expect(resolveDisplayTranslation(const [
    Translation(id: 'kjv', name: 'King James Version'),
    Translation(id: 'NKJV', name: 'Abbreviated'),
  ]).id, 'NKJV');
  expect(resolveDisplayTranslation(const [
    Translation(id: 'primary', name: 'New King James Version'),
    Translation(id: 'other', name: 'Other'),
  ]).id, 'primary');
  expect(resolveDisplayTranslation(const [
    Translation(id: 'z', name: 'Zulu'),
    Translation(id: 'a', name: 'Alpha'),
  ]).id, 'a');
  expect(() => resolveDisplayTranslation(const []), throwsStateError);
});
```

Also assert that a repository hit retains its source translation ID.

- [ ] **Step 2: Run `flutter test test/matching_test.dart`**

Expected: FAIL because the resolver, evidence types, and repository methods do not exist.

- [ ] **Step 3: Add exact canonical types**

```dart
enum EvidenceKind { explicitReference, lexical, semantic }

class DetectionEvidence {
  const DetectionEvidence({
    required this.reference,
    required this.score,
    required this.kind,
    this.sourceTranslationId,
  });
  final ScriptureReference reference;
  final double score;
  final EvidenceKind kind;
  final String? sourceTranslationId;
}

class SourcedPassage {
  const SourcedPassage({required this.translationId, required this.passage});
  final String translationId;
  final Passage passage;
}
```

Add value equality/hashCode to `ScriptureReference`. Resolve NKJV by trimmed case-insensitive ID, then normalized full name, then ID/name sorting.

- [ ] **Step 4: Implement bounded all-translation repository APIs**

```dart
Future<List<SourcedPassage>> quoteCandidatesAcrossTranslations(
  List<String> tokens, {int limitPerTranslation = 40});
Future<String> fingerprint();
```

Use one parameterized SQLite query, the existing 64-token bound, a 1–40 per-translation bound, and deterministic translation/hit/passage ordering. Define the fingerprint as SHA-256 over schema version plus sorted, length-prefixed UTF-8 fields `(translationId, book, chapter, startVerse, endVerse, displayText)` for individual verses. Both Dart and Python must use the same byte contract; text contributes to the hash but is never logged or returned.

- [ ] **Step 5: Run `flutter test test/matching_test.dart test/widget_test.dart`**

Expected: PASS after repository fakes adopt the APIs.

- [ ] **Step 6: Commit**

```bash
git add lib/core/models.dart lib/features/bible lib/features/matching/detection_evidence.dart test/matching_test.dart test/widget_test.dart
git commit -m "refactor: add canonical scripture evidence"
```

---

### Task 2: Cross-Translation Lexical Detection

**Files:**
- Create: `lib/features/matching/lexical_evidence_matcher.dart`
- Modify: `lib/features/matching/reference_parser.dart`
- Modify: `lib/features/matching/quote_matcher.dart`
- Modify: `lib/features/matching/match_stabilizer.dart`
- Test: `test/matching_test.dart`

**Interfaces:**
- Consumes: `DetectionEvidence`, `SourcedPassage`, and all-translation repository lookup.
- Produces: `LexicalEvidenceMatcher.match(String)` and `ReferenceParser.parseAny(String, List<Translation>)`.

- [ ] **Step 1: Replace selected-translation tests with cross-translation tests**

```dart
final matches = await LexicalEvidenceMatcher(repository).match(
  'completely different wording in the second translation',
);
expect(matches.single.reference, john316.reference);
expect(matches.single.sourceTranslationId, 'beta');
```

Add cases proving duplicate John 3:16 hits merge and materially tied Romans/John leaders are suppressed.

- [ ] **Step 2: Run `flutter test test/matching_test.dart`**

Expected: FAIL because the new matcher and parser method do not exist.

- [ ] **Step 3: Extract translation-neutral lexical scoring**

Reuse significant tokens, LCS, Jaccard, and coverage. Score at most 40 hits per translation, group by `ScriptureReference`, retain strongest source, sort deterministically, and suppress materially tied non-overlapping leaders using `MatchConfig.replacementMargin`.

- [ ] **Step 4: Parse references once and validate across translations**

Validate display translation first, then remaining translations. Return `DetectionEvidence(kind: EvidenceKind.explicitReference, score: 1)` and retain strict book aliases.

- [ ] **Step 5: Run `flutter test test/matching_test.dart`**

Expected: PASS for cross-translation wording, grouping, ambiguity, explicit priority, and reset.

- [ ] **Step 6: Commit**

```bash
git add lib/features/matching test/matching_test.dart
git commit -m "feat: match quotations across translations"
```

---

### Task 3: Versioned Semantic Index Reader

**Files:**
- Create: `lib/features/semantic/semantic_retriever.dart`
- Create: `lib/features/semantic/semantic_index.dart`
- Create: `test/semantic_index_test.dart`
- Create: `test/fixtures/semantic/tiny_index.bin`

**Interfaces:**
- Produces: `SemanticHit`, `SemanticAssetMetadata`, `SemanticRetriever`, `SemanticStatus`, `SemanticIndex.parse`, and `SemanticIndex.search`.

- [ ] **Step 1: Write failing index tests**

Cover valid synthetic input, bad magic, unsupported version, truncation, wrong model, wrong dimension, wrong fingerprint, zero-norm query, deterministic ties, and top-eight bounding.

```dart
final index = SemanticIndex.parse(
  bytes,
  expectedModelId: 'BAAI/bge-base-en-v1.5',
  expectedDimensions: 768,
  expectedBibleFingerprint: 'fixture-db',
);
expect(index.search(query, limit: 8), hasLength(lessThanOrEqualTo(8)));
```

- [ ] **Step 2: Run `flutter test test/semantic_index_test.dart`**

Expected: FAIL because semantic index types do not exist.

- [ ] **Step 3: Implement this little-endian format**

```text
8 bytes  magic: SCRIPIDX
u16      format version: 1
u16      dimensions: 768
u32      metadata JSON byte length
u32      row count
bytes    UTF-8 metadata JSON
rows     u8 translationOrdinal, u8 book, u16 chapter, u16 verse,
         f32 scale, int8[dimensions]
```

Metadata keys: `modelId`, `modelRevision`, `bibleFingerprint`, `translations`, `quantization`, `createdByVersion`. Reject invalid ordinals and duplicate translation/reference rows.

- [ ] **Step 4: Implement bounded search off the UI isolate**

Require a normalized 768-element query. Score rows as `dot(query, quantized) * scale`, retain only top N, tie-break by canonical reference/translation, and use `Isolate.run` with transferable bytes.

- [ ] **Step 5: Run `flutter test test/semantic_index_test.dart`**

Expected: PASS for all malformed-input and search cases.

- [ ] **Step 6: Commit**

```bash
git add lib/features/semantic test/semantic_index_test.dart test/fixtures/semantic/tiny_index.bin
git commit -m "feat: add validated semantic index"
```

---

### Task 4: Reproducible Model and Index Tooling

**Files:**
- Create: `tool/fetch_semantic_model.py`
- Create: `tool/build_semantic_index.py`
- Create: `tool/semantic_index_format.py`
- Create: `tool/semantic_model_manifest.json`
- Create: `tool/test_semantic_tools.py`
- Create: `assets/semantic/.gitkeep`
- Modify: `.gitignore`
- Modify: `docs/superpowers/specs/2026-09-25-semantic-scripture-detection-design.md`

**Interfaces:**
- Consumes: SQLite schema version 1 and Task 3's binary format.
- Produces: verified private model files, runtime asset copies, and `assets/semantic/scripture_embeddings.bin`.

- [ ] **Step 1: Ignore assets before download**

```gitignore
/private/models/
/assets/semantic/*
!/assets/semantic/.gitkeep
```

Run only `git check-ignore private/models/example assets/semantic/model.onnx`; both must be ignored.

- [ ] **Step 2: Write pure temporary-file Python tests**

Use `unittest`, a tiny SQLite DB, and a fake embedder. Pin deterministic ordering, single-verse selection, normalized int8 quantization, metadata, atomic replacement, wrong-schema rejection, and an exact mocked Hugging Face repository/revision/allow-list.

- [ ] **Step 3: Implement the fetch tool**

Use PEP 723 metadata with Python `>=3.12` and `huggingface-hub==1.32.0`. Pin model revision `a5beb1e3e68b9ab74eb54cfd186867f64f240e1a`; fetch `onnx/model.onnx`, `config.json`, `tokenizer.json`, `tokenizer_config.json`, `special_tokens_map.json`, `vocab.txt`, and `README.md`; verify sizes and SHA-256 values from `tool/semantic_model_manifest.json` before atomic runtime copies. Record BGE's MIT model-card license and bundle its README attribution because that pinned repository has no standalone license file.

- [ ] **Step 4: Implement deterministic generation**

Use PEP 723 metadata with `sentence-transformers==6.0.1` and `numpy==2.5.3`. Read only `start_verse = end_verse`, order translation/book/chapter/verse, normalize embeddings, per-row int8 quantize, write Task 3's format atomically, and print only aggregate counts/timing/size.

- [ ] **Step 5: Ask the owner to run; do not execute**

```bash
uv run tool/test_semantic_tools.py
uv run tool/fetch_semantic_model.py
uv run tool/build_semantic_index.py \
  --database assets/bibles.db \
  --model private/models/bge-base-en-v1.5 \
  --output assets/semantic/scripture_embeddings.bin
git status --short --ignored
```

Expected: tests pass; private/generated files are ignored; output contains no verse text. Wait for reported results before Task 5 integration.

- [ ] **Step 6: Commit without generated assets**

```bash
git add .gitignore assets/semantic/.gitkeep tool/fetch_semantic_model.py tool/build_semantic_index.py tool/semantic_index_format.py tool/semantic_model_manifest.json tool/test_semantic_tools.py docs/superpowers/specs/2026-09-25-semantic-scripture-detection-design.md
git commit -m "feat: add semantic asset tooling"
```

---

### Task 5: BGE Tokenizer and ONNX Runtime Adapter

**Files:**
- Create: `lib/features/semantic/bge_tokenizer.dart`
- Create: `lib/features/semantic/onnx_text_embedder.dart`
- Create: `test/bge_tokenizer_test.dart`
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Modify: `ios/Runner.xcodeproj/project.pbxproj`
- Create: `android/app/proguard-rules.pro`
- Modify: `android/app/build.gradle.kts`

**Interfaces:**
- Produces: `BgeTokenizer.encode(String, {int maxLength = 512})` and `OnnxTextEmbedder.embed(String)`.

- [ ] **Step 1: Write failing tokenizer tests**

Cover lowercase, punctuation, WordPiece continuation, unknown tokens, `[CLS]`/`[SEP]`, safe truncation, zero padding, attention mask, and token-type IDs.

```dart
final inputs = tokenizer.encode('Loved worlds!');
expect(inputs.inputIds.take(6), [2, 5, 6, 7, 8, 3]);
expect(inputs.attentionMask.take(6), everyElement(1));
expect(inputs.tokenTypeIds, everyElement(0));
```

- [ ] **Step 2: Run `flutter test test/bge_tokenizer_test.dart`**

Expected: FAIL because `BgeTokenizer` does not exist.

- [ ] **Step 3: Implement BERT-compatible WordPiece**

Use greedy longest match with `##`, Unicode whitespace/punctuation splitting, BGE uncased normalization, a 512-token cap preserving `[SEP]`, and fixed `Int64List` tensors shaped `[1, 512]`. Do not retain source text.

- [ ] **Step 4: Add runtime dependency and platform settings**

Add `flutter_onnxruntime: 1.8.4`, declare `assets/semantic/`, set every iOS deployment target to `16.0`, add `-keep class ai.onnxruntime.** { *; }`, and wire ProGuard into release. Run `flutter pub get` to produce `pubspec.lock`; do not run mobile builds.

- [ ] **Step 5: Implement normalized inference**

Create a session from `assets/semantic/model.onnx`; supply `input_ids`, `attention_mask`, `token_type_ids`; mean-pool last hidden state with the mask; L2-normalize 768 floats; release tensors/session in `finally`; serialize access to one session.

- [ ] **Step 6: Run `flutter test test/bge_tokenizer_test.dart test/semantic_index_test.dart`**

Expected: PASS without loading private assets.

- [ ] **Step 7: Commit**

```bash
git add pubspec.yaml pubspec.lock ios/Runner.xcodeproj/project.pbxproj android/app lib/features/semantic/bge_tokenizer.dart lib/features/semantic/onnx_text_embedder.dart test/bge_tokenizer_test.dart
git commit -m "feat: add on-device BGE inference"
```

---

### Task 6: Guarded Semantic Service and Detection Engine

**Files:**
- Create: `lib/features/semantic/semantic_search_service.dart`
- Create: `lib/features/matching/scripture_detection_engine.dart`
- Modify: `lib/features/matching/match_stabilizer.dart`
- Delete: `lib/features/matching/scripture_matcher.dart`
- Modify: `test/matching_test.dart`
- Create: `test/semantic_search_service_test.dart`

**Interfaces:**
- Consumes: Tasks 1–5.
- Produces: `ScriptureDetectionEngine.match/current/reset` and `SemanticSearchService.initialize/search/status/dispose`.

- [ ] **Step 1: Write failing semantic guard tests**

Prove score `< 0.82` rejects, winner margin `< 0.06` rejects, first clear window waits, second consecutive canonical winner promotes, an intervening reference resets support, and explicit/high lexical evidence skips semantics.

- [ ] **Step 2: Write failing service lifecycle tests**

Prove `initializing -> ready`, bad assets produce `unavailable` without throwing, pre-ready search returns empty, one search runs at once, pending text is replaced by newest text, and disposal suppresses late completion.

- [ ] **Step 3: Run `flutter test test/matching_test.dart test/semantic_search_service_test.dart`**

Expected: FAIL because service and engine do not exist.

- [ ] **Step 4: Implement the failure-isolated service**

```dart
enum SemanticStatus { initializing, ready, unavailable }

abstract interface class SemanticRetriever {
  SemanticStatus get status;
  Future<List<SemanticHit>> search(String text, {int limit = 8});
}
```

Initialize model/tokenizer/index/fingerprint lazily. Catch asset/format/runtime errors, retain only a non-sensitive diagnostic category, notify `unavailable`, and return empty results. Coalesce one in-flight plus latest pending query.

- [ ] **Step 5: Implement canonical detection orchestration**

Use explicit, strong lexical, then semantic fallback. Resolve accepted references to NKJV `MatchCandidate`s. Centralize `semanticThreshold = 0.82`, `semanticWinnerMargin = 0.06`, and `semanticConfirmationWindows = 2` in `MatchConfig`. Preserve replacement margin, three distinct alternatives, and no result on material ties.

- [ ] **Step 6: Run the focused tests**

Expected: PASS for priority, all semantic gates, failure isolation, coalescing, and disposal.

- [ ] **Step 7: Commit**

```bash
git add lib/features/matching lib/features/semantic test/matching_test.dart test/semantic_search_service_test.dart
git commit -m "feat: add guarded semantic scripture detection"
```

---

### Task 7: Translation-Neutral Session Wiring

**Files:**
- Modify: `lib/core/models.dart`
- Modify: `lib/features/session/session_controller.dart`
- Modify: `lib/main.dart`
- Modify: `test/session_controller_test.dart`
- Modify: `test/privacy_test.dart`

**Interfaces:**
- Produces: parameterless `SessionController.start()` and `TranscriptMatcher = Future<MatchUpdate?> Function(String)`.

- [ ] **Step 1: Migrate tests and add stale-semantic coverage**

Replace `start(_translation)` with `start()`, one-argument matcher fakes, and remove translation-state assertions. Add a delayed match proving Stop then Start cannot apply the previous session completion.

- [ ] **Step 2: Run `flutter test test/session_controller_test.dart test/privacy_test.dart`**

Expected: compile failure against the old API.

- [ ] **Step 3: Remove translation from controller state/APIs**

```dart
typedef TranscriptMatcher = Future<MatchUpdate?> Function(String finalizedText);
Future<void> start();
```

Keep generation guards, reset at session boundaries, and immediate idempotent Stop.

- [ ] **Step 4: Wire one app-lifetime engine**

Resolve display translation once, construct semantic service initially unavailable-to-search, construct the detection engine, call semantic initialization with `unawaited` after UI wiring, pass display translation/status to the listener, and own repository/model disposal for app lifetime.

- [ ] **Step 5: Run the controller/privacy tests**

Expected: PASS for slow match Stop, restart isolation, bounds, and absence of persisted translation choice.

- [ ] **Step 6: Commit**

```bash
git add lib/core/models.dart lib/features/session/session_controller.dart lib/main.dart test/session_controller_test.dart test/privacy_test.dart
git commit -m "refactor: make listening translation neutral"
```

---

### Task 8: Remove Translation UI

**Files:**
- Modify: `lib/features/listener/listener_screen.dart`
- Modify: `lib/features/listener/passage_sheet.dart`
- Modify: `test/widget_test.dart`

**Interfaces:**
- Consumes: fixed display translation, parameterless Start, and `ValueListenable<SemanticStatus>`.

- [ ] **Step 1: Load `flutter-add-widget-test` and write failing expectations**

Assert no dropdown/selection text, ready copy “Matches all bundled translations · Displays NKJV”, parameterless Start, named non-NKJV fallback, and unavailable copy “Paraphrase matching unavailable · quotation matching remains active” without disabling Start.

- [ ] **Step 2: Run `flutter test test/widget_test.dart`**

Expected: FAIL because translation controls still exist.

- [ ] **Step 3: Simplify `ListenerScreen`**

Delete shared-preferences import, loader/saver typedefs, selected state, restore/select methods, dropdown, and preference key. Require `displayTranslation` and semantic status. Use display ID for context and parameterless Start.

- [ ] **Step 4: Keep copy accessible and restrained**

Use one supporting `Semantics` block; show semantic unavailability neutrally, not as a fatal error. Preserve privacy copy, scripture-first hierarchy, large text, and stale-result behavior.

- [ ] **Step 5: Run `flutter test test/widget_test.dart`**

Expected: PASS at 390×844 and 800×900 with 2× text, no overflow, and working context.

- [ ] **Step 6: Commit**

```bash
git add lib/features/listener test/widget_test.dart
git commit -m "feat: remove translation selection"
```

---

### Task 9: Evaluator and Performance Gates

**Files:**
- Modify: `tool/evaluate.dart`
- Modify: `test/evaluate_test.dart`
- Create: `test/semantic_performance_test.dart`

**Interfaces:**
- Produces: translation-neutral aggregate evaluation and structural performance checks.

- [ ] **Step 1: Write failing translation-neutral evaluator tests**

Remove required `translation` fixture keys. Cover transcript, windows, nullable expected, malformed rows, lexical-only mode, and canonical top-one/top-four.

- [ ] **Step 2: Run `flutter test test/evaluate_test.dart`**

Expected: FAIL because translation is still required.

- [ ] **Step 3: Migrate evaluator**

Resolve display translation and construct one engine per fixture. Accept optional `--semantic-index` and `--model`. Print aggregate metrics and semantic mode only; never individual text, labels, or vectors.

- [ ] **Step 4: Add a synthetic structural performance test**

Build 2,000 deterministic 768-dimension rows in memory, run five searches, and assert eight results maximum, one active search, no queued backlog after disposal, and no retained transcript. Do not assert CI wall-clock timing.

- [ ] **Step 5: Run `flutter test test/evaluate_test.dart test/semantic_performance_test.dart`**

Expected: PASS without private assets.

- [ ] **Step 6: Ask the owner to run; do not execute**

```bash
dart run tool/evaluate.dart \
  --database assets/bibles.db \
  --fixtures private/evaluation/sermons.ndjson \
  --model assets/semantic/model.onnx \
  --semantic-index assets/semantic/scripture_embeddings.bin

flutter run -d <android-device-id> --profile \
  --dart-define=DEEPGRAM_API_KEY="$DEEPGRAM_API_KEY"

flutter run -d <iphone-device-id> --profile \
  --dart-define=DEEPGRAM_API_KEY="$DEEPGRAM_API_KEY"
```

Request aggregate metrics, cold initialization, semantic p50/p95, peak memory, and a 20-minute thermal/battery observation per device. Keep FP32 unless an optimized artifact preserves false-positive/top-one quality and improves device behavior.

- [ ] **Step 7: Commit**

```bash
git add tool/evaluate.dart test/evaluate_test.dart test/semantic_performance_test.dart
git commit -m "feat: evaluate semantic scripture detection"
```

---

### Task 10: Documentation and Final Verification

**Files:**
- Modify: `README.md`
- Modify: `PRODUCT.md`
- Modify: `DESIGN.md`
- Modify: `docs/operations/internal-release.md`
- Modify: `docs/operations/acceptance-checklist.md`

**Interfaces:**
- Produces: accurate setup, operator, evaluation, and release guidance.

- [ ] **Step 1: Update product/design language**

Replace selected-translation and paraphrase-exclusion claims with all-translation lexical plus guarded on-device semantics. Remove selector design requirements and document NKJV/fallback display.

- [ ] **Step 2: Update setup/release commands**

Document `uv`, owner-run model fetch, Bible generation, index generation, aggregate evaluation, ignored-file inspection, iOS 16, attribution, and generated asset exclusions.

- [ ] **Step 3: Replace obsolete acceptance checks**

Check all translations contribute evidence, NKJV display/fallback naming, safe semantic degradation, agreed false-positive ceiling, prompt Stop during inference, three-second useful result, and 90-minute memory/thermal behavior.

- [ ] **Step 4: Run non-generation verification only**

```bash
dart format --output=none --set-exit-if-changed lib test tool
flutter test
flutter analyze
git diff --check
git status --short --ignored
```

Expected: all checks pass; private/generated assets remain ignored. Do not run Bible/model/index generation, `flutter build`, or release scripts.

- [ ] **Step 5: Inspect privacy and lifecycle**

Search for transcript/vector logging, `selected_translation_id`, `SharedPreferences`, old `ScriptureMatcher`, and translation-argument `start(...)`. Confirm semantic completion is generation-guarded and private assets are unstaged.

- [ ] **Step 6: Request owner-run release verification**

Provide the exact final block from `docs/operations/internal-release.md`; ask the owner to run generation, private evaluation, both device checks, and release builds. Record aggregate/non-sensitive output only.

- [ ] **Step 7: Commit**

```bash
git add README.md PRODUCT.md DESIGN.md docs/operations .gitignore assets/semantic/.gitkeep pubspec.yaml pubspec.lock android ios lib test tool
git commit -m "docs: update semantic detection release workflow"
```
