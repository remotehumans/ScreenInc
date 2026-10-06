# ScreenInc hand gesture verification

Version 0.4.1, 22 September 2026.

## Implemented

AVFoundation camera capture feeds a single-hand Apple Vision request on a separate inference queue. Frames are not recorded or sent over the network. A busy-frame gate bounds inference work; stale results are rejected. Capture can stop independently of an inference stall. Eight seconds without delivered tracking results shuts the camera down with a message.

Version 0.4.0 used explicit CPU compute selection after a default-device request stalled in Neural Engine loading. User testing then reported jitter, missed gestures, and confusion about starting drawing. Version 0.4.1 prefers the GPU, with CPU fallback when no GPU is available. It accepts results up to 650 ms old, tolerates lower sampling rates, freezes input during a single short detection gap, and retains the release guard after sustained loss. Tiny stationary movements are suppressed and default smoothing is stronger.

The local camera preview shows hand framing. Setup reports recognised pinch state, delivered frame rate and frame delay, and offers adjustable pinch sensitivity. Starting the camera keeps setup in front. **2. Start drawing** closes both setup and Studio, which otherwise suppress canvas input.

The input state machine smooths coordinates, maps a comfortable camera region to the chosen screen, debounces pinch onset, uses different pinch/release thresholds, and requires a release after lost tracking. Open palm dwell opens a temporary menu. A menu-selection pinch cannot become a drawing stroke. Pausing allows menu access; stopping restores the prior drawing mode.

Canvas pointer methods are shared between native mouse events and gesture input. This preserves shapes, partial erasing, selection/moving/resizing, gradients, fading, undo and snapshots without posting system mouse events.

## Automated checks

`swift test --disable-sandbox`

42 XCTest tests pass, including 18 gesture checks:

- Stable pinch onset, release hysteresis and jitter.
- Tracking loss, stale results, large position jumps and invalid coordinates.
- Slower inference still recognises pinches; brief missing detections freeze input without splitting a stroke; small stationary jitter is suppressed.
- Open-palm dwell and rearming, comfortable reach mapping.
- Production canvas drawing, menu tool selection without accidental ink, undo/redo.
- Loss during a stroke, pause, two-step clear confirmation.
- Shared selection/move and partial eraser transactions.
- All menu pages have distinct, reachable hit regions.
- Production menu and native SwiftUI settings rendering.
- The production Vision request returns no hand for a blank frame.

Inspected [menu](evidence/hand-gesture-menu.png) and [settings](evidence/hand-gesture-settings.png) renders. These are test fixtures made by the production rendering code, not screenshots of a live camera session. The settings fixture uses a 1000 × 700 virtual canvas.

## Remaining live checks

During 0.4.1 testing the Mac was unlocked. CUA verified the installed setup controls and live hand-detection feedback. One observed reading was **Ready · pinch to draw, 32 fps · 5 ms**. These are a momentary delivery rate and frame-processing delay, not a sustained benchmark or end-to-end drawing latency. No camera images were saved. Physical pinch reliability, drawing comfort, and the following checks still need validation:

1. Allow/deny Camera permission in the installed bundle, then restart.
2. Detect a physical hand in ordinary and dim lighting; check each handedness and camera mirroring.
3. Pinch, release, and draw freehand and shapes; measure delay and jitter under actual inference load.
4. Open the menu, choose a colour/gradient/tool, erase, undo and save a snapshot with gestures alone.
5. Remove the hand during a stroke, return while pinched, then release; confirm no connecting line.
6. Pause/resume/stop, disconnect the camera, sleep/wake, and verify the camera indicator turns off.
7. Test an external/Continuity camera, multiple displays and presentation sharing.

Text entry and image import remain mouse/keyboard workflows. Narration-aware screen emphasis is deferred.
