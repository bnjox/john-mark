# Mobile Scripture Listener Design

**Date:** 2026-09-24  
**Status:** Approved

## Purpose

Build an internal Flutter application for Android and iPhone that helps a church AV operator follow scripture during a live sermon. While the app remains open, it captures microphone audio, streams it to Deepgram for English transcription, recognizes explicit Bible references and close or imperfect quotations, and displays the most likely passage from the operator's selected translation.

The application is an operator aid. It does not directly control a projector, presentation software, OBS, FreeShow, or another audience-facing system.

## Goals

- Capture live sermon audio from the phone microphone while the app is in the foreground.
- Stream audio to Deepgram Nova-3 and show a temporary live transcript.
- Detect explicit spoken references and close or imperfect scripture quotations.
- Prefer missing an uncertain result over displaying a false match.
- Feature the strongest accepted passage and show up to three alternatives.
- Aim to display a useful result within three seconds after enough identifying speech is available under normal connectivity.
- Bundle multiple supplied Bible translations and search only the translation selected before the session.
- Handle a temporary connection loss visibly and resume from live audio when connectivity returns.
- Run for a normal 60–90 minute sermon without increasing delay or unbounded memory use.
- Avoid persisting sermon audio, transcripts, detected passages, or session history.

## Non-goals for the MVP

- Uploaded or prerecorded media processing in the product interface
- Background listening while the screen is locked or another app is active
- Offline transcription
- Recovering speech missed during a network interruption
- Broad paraphrase or theological-concept inference
- Semantic embeddings or large language model matching
- Speaker identification
- Transcript editing, export, or history
- External display or presentation-software integration
- User accounts, cloud synchronization, or a custom application backend
- Runtime Bible import or translation downloads
- Public app-store distribution

## Product constraints and accepted risks

- The initial release is privately distributed for one church and supports Android and iPhone from one Flutter codebase.
- The church supplies the FSB and XML Bible source files. The project owner is responsible for translation authorization and legal review.
- Translation names and count are data-driven; application code must not assume a fixed list.
- Deepgram necessarily receives live audio for transcription. Provider processing is governed by the configured Deepgram account and terms.
- There is no token service or streaming proxy. A permanent Deepgram credential is injected during release builds and used by the app directly.
- A credential embedded in a mobile binary can be extracted. This is an explicitly accepted internal-use risk.
- The credential must not be committed to source control. It should use the narrowest practical permissions, have usage alerts or limits, and be easy to rotate through a new build.
- Normal operation requires an internet connection. On-device matching remains available, but it cannot receive new input while cloud transcription is unavailable.

## Architecture

```text
Phone microphone
    |
    v
Foreground audio capture -- bounded in-memory queue
    |
    v
Deepgram live WebSocket -- interim/final transcript events
    |
    v
On-device matching pipeline
    |-- explicit-reference parser
    |-- quote candidate retrieval
    `-- score and stability policy
    |
    v
Flutter presentation state
    |-- featured passage
    |-- up to three alternatives
    `-- recent live transcript and session status

Bundled bibles.db --> selected translation --> matcher and passage lookup
```

The app uses cloud transcription and deterministic on-device scripture matching. Deepgram-specific behavior is isolated behind a transcription interface so another provider can replace it without changing session, matching, or presentation logic.

### Components

#### Session controller

The session controller owns Start and Stop, microphone permission, app lifecycle, connectivity, cancellation, elapsed time, queue limits, and user-visible status. It coordinates the other components without implementing their internal behavior.

Only one session may run at a time. Stopping is idempotent and releases the microphone and network connection. Backgrounding the app stops the MVP session cleanly.

#### Audio source

The audio source captures mono PCM in a format accepted by the configured Deepgram stream. Frames are copied into a fixed-capacity in-memory queue and are never written to disk.

Audio capture must not block on networking, matching, or rendering. If transmission falls behind, stale queued frames are discarded so the displayed result returns to live speech instead of accumulating delay.

#### Transcription adapter

The initial adapter connects directly to Deepgram's live WebSocket API using Nova-3 monolingual English. It exposes provider-neutral events:

- connecting, connected, reconnecting, and failed states;
- interim transcript text;
- finalized transcript segments;
- timing and confidence metadata when provided; and
- authentication, quota, network, and service errors.

The adapter uses interim and final results and may configure scripture-relevant keyterms to improve recognition of difficult Bible book names. Keyterms are hints and must not be treated as proof that a reference was spoken.

#### Bible repository

The repository opens one generated, read-only `bibles.db` asset. It lists available translations and provides validated reference lookup, verse-range lookup, surrounding context, and search-index access for one selected translation.

Translation selection is available only while stopped. All matching during a session is isolated to that selection.

#### Explicit-reference parser

The parser normalizes punctuation, ordinals, number words, common book aliases, and spoken chapter/verse markers. It supports forms such as:

