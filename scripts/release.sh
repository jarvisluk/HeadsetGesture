#!/bin/zsh
# Builds a universal, Developer ID-signed and notarized release from a clean,
# pushed main branch, then tags it and uploads it as a GitHub Release.
#
# The version comes from Resources/Info.plist (CFBundleShortVersionString and
# CFBundleVersion); bump both and commit before running.
#
#   ./scripts/release.sh              # creates a draft release
#   PUBLISH=1 ./scripts/release.sh    # publishes immediately
#
# Environment:
#   NOTARY_PROFILE  notarytool Keychain profile (default: HeadsetGesture)
#   RELEASE_REPO    GitHub repository (default: jarvisluk/HeadsetGesture)
set -euo pipefail

project_dir="${0:A:h:h}"
info_plist="$project_dir/Resources/Info.plist"
notary_profile="${NOTARY_PROFILE:-HeadsetGesture}"
repo="${RELEASE_REPO:-jarvisluk/HeadsetGesture}"
publish="${PUBLISH:-0}"

fail() {
    echo "Release aborted: $1" >&2
    exit 1
}

cd "$project_dir"

version="$(plutil -extract CFBundleShortVersionString raw "$info_plist")"
build_number="$(plutil -extract CFBundleVersion raw "$info_plist")"
bundle_id="$(plutil -extract CFBundleIdentifier raw "$info_plist")"
tag="v$version"
asset="$project_dir/dist/HeadsetGesture-$version.zip"

# Preflight: everything that can fail cheaply fails before the slow build.
[[ "$(git branch --show-current)" == "main" ]] || fail "releases are cut from main"
git diff --quiet && git diff --cached --quiet || fail "commit or stash local changes first"
git fetch --quiet origin main --tags
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail "main is not in sync with origin/main"
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    fail "tag $tag already exists; bump CFBundleShortVersionString in Resources/Info.plist"
fi
gh auth status >/dev/null 2>&1 || fail "run 'gh auth login' first"
xcrun notarytool history --keychain-profile "$notary_profile" >/dev/null 2>&1 \
    || fail "notary profile '$notary_profile' not found; run: xcrun notarytool store-credentials $notary_profile"

echo "Releasing Headset Gesture $version ($build_number) as $tag"

BUNDLE_IDENTIFIER="$bundle_id" \
MARKETING_VERSION="$version" \
BUILD_NUMBER="$build_number" \
NOTARY_PROFILE="$notary_profile" \
"$project_dir/scripts/prepare-release.sh"

REQUIRE_UNIVERSAL=1 REQUIRE_SECURE_TIMESTAMP=1 REQUIRE_NOTARIZED=1 \
"$project_dir/scripts/check-release.sh"

cp "$project_dir/dist/Headset-Gesture.app.zip" "$asset"
(cd "${asset:h}" && shasum -a 256 "${asset:t}" > "${asset:t}.sha256")
cat "$asset.sha256"

git tag -a "$tag" -m "Headset Gesture $version"
git push origin "$tag"

release_flags=(--repo "$repo" --title "Headset Gesture $version" --generate-notes --verify-tag)
[[ "$publish" == "1" ]] || release_flags+=(--draft)
gh release create "$tag" "$asset" "$asset.sha256" "${release_flags[@]}"

if [[ "$publish" == "1" ]]; then
    echo "Published: https://github.com/$repo/releases/tag/$tag"
else
    echo "Draft created. Review it, then publish with: gh release edit $tag --repo $repo --draft=false"
fi
