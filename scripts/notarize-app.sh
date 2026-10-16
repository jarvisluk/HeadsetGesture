#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
app_dir="$project_dir/dist/Headset Gesture.app"
zip_path="$project_dir/dist/Headset-Gesture.app.zip"
notary_profile="${NOTARY_PROFILE:-}"

if [[ -z "$notary_profile" ]]; then
    echo "Set NOTARY_PROFILE to a notarytool Keychain profile." >&2
    echo "Create one with: xcrun notarytool store-credentials <profile-name>" >&2
    exit 1
fi

REQUIRE_SECURE_TIMESTAMP=1 "$project_dir/scripts/check-release.sh" "$app_dir"

rm -f "$zip_path"
ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$zip_path"

xcrun notarytool submit "$zip_path" \
    --keychain-profile "$notary_profile" \
    --wait
xcrun stapler staple "$app_dir"
xcrun stapler validate "$app_dir"

rm -f "$zip_path"
ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$zip_path"
spctl --assess --type execute --verbose=2 "$app_dir"

echo "Notarized app: $app_dir"
echo "Distribution zip: $zip_path"