- “John three sixteen”
- “John chapter three verse sixteen”
- “First Corinthians thirteen four through seven”

Every parsed result is validated against the selected translation. Book names are matched from an explicit alias table rather than unrestricted fuzzy matching, preventing ordinary names or phrases from becoming references.

#### Quote matcher

The quote matcher analyzes finalized transcript text combined with a short rolling context window. It retrieves a bounded candidate set using rare tokens and ordered phrases, then scores individual verses and short adjacent ranges.

The score combines:

- ordered phrase coverage;
- significant-token overlap;
- tolerance for small transcription or wording differences;
- how much of the transcript and candidate each other explains; and
- transcription confidence when available.

The matcher does not infer passages from broad themes. All scoring is deterministic and configurable for evaluation against representative sermons.

#### Match stabilizer

The stabilizer applies the precision-first display policy:

- A validated explicit reference outranks quotation candidates.
- A strong quotation can be accepted immediately.
- A borderline quotation requires supporting evidence in consecutive finalized windows.
- A weak new result cannot displace a stronger displayed result.
- Repeated evidence strengthens the current result instead of creating duplicates.
- Alternatives must be distinct passages and pass their own minimum threshold.
- When no stronger result exists, the current passage remains visible with a “No stronger match yet” state.

#### Presentation layer

Flutter widgets render immutable presentation state and send user actions to the controller. Widgets do not open microphones, manage WebSockets, query raw database tables, or calculate match scores.

## Bible build pipeline

The supplied FSB and XML files are development-time inputs. A conversion tool runs before release and creates one generated SQLite asset:

```text
Supplied FSB/XML files
        |
        v
Validation and normalization tool
        |
        v
assets/bibles.db
    |-- translations
    |-- books and aliases
    |-- verses and verse ranges
    `-- lexical search data
