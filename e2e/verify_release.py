"""Check the draft release a scenario produced against what that scenario must yield."""
import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# caches: runtimes that must ship as standalone assets; options: FOMOD picker options;
# fomod: whether the AIO must be FOMOD-wrapped; clang: whether the FOMOD must offer the clang-cl option.
CLANG_OPTION = "clang-cl build (experimental, may be faster)"
DEFAULT_OPTION = "Default build (recommended)"
EXPECT = {
    "valid": dict(caches={"SE", "VR"}, options={"SE/AE", "VR"}, fomod=True, clang=True),
    "bad-se-cache": dict(caches={"VR"}, options={"VR"}, fomod=True, clang=True),
    "truncated-vr-blob": dict(caches={"SE"}, options={"SE/AE"}, fomod=True, clang=True),
    "no-caches": dict(caches=set(), options=set(), fomod=True, clang=True),
    "no-clang": dict(caches={"SE", "VR"}, options={"SE/AE", "VR"}, fomod=True, clang=False),
    "bad-clang-dll": dict(caches={"SE", "VR"}, options={"SE/AE", "VR"}, fomod=True, clang=False),
    "aio-without-dll": dict(caches={"SE", "VR"}, options=set(), fomod=False, clang=True),
}


def run(*command):
    return subprocess.run(command, check=True, capture_output=True, text=True).stdout


def extract(archive, destination):
    subprocess.run(["7z", "x", "-y", f"-o{destination}", str(archive)], check=True, capture_output=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--scenario", required=True, choices=sorted(EXPECT))
    parser.add_argument("--tag", required=True)
    args = parser.parse_args()
    expect = EXPECT[args.scenario]
    failures = []

    def check(condition, message):
        print(("ok   " if condition else "FAIL ") + message)
        if not condition:
            failures.append(message)

    release = json.loads(run("gh", "release", "view", args.tag, "--json", "assets,isDraft"))
    names = sorted(asset["name"] for asset in release["assets"])
    print("assets:", names)
    check(release["isDraft"], "release is a draft")

    work = Path(tempfile.mkdtemp())
    run("gh", "release", "download", args.tag, "--pattern", "*.7z", "--dir", str(work))

    for runtime in ("SE", "VR"):
        present = f"ShaderCache-{runtime}-{args.tag}.7z" in names
        check(present == (runtime in expect["caches"]), f"{runtime} cache asset {'present' if present else 'absent'} as expected")

    aio = next((work / n for n in names if re.fullmatch(r"CommunityShaders_AIO-.*\.7z", n)), None)
    check(aio is not None, "AIO asset present")
    if aio:
        tree = work / "aio"
        extract(aio, tree)
        has_fomod = (tree / "fomod" / "ModuleConfig.xml").is_file()
        check(has_fomod == expect["fomod"], f"AIO is {'FOMOD-wrapped' if has_fomod else 'the plain AIO'} as expected")
        dll_paths = [tree / "Core/SKSE/Plugins/CommunityShaders.dll", tree / "DefaultBuild/SKSE/Plugins/CommunityShaders.dll"] if has_fomod else [tree / "SKSE/Plugins/CommunityShaders.dll"]
        dll = next((path for path in dll_paths if path.is_file()), dll_paths[0])
        check(dll.is_file() == (args.scenario != "aio-without-dll"), "plugin DLL presence matches the scenario")
        if has_fomod:
            config = (tree / "fomod" / "ModuleConfig.xml").read_text(encoding="utf-8-sig")
            options = set(re.findall(r'<plugin name="([^"]+)"', config))
            wanted = set(expect["options"]) | ({CLANG_OPTION, DEFAULT_OPTION} if expect["clang"] else set())
            check(options == wanted, f"FOMOD options {sorted(options)} == {sorted(wanted)}")
            for option in options - {CLANG_OPTION, DEFAULT_OPTION}:
                subdir = {"SE/AE": "ShaderCache-SE-AE", "VR": "ShaderCache-VR"}[option]
                check((tree / subdir / "ShaderCache" / "Manifest.json").is_file(), f"{option} option files are staged")
            if CLANG_OPTION in options:
                staged = (tree / "ClangCL/SKSE/Plugins/CommunityShaders.dll").read_bytes()
                check(b"CLANG-MARKER" in staged, "clang option stages the clang DLL")
                default = (tree / "DefaultBuild/SKSE/Plugins/CommunityShaders.dll").read_bytes()
                check(b"MSVC-MARKER" in default, "default option stages the default (MSVC) DLL")
                check(not (tree / "Core/SKSE/Plugins/CommunityShaders.dll").exists(), "Core no longer carries a DLL")
                check("priority" not in config, "no same-path priority overwrite")
            else:
                check((tree / "Core/SKSE/Plugins/CommunityShaders.dll").is_file(), "Core keeps the default DLL when no clang page is offered")

    check(not any("ClangCL" in name for name in names), "no standalone clang asset is published")

    shutil.rmtree(work, ignore_errors=True)
    if failures:
        print(f"\n{len(failures)} check(s) failed", file=sys.stderr)
        return 1
    print("\nall checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
