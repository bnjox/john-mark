# Semantic Scripture Detection Design

**Date:** 2026-09-25  
**Status:** Approved design; not yet implemented

## Purpose

Improve John Mark so it can identify scripture when a preacher uses
different wording or a paraphrase. Detection will use every bundled Bible
translation and an on-device semantic model, while displayed scripture remains
canonical Bible text from NKJV.

The ready screen will no longer ask the operator to select a translation.

## Product decisions

- Search all bundled translations automatically.
- Display detected passages and surrounding context in NKJV.
- If NKJV is unavailable, select a deterministic fallback translation and name
  it in the interface.
- Use semantic retrieval only on-device. No transcript text is sent to another
  model service.
- Preserve the precision-first policy: showing no result is better than showing
  an unrelated verse.
- Replace translation-specific internal interfaces cleanly instead of adding a
  compatibility layer.
- Keep cleanup limited to the matching, repository, session, startup, and UI
  code touched by this feature.
- Do not modify or overwrite unrelated Bible-builder work already in progress.
- The coding agent must not run Bible generation, semantic-index generation, or
  application build scripts. It must provide commands for the project owner to
  run.

## Detection architecture

```text
Final transcript window
        |
        +--> explicit-reference parser
        |
        +--> lexical search across every bundled translation
        |
        `--> on-device semantic search when stronger evidence is absent
                    |
                    v
        evidence grouped by canonical Bible reference
                    |
                    v
        precision and stability policy
                    |
                    v
        NKJV passage resolver --> presentation state --> UI
```

The current translation-specific matcher will be replaced by a
translation-neutral `ScriptureDetectionEngine`. Matching output will identify a
canonical book, chapter, and verse range plus confidence and evidence metadata.
It will not carry translation-specific display text.

### Evidence priority

1. A valid explicit spoken reference has highest priority.
2. Lexical matching searches all translations and groups duplicate evidence by
   canonical reference.
3. Semantic retrieval runs only when explicit and lexical evidence are not
   strong enough.
4. A semantic-only candidate must clear a strict similarity threshold, beat the
   runner-up by a configured margin, and receive support in consecutive
   finalized transcript windows.
5. Weak new evidence cannot displace a stronger displayed result.

These rules are intended to stop broad sermon themes and common religious
phrases from continually selecting unrelated verses.

### Concurrency and degradation

Model inference and index scoring must run outside the UI and audio-delivery
paths. Semantic work is bounded and coalesced so a new finalized transcript
does not create an unbounded queue.

Explicit-reference and lexical matching remain usable while semantic assets are
initializing. If the model or index cannot load or fails validation, the app
continues in lexical-only mode and exposes a non-blocking status rather than
failing the listening session.

## Display translation

At startup, the app resolves the display translation in this order:

1. A bundled translation whose normalized identifier is `nkjv`.
2. A bundled translation whose normalized name is New King James Version.
3. The first translation in a deterministic repository ordering.

The same resolved translation is used for the featured passage, alternatives,
and surrounding context. When the fallback is not NKJV, the ready and listening
interfaces identify the translation being displayed.

## Interface changes

- Remove the translation dropdown.
- Remove translation preference loading, saving, and persistence.
- Explain briefly that matching uses all bundled translations and displays
  NKJV.
- Enable Start Listening when transcription is configured and at least one
  translation is available.
- Do not expose lexical-versus-semantic implementation details in each result.
- Keep the existing canonical scripture, confidence, alternatives, transcript,
  and context hierarchy.

## Semantic model

### Selected model

Use **BAAI/bge-base-en-v1.5**, an MIT-licensed English embedding model with 109
million parameters, 768-dimensional output, and a 512-token maximum sequence
length.

BGE-base is preferred over BGE-small for retrieval quality. BGE-large is not the
initial choice: its published retrieval improvement over base is modest, while
its inference latency, memory requirement, and battery cost are substantially
higher on ordinary phones. The embedding adapter must keep the model replaceable
without changing the detection engine.

Approximate upstream artifact sizes are:

| Model or artifact | Approximate size | Dimensions |
| --- | ---: | ---: |
| BGE-small FP32 | 133 MB | 384 |
| BGE-base FP32 ONNX | 436 MB | 768 |
| BGE-base FP16 ONNX | 218 MB | 768 |
| BGE-base Q4 ONNX variants | 96–149 MB | 768 |
| BGE-large FP32 ONNX | 1.34 GB | 1024 |
| Tokenizer and configuration files | Less than 1 MB | — |

With approximately 31,102 verses and four translations, an int8 BGE-base
scripture index is approximately 96 MB before metadata. The expected initial
bundle increase with the FP32 model is roughly 530–570 MB. Actual release size
must be recorded after assets are generated.

FP32 is the quality baseline. FP16 or another optimized model may replace it
only after representative evaluation shows no material loss and supported
devices show better runtime behavior.

### Runtime assets

The release app bundles:

- the selected ONNX model;
- tokenizer vocabulary and configuration;
- model and license metadata; and
- a generated scripture embedding index.

The runtime validates the model identifier, pinned revision, tokenizer,
embedding dimensions, index format version, translation set, and Bible database
fingerprint. A stale or incompatible index is rejected safely.

## Semantic index generation

A separate Python tool will read `assets/bibles.db`, embed each verse from every
bundled translation, quantize the normalized vectors for search, and write a
contiguous index with canonical reference metadata. Nearby winning verses may
be combined into short passage ranges before NKJV display lookup.

The generator stays separate from the existing Bible importer. It uses `uv`
with pinned Python dependencies. Direct `python` and `pip` workflows are not
part of the supported process.

Private model files and generated semantic assets must be ignored by Git before
they are downloaded or generated. Model and Bible distribution rights remain a
release responsibility even when upstream code and weights use permissive
licenses.

## Model download guide

### Important current-state warning

Do not run the download command until implementation has added the private model
and generated semantic asset paths to `.gitignore`. The command is recorded now
for later use; the feature and its helper scripts do not exist yet.

### Direct pinned download

The official FP32 ONNX model and tokenizer can be downloaded from Hugging Face
with `uv`:

```bash
uvx --from huggingface-hub hf download \
  BAAI/bge-base-en-v1.5 \
  onnx/model.onnx \
  config.json \
  tokenizer.json \
  tokenizer_config.json \
  special_tokens_map.json \
  vocab.txt \
  --revision a5beb1e3e68b9ab74eb54cfd186867f64f240e1a \
  --local-dir private/models/bge-base-en-v1.5
