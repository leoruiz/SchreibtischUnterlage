#!/bin/zsh

set -euo pipefail

root_directory=${0:A:h:h}
source_icon="$root_directory/Resources/AppIcon.svg"
output_icon=${1:-"$root_directory/Resources/AppIcon.icns"}
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/SchreibtischUnterlage-AppIcon.XXXXXX")
iconset_directory="$temporary_directory/AppIcon.iconset"
master_icon="$temporary_directory/master.png"

function cleanup {
    rm -rf "$temporary_directory"
}
trap cleanup EXIT

mkdir -p "$iconset_directory"
sips -s format png "$source_icon" --out "$master_icon" >/dev/null

function render_icon {
    local size=$1
    local filename=$2

    sips \
        --resampleHeightWidth "$size" "$size" \
        "$master_icon" \
        --out "$iconset_directory/$filename" \
        >/dev/null
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

mkdir -p "${output_icon:h}"
iconutil --convert icns --output "$output_icon" "$iconset_directory"
