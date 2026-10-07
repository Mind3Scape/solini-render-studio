#!/usr/bin/env python3
"""Strict, region-based motion audit for collection films (reveal + living loop).

Whole-frame SSIM/MAD accepts a nearly frozen clip: a few moving leaves, or codec
noise, average out to a "non-zero" number. This tool instead measures what a
person sees in the small iPhone hero:

* the film is decoded at hero scale (default 360 px wide = 1 px per point on a
  ~360 pt card) and cropped to the visible aspect-fill window (card is 1:1.30);
* a light blur removes codec shimmer, then motion is the absolute luma change
  over a 0.25 s lag (6 frames at 24 fps): slow ripples and sways that are
  invisible frame-to-frame become measurable, codec noise does not;
* the picture is split into tiles; a tile is ALIVE in a 0.5 s window when its
  lagged change exceeds the threshold;
* the loop is checked over three wrapped cycles (exactly what AVPlayerLooper
  shows), the reveal→loop handoff is checked on the concatenated sequence, and
  the reveal's last seconds are compared with the loop so an ease-out freeze
  before the handoff is caught;
* optional named regions: `rigid` regions (the product) must stay still,
  `alive` regions (water, foliage, fabric) must move in every window.

It never modifies footage. Requires ffmpeg/ffprobe and numpy.

Examples
  python3 motion_regions.py --loop ninfea-loop-v1.mp4 --intro ninfea-film-v3.mp4 \
      --region tub=0.18,0.42,0.82,0.80:rigid --region water=0.30,0.45,0.70,0.55:alive \
      --heatmap ninfea-heat.png
  python3 motion_regions.py --loop candidate.mp4            # loop only

Exit code 0 = PASS, 1 = FAIL (reasons printed in JSON).
"""
import argparse
import json
import subprocess
import sys

import numpy as np

FPS_DEFAULT = 24


def probe(path):
    data = json.loads(subprocess.check_output(
        ["ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", path]))
    video = next(s for s in data["streams"] if s["codec_type"] == "video")
    num, den = (int(v) for v in video["avg_frame_rate"].split("/"))
    return dict(width=int(video["width"]), height=int(video["height"]),
                fps=num / den if den else FPS_DEFAULT,
                duration=float(data["format"]["duration"]),
                audio=any(s["codec_type"] == "audio" for s in data["streams"]))


def decode(path, width, card_aspect):
    """Gray float frames at hero scale, cropped to the aspect-fill window."""
    info = probe(path)
    height = int(round(width * info["height"] / info["width"] / 2) * 2)
    raw = subprocess.check_output([
        "ffmpeg", "-v", "error", "-i", path, "-vf", f"scale={width}:{height}:flags=area",
        "-pix_fmt", "gray", "-f", "rawvideo", "-"])
    frames = np.frombuffer(raw, np.uint8).reshape(-1, height, width).astype(np.float32)
    visible = int(round(width * card_aspect))
    if visible < height:  # .resizeAspectFill crops top and bottom equally
        top = (height - visible) // 2
        frames = frames[:, top:top + visible]
    return frames, info


def blur(frames):
    """3x3 box blur per frame (removes codec mosquito noise, keeps real motion)."""
    padded = np.pad(frames, ((0, 0), (1, 1), (1, 1)), mode="edge")
    acc = np.zeros_like(frames)
    for dy in range(3):
        for dx in range(3):
            acc += padded[:, dy:dy + frames.shape[1], dx:dx + frames.shape[2]]
    return acc / 9.0


def lagged_change(frames, lag):
    """|f[t] - f[t-lag]| for t >= lag. Shape (T-lag, H, W)."""
    return np.abs(frames[lag:] - frames[:-lag])