```

Implementation will add a checked helper so the preferred command becomes:

```bash
uv run tool/fetch_semantic_model.py
```

That helper must pin the repository revision, download only required runtime
files, verify expected hashes, retain required license metadata, and place the
assets in ignored paths.

### Index generation command

After the Bible database and model assets exist, the supported command will be:

```bash
uv run tool/build_semantic_index.py \
  --database assets/bibles.db \
  --model private/models/bge-base-en-v1.5 \
  --output assets/scripture_embeddings.bin
```

Implementation may add required explicit flags, but must keep this command and
the release documentation synchronized. The coding agent will provide the final
command rather than executing it.

### Upstream references

- Model card and files: <https://huggingface.co/BAAI/bge-base-en-v1.5>
- Official BGE v1/v1.5 documentation:
  <https://bge-model.com/bge/bge_v1_v1.5.html>
- Optimized ONNX variants:
  <https://huggingface.co/onnx-community/bge-base-en-v1.5-ONNX>

## Error handling

- Missing NKJV: use and identify the deterministic display fallback.
- Missing model or index: continue with explicit and lexical detection.
- Stale model/index pair: reject semantic retrieval and report lexical-only
  operation without interrupting the session.
- Semantic timeout or inference failure: discard that semantic attempt; do not
  terminate listening or block Stop.
- Empty translation database: keep Start disabled and show the existing Bible
  availability error.

## Verification scope

Verification will stay focused on behavior made risky by this change:

- cross-translation lexical evidence maps to one canonical reference;
- detected references resolve to NKJV display text;
- deterministic display fallback works when NKJV is absent;
- semantic-only results require threshold, winner margin, and repeated support;
- explicit references outrank semantic evidence;
- stale or missing semantic assets degrade to lexical-only operation;
- semantic work is bounded and does not block session Stop;
- the ready screen has no translation dropdown or saved preference dependency;
  and
- generated index metadata detects model/database incompatibility.

Representative private sermon fixtures are required to tune thresholds and
compare FP32 with optimized model variants. Tests must not duplicate unrelated
coverage or commit private transcript, Bible, model, or generated-index data.

## Documentation and release updates

Implementation must update the README and internal release checklist with:

- installation of `uv`;
- private model download;
- Bible database generation;
- semantic index generation;
- required ignored asset paths;
- model and index validation;
- device latency and memory checks; and
- attribution and distribution review.
