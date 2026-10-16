#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
configuration="${1:-release}"
app_dir="$project_dir/dist/Headset Gesture.app"
zip_path="$project_dir/dist/Headset-Gesture.app.zip"
release_build="${RELEASE_BUILD:-0}"
universal_build="${UNIVERSAL_BUILD:-0}"

cd "$project_dir"

if [[ "$universal_build" == "1" ]]; then
    build_root="$(mktemp -d /tmp/headset-gesture-universal.XXXXXX)"
    trap 'rm -rf "$build_root"' EXIT

    for architecture in arm64 x86_64; do
        swift build \
            -c "$configuration" \
            --arch "$architecture" \
            --scratch-path "$build_root/$architecture"
    done

    executable_source="$build_root/HeadsetGesture"
    lipo -create \
        "$build_root/arm64/arm64-apple-macosx/$configuration/HeadsetGesture" \
        "$build_root/x86_64/x86_64-apple-macosx/$configuration/HeadsetGesture" \
        -output "$executable_source"
else
    swift build -c "$configuration"
    executable_source="$project_dir/.build/$configuration/HeadsetGesture"
fi

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS"
mkdir -p "$app_dir/Contents/Resources"
cp "$executable_source" "$app_dir/Contents/MacOS/HeadsetGesture"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
cp "$project_dir/Resources/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"

if [[ -n "${BUNDLE_IDENTIFIER:-}" ]]; then
    plutil -replace CFBundleIdentifier -string "$BUNDLE_IDENTIFIER" "$app_dir/Contents/Info.plist"
fi
if [[ -n "${MARKETING_VERSION:-}" ]]; then
    plutil -replace CFBundleShortVersionString -string "$MARKETING_VERSION" "$app_dir/Contents/Info.plist"
fi
if [[ -n "${BUILD_NUMBER:-}" ]]; then
    plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$app_dir/Contents/Info.plist"
fi
if [[ -n "${COPYRIGHT_NOTICE:-}" ]]; then
    plutil -replace NSHumanReadableCopyright -string "$COPYRIGHT_NOTICE" "$app_dir/Contents/Info.plist"
fi

signing_identity="${CODE_SIGN_IDENTITY:-}"
if [[ -z "$signing_identity" ]]; then
    signing_identity="$({ security find-identity -v -p codesigning 2>/dev/null || true; } \
        | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' \
        | head -n 1)"
fi

if [[ -n "$signing_identity" ]]; then
    echo "Signing with: $signing_identity"
    signing_arguments=(--force --options runtime --sign "$signing_identity")
    if [[ "$release_build" == "1" ]]; then
        signing_arguments+=(--timestamp)
    else
        signing_arguments+=(--timestamp=none)
    fi

    if ! codesign "${signing_arguments[@]}" "$app_dir"; then
        if [[ "$release_build" == "1" ]]; then
            echo "Release signing failed; refusing to create an ad-hoc release artifact." >&2
            exit 1
        fi
        echo "Warning: the signing identity could not be used; falling back to ad-hoc signing." >&2
        echo "Unlock the signing key in Keychain Access to keep privacy permissions across rebuilds." >&2
        codesign --force --sign - "$app_dir"
    fi
else
    if [[ "$release_build" == "1" ]]; then
        echo "A Developer ID Application identity is required for a release build." >&2
        exit 1
    fi
    echo "Warning: no Developer ID identity found; using ad-hoc signing." >&2
    echo "Privacy permissions may need to be granted again after every rebuild." >&2
    codesign --force --sign - "$app_dir"
fi

codesign --verify --deep --strict "$app_dir"
rm -f "$zip_path"
ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$zip_path"

echo "App: $app_dir"
echo "Zip: $zip_path"
