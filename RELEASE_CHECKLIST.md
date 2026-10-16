# Release Checklist

This workflow targets direct distribution with a Developer ID signature and Apple notarization. It is not a Mac App Store submission workflow.

## Required before the first public build

- [ ] Choose and keep one permanent reverse-DNS Bundle ID. Changing it later resets the app's identity and privacy grants.
- [ ] Confirm the public product name, copyright owner, support address, and project URL.
- [ ] Choose a software license and add its `LICENSE` file. No license has been assumed for this repository.
- [ ] Review `PRIVACY.md` and publish it at a stable URL if a download page or store listing requires one.
- [ ] Set the marketing version and a monotonically increasing build number.
- [ ] Confirm the Developer ID Application certificate and notarization Keychain profile on the release Mac.
- [ ] Test first launch, permission denial, later permission grant, reconnect, relaunch, and uninstall/reinstall on a clean Mac user account.
- [ ] Test at least one Apple silicon Mac and one Intel Mac, plus every supported macOS major version that is practical.
- [ ] Verify behavior with the exact headset models named on the download page. The current HID match uses the product name `Headset`.
- [ ] Decide whether the public release needs English only or Chinese localization as well.
- [ ] Add support and release channels: issue tracker, changelog, checksums, and a rollback copy of the previous signed build.

## Build and distribution

1. Generate the icon after changing its 1024×1024 source:

   ```sh
   ./scripts/generate-app-icon.sh
   ```

2. Store notarization credentials once:

   ```sh
   xcrun notarytool store-credentials HeadsetGesture
   ```

3. Build a universal, Developer ID-signed release with a secure timestamp:

   ```sh
   BUNDLE_IDENTIFIER=com.example.HeadsetGesture \
   MARKETING_VERSION=1.2.0 \
   BUILD_NUMBER=4 \
   COPYRIGHT_NOTICE='Copyright © 2026 Your Name. All rights reserved.' \
   NOTARY_PROFILE=HeadsetGesture \
   ./scripts/prepare-release.sh
   ```

4. Keep the notarized zip from `dist/`, record its SHA-256 checksum, and test that exact archive on another Mac before publishing it.
