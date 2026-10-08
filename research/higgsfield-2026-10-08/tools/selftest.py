#!/usr/bin/env python3
"""Offline self-test of loop_interval.py on synthetic takes (no generated media needed).

1. PERIODIC: travelling water-like ripples with a 96-frame period over a still «product»
   block, 8 s at 24 fps. The scan must find a 96-frame interval with ~zero jump that passes
   the motion gates; cut must write exact frame counts and re-audit PASS.
2. DRIFTING: the same ripples plus slow aperiodic drift. No interval matches exactly; the
   scan must report a larger jump than PERIODIC (a gate, not a silent pass).
3. FROZEN TAIL: motion that eases out and holds a still frame for the last 1.5 s: the
   take's live share per window must show the dead tail.
4. BLEND: cutting DRIFTING with --blend reports a high-frequency dip (doubling) < 1.
Writes only to the ignored tmp/higgsfield-loop/selftest.
"""
import json
import os
import subprocess
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
OUT = os.path.join(ROOT, "tmp", "higgsfield-loop", "selftest")
TOOL = os.path.join(HERE, "loop_interval.py")
W, H, FPS, N = 360, 540, 24, 192
REGIONS = ["--region", "tub=0.30,0.45,0.70,0.65:rigid", "--region", "sea=0.0,0.0,1.0,0.40:alive"]


def take(path, drift=0.0, freeze_tail=False):
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    enc = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "gray",
                            "-s", f"{W}x{H}", "-framerate", str(FPS), "-i", "-", "-c:v", "libx264",
                            "-crf", "14", "-pix_fmt", "yuv420p", "-g", "24", path], stdin=subprocess.PIPE)
    phase_t = 0.0
    for t in range(N):
        speed = 1.0
        if freeze_tail and t >= N - 60:
            # Eases out over 1 s, then holds a still frame for the last 1.5 s.
            speed = 0.0 if t >= N - 36 else (N - 36 - t) / 24.0
        phase_t += speed
        p = 2 * np.pi * phase_t / 96.0
        sea = (128 + 40 * np.sin(x / 9.0 + 2 * p) + 30 * np.sin(y / 7.0 - 3 * p)
               + 20 * np.sin((x + y) / 13.0 + p) + drift * 25 * np.sin(x / 31.0 + 0.11 * phase_t))
        frame = sea
        frame[int(0.45 * H * 1.0):int(0.65 * H), int(0.30 * W):int(0.70 * W)] = 200  # still product
        enc.stdin.write(np.clip(frame, 0, 255).astype(np.uint8).tobytes())
    enc.stdin.close()
    assert enc.wait() == 0


def run(*args):
    r = subprocess.run([sys.executable, TOOL, *args], capture_output=True, text=True)
    return r.returncode, json.loads(r.stdout[r.stdout.index("{"):]) if "{" in r.stdout else r.stderr


