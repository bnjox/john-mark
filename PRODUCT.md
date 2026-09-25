# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Users

Church AV operators using a phone during a live sermon to identify scripture quickly and accurately.

## Product Purpose

Scripture Listener captures foreground microphone audio, transcribes it live, and displays precision-first scripture matches from the operator's selected bundled translation. Success means a useful passage appears promptly when evidence is strong while uncertain or unrelated speech produces no result.

## Positioning

The product combines live transcription with deterministic, translation-specific on-device reference and quotation matching; it does not infer broad themes or use generated theological interpretation.

## Operating Context

The app is used for 60–90 minute sermons in a dim AV environment. The operator selects a translation before listening, monitors one featured passage and up to three alternatives, and may open surrounding verse context. The app remains foreground-only and stops when backgrounded.

## Capabilities and Constraints

- Flutter supports Android and iPhone from one codebase.
- Deepgram Nova-3 receives live audio directly over WebSocket.
- Sermon audio, transcript, passage history, and session history remain memory-only.
- Bible translations are supplied privately and compiled into a bundled read-only SQLite database.
- Explicit references and close quotations are supported; broad paraphrase inference is excluded.
- One featured passage and at most three alternatives are shown.
- Connectivity loss discards queued audio and resumes from current speech without replay.

## Brand Commitments

The product name is **Scripture Listener**. The approved interface direction is a restrained dark operator console with high contrast, scripture-first hierarchy, warm amber status/action accents, and native platform expectations.

## Evidence on Hand

The approved product design and interaction wireframes are in `docs/superpowers/specs/2026-09-24-mobile-scripture-listener-design.md`. Private Bible data and sermon evaluation fixtures must not be fabricated or committed.

## Product Principles

- Prefer no result over a weak or misleading result.
- Keep scripture dominant and live transcript secondary.
- Make session state unmistakable at a glance.
- Bound all live data and leave no sermon history behind.
- Preserve familiar, accessible mobile interaction patterns.

## Accessibility & Inclusion

Support large text without clipping, semantic regions, high contrast, 48dp touch targets, wrapping content, and responsive phone/tablet layouts based on available width.
