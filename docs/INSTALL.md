# Install ScreenInc

Requires macOS 14 or later. Download the universal DMG from:
https://github.com/remotehumans/ScreenInc/releases/latest

Open the DMG, drag ScreenInc to Applications, and eject the disk image.
Open ScreenInc from Applications. It appears as a slim toolbar and menu-bar app.

## First launch

Check the release notes for the download you chose. The published 0.4.1 preview
is ad-hoc signed and is not Apple-notarized. If macOS blocks it and you trust
this release, try opening it once, then use System Settings → Privacy & Security
→ Open Anyway. Managed Macs may prohibit this.

A Developer ID-signed release identifies Elliott Callender as its developer.
Notarization status is stated in that release’s notes. Do not disable Gatekeeper.

## Start drawing

Click the pencil, then drag on the screen. Escape returns control to other apps.
F switches new ink between fading and staying on screen. Tab toggles the toolbar.
The colour circle opens quick settings; the stacked squares open Studio.

## Camera gestures — WIP

Camera gestures are experimental and are not working reliably in real-world use.
Use a mouse or trackpad for presentations and training. The following steps are
for testing the intended interaction only.

For experimental camera controls, click the hand, choose Start camera, allow Camera access,
and wait for “Ready · pinch to draw”. Choose “2. Start drawing”. Point to aim;
pinch and hold to draw; release to stop. Hold an open palm to show tools, then
point at a tool and pinch once. Release before starting a drawing pinch.

## Permissions and privacy

Basic drawing does not need Screen Recording access. Magnification and copying
screen regions do. Camera gestures require Camera access and process frames
locally without recording or uploading them. Accessibility is used for optional
hold-Fn switching and remote slide-key control. The phone remote is optional,
uses local HTTP and a random pairing link, and should be used on trusted Wi-Fi.

## Uninstall

Quit through the menu-bar menu, then move ScreenInc from Applications to Trash.
Your drawings and settings remain in ~/Library/Application Support/ScreenInc/.
Remove that folder only if you also want to delete your saved work.
