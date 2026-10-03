---
name: John Mark
description: A restrained, scripture-first dark console for live sermon operators.
colors:
  warm-amber-seed: "#D6A84B"
  console-surface: "#101112"
typography:
  passage-reference:
    fontSize: "24sp"
    fontWeight: 700
  scripture-body:
    fontSize: "22sp"
    fontWeight: 400
    lineHeight: 1.45
  section-label:
    fontSize: "14sp"
    fontWeight: 700
    letterSpacing: "1.1sp"
  action-label:
    fontSize: "14sp"
    fontWeight: 700
  supporting-body:
    fontSize: "14sp"
    fontWeight: 400
    lineHeight: 1.45
rounded:
  indicator: "2dp"
  panel: "12dp"
  featured: "16dp"
spacing:
  xs: "4dp"
  sm: "8dp"
  md: "12dp"
  base: "16dp"
  content: "20dp"
  lg: "24dp"
  xl: "28dp"
  2xl: "32dp"
components:
  primary-action:
    typography: "{typography.action-label}"
    height: "56dp"
    width: "min 48dp"
  transcript-panel:
    rounded: "{rounded.panel}"
    padding: "{spacing.base}"
  featured-passage:
    rounded: "{rounded.featured}"
    padding: "{spacing.content}"
  empty-passage:
    rounded: "{rounded.featured}"
    padding: "24dp 16dp"
---

# Design System: John Mark

## Overview

**Creative North Star: "The Quiet Operator Console"**

John Mark is an adaptive native Flutter interface for a dim, long-running production environment. Its visual language is restrained and operational: a near-black foundation, semantic Material 3 surfaces, one warm amber seed for action and live-state emphasis, and no decorative religious imagery. Native controls and platform behavior carry more authority than custom styling.

The hierarchy is scripture-first. The current detected reference and passage are the strongest reading moment; alternatives follow, while transcript and privacy copy remain clearly supporting information. Confidence is expressed in plain language instead of scores, and every featured result explicitly says whether it is current or stale.

**Key Characteristics:**

- Adaptive native Flutter with Material 3 controls and safe-area-aware layouts.
- Restrained dark tonal surfaces with warm amber reserved for action, live state, and confidence.
- Scripture-first reading hierarchy with supporting transcript content kept visually quieter.
- Compact single-column and wide two-column compositions driven by available width.
- Accessible wrapping, semantic regions, large touch targets, and foreground-only lifecycle behavior.

## Colors

The palette is generated through a dark Material 3 `ColorScheme` from the warm amber seed, with the console surface explicitly fixed to near-black.

### Primary

- **Warm Amber Seed:** Source for Material 3 primary roles. Use the resolved `colorScheme.primary` for live status, confidence, and the filled start action rather than applying the seed as a raw decoration color.

### Neutral

- **Console Surface:** Scaffold and app-bar ground. It establishes the low-glare operator environment.
- **Semantic Surface Containers:** Use `surfaceContainer` for transcript and empty-result panels, and `surfaceContainerHigh` for the featured interactive passage.
- **Semantic On-Surface Text:** Use `onSurface` for primary reading content and `onSurfaceVariant` for section labels, hints, empty states, and privacy copy.
- **Semantic Outline:** Use `outlineVariant` for the passage sheet handle and other subtle boundaries.
- **Semantic Error:** Use `error` for unavailable service, missing translations, and session failure messages.

**The Semantic Color Rule.** Components consume Material 3 color roles; only the seed and base surface are fixed raw colors.

**The Amber Restraint Rule.** Amber communicates action, active session state, or match confidence. It is not general decoration.

## Typography

**Display Font:** Native platform default through Flutter's Material theme
**Body Font:** Native platform default through Flutter's Material theme

**Character:** The system typeface keeps the console familiar on Android and iPhone. Hierarchy comes from Material 3 roles, weight, spacing, and line height; there are no bundled or branded fonts.

### Hierarchy

- **Passage Reference:** `headlineSmall` with bold weight; names the featured passage and passage-sheet context.
- **Scripture Body:** `titleLarge` with generous line height; carries the featured verse and surrounding context.
- **Status / Field Title:** `titleMedium`, bold only when session state needs emphasis.
- **Transcript Body:** `bodyLarge` at 1.5 line height; readable but subordinate to scripture.
- **Supporting Body:** `bodyMedium` with semantic variant color and relaxed line height for privacy and contextual instructions.
- **Section Label:** `labelLarge`, bold, uppercase, and tracked for compact operational headings such as “DETECTED SCRIPTURE” and “LIVE TRANSCRIPT.”
- **Elapsed Time:** `titleMedium` with tabular figures so the session clock does not shift while updating.

**The Role-First Type Rule.** Choose a Material text role before applying the few implemented overrides; do not introduce screen-specific font families or arbitrary sizes.

