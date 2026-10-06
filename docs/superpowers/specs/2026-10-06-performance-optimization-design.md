# John Mark Performance Optimization Design

**Date:** 2026-10-06

## Objective

Make John Mark start, read bundled scripture, and return scripture matches fast
enough for live operation on the connected TECNO CK6 running Android 14.
Optimize both cold launch and finalized-transcript-to-scripture latency without
replacing BGE-base, weakening match thresholds, persisting sermon data, or
logging private content.

Internal schema and implementation compatibility may break where a clean
replacement removes a measured bottleneck. Do not add compatibility wrappers,
temporary bypasses, or benchmark-only production behavior.

## Measured Baseline

The current generated assets and profile build have these properties:

- `assets/bibles.db` is 860,676,096 bytes.
- About 605 MB of the database belongs to obsolete `passage_tokens` storage and
  its index, even though the current builder no longer creates or queries them.
- The database contains 358,737 precomposed one-, two-, and three-verse
  passages for 124,369 unique verses.
- Every process launch loads, writes, flushes, and renames the full database
  before `runApp`.
- The profile APK is about 765 MB.
- A measured TECNO launch remained on the Android splash screen for 12.524
  seconds before the first Flutter window was drawn.
- Semantic startup re-hashes every verse, parses a 97 MB index on the UI
  isolate, and delays worker creation and a second full index transformation
  until the first query.
- A desktop profile of the exact index implementation took about 1.0 seconds
  per warm vector scan and reached about 529 MB RSS before BGE inference.
- Short BGE inputs are padded to 512 tokens, so ordinary sermon queries pay the
  model cost of the maximum sequence length.
- Controller notifications can rebuild the listening screen twice: once from
  the screen listener's `setState` and once from `ListenableBuilder`.
- No production timeline spans currently attribute startup or search latency.

These measurements are baseline evidence, not final acceptance statistics.
Final p50 and p95 values require repeated profile-mode runs on the TECNO.

## Selected Approach

Use a storage-first, exact-semantics redesign:

1. Render a lightweight Flutter shell before runtime initialization.
2. Replace the generated database with a compact, versioned single-verse
   corpus and install it only when its manifest changes.
3. Replace runtime corpus hashing with a build-time content fingerprint.
4. Load, validate, parse, and retain the semantic index in one long-lived
   worker isolate before the first semantic query.
5. Reduce exact BGE and index work without changing the model or thresholds.
6. Narrow frequently changing UI rebuilds and remove redundant reads.
7. Add privacy-safe instrumentation and enforce device acceptance budgets.

Approximate-nearest-neighbor search, model quantization, and a forked native
ONNX wrapper are excluded from this pass. They add quality or maintenance risk
before exact optimizations have been measured.

## Runtime Architecture

```text
Native launch
    |
    v
Lightweight Flutter bootstrap shell (first frame)
    |
    +--> read tiny corpus manifest
    |
    +--> open matching installed database
    |        or atomically install and validate changed asset
    |
    `--> start persistent semantic worker isolate
             |
             `--> load, validate, parse, and retain semantic index

Database ready --------------------------> usable ready screen
Semantic worker + BGE ready ------------> semantic matching ready

Final transcript
    |
    +--> explicit reference parser --> indexed SQLite range read
    |
    `--> BGE-base inference --> exact worker top-K scan
                                      |
                                      v
                              parallel passage hydration
                                      |
                                      v
                               focused UI publication
```

`runApp` must not await the database, model, tokenizer, corpus hash, or semantic
index. The bootstrap shell owns loading, retry, and fatal corpus-unavailable
states. Explicit references become available when SQLite is ready. Semantic
matching initializes independently and retains the existing safe degradation
behavior when semantic assets are unavailable.

If finalized text arrives before semantic initialization completes, retain the
latest eligible request and evaluate it when the service becomes ready, subject
to the current session generation. Never publish a result from a stopped or
restarted session.

## Compact Corpus Format

The new read-only SQLite schema is:

```sql
CREATE TABLE metadata (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
) WITHOUT ROWID;

CREATE TABLE translations (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL
) WITHOUT ROWID;

