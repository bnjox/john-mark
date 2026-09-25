---
version: 1
slug: "lib-features-listener-listener-screen-dart"
primary_target: "lib/features/listener/listener_screen.dart"
related_targets: ["lib/features/listener/scripture_panel.dart","lib/features/listener/passage_sheet.dart"]
---

# Listener screen

Mode: Operate

Audience: a church AV operator following a live sermon in a dim control area.
Task: choose one bundled translation, start or stop a foreground listening session, identify the strongest scripture result, scan alternatives, and inspect context.
Constraints: scripture dominates transcript; session and connection state remain unmistakable; responsive at 390px and 800px with large text; native controls and safe areas; no session history.

## Direction contract

THESIS: A quiet live console built around the currently detected passage, refusing dashboard clutter and decorative religious motifs.

OWN-WORLD: Near-black tonal surfaces, warm amber for the sole action and live-state emphasis, cool neutral text, thin semantic dividers, restrained 12–16dp corners, and native Material 3 controls.

STORY: The operator first confirms translation and privacy, starts listening, then reads session state, scripture, alternatives, and only afterward the supporting transcript. Every state explains whether the result is current or stale.

FIRST VIEWPORT: On phones, a compact status bar leads into one scrollable scripture-first column with the transcript below and a full-width stop action. At 600px and above, a centered 1,000px workspace places scripture left and transcript right while status spans the top.

FORM: Restrained dark operator console, selected directly from the approved implementation brief; no generated seed was needed because the user pinned this direction.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