## Layout

All screens respect native safe areas and scroll vertically so large text can wrap without clipping. Main content uses 20dp horizontal insets, with 16–32dp vertical rhythm. Ready-state content is centered and capped at 640dp; active listening content is centered and capped at 1000dp.

Below 600dp available width, the listening view is one scripture-first column: status, detected scripture, alternatives, transcript, then the stop action. At 600dp and above, status still spans the workspace while scripture and transcript form a 3:2 row separated by 24dp. The stop action remains after the content rather than competing with it.

Status uses `Wrap`, not a fixed row, so its label and timer reflow at narrow widths and large text sizes. Reference/confidence pairs also wrap. Alternative results remain bounded to three.

**The Scripture-First Rule.** Responsive rearrangement may move supporting content beside scripture, never ahead of it.

## Elevation & Depth

The system is flat and tonal. Depth comes from Material 3 surface-container roles and interactive ink response, not custom shadows. The featured passage uses the higher tonal container because it is both the primary reading surface and a tap target; passive transcript and empty states use the lower container.

**The Tonal-Only Rule.** Do not add decorative shadows or glass effects; distinguish hierarchy with semantic surface levels.

## Shapes

The recurring form language is softly restrained: 12dp corners for supporting panels and 16dp corners for scripture containers. The passage-sheet grabber is a compact capsule with a 2dp radius. Native Material controls retain their themed shapes rather than being manually forced into the panel radius system.

## Components

### Buttons

- **Primary:** A Material 3 `FilledButton.icon` for “Start Listening,” with a 56dp minimum height, 48dp minimum width, bold label, and equalizer icon.
- **Stop:** A Material 3 `OutlinedButton.icon` for “Stop Listening,” matching the primary action's minimum dimensions and using a stop icon.
- **Sheet Action:** A native `TextButton` with a 48dp minimum touch target.
- **States:** Disabled and pressed appearances come from the Material theme. Do not hand-color them.

### Matching Summary

The ready state contains no translation selector. One supporting semantic block
states that matching uses all bundled translations and names the fixed display
translation: NKJV when available, otherwise the deterministic fallback. If
semantic matching is unavailable, explain neutrally that quotation matching
remains active; do not style this as a fatal service error or disable Start.

### Cards / Containers

- **Featured Passage:** High tonal surface, 16dp corners, 20dp padding, clipped Material ink, and a minimum 48dp interactive height. Tapping opens surrounding context.
- **Empty Passage:** Standard tonal surface, 16dp corners, and 16dp horizontal by 24dp vertical padding.
- **Transcript Panel:** Standard tonal surface, 12dp corners, and 16dp padding.
- **Alternatives:** Native list tiles with at least 56dp height and no separate card shells.

### Session Status

An 18dp radio-state icon and bold `titleMedium` label share the active semantic primary color. Active states append a tabular `HH:MM:SS` clock. Ready and inactive states use `onSurfaceVariant`. Status text is explicit: Ready, Connecting, Listening, Listening · quiet, Reconnecting, Live audio delayed, Microphone blocked, or Service unavailable.

### Confidence and Freshness

The featured result uses the exact vocabulary **Current · High**, **Current · Possible**, **Stale · High**, or **Stale · Possible**. Alternatives show confidence only: **High** or **Possible**. Screen-reader labels expand these compact phrases into “Result current/stale, confidence high/possible.” Do not expose numerical confidence.

### Passage Sheet

Surrounding context opens in a scroll-controlled native modal bottom sheet. It uses 24dp horizontal padding, a subtle 40×4dp handle, a loading progress indicator, scripture typography matching the featured passage, and an explicit Close action.

## Do's and Don'ts

### Do:

- **Do** keep scripture visually dominant over transcript, privacy, and operational metadata.
- **Do** use Material 3 semantic color and type roles so contrast and native behavior remain coherent.
- **Do** preserve wrapping, scrolling, semantic containers, descriptive control labels, and 48dp minimum interactive targets.
- **Do** stop listening when the app leaves the foreground, disable the wakelock, and present any retained result as stale when the state says it is stale.
- **Do** keep live transcript and passage history ephemeral and explain that behavior in the ready state.
- **Do** name the display translation and explain that every bundled translation contributes matching evidence.

### Don't:

- **Don't** add decorative religious motifs, dashboard chrome, raw confidence scores, or extra accent colors.
- **Don't** place transcript before scripture or promote more than three alternatives.
- **Don't** freeze phone layouts onto wide screens; switch to the implemented 3:2 workspace at 600dp.
- **Don't** hard-code platform fonts, bypass safe areas, clip large text, or replace native controls without a platform-specific need.
- **Don't** imply background listening or preserve sermon/session history after listening stops.
- **Don't** add translation selection or expose lexical-versus-semantic implementation details on individual results.