def tile_means(change, rows, cols):
    t, h, w = change.shape
    h2, w2 = h - h % rows, w - w % cols
    c = change[:, :h2, :w2].reshape(t, rows, h2 // rows, cols, w2 // cols)
    return c.mean(axis=(2, 4))  # (T, rows, cols)


def windows(series, size):
    """Mean over consecutive non-overlapping windows along axis 0."""
    n = len(series) // size
    if n == 0:
        return series.mean(axis=0, keepdims=True)
    return series[:n * size].reshape(n, size, *series.shape[1:]).mean(axis=1)


def region_slice(spec, h, w):
    x0, y0, x1, y1 = spec
    return slice(int(y0 * h), max(int(y1 * h), int(y0 * h) + 1)), \
        slice(int(x0 * w), max(int(x1 * w), int(x0 * w) + 1))


def parse_region(text):
    name, rest = text.split("=", 1)
    coords, _, kind = rest.partition(":")
    values = [float(v) for v in coords.split(",")]
    if len(values) != 4 or kind not in ("rigid", "alive", ""):
        raise argparse.ArgumentTypeError(f"bad region {text!r}")
    return dict(name=name, rect=values, kind=kind or "alive")


def timeline(frames, args, lag):
    change = lagged_change(blur(frames), lag)
    tiles = tile_means(change, args.rows, args.cols)
    win = windows(tiles, int(round(args.fps * args.window)))
    alive = win > args.alive
    return change, tiles, win, alive.reshape(len(win), -1).mean(axis=1)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--loop", required=True)
    p.add_argument("--intro")
    p.add_argument("--width", type=int, default=360, help="hero width in px (≈ points)")
    p.add_argument("--card-aspect", type=float, default=1.30, help="card height / width")
    p.add_argument("--rows", type=int, default=8)
    p.add_argument("--cols", type=int, default=6)
    p.add_argument("--lag", type=float, default=0.25, help="seconds")
    p.add_argument("--window", type=float, default=0.5, help="seconds")
    p.add_argument("--alive", type=float, default=1.5,
                   help="tile mean lagged luma change (0-255) that counts as visible motion")
    p.add_argument("--min-alive-fraction", type=float, default=0.18,
                   help="every window must have at least this share of live tiles")
    p.add_argument("--min-median-fraction", type=float, default=0.30,
                   help="median window must have at least this share of live tiles")
    p.add_argument("--rigid-max", type=float, default=1.0,
                   help="max mean lagged change inside rigid regions")
    p.add_argument("--seam-ratio", type=float, nargs=2, default=(0.5, 2.0),
                   help="allowed ratio of seam step to median step")
    p.add_argument("--tail-ratio", type=float, default=0.6,
                   help="reveal's last seconds must keep this share of the loop's motion")
    p.add_argument("--region", type=parse_region, action="append", default=[])
    p.add_argument("--heatmap", help="write a PNG of where motion lives in the loop")
    args = p.parse_args()

    loop, loop_info = decode(args.loop, args.width, args.card_aspect)
    args.fps = loop_info["fps"]
    lag = max(1, int(round(args.fps * args.lag)))
    failures = []
    report = dict(loop=dict(file=args.loop, **loop_info, frames=len(loop)))

    # Three wrapped cycles: exactly what the looper shows, seams included.
    cycles = np.concatenate([loop, loop, loop])
    change, tiles, win, frac = timeline(cycles, args, lag)
    steps = np.abs(np.diff(blur(cycles), axis=0)).mean(axis=(1, 2))
    n = len(loop)
    median_step = float(np.median(steps[:n - 1]))
    seam_step = float(steps[n - 1])
    seam_ratio = seam_step / max(median_step, 1e-6)
    report["loop"].update(
        median_window_alive=float(np.median(frac)), min_window_alive=float(frac.min()),
        dead_windows=int((frac < args.min_alive_fraction).sum()), windows=len(frac),
        mean_lagged_change=float(change.mean()), median_step=median_step,
        seam_step=seam_step, seam_ratio=seam_ratio,
        alive_tile_map=(tiles.mean(axis=0) > args.alive).astype(int).tolist())
    if frac.min() < args.min_alive_fraction:
        failures.append(f"loop has {int((frac < args.min_alive_fraction).sum())} of {len(frac)} "
                        f"half-second windows with <{args.min_alive_fraction:.0%} live tiles "
                        f"(min {frac.min():.0%})")
    if np.median(frac) < args.min_median_fraction:
        failures.append(f"loop median live share {np.median(frac):.0%} < {args.min_median_fraction:.0%}"
                        " — motion too small to read in the hero")
    lo, hi = args.seam_ratio
    if not lo <= seam_ratio <= hi and median_step > 0.05:
        failures.append(f"seam step is {seam_ratio:.2f}× the median step (allowed {lo}–{hi})")

    # Regions: rigid product must not move, living regions must move in every window.
    h, w = cycles.shape[1:]
    region_report = {}
    blurred_change = change
    for region in args.region:
        ys, xs = region_slice(region["rect"], h, w)
        series = blurred_change[:, ys, xs].mean(axis=(1, 2))
        per_window = windows(series, int(round(args.fps * args.window)))
        entry = dict(kind=region["kind"], mean=float(series.mean()),
                     min_window=float(per_window.min()), max_window=float(per_window.max()))
        if region["kind"] == "rigid" and entry["mean"] > args.rigid_max:
            failures.append(f"rigid region {region['name']} moves (mean {entry['mean']:.2f})")
        if region["kind"] == "alive" and entry["min_window"] < args.alive:
            failures.append(f"region {region['name']} stalls (min window {entry['min_window']:.2f}"
                            f" < {args.alive})")
        region_report[region["name"]] = entry
    if region_report:
        report["regions"] = region_report

    if args.intro:
        intro, intro_info = decode(args.intro, args.width, args.card_aspect)
        _, _, _, intro_frac = timeline(intro, args, lag)
        tail_windows = max(1, int(round(1.5 / args.window)))
        tail = float(intro_frac[-tail_windows:].mean())
        loop_level = float(np.median(frac))
        joined = np.concatenate([intro[-int(args.fps * 2):], loop[:int(args.fps * 2)]])
        joined_steps = np.abs(np.diff(blur(joined), axis=0)).mean(axis=(1, 2))
        k = int(args.fps * 2) - 1
        join_ratio = float(joined_steps[k] / max(np.median(joined_steps), 1e-6))
        _, _, _, join_frac = timeline(joined, args, lag)
        report["intro"] = dict(
            file=args.intro, **intro_info, frames=len(intro),
            alive_by_window=[round(float(v), 3) for v in intro_frac],
            tail_alive=tail, loop_median_alive=loop_level,
            handoff_step_ratio=join_ratio, handoff_min_window_alive=float(join_frac.min()))
        if tail < max(args.tail_ratio * loop_level, args.min_alive_fraction):
            failures.append(f"reveal eases out: last 1.5 s live share {tail:.0%} "
                            f"(loop {loop_level:.0%}, floor {args.min_alive_fraction:.0%})")
        intro_median = float(np.median(intro_frac))
        report["intro"]["median_alive"] = intro_median
        if intro_median < args.min_alive_fraction:
            failures.append(f"reveal is mostly a still image: median live share {intro_median:.0%}")
        if not lo <= join_ratio <= hi and np.median(joined_steps) > 0.05:
            failures.append(f"handoff step is {join_ratio:.2f}× the surrounding median")
        if join_frac.min() < args.min_alive_fraction:
            failures.append(f"a half-second around the handoff is nearly still ({join_frac.min():.0%})")

    if args.heatmap:
        heat = change[:n].mean(axis=0)
        scaled = np.clip(heat / (args.alive * 3) * 255, 0, 255).astype(np.uint8)
        base = cycles[0].astype(np.uint8) // 3
        image = np.maximum(base, scaled)
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "gray",
                        "-s", f"{w}x{h}", "-i", "-", args.heatmap], input=image.tobytes(), check=True)
        report["heatmap"] = args.heatmap

    report["thresholds"] = dict(width=args.width, lag_s=args.lag, window_s=args.window,
                                alive=args.alive, min_alive_fraction=args.min_alive_fraction,
                                min_median_fraction=args.min_median_fraction)
    report["result"] = "PASS" if not failures else "FAIL"
    report["failures"] = failures
    print(json.dumps(report, indent=2, ensure_ascii=False))
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
