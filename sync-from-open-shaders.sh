#!/usr/bin/env bash
# Copy the release-attach pieces from an open-shaders checkout into this repo so the
# workflow under test runs unmodified. Usage: sync-from-open-shaders.sh <open-shaders checkout>
set -euo pipefail
src="$1"
here="$(cd "$(dirname "$0")" && pwd)"
copy() { mkdir -p "$here/$(dirname "$1")"; cp -r "$src/$1" "$here/$1"; }
copy .github/workflows/_attach-release-artifacts.yaml
copy .github/actions/publish-release
copy .github/scripts
copy .github/configs/fomod-metadata.yaml
copy .github/configs/project.yaml
copy .github/assets/logo
copy tools/verify_shader_cache.py
copy tools/build-shader-cache.py
copy tools/feature-flip-impact.py
git -C "$src" log -1 --format='%H %s' > "$here/SYNCED_FROM.txt"
echo "Synced from $(cat "$here/SYNCED_FROM.txt")"