def main():
    os.makedirs(OUT, exist_ok=True)
    checks = []
    periodic, drifting, frozen = (os.path.join(OUT, n) for n in ("periodic.mp4", "drifting.mp4", "frozen.mp4"))
    take(periodic)
    take(drifting, drift=1.0)
    take(frozen, freeze_tail=True)
    # Card aspect 1.5 = the synthetic 2:3 frame, so regions are in full-frame coordinates.
    common = ["--card-aspect", "1.5", *REGIONS, "--min-reveal", "0.5", "--max-reveal", "3.5", "--top", "5"]
    code, p = run("scan", periodic, *common)
    best = p["best"]
    checks.append(("periodic: an interval passes", best is not None))
    checks.append(("periodic: loop length is the 96-frame period", best and (best["b"] - best["a"]) % 96 == 0))
    checks.append(("periodic: seam jump < 0.5 median step", best and best["jump"] < 0.5))
    checks.append(("periodic: motion keeps direction", best and best["direction"] > 0.5))
    code_d, d = run("scan", drifting, *common)
    checks.append(("drifting: best jump is larger than periodic", d["top"][0]["jump"] > (best or {"jump": 0})["jump"]))
    code_f, f = run("scan", frozen, *common)
    tail = f["take_alive_by_window"][-2:]
    checks.append(("frozen tail: the held still frame reads as dead", tail[-1] < 0.18))
    if best:
        code_c, c = run("cut", periodic, "--a", str(best["a"]), "--b", str(best["b"]), "--out", os.path.join(OUT, "cut"),
                        "--name", "synthetic", "--version", "9", "--card-aspect", "1.5", *REGIONS)
        frames = lambda path: int(subprocess.check_output(["ffprobe", "-v", "error", "-count_frames", "-select_streams",
                                  "v:0", "-show_entries", "stream=nb_read_frames", "-of", "csv=p=0", path]).decode())
        checks.append(("cut: reveal has exactly a frames", frames(os.path.join(OUT, "cut", "synthetic-film-v9.mp4")) == best["a"]))
        checks.append(("cut: loop has exactly b−a frames", frames(os.path.join(OUT, "cut", "synthetic-loop-v9.mp4")) == best["b"] - best["a"]))
        checks.append(("cut: re-audit of the encoded files passes", c.get("audit_result") == "PASS"))
    # Closed take (start = end by construction): rotated loop has no joint larger than a normal step.
    if best:
        code_z, z = run("cut", periodic, "--a", "30", "--b", "192", "--closed", "--out", os.path.join(OUT, "closed"),
                        "--name", "synthetic", "--version", "7", "--card-aspect", "1.5", *REGIONS)
        m = json.load(open(os.path.join(OUT, "closed", "synthetic-v7-manifest.json")))
        checks.append(("closed: rotated loop keeps all 192 frames", m["interval"]["a"] == 30 and frames(os.path.join(OUT, "closed", "synthetic-loop-v7.mp4")) == 192))
        checks.append(("closed: largest joint ≤ 1.5× a normal step", m["joints"]["largest"][0]["ratio"] <= 1.5))
        # A perfect bridge (period 96): from frame 109 back to frame 40 ≡ 136 → loop take[40:136].
        bridge = os.path.join(OUT, "bridge.mp4")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", periodic, "-vf", "select='between(n\\,109\\,136)',setpts=N/24/TB",
                        "-c:v", "libx264", "-crf", "14", "-pix_fmt", "yuv420p", bridge], check=True)
        code_g, gq = run("cut", periodic, "--a", "40", "--b", "110", "--bridge", bridge, "--out", os.path.join(OUT, "bridged"),
                         "--name", "synthetic", "--version", "6", "--card-aspect", "1.5", *REGIONS)
        mb = json.load(open(os.path.join(OUT, "bridged", "synthetic-v6-manifest.json")))
        checks.append(("bridge: duplicated endpoints dropped", mb["bridge"]["dropped_head"] and mb["bridge"]["dropped_tail"]))
        checks.append(("bridge: loop = take + bridge = 96 frames", frames(os.path.join(OUT, "bridged", "synthetic-loop-v6.mp4")) == 96))
        checks.append(("bridge: joints invisible (≤ 1.5× step)", mb["joints"]["largest"][0]["ratio"] <= 1.5))
    # Whole closed clip: the periodic take (period 96, 192 frames) closes after its last frame.
    code_k, k = run("closure", periodic, "--card-aspect", "1.5", *REGIONS)
    checks.append(("closure: last frame is a continuation, not a duplicate", not k["last_is_duplicate"]))
    checks.append(("closure: whole clip chosen, joint ≈ one step", k["chosen_b"] == 192 and 0.5 <= [o for o in k["options"] if o["b"] == 192][0]["joint_step"] <= 1.5))
    checks.append(("closure: passes", k["passes"]))
    top = d["top"][0]
    code_b, b = run("cut", drifting, "--a", str(max(top["a"], 12)), "--b", str(top["b"]), "--out", os.path.join(OUT, "blend"),
                    "--name", "synthetic", "--version", "8", "--blend", "12", "--card-aspect", "1.5", *REGIONS)
    checks.append(("blend: doubling is reported (HF dip < 1)", b.get("blend") and b["blend"]["hf_ratio_min"] < 1.0))
    for name, ok in checks:
        print(("PASS " if ok else "FAIL ") + name)
    print(json.dumps(dict(periodic_best=best and {k: best[k] for k in ("a", "b", "jump", "seam_step", "direction", "speed_ratio")},
                          drifting_best={k: top[k] for k in ("a", "b", "jump", "seam_step", "direction")},
                          frozen_tail=tail, blend=b.get("blend") and {k: b["blend"][k] for k in ("frames", "hf_ratio_min")}), indent=1))
    return 0 if all(ok for _, ok in checks) else 1


if __name__ == "__main__":
    sys.exit(main())