```

The app does not parse source FSB or XML files during normal operation. The converter:

1. Identifies each source translation and format.
2. Converts books, chapters, verses, and combined verse ranges into a canonical schema.
3. Retains clean display text and creates separate normalized search text.
4. Validates positive and unique numbering, non-empty text, ordered ranges, and canonical book mapping.
5. Builds the lexical data needed for bounded candidate retrieval.
6. Produces deterministic output so unchanged inputs do not create unexplained database differences.

Malformed or unsupported source data fails the release build with a file- and location-specific error. It must never create a partially valid bundled translation.

## Real-time data flow

1. The operator selects a bundled translation and taps **Start Listening**.
2. The app requests microphone access when required.
3. The transcription adapter connects to Deepgram before audio delivery begins.
4. Audio frames enter a bounded memory queue and stream to Deepgram.
5. Interim text updates the recent live transcript only.
6. Finalized segments are appended to a bounded rolling text window.
7. The explicit-reference parser and quote matcher produce candidates.
8. The stabilizer accepts, retains, or rejects candidates according to calibrated thresholds.
9. The presentation layer receives a featured result, up to three alternatives, and matching status.
10. Processed audio and transcript text outside the rolling windows are discarded.
11. Stop clears all transient session state and releases microphone and network resources.

The three-second target begins when enough identifying words have been spoken. It does not begin at the start of a quotation whose distinctive wording occurs later.

## Interface

### Ready state

```text
+---------------------------------+
| Scripture Listener       Ready ●|
+---------------------------------+
| Translation                     |
| [ NKJV                       ▾ ] |
|                                 |
| Microphone                      |
| Built-in microphone             |
|                                 |
|        [ Start Listening ]      |
|                                 |
| Audio is sent for transcription |
| and is not saved by this app.   |
+---------------------------------+
```

### Listening state

```text
+---------------------------------+
| Listening…  00:37:24    Online ●|
+---------------------------------+
| DETECTED SCRIPTURE              |
|                                 |
| John 3:16                  High |
| +-----------------------------+ |
| | For God so loved the world  | |
| | that He gave His only ...   | |
| +-----------------------------+ |
|                                 |
| OTHER POSSIBILITIES             |
| 1  Romans 5:8          Possible |
| 2  1 John 4:9          Possible |
| 3  John 3:17           Possible |
+---------------------------------+
| LIVE TRANSCRIPT                 |
| “…that whoever believes in Him  |
| should not perish but have…”    |
|                                 |
|        [ Stop Listening ]       |
+---------------------------------+
```

### Interaction rules

- Scripture is visually dominant; the transcript is secondary and limited to recent rolling context.
- Tapping an alternative promotes it locally without changing the matcher's calculated confidence.
- Tapping the featured passage opens its complete detected range with previous and next verse context.
- Translation cannot change while listening.
- The app prevents screen sleep during an active session.
- Confidence is expressed as **High** or **Possible**, not as an uncalibrated percentage.
- Touch targets, contrast, focus semantics, and text scaling must support quick use in a dim AV environment.
- The interface distinguishes ready, connecting, listening, silence, reconnecting, delayed, stopped, permission denied, and service error states.

## Failure handling

- **Microphone permission denied:** remain stopped and explain how to enable permission.
- **No microphone or capture failure:** stop safely, retain the currently displayed passage, and provide a specific error.
- **Temporary connection loss:** mark the current passage stale, stop accumulating audio, and retry with bounded exponential backoff.
- **Connection restored:** resume from current live audio. Do not replay or claim to recover missed speech.
- **Authentication or quota failure:** stop automatic retries and show an actionable service error.
- **Processing delay:** discard stale queued audio and show a delayed state until the pipeline returns to live input.
- **No reliable match:** retain the current passage and do not force a candidate.
- **App backgrounded:** stop listening and clear transient session data.
- **Phone call or audio interruption:** pause capture and require explicit resume when the platform cannot restore the session safely.
- **Unexpected Bible asset failure:** disable the affected translation without crashing. The build pipeline should make this unreachable in a valid release.

## Privacy and persistence

The application does not intentionally persist:

- raw or encoded sermon audio;
- interim or finalized transcripts;
- detected passage history;
- session timing or activity history; or
- scripture-matching analytics derived from a sermon.

These values must also be excluded from application logs, crash reports, and analytics payloads. Closing or stopping the session clears them from application memory. The app persists only operational preferences, such as the last selected translation, and bundles the generated Bible database.

Deepgram receives audio required for transcription. The product UI discloses this before listening. Provider-side handling is outside the app and must be configured and reviewed separately for the church's account.

## Verification strategy

### Essential automated tests

The MVP uses a deliberately small test suite focused on failures that would be expensive to discover during a live sermon:

- Representative FSB and XML fixtures convert correctly, while malformed source data fails instead of producing a partial Bible.
- Table-driven reference and quote fixtures cover the main successful forms, likely transcription errors, ambiguous passages, and unrelated speech that must not match.
- Stability tests verify that weak candidates cannot displace stronger results and that no more than three distinct alternatives are returned.
- Session lifecycle tests verify Start, Stop, cancellation, bounded queues, and reconnection without retaining stale audio.
- One privacy check confirms that a completed session creates no audio, transcript, passage-history, or session-history files.
- A small Flutter widget test covers the primary flow from ready state through listening, result display, and Stop.

Platform permission dialogs, audio interruptions, accessibility, device lifecycle behavior, and visual details are checked manually on representative phones rather than reproduced in a large automated suite.

### Recorded-sermon evaluation

A development-only replay harness sends representative recordings through the same transcription and matching boundaries used by live capture. It also accepts prepared transcript fixtures so matching can be evaluated independently of transcription. Private recordings, Bible source files, generated licensed assets, and credentials remain outside source control as required by project policy.

Measurements include:

- latency from identifying speech to an accepted passage;
- explicit-reference accuracy when the needed words are transcribed;
- top-one and top-four quotation accuracy;
- false-positive frequency on speech with no scripture quotation;
- reconnect behavior;
- queue depth and memory over 90 minutes; and
- battery and thermal behavior on representative Android and iPhone devices.

## MVP acceptance criteria

- The application runs on representative Android and iPhone devices from one Flutter codebase.
- All supplied, valid build-time translations appear in the selector and resolve canonical references correctly.
- Only the selected translation is searched during a session.
- Under normal connectivity, a useful accepted result appears within three seconds after enough identifying speech is available.
- Explicit references resolve reliably when Deepgram transcribes the relevant words correctly.
- The calibrated matcher detects representative close quotations while meeting the evaluation set's agreed false-positive threshold.
- One featured result and no more than three distinct alternatives are shown.
- A 90-minute session does not crash, leak workers, grow queues without bound, or accumulate increasing delay.
- Temporary network loss does not accumulate or replay stale audio, and live processing resumes after reconnection.
- Backgrounding stops capture as communicated by the interface.
- No sermon audio, transcript, detected-passage history, or session history is persisted or logged.
- The release credential is absent from source control and can be rotated through the build process.

The numeric match thresholds and acceptable false-positive rate are calibration outputs, not arbitrary design constants. They must be recorded from representative sermon evaluation before the MVP is declared ready.

## Delivery sequence

1. Establish Flutter application boundaries and a provider-neutral transcription contract.
2. Build and test the FSB/XML-to-`bibles.db` conversion pipeline.
3. Implement canonical lookup and deterministic explicit-reference parsing.
4. Implement lexical candidate retrieval, scoring, and stability using transcript fixtures.
5. Prove foreground microphone capture and Deepgram streaming on Android and iPhone.
6. Connect the bounded session controller and mobile interface.
7. Calibrate latency and precision with representative sermon recordings.
8. Run privacy checks, reconnect tests, device accessibility checks, and a 90-minute live soak before internal release.
