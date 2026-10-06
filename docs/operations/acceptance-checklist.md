# Internal release acceptance checklist

Record this checklist for each candidate without transcript, verse, audio, API
key, Bible source, or generated database content.

## Release record

- Version/build: ____________________
- Git commit: ____________________
- Date: ____________________
- Evaluator/device operator: ____________________
- Android model and OS: ____________________
- iPhone model and iOS: ____________________
- Legal approval reference (metadata only): ____________________

## Automated gates

- [ ] `dart format --output=none --set-exit-if-changed tool lib test` passes.
- [ ] `flutter test` passes.
- [ ] `flutter analyze` passes.
- [ ] Private Bible files, fixtures, `assets/bibles.db`, credentials, and
      signing material are absent from the Git diff and release logs; generated
      model and semantic-index assets are ignored and unstaged.
- [ ] The pinned semantic model and generated index validate against the release
      Bible fingerprint, model revision, dimensions, and translation set.
- [ ] Evaluation used representative private fixtures and the release Bible
      database.

Aggregate metrics only:

- Total: __________
- Top-one: __________
- Top-four: __________
- False-positive: __________
- No-result: __________
- Median-time: __________ ms
- Agreed false-positive limit: __________
- [ ] Lexical CLI and mobile semantic profile results both meet the agreed
      false-positive ceiling while preserving representative expected matches.

## Android and iPhone behavior

Run every item on both representative devices unless the item names one
platform.

- [ ] Fresh install requests microphone permission and explains its purpose.
- [ ] Permission denial leaves the app stopped and recoverable.
- [ ] Start opens one foreground listening session; repeated taps do not create
      duplicate capture.
- [ ] Stop ends capture promptly; repeated Stop is safe.
- [ ] The screen remains awake only while actively listening.
- [ ] Backgrounding the app stops and clears the session.
- [ ] Temporary network loss reconnects from current speech without replaying
      queued audio.
- [ ] A deliberately invalid key reaches a terminal, non-retrying service
      error without exposing the key.
- [ ] Representative wording unique to each bundled translation contributes
      evidence to the same canonical scripture reference.
- [ ] Results and surrounding context display NKJV when bundled.
- [ ] With NKJV absent, the deterministic fallback translation is named and is
      used consistently for results and context.
- [ ] Representative explicit references resolve correctly.
- [ ] Representative quotations and paraphrases produce useful top-one/top-four
      semantic results only when scores meet the configured threshold.
- [ ] Missing, stale, and invalid semantic assets leave explicit-reference
      matching usable.
- [ ] Unrelated sermon speech does not force a scripture result.
- [ ] The featured result and alternatives never exceed one plus three.
- [ ] Stop remains prompt during active semantic inference, and a late semantic
      completion cannot update a stopped or restarted session.
- [ ] Large accessibility text remains readable with no clipped controls or
      inaccessible actions on narrow and wide layouts.
- [ ] Android release APK installs and launches with release signing.
- [ ] The Xcode-signed iOS archive installs through the chosen internal
      distribution channel.

## Soak, privacy, and operations

- [ ] A continuous 90-minute live session completes on Android without crash,
      unbounded memory/queue growth, excessive thermal load, or increasing
      latency.
- [ ] A continuous 90-minute live session completes on iPhone with the same
      checks.
- [ ] Under normal connectivity, a useful result appears within three seconds
      after enough identifying speech is available.
- [ ] Profile measurements record semantic cold initialization, p50/p95 search
      latency, and peak memory on both representative devices without private
      text or vectors.
- [ ] Stop and background leave no persisted sermon audio, transcript, detected
      passage history, or session history.
- [ ] Device logs, crash output, and network diagnostics contain no sermon
      audio/transcript/verse text and no credential.
- [ ] Deepgram retention, access, quota, and monitoring settings have been
      reviewed for the organization's account.
- [ ] Bible ownership/distribution rights and required attribution are approved
      for this exact internal release.
- [ ] BGE model attribution, MIT model-card terms, and bundled model
      distribution are approved for this exact internal release.
- [ ] Operators know that key rotation requires a newly signed rebuild and
      redistribution before revoking the old key.

## Decision

- [ ] **Accepted for internal release**

Approver: ____________________  Date: ____________________

Exceptions (no private content):

______________________________________________________________________________
