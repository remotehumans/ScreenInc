# ScreenInc 0.3 feature verification — 2026-09-21

This implements the entire user-confirmed feature-gap table, plus gradient colours. Implementation and validation are distinct; hardware/permission checks below remain open in `remote-humans-agi-m51g`.

| Area | Implemented | Evidence and remaining boundary |
|---|---|---|
| Editing | Select, marquee, move, resize, recolour, duplicate, groups, order, cross-screen dragging and screen picker | Native event tests cover selection/drag/resize/delete; model tests cover group/order/recolour; installed app duplication verified. Cross-display geometry tested with synthetic windows; physical displays unverified. |
| Erasing | Partial freehand cuts, whole-object option, area deletion, gesture undo | Sparse segments split correctly; eraser drag undoes in one step; shape interiors do not erase outlines. |
| Snapshots | Persistent previews, naming, restore, cycling, PNG drag export, portable JSON, session recovery | Save/preview/relaunch verified in installed app. Serialization and display remapping tested. Drag-out into a receiving app is not manually verified. |
| Presentation | Halo, click rings, sequential badges, countdown, lower-third titles | Installed countdown/title observed; badge sequence and presentation rendering tested. Outside-app pointer effects need physical validation. |
| Spotlight | Adjustable circle/rectangle, magnification, region clipboard capture | Region events and synthetic captured-image magnifier render tested. Real ScreenCaptureKit permission/capture flow remains unverified. |
| Keys | Global recorder, tool remapping, presets, hold-Fn inversion | Local drawing switch verified. Automated event sent to Calculator did not activate ScreenInc; physical global shortcut and hold-Fn remain open. Carbon registration reports success. |
| Appearance | Custom colours, per-tool memory, two-colour gradients, opacity, shadows, board colour, longer fade delays | Pixel tests verify gradient direction, shadow outside bounds, opacity, pressure widths; restart colour memory tested. Installed remote stroke rendered orange-to-blue. |
| Export | PNG, vector PDF, flattened RGBA PSD with ICC profile, drawing clipboard | Native decoders open all formats; PDF bounds, PSD dimensions/alpha/sRGB pixels checked. Photoshop itself was not available for application-level testing. |
| Hardware/extras | Tablet pressure and eraser events, iOS browser remote/drawing pad, repeat, seven-step guide | Pressure renderer and remote validation tested; paired browser drawing reaches installed Mac app. Actual tablet, iOS Safari and external slide key delivery remain unverified. |
| Review fixes | Multiline text, preserved preferences, explicit fade/keep, up to 120-second hold, session recovery, gesture undo | Native text tests, restart and mode UI verified; existing fade tests retained. |
| Additional content | Image import and triangle tool | Triangle rendering path is present; native file-picker import and undo were visually verified. |

Camera hand controls were added in 0.4.0. See [gesture verification](hand-gesture-verification.md) for the additional tests, rendering evidence, and live-camera limits.

## Automated run

`swift test --disable-sandbox` passes 42 XCTest tests with no failures. These exercise native event handlers and production drawing, persistence, HTTP server and exports. They do not substitute for hardware or a real OS permission grant. The legacy optional four-second fade renderer test body only runs when `SCREEN_INK_VISUAL_OUTPUT` is set; the exact fade timing unit tests run every time.

`SCREEN_INK_FEATURE_OUTPUT=/tmp/screeninc-feature-evidence swift test --disable-sandbox` also generates [gradient presentation evidence](evidence/gradient-presentation-render.png). This is a production-renderer fixture, not a claimed desktop recording.

The remote HTTP test opens the real listener, fetches its page, rejects a wrong pairing token, posts a command, and stops the listener. The installed-app browser check dragged on the served canvas, observed the gradient stroke on the Mac, duplicated it, and saved a visible snapshot. Pairing was stopped after testing.

## Visual checks and fixes

Studio is separate from the 44-point palette. Tool labels were widened after inspection. Remote pairing content scrolls instead of truncating. Selection decoration hides outside Select mode. Switching from Studio to a drawing tool restores canvas focus. Imported images explicitly clip and blend within their own bounds, preserving the surrounding ink; this was verified in the installed app. Native dialogs and text fields are excluded from drawing-key handling. Gradient shadows use a transparency layer so clipping does not remove the shadow or multiply opacity.

A full-display screenshot was rejected by automatic approval review because unrelated private content could be captured. Testing continued with scoped CUA app screenshots. No workaround capture was attempted. The CUA canvas drag call fails with `windowNotFoundAtPosition`; direct native-event tests and browser-remote input provide separate evidence, not a physical-pointer pass.

## Implementation references

- [Apple ScreenCaptureKit screenshot API](https://developer.apple.com/documentation/ScreenCaptureKit/SCScreenshotManager/captureImage%28contentFilter%3Aconfiguration%3AcompletionHandler%3A%29) for screen capture.
- [Adobe Photoshop file-format specification](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/) for PSD planar channels and ICC resource 1039.
- [Original research and first-version checks](research-and-verification.md).
