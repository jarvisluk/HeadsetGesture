# Release Checklist

Releases are Developer ID-signed, notarized by Apple and published as GitHub Releases on [jarvisluk/HeadsetGesture](https://github.com/jarvisluk/HeadsetGesture/releases). Signing happens on the maintainer's Mac; CI only builds and tests.

## Fixed decisions

- Bundle ID: `io.github.jarvisluk.HeadsetGesture`. Never change it: macOS ties privacy permissions and preferences to it. Settings from the pre-release ID `local.codex.HeadsetGesture` are migrated once on first launch.
- License: MIT, copyright Jarvis Luk.
- Versions live in `Resources/Info.plist`: `CFBundleShortVersionString` (marketing version, tagged as `v<version>`) and `CFBundleVersion` (build number, must increase with every release).

## One-time setup on the release Mac

1. A **Developer ID Application** certificate in the login keychain (`security find-identity -v -p codesigning`).
2. Notarization credentials stored under the profile name `HeadsetGesture`. Use an [app-specific password](https://support.apple.com/102654) for your Apple ID:

   ```sh
   xcrun notarytool store-credentials HeadsetGesture --apple-id <apple-id> --team-id <team-id>
   ```

3. The GitHub CLI signed in with push access: `gh auth login`.

## Every release

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`, commit on `main` and push. Wait for CI to pass.
2. If the icon source changed, run `./scripts/generate-app-icon.sh` and commit the new `.icns` first.
3. Run the release:

   ```sh
   ./scripts/release.sh
   ```

   It refuses to run unless `main` is clean and pushed, the tag is new, `gh` is signed in and the notary profile exists. It then builds a universal binary, signs it with a secure timestamp, notarizes and staples it, checks the result with `spctl`, writes `dist/HeadsetGesture-<version>.zip` plus a `.sha256` file, pushes the `v<version>` tag and creates a **draft** GitHub Release with generated notes.

4. Download the zip from the draft, test it on another Mac (first launch, permission grant, reconnect, relaunch), then publish:

   ```sh
   gh release edit v<version> --repo jarvisluk/HeadsetGesture --draft=false
   ```

   `PUBLISH=1 ./scripts/release.sh` skips the draft step.

## Before the first public release

- [ ] Test on a clean user account: first launch, permission denial, later grant, reconnect, relaunch, uninstall and reinstall.
- [ ] Test on Apple silicon and Intel, and on each supported macOS major version you can reach.
- [ ] Verify the headset models named on the download page. The HID match uses the product name `Headset`.
- [ ] Keep the previous signed zip as a rollback copy.
