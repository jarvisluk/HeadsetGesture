#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
app_dir="${1:-$project_dir/dist/Headset Gesture.app}"
info_plist="$app_dir/Contents/Info.plist"
executable="$app_dir/Contents/MacOS/HeadsetGesture"
allow_development_bundle_id="${ALLOW_DEVELOPMENT_BUNDLE_ID:-0}"
require_universal="${REQUIRE_UNIVERSAL:-0}"
require_secure_timestamp="${REQUIRE_SECURE_TIMESTAMP:-0}"
require_notarized="${REQUIRE_NOTARIZED:-0}"

fail() {
    echo "Release check failed: $1" >&2
    exit 1
}

[[ -d "$app_dir" ]] || fail "app bundle not found at $app_dir"
[[ -f "$info_plist" ]] || fail "Info.plist is missing"
[[ -x "$executable" ]] || fail "main executable is missing or not executable"

bundle_id="$(plutil -extract CFBundleIdentifier raw "$info_plist")"
version="$(plutil -extract CFBundleShortVersionString raw "$info_plist")"
build_number="$(plutil -extract CFBundleVersion raw "$info_plist")"
icon_file="$(plutil -extract CFBundleIconFile raw "$info_plist")"
copyright_notice="$(plutil -extract NSHumanReadableCopyright raw "$info_plist")"

if [[ "$allow_development_bundle_id" != "1" ]]; then
    case "$bundle_id" in
        local.*|com.example.*|com.yourname.*)
            fail "replace the placeholder Bundle ID '$bundle_id' with a stable reverse-DNS identifier"
            ;;
    esac
fi
[[ -n "$version" ]] || fail "marketing version is empty"
[[ -n "$build_number" ]] || fail "build number is empty"
[[ "$copyright_notice" != "Created locally for headset gesture remapping." ]] || fail "replace the placeholder copyright notice"
[[ -f "$app_dir/Contents/Resources/${icon_file%.icns}.icns" ]] || fail "AppIcon.icns is missing from the bundle"

codesign --verify --deep --strict --verbose=2 "$app_dir"
signing_details="$(codesign -dvvv "$app_dir" 2>&1)"
[[ "$signing_details" == *"Authority=Developer ID Application:"* ]] || fail "bundle is not signed with Developer ID Application"
[[ "$signing_details" == *"flags=0x10000(runtime)"* ]] || fail "Hardened Runtime is not enabled"

if [[ "$require_secure_timestamp" == "1" && "$signing_details" != *"Timestamp="* ]]; then
    fail "Developer ID signature has no secure timestamp"
fi

architectures="$(lipo -archs "$executable")"
if [[ "$require_universal" == "1" ]]; then
    [[ " $architectures " == *" arm64 "* ]] || fail "arm64 slice is missing"
    [[ " $architectures " == *" x86_64 "* ]] || fail "x86_64 slice is missing"
fi

if [[ "$require_notarized" == "1" ]]; then
    xcrun stapler validate "$app_dir"
    spctl --assess --type execute --verbose=2 "$app_dir"
fi

echo "Release checks passed"
echo "Bundle ID: $bundle_id"
echo "Version: $version ($build_number)"
echo "Architectures: $architectures"
