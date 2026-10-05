"""Build synthetic release artifacts for one scenario under ./e2e-out/<artifact-name>/."""
import argparse
import json
import shutil
import struct
import subprocess
import sys
from pathlib import Path

DIGEST = "0123456789abcdef0123456789abcdef"
DLL_BYTES = 1_200_000


def dxbc(stage=0):
    return b"DXBC" + bytes(16) + struct.pack("<IIII4sIII", 1, 52, 1, 36, b"SHEX", 8, stage << 16 | 0x50, 2)


def write_cache(path, break_manifest=False, truncate_blob=False):
    (path / "Sky").mkdir(parents=True)
    (path / "Info.ini").write_text("[Cache]\nPluginVersion = 1-0-0\n", encoding="utf-8")
    blobs = ["Sky/a.pso", "Sky/b.pso"]
    for name in blobs:
        (path / name).write_bytes(dxbc())
    if truncate_blob:
        blob = path / blobs[0]
        blob.write_bytes(blob.read_bytes()[:20])
    manifest = "{not json" if break_manifest else json.dumps({"schemaVersion": 1, "entries": dict.fromkeys(blobs, DIGEST)})
    (path / "Manifest.json").write_text(manifest, encoding="utf-8")


def write_aio(directory, marker, dll_bytes=DLL_BYTES, with_dll=True):
    tree = directory.parent / f"{directory.name}-tree"
    shutil.rmtree(tree, ignore_errors=True)
    (tree / "SKSE/Plugins/CommunityShaders").mkdir(parents=True)
    (tree / "Shaders/Features").mkdir(parents=True)
    (tree / "Shaders/Features/Example.ini").write_text("[Info]\nVersion = 1-0-0\n", encoding="utf-8")
    if with_dll:
        (tree / "SKSE/Plugins/CommunityShaders.dll").write_bytes(b"MZ" + marker + bytes(max(dll_bytes - 2 - len(marker), 0)))
    directory.mkdir(parents=True)
    subprocess.run(["7z", "a", "-t7z", str((directory / "CommunityShaders_AIO-20261005.7z").resolve()), "."], cwd=tree, check=True, capture_output=True)
    shutil.rmtree(tree)


SCENARIOS = {
    "valid": {},
    "bad-se-cache": {"se": "broken-manifest"},
    "truncated-vr-blob": {"vr": "truncated-blob"},
    "no-caches": {"se": None, "vr": None},
    "no-clang": {"clang": None},
    "bad-clang-dll": {"clang": "tiny"},
    "aio-without-dll": {"aio": "no-dll"},
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--scenario", required=True, choices=sorted(SCENARIOS))
    parser.add_argument("--out", type=Path, default=Path("e2e-out"))
    args = parser.parse_args()
    shapes = {"se": "valid", "vr": "valid", "clang": "valid", "aio": "valid", **SCENARIOS[args.scenario]}
    shutil.rmtree(args.out, ignore_errors=True)

    write_aio(args.out / "dist-artifacts", b"MSVC-MARKER", with_dll=shapes["aio"] != "no-dll")
    for key, name in (("se", "ShaderCache-SE"), ("vr", "ShaderCache-VR")):
        shape = shapes[key]
        if shape is None:
            continue
        write_cache(args.out / name, break_manifest=shape == "broken-manifest", truncate_blob=shape == "truncated-blob")
    if shapes["clang"] is not None:
        write_aio(args.out / "dist-artifacts-clang-cl", b"CLANG-MARKER", dll_bytes=100 if shapes["clang"] == "tiny" else DLL_BYTES)
    print(f"Built scenario {args.scenario}: {sorted(p.name for p in args.out.iterdir())}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
