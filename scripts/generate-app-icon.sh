#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
source_image="$project_dir/Resources/Brand/AppIcon.png"
output_icon="$project_dir/Resources/AppIcon.icns"
iconset_dir="$(mktemp -d /tmp/headset-gesture-iconset.XXXXXX)/AppIcon.iconset"

trap 'rm -rf "${iconset_dir:h}"' EXIT

if [[ ! -f "$source_image" ]]; then
    echo "Missing icon source: $source_image" >&2
    exit 1
fi

width="$(sips -g pixelWidth "$source_image" | awk '/pixelWidth/ { print $2 }')"
height="$(sips -g pixelHeight "$source_image" | awk '/pixelHeight/ { print $2 }')"
if [[ "$width" != "1024" || "$height" != "1024" ]]; then
    echo "App icon source must be exactly 1024x1024 pixels." >&2
    exit 1
fi

mkdir -p "$iconset_dir"

render_icon() {
    local size="$1"
    local filename="$2"
    sips -z "$size" "$size" "$source_image" --out "$iconset_dir/$filename" >/dev/null
}

render_icon 16 icon_16x16.png
render_icon 32 icon_16x16@2x.png
render_icon 32 icon_32x32.png
render_icon 64 icon_32x32@2x.png
render_icon 128 icon_128x128.png
render_icon 256 icon_128x128@2x.png
render_icon 256 icon_256x256.png
render_icon 512 icon_256x256@2x.png
render_icon 512 icon_512x512.png
render_icon 1024 icon_512x512@2x.png

iconutil -c icns "$iconset_dir" -o "$output_icon"
echo "Generated: $output_icon"
