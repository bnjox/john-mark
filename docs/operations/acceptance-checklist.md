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
      signing material are absent from the Git diff and release logs.
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
- [ ] The strictest tested matcher thresholds meeting that limit were selected
      while preserving representative expected matches.

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
- [ ] Each selected translation is searched in isolation.
- [ ] Representative explicit references resolve correctly.
- [ ] Representative close quotations produce useful top-one/top-four results.
- [ ] Unrelated sermon speech does not force a scripture result.
- [ ] The featured result and alternatives never exceed one plus three.
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
- [ ] Stop and background leave no persisted sermon audio, transcript, detected
      passage history, or session history.
- [ ] Device logs, crash output, and network diagnostics contain no sermon
      audio/transcript/verse text and no credential.
- [ ] Deepgram retention, access, quota, and monitoring settings have been
      reviewed for the organization's account.
- [ ] Bible ownership/distribution rights and required attribution are approved
      for this exact internal release.
- [ ] Operators know that key rotation requires a newly signed rebuild and
      redistribution before revoking the old key.

## Decision

- [ ] **Accepted for internal release**

Approver: ____________________  Date: ____________________

Exceptions (no private content):

______________________________________________________________________________
