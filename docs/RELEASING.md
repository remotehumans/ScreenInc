# Releases

Run `swift test --disable-sandbox` and `./script/package_release.sh` on macOS
with Xcode command line tools. The script builds arm64 and x86_64 in release
mode, creates a universal app, verifies its signature and architectures, and
makes a drag-to-Applications DMG with a SHA-256 checksum. It does not stop or
replace an installed app. Version and bundle metadata live in Assets/Info.plist.

Without credentials, the output is explicitly named `universal-preview.dmg`.
Ad-hoc signing does not establish developer identity or pass Gatekeeper.

For a trusted direct download, use a **Developer ID Application** certificate,
not Apple Development or Apple Distribution. Store notarization credentials
locally with `xcrun notarytool store-credentials`, then run:

```sh
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="screeninc-notary" ./script/package_release.sh
```

The signed path enables hardened runtime and the camera entitlement. The script
submits the DMG, waits for acceptance, and staples and validates its ticket.
Never commit certificates, private keys, passwords, or keychain profiles.
If NOTARY_PROFILE is absent, signing alone does not notarize the release.

Before publishing a signed release, mount it and assess the contained app with
`spctl --assess --type execute --verbose`, launch it on a second Mac, and test
camera permissions. Check Intel hardware before claiming Intel runtime support.
The CI template in `docs/ci/macos-checks.yml` tests and builds preview artifacts; it does not publish releases. Copy it to `.github/workflows/ci.yml` to enable it. The publishing account currently lacks GitHub workflow-write permission.

Publish the DMG, its checksum and optional demo using GitHub Releases. Keep large
videos as release assets rather than Git objects. The v0.4.1 demonstration was
provided by Elliott on 6 October 2026; it includes context from ScreenBrush.

## Existing asc authentication

If `asc` already has an authorised Apple API profile, the signed DMG can be
submitted without copying its credentials into another keychain profile:

```sh
asc notarization submit --file dist/ScreenInc-VERSION-universal-signed.dmg --wait
xcrun stapler staple dist/ScreenInc-VERSION-universal-signed.dmg
xcrun stapler validate dist/ScreenInc-VERSION-universal-signed.dmg
```

Check that Apple reports Accepted. Regenerate the SHA-256 checksum after stapling,
then mount the DMG and check the contained app with Gatekeeper before publishing.
Never publish the pre-stapling checksum alongside the modified disk image.
