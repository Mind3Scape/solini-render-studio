#!/usr/bin/env python3
"""Adopt ONE visually accepted candidate (a `loop_interval.py cut` folder) as a collection's release.

Dry run by default: prints what would change. With --apply it
  1. copies the reveal, loop and both posters named in the cut manifest into ios/Salini/Resources;
  2. rewrites exactly that collection's entry in CollectionCinemaAssets.releases
     (ios/Salini/NinfeaCinema.swift): version, file names, loopFrames (measured), source;
  3. lists the previous release's files that nothing references any more; --exclude-old adds them to
     the app target's `excludes` in ios/project.yml (the files stay in the repository as sources),
     skipping any file a Swift source still names.
It never touches other collections, the build number, git, or the simulator. Run the release tests
afterwards (Codex): CinemaReleaseTests checks names, sizes, loop length, silence and poster aspect.

  python3 adopt_release.py --collection greca --cut tmp/.../candidates/greca --version v2 \\
      --source "Kling 3.0 Pro start=end, job …, sha256 …"            # dry run
  python3 adopt_release.py ... --apply [--exclude-old]
"""
import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
RES = os.path.join(ROOT, "ios", "Salini", "Resources")
SWIFT = os.path.join(ROOT, "ios", "Salini", "NinfeaCinema.swift")


def frames(path):
    return int(subprocess.check_output(["ffprobe", "-v", "error", "-count_frames", "-select_streams", "v:0",
                                        "-show_entries", "stream=nb_read_frames", "-of", "csv=p=0", path]).decode())


def entry_pattern(collection):
    return re.compile(r"(    \." + collection + r": CinemaRelease\(\n)(.*?)(\),\n)", re.S)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--collection", required=True, choices=["ninfea", "aria", "opera", "greca"])
    p.add_argument("--cut", required=True, help="folder written by loop_interval.py cut")
    p.add_argument("--version", required=True, help='release label, e.g. "v2"')
    p.add_argument("--source", required=True, help="provenance: model, job id, take sha256")
    p.add_argument("--apply", action="store_true")
    p.add_argument("--exclude-old", action="store_true")
    a = p.parse_args()

    manifests = glob.glob(os.path.join(a.cut, "*-manifest.json"))
    if len(manifests) != 1:
        raise SystemExit(f"expected one manifest in {a.cut}, found {manifests}")
    m = json.load(open(manifests[0]))
    if m["collection"] != a.collection:
        raise SystemExit(f"manifest is for {m['collection']}, not {a.collection}")
    files = m["files"]
    if not files.get("intro"):
        raise SystemExit("the app's player needs a reveal file (cut with a ≥ 1)")
    names = dict(intro=files["intro"], loop=files["loop"], start=files["start_poster"], final=files["final_poster"])
    for k, f in names.items():
        if not os.path.exists(os.path.join(a.cut, f)):
            raise SystemExit(f"missing {f}")
    loop_frames = frames(os.path.join(a.cut, names["loop"]))
    if loop_frames != m["interval"]["loop_frames"]:
        raise SystemExit(f"loop file has {loop_frames} frames, manifest says {m['interval']['loop_frames']}")

    swift = open(SWIFT, encoding="utf-8").read()
    match = entry_pattern(a.collection).search(swift)
    if not match:
        raise SystemExit(f"no .{a.collection} entry in {SWIFT}")
    old_body = match.group(2)
    old_files = re.findall(r'"([^"]+\.(?:png|jpg))"|intro: "([^"]+)"|loop: "([^"]+)"', old_body)
    old = set()
    for png, intro, loop in old_files:
        old |= {x + ".mp4" if x and not x.endswith((".png", ".jpg")) else x for x in (png, intro, loop) if x}
    stem = lambda f: os.path.splitext(f)[0]
    source = a.source.replace("\\", "\\\\").replace('"', '\\"')
    new_body = (f'      version: "{a.version}", intro: "{stem(names["intro"])}", loop: "{stem(names["loop"])}",\n'
                f'      startPoster: "{names["start"]}", finalPoster: "{names["final"]}", loopFrames: {loop_frames},\n'
                f'      source: "{source}"')
    new_swift = swift[:match.start(2)] + new_body + swift[match.end(2):]
    new_files = {names["intro"], names["loop"], names["start"], names["final"]}
    stale = sorted(f for f in old - new_files if os.path.exists(os.path.join(RES, f)))

    print(f"{a.collection}: {m['interval']['mode']} a={m['interval']['a']} b={m['interval']['b']} "
          f"reveal {m['interval']['reveal_seconds']} s, loop {loop_frames} frames ({m['interval']['loop_seconds']} s)")
    print("copy →", ", ".join(sorted(new_files)))
    print("entry before:\n" + old_body + "\nentry after:\n" + new_body)
    print("previous files now unreferenced:", stale or "none")
    if not a.apply:
        print("dry run — nothing changed (use --apply)")
        return 0
    for f in new_files:
        shutil.copy2(os.path.join(a.cut, f), os.path.join(RES, f))
    with open(SWIFT, "w", encoding="utf-8") as out:
        out.write(new_swift)
    if a.exclude_old:
        sources = glob.glob(os.path.join(ROOT, "ios", "Salini", "*.swift"))
        code = "".join(open(x, encoding="utf-8").read() for x in sources)
        project = os.path.join(ROOT, "ios", "project.yml")
        yml = open(project, encoding="utf-8").read()
        anchor = "        excludes:\n"
        if anchor not in yml:
            raise SystemExit("no app-target excludes list in project.yml")
        added = []
        for f in stale:
            line = f"          - Resources/{f}\n"
            if f'"{stem(f)}"' in code or f'"{f}"' in code:
                print("kept in bundle (still referenced in Swift):", f)
            elif line not in yml:
                yml = yml.replace(anchor, anchor + line, 1)
                added.append(f)
        with open(project, "w", encoding="utf-8") as out:
            out.write(yml)
        print("excluded from the bundle (kept as sources):", added or "none")
    print("applied; run CinemaReleaseTests and the playback tests")
    return 0


if __name__ == "__main__":
    sys.exit(main())
