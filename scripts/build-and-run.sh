#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
configuration="${1:-release}"
build_app_dir="$project_dir/dist/Headset Gesture.app"
app_dir="${HEADSET_GESTURE_INSTALL_PATH:-/Applications/Headset Gesture.app}"
executable_path="$app_dir/Contents/MacOS/HeadsetGesture"
bundle_id="$(plutil -extract CFBundleIdentifier raw "$project_dir/Resources/Info.plist")"

"$script_dir/build-app.sh" "$configuration"

if pgrep -x HeadsetGesture >/dev/null 2>&1; then
    echo "Stopping existing HeadsetGesture instance..."
    osascript -e "tell application id \"$bundle_id\" to quit" >/dev/null 2>&1 || true

    for _ in {1..30}; do
        if ! pgrep -x HeadsetGesture >/dev/null 2>&1; then
            break
        fi
        sleep 0.1
    done

    if pgrep -x HeadsetGesture >/dev/null 2>&1; then
        echo "App did not quit normally; stopping it now..."
        pkill -x HeadsetGesture
    fi
fi

echo "Installing: $app_dir"
ditto "$build_app_dir" "$app_dir"
codesign --verify --deep --strict "$app_dir"

echo "Launching: $app_dir"
open -n "$app_dir"

for _ in {1..30}; do
    if pgrep -f "$executable_path" >/dev/null 2>&1; then
        echo "HeadsetGesture is running."
        exit 0
    fi
    sleep 0.1
done

echo "HeadsetGesture did not remain running after launch." >&2
exit 1