CREATE TABLE books (
  translation_id TEXT NOT NULL,
  number INTEGER NOT NULL,
  name TEXT NOT NULL,
  PRIMARY KEY (translation_id, number)
) WITHOUT ROWID;

CREATE TABLE verses (
  translation_id TEXT NOT NULL,
  book_number INTEGER NOT NULL,
  chapter INTEGER NOT NULL,
  verse INTEGER NOT NULL,
  display_text TEXT NOT NULL,
  PRIMARY KEY (translation_id, book_number, chapter, verse)
) WITHOUT ROWID;
```

The corpus stores each verse once. Passage ranges use one primary-key-backed
`BETWEEN` query and compose labels and display text at runtime. No normalized
text, token table, token index, duplicate range text, duplicate labels, or
redundant reference index remains.

The builder emits a small manifest containing:

- manifest format version;
- database schema version;
- immutable asset ID;
- database byte length;
- translation IDs;
- corpus fingerprint contract version;
- corpus fingerprint.

The fingerprint is SHA-256 over deterministic, length-prefixed individual verse
fields. Its contract version is independent of SQLite `user_version`. When the
individual verse corpus is unchanged, the compact database must validate
against the existing semantic index without re-embedding it.

## Database Installation and Recovery

On startup, read the small manifest before touching the database asset.

- If the installed marker and database metadata match the manifest, open the
  installed database directly.
- Otherwise copy the bundled database to a temporary file, validate its byte
  length, metadata, integrity, translation set, and fingerprint, then atomically
  rename it and atomically publish the marker.
- Remove abandoned temporary files before retrying installation.
- If opening a supposedly matching installed database fails, perform one clean
  reinstall from the bundled asset.
- If the bundled database fails validation, show a corpus-unavailable state
  with a retry action. Do not loop automatically.

Only app-owned generated database files may be replaced. Sermon/session data
remains memory-only.

## Semantic Initialization and Search

The semantic worker is long-lived and owns the complete parsed index. It loads
the Flutter asset from the background isolate using the root isolate token and
background binary messenger, or receives the bytes once as
`TransferableTypedData` if direct worker asset loading proves unsupported on a
target platform. Ordinary mutable index structures must never be copied between
isolates.

The worker:

- validates header, model ID/revision, dimensions, corpus fingerprint,
  translations, quantization, row bounds, and uniqueness;
- retains vectors and metadata in compact typed buffers;
- uses packed integer reference keys instead of allocated strings;
- scans every vector exactly;
- keeps the strongest translation score per canonical verse;
- retains only the requested top K with deterministic tie ordering instead of
  sorting every canonical verse;
- accepts small normalized query vectors and returns compact hit records;
- starts during semantic initialization, not on the first user query.

The search service keeps one active request and only the latest pending request.
Worker or asset failure marks semantics unavailable, completes pending requests
without results, and leaves explicit-reference lookup operational.

## BGE Inference

BGE-base-en-v1.5, its pinned revision, tokenizer vocabulary, pooling,
normalization, and score thresholds remain unchanged.

Tokenization emits tensors at the actual sequence length, including required
special tokens, capped at 512. It does not pad every request to 512 elements.
The model's dynamic input compatibility must be asserted before rollout.
Evaluation must confirm stable expected top results and confidence bands; any
material retrieval regression rejects this optimization.

The existing ONNX session is reused. `flutter_onnxruntime` 1.8.4 does not expose
graph optimization, thread, memory, or execution-provider session options, so
this design does not add unsupported configuration or fork native wrappers.

## Repository and Matching Path

- A passage lookup performs one indexed verse-range query.
- Context lookup reads only the required chapter/range and never scans unrelated
  translations or books.
- Semantic candidates are deduplicated and ranked before hydration.
- Up to four display passages are loaded concurrently with `Future.wait` while
  preserving deterministic result order.
- Database lookup errors do not terminate a listening session.
- No speculative passage cache is added unless device traces show SQLite reads
  are material after compaction.

## UI Update Boundaries

The controller remains the session source of truth, but one notification must
cause at most one relevant rebuild.

- Wakelock and lifecycle synchronization do not call `setState` unless visible
  local state changed.
- Interim transcript changes rebuild the transcript region, not the complete
  scripture/status/action hierarchy.
- Elapsed-time ticks rebuild only status time.
- Match publication rebuilds scripture results and freshness state.
- Promoting an alternative remains local UI state and resets only when the
  controller publishes a new featured result.
- Passage context owns and memoizes its lookup future for the sheet lifetime.

The current visual design and accessibility behavior remain unchanged except
for explicit bootstrap, retry, and unavailable states required by asynchronous
startup.

## Instrumentation and Privacy

Add `dart:developer` timeline spans or equivalent structured timing around:

- first-frame/bootstrap milestones;
- manifest read;
- database open/install/validation;
- semantic worker startup and index load/parse;
- tokenizer and ONNX inference;
- exact vector search;
- passage hydration;
- match publication.

Instrumentation records operation names, durations, row counts, byte counts,
and status categories only. It must never record audio, transcript text, verse
text, vectors, API keys, or passage history.

## Acceptance Budgets

Measure profile builds on the connected TECNO CK6 running Android 14.

| Measurement | Budget |
| --- | --- |
| First Flutter frame | p95 <= 1 second |
| Normal cold process launch to usable ready screen | p95 <= 2 seconds |
| Fresh install or changed database to usable ready screen | <= 5 seconds |
| Finalized transcript to displayed scripture | p50 <= 2 seconds |
| Finalized transcript to displayed scripture | p95 <= 4 seconds |
| Finalized transcript to displayed scripture | hard ceiling 5 seconds when semantics are ready |

Also require:

- no UI or raster jank during representative interim/final transcript bursts;
- no duplicate resident semantic index representation;
- recorded semantic-ready and peak-search RSS improvements or a justified
  trade-off;
- unchanged expected top result and confidence band on fixed evaluation cases;
- no threshold loosening;
- prompt Stop/background behavior during active inference;
- no late result publication across a session generation boundary.

## Verification

Automated verification includes:

- builder tests for deterministic compact schema, manifest, and fingerprint;
- repository tests for single verses, ranges, missing verses, and context;
- semantic parser/worker tests for invalid assets, deterministic exact top K,
  ties, worker reuse, disposal, and compact result transfer;
- tokenizer and embedding-shape tests for short, maximum, and truncated input;
- matcher tests for ordered concurrent hydration and startup-pending requests;
- widget tests for bootstrap, retry, ready, listening, semantic-unavailable,
  context, and large-text states;
- `dart format --output=none --set-exit-if-changed tool lib test integration_test`;
- `flutter analyze`;
- complete `flutter test`;
- Python semantic-tool tests;
- profile APK build.

Device verification includes repeated ADB cold-process launches, fresh-install
launches, a profile integration performance harness, DevTools/Timeline and
frame analysis, memory capture, and representative screenshots inspected for
the affected visual states. Record p50/p95 and the exact build/device metadata
in the release acceptance checklist.

## Cleanup Scope

Remove code and generated structures used only by obsolete tokenized lexical
storage, runtime corpus hashing, repeated database installation, UI-isolate
index expansion, lazy first-query worker conversion, duplicate listener-driven
rebuilds, and repeated sheet futures. Update affected documentation and tests.

Do not rewrite historical design records, redesign unrelated UI, add broad
dependency churn, introduce approximate search, or change BGE-base in this
pass. Upgrade a dependency only when required for Flutter 3.47 compatibility,
correctness, or a measured performance improvement.

## Source Basis

This design follows current official guidance:

- Flutter performance profiling: <https://docs.flutter.dev/perf/ui-performance>
- Flutter performance best practices: <https://docs.flutter.dev/perf/best-practices>
- Flutter concurrency and isolates: <https://docs.flutter.dev/perf/isolates>
- Flutter DevTools Performance view:
  <https://docs.flutter.dev/tools/devtools/performance>
- Dart isolates: <https://dart.dev/language/isolates>
- `TransferableTypedData`:
  <https://api.dart.dev/dart-isolate/TransferableTypedData-class.html>
- ONNX Runtime graph optimization:
  <https://onnxruntime.ai/docs/performance/model-optimizations/graph-optimizations.html>
- ONNX Runtime threading:
  <https://onnxruntime.ai/docs/performance/tune-performance/threading.html>
- ONNX Runtime mobile guidance:
  <https://onnxruntime.ai/docs/tutorials/mobile/>
