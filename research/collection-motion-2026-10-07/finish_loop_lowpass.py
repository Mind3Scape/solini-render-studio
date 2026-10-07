#!/usr/bin/env python3
"""Pin a generated loop to its reveal's last frame, correcting only exposure/colour drift.

Successor to ../collection-films-2026-10-06/finish_loop.py. That script added the
full-resolution difference (anchor − first frame) to the clip. When leaves or water
in the generated first frame are not exactly where they are in the reveal's last
frame, that difference contains edges, and adding it paints a ghost of the reveal's
leaves over the moving ones for the first and last second — a dissolve in disguise
that also visually damps motion near the seam.

Here the residual is low-passed (two passes of a large box blur ≈ Gaussian, radius
~2% of the width), so only slow tonal drift is corrected. Structure is never
transferred. If the low-frequency residual is small but the full residual is large,
the clip does not actually start on the reveal's last frame: the script refuses it
instead of hiding the mismatch (override with --force for inspection only).

Run the region audit on the output afterwards (motion_regions.py); this script does
not create motion and cannot rescue a static take.

  python3 finish_loop_lowpass.py intro.mp4 generated-loop.mp4 finished-loop.mp4
"""
import argparse
import json
import subprocess

import numpy as np


def info(path):
    data = json.loads(subprocess.check_output(
        ["ffprobe", "-v", "error", "-show_streams", "-of", "json", path]))
    return next(t for t in data["streams"] if t["codec_type"] == "video")


def box(a, r):
    """Separable box blur with edge clamping, via cumulative sums."""
    for axis in (0, 1):
        pad = [(0, 0), (0, 0)]
        pad[axis] = (r + 1, r)
        p = np.pad(a, pad, mode="edge")
        c = np.cumsum(p, axis=axis)
        hi = np.take(c, np.arange(2 * r + 1, c.shape[axis]), axis=axis)
        lo = np.take(c, np.arange(0, c.shape[axis] - 2 * r - 1), axis=axis)
        a = (hi - lo) / (2 * r + 1)
    return a


def lowpass(planes, radius):
    out = []
    for plane, r in zip(planes, (radius, radius // 2, radius // 2)):
        out.append(box(box(plane, r), r))
    return out


def split(frame, w, h):
    y = frame[:w * h].reshape(h, w)
    u = frame[w * h:w * h * 5 // 4].reshape(h // 2, w // 2)
    v = frame[w * h * 5 // 4:].reshape(h // 2, w // 2)
    return [y, u, v]


def join(planes):
    return np.concatenate([p.ravel() for p in planes])


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("intro")
    p.add_argument("source")
    p.add_argument("output")
    p.add_argument("--radius", type=int, default=0, help="blur radius px (default 2%% of width)")
    p.add_argument("--max-structure", type=float, default=4.0,
                   help="refuse if the high-frequency part of the head residual exceeds this MAE")
    p.add_argument("--force", action="store_true")
    a = p.parse_args()

    meta = info(a.source)
    w, h = int(meta["width"]), int(meta["height"])
    assert meta["pix_fmt"] == "yuv420p", "keep the source YUV untouched"
    assert (int(info(a.intro)["width"]), int(info(a.intro)["height"])) == (w, h)
    radius = a.radius or max(8, w // 50)
    size = w * h * 3 // 2

    def frame(path, last=False):
        args = ["ffmpeg", "-v", "error"] + (["-sseof", "-0.042"] if last else []) + [
            "-i", path, "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "yuv420p", "-"]
        return np.frombuffer(subprocess.check_output(args), np.uint8).astype(np.float32)

    anchor, first, last = frame(a.intro, True), frame(a.source), frame(a.source, True)
    head_full, tail_full = anchor - first, anchor - last
    head = lowpass(split(head_full, w, h), radius)
    tail = lowpass(split(tail_full, w, h), radius)
    structure = float(np.abs(head_full - join(head)).mean())
    count = int(meta["nb_frames"])
    report = dict(source_frames=count, output_frames=count - 1, radius=radius,
                  head_residual_mae=float(np.abs(head_full).mean()),
                  head_lowpass_mae=float(np.abs(join(head)).mean()),
                  head_structure_mae=structure,
                  tail_residual_mae=float(np.abs(tail_full).mean()))
    print(json.dumps(report), flush=True)
    if structure > a.max_structure and not a.force:
        raise SystemExit(f"start frame differs structurally from the reveal end ({structure:.2f} MAE);"
                         " regenerate from the exact last frame instead of masking it")

    decoder = subprocess.Popen(["ffmpeg", "-v", "error", "-i", a.source, "-f", "rawvideo",
                                "-pix_fmt", "yuv420p", "-"], stdout=subprocess.PIPE)
    encoder = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo",
                                "-pixel_format", "yuv420p", "-video_size", f"{w}x{h}",
                                "-framerate", meta["avg_frame_rate"], "-i", "-", "-an",
                                "-c:v", "libx264", "-preset", "slow", "-crf", "18",
                                "-pix_fmt", "yuv420p", "-g", "24", "-flags", "+cgop",
                                "-movflags", "+faststart", a.output], stdin=subprocess.PIPE)
    head_flat, tail_flat = join(head), join(tail)
    try:
        for i in range(count):
            raw = decoder.stdout.read(size)
            if len(raw) != size:
                raise RuntimeError(f"incomplete source frame {i}")
            if i == count - 1:  # the duplicated endpoint; frame 0 follows it in the loop
                continue
            t = i / (count - 1)
            s = t * t * (3 - 2 * t)
            pixels = np.frombuffer(raw, np.uint8).astype(np.float32)
            pixels = pixels + head_flat * (1 - s) + tail_flat * s
            encoder.stdin.write(np.clip(np.rint(pixels), 0, 255).astype(np.uint8).tobytes())
    finally:
        decoder.stdout.close()
        encoder.stdin.close()
    assert decoder.wait() == 0 and encoder.wait() == 0


if __name__ == "__main__":
    main()
