# Research and verification — 21 September 2026

This is a historical record of the initial prototype. For current features and test limits, see the README, feature-verification.md and hand-gesture-verification.md.

## Sources

- [ScreenBrush App Store description](https://apps.apple.com/us/app/screenbrush/id1233965871): drawing above apps, shapes/text, ghost mode, whiteboard, snapshots, shortcuts, multiple screens and Plus features.
- [ScreenBrush official site](https://screenbrush.app/): product overview and example imagery.
- [Remote Work Hacks — ScreenBrush](https://www.youtube.com/watch?v=Blf_XZ6BtR4): short demonstration; drawing around 00:31–00:54, shape/text tools around 00:56–01:10, persistence around 01:13–01:27, spotlight around 01:28–01:38.
- [ScreenBrush annotation review](https://www.youtube.com/watch?v=-MOZeVVIzl0): toolbar and tool use around 02:03–03:33, stylus/colour controls around 03:51–04:52, fading around 04:37–05:09, text/movement around 05:16–05:20.

The two public YouTube videos were analysed with the user's existing Gemini 3.8 Flash API account and video processing enabled. Timing estimates differ between videos and are not treated as one exact ScreenBrush default. No claim is made to have run ScreenBrush itself.

## Behaviour adopted

- Each stroke stays opaque during drawing, then independently holds and fades after release.
- Default hold is 2 seconds; fade is a 1-second smoothstep opacity transition. Other holds are 5 and 10 seconds. Keep mode applies to future drawings.
- Keep the canvas unobstructed: a narrow vertical toolbar at the right edge, secondary controls in a popover, keyboard shortcuts and hide/show.
- Use a transparent native overlay with explicit draw and click-through modes. Keep UI assets and implementation original.

The initial wide toolbar was replaced after Elliott said it obstructed the screen. The resulting 44-point palette occupies about 1.3% of a 1440×900 screen, compared with about 8.5% for the initial 690×160 palette.

## Verification performed

- SwiftPM build, real .app launch and ad-hoc signature succeeded on this Apple Silicon Mac.
- Nine XCTest cases passed: independent fade timing, permanent ink, history branching/clear recovery, eraser hit geometry, arrow hits, JSON round trip, native mouse-event handler lifecycle, text commit/laser separation, and production-renderer evidence generation.
- Native UI automation verified palette buttons, settings popover, drawing activation, keyboard tool/whiteboard/keep actions, the actual open-file dialog and restored drawings, undo and redo, hide/show, and exit from drawing.
- Inspected production-rendered shapes, smoothed freehand line, text and spotlight at Retina resolution.
- `compact-palette.png` is a real desktop capture of the running app with a saved test drawing loaded through its open-file dialog.
- `fade-render-test.mp4` is a deterministic 30 fps renderer test, not a recording of a human drag. Gemini's visual review found no flicker, geometry changes, abrupt cutoff or remaining stroke pixels. Unit assertions establish the exact 2-second hold and 1-second fade; the model's timestamp prose was inconsistent and is not used as timing evidence.

## Verification limits

The native computer-use tool repeatedly returned `windowNotFoundAtPosition` for coordinate drags on the canvas, including when tested temporarily at normal window level. Element-based buttons and keyboard interactions worked. Mouse-down/drag/up handlers were tested directly with native events in XCTest; an end-to-end physical-pointer drag has not been verified. The temporary window-level test flag was removed.

Multiple physical displays, fullscreen Spaces, tablet pressure and live meeting screen sharing were not exercised. The app does not implement pressure modulation. No claim of full ScreenBrush feature parity, notarization or universal-binary distribution is made.
