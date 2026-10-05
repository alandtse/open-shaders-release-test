#!/usr/bin/env bash
# Package the clang-cl plugin DLL, under SKSE/Plugins so MO2/VFS installers root-detect it,
# plus a short readme, as a drop-in replacement for the matching AIO's DLL.
#
# Usage: package-clang-dll.sh <dir containing the clang-cl AIO archive> <release tag> <output.7z>
set -euo pipefail

src_dir="$1"
tag="$2"
output="$(realpath -m "$3")"
min_dll_bytes=1000000

aio=$(find "$src_dir" -maxdepth 1 \( -name 'CommunityShaders_AIO-*.7z' -o -name 'CommunityShaders_AIO-*.zip' \) -print -quit)
if [ -z "$aio" ]; then
  echo "No AIO archive in $src_dir" >&2
  exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

7z x -y -o"$work/stage" "$aio" 'SKSE/Plugins/CommunityShaders.dll' >/dev/null
dll="$work/stage/SKSE/Plugins/CommunityShaders.dll"
if [ ! -s "$dll" ]; then
  echo "CommunityShaders.dll missing from $aio" >&2
  exit 1
fi
if [ "$(wc -c < "$dll")" -lt "$min_dll_bytes" ] || [ "$(head -c 2 "$dll")" != "MZ" ]; then
  echo "CommunityShaders.dll in $aio is not a plausible Windows DLL" >&2
  exit 1
fi

cat > "$work/stage/README_ClangCL.txt" <<README
Open Shaders ${tag}: experimental clang-cl build of the plugin DLL

This is the same source as the main release, compiled with clang-cl and ThinLTO
instead of MSVC. It is unsupported and may behave differently from the main build.
Early measurements showed lower CPU time in some render zones, but they came from
single runs and are not proven on every setup.

Install: with the matching ${tag} AIO already installed, replace
SKSE/Plugins/CommunityShaders.dll with the DLL in this archive. Do not mix versions.
To go back, restore the DLL from the AIO.

If you see a crash or a rendering problem, retest with the main DLL before reporting,
and say which build you were using.
README

mkdir -p "$(dirname "$output")"
rm -f "$output"
(cd "$work/stage" && 7z a -t7z -mx=7 "$output" SKSE README_ClangCL.txt >/dev/null)
echo "Packaged $output"
