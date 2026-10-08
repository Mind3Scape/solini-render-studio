#!/usr/bin/env python3
"""Find and cut a naturally moving loop interval inside ONE continuous generated take.

A Kling/Higgsfield take of 8 s that moves from its first to its last frame is cut as

    reveal = take[0, a)        loop = take[a, b)        (b ≤ last frame)

so the reveal→loop handoff is the take's own continuity (frame a−1 → a) and the only
artificial transition is the loop seam  b−1 → a. AVPlayerLooper then repeats [a, b).
No ping-pong, no slow-down, no still frames, no dissolve between stills.

`scan` measures every admissible (a, b) on the phone crop and ranks them by how much the
seam deviates from the take's own frame-to-frame motion:

* jump      — mean |F[a] − F[b]| in the moving area, in units of the take's median step.
              F[b] is what would naturally follow b−1; F[a] is what the loop shows instead.
              0 = exact continuation; ~1 = one extra step of change (normally invisible).
* local     — the same for the worst tile (8×6 grid): a breaking wave or foam that appears in
              one place is invisible in the frame mean but obvious on the phone.
* seam step — mean |F[a] − F[b−1]| / median step: the step actually displayed (≈1 is natural;
              ≪1 is a hitch/pause, ≫1 a pop).
* direction — correlation of the displayed seam difference F[a]−F[b−1] with the natural one
              F[b]−F[b−1]: > 0 means the motion keeps its direction across the seam.
* speed     — lagged-change (0.25 s) level just before b vs just after a: a ratio far from 1
              is a visible speed-up/slow-down at the seam.
* exposure  — |mean luma F[a] − mean luma F[b]| (global flicker).
* rigid     — mean |F[a] − F[b]| inside rigid (product) regions: the product must not jump.

The ranked candidates are then gated with motion_regions.py's own measurements on the loop
tripled exactly as the looper shows it (live share per 0.5 s window, rigid/alive regions).

`cut` writes frame-exact reveal and loop files from the full-resolution YUV source (no RGB
round trip), the two posters (reveal frame 0, loop frame 0) and a manifest JSON, and runs
motion_regions.py on the result. `--blend K` optionally crossfades the last K loop frames
with the K source frames leading into `a`. That is still a dissolve of moving footage: it is
reported with a doubling metric and must be justified at phone crop — prefer an interval
that passes without it, or another generative take.

  python3 loop_interval.py scan take.mp4 --region tub=0.25,0.48,0.70,0.66:rigid --top 8
  python3 loop_interval.py closure closed-take.mp4 --region ...      # whole start=end clip
  python3 loop_interval.py cut take.mp4 --a 52 --b 170 --out DIR --name greca --version 2 \\
      --region tub=0.25,0.48,0.70,0.66:rigid --region sea=0.10,0.28,0.95,0.40:alive

Requires ffmpeg/ffprobe and numpy. Never modifies the source.
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
MOTION = os.path.normpath(os.path.join(HERE, "..", "..", "collection-motion-2026-10-07"))
sys.path.insert(0, MOTION)
import motion_regions as mr  # noqa: E402  (reuse the accepted analyzer, do not fork it)
import finish_loop_lowpass as lowpass_finish  # noqa: E402  (same tonal-only correction as the accepted finisher)


# MARK: measurement

#: Mean blurred luma step (0-255, hero scale) below which frame-to-frame change is treated as
#: codec noise for normalisation. Measured on the shipped, nearly static loops: 0.01-0.07.
STEP_FLOOR = 0.25
#: Tile grid for the local (worst-tile) seam jump, matching motion_regions' defaults.
TILE_ROWS, TILE_COLS = 8, 6


def masks(regions, h, w):
    rigid = np.zeros((h, w), bool)
    alive = np.zeros((h, w), bool)
    for r in regions:
        ys, xs = mr.region_slice(r["rect"], h, w)
        (rigid if r["kind"] == "rigid" else alive)[ys, xs] = True
    moving = alive if alive.any() else ~rigid  # without alive regions: everything but the product
    return moving, rigid


def seam_table(F, moving, rigid, fps, a_range, len_range, lag):
    """Metrics for every admissible (a, b). F: blurred hero-scale gray frames (T, H, W)."""
    T = len(F)
    m = moving.astype(np.float32)
    msum = max(m.sum(), 1.0)
    rsum = rigid.sum()
    steps = np.array([float((np.abs(F[t + 1] - F[t]) * m).sum() / msum) for t in range(T - 1)])
    # Normalise by the take's own motion, but never by less than a codec-noise floor: on a
    # nearly frozen take a tiny median step would turn compression noise into «huge jumps».
    median_step = max(float(np.median(steps)), STEP_FLOOR)
    luma = F.mean(axis=(1, 2))
    lagged = np.array([float((np.abs(F[t] - F[t - lag]) * m).sum() / msum) if t >= lag else np.nan
                       for t in range(T)])
    flat_m = m.ravel()
    rows = []
    a_lo, a_hi = a_range
    n_lo, n_hi = len_range
    for a in range(a_lo, min(a_hi, T - 2) + 1):
        for b in range(a + n_lo, min(a + n_hi, T - 1) + 1):  # b ≤ T−1: F[b] must exist
            jump_img = np.abs(F[a] - F[b])
            jump = float((jump_img * m).sum() / msum) / median_step
            # Local pops (a wave breaking on the island in one frame) vanish in a frame mean:
            # the worst tile of the moving area, in the same median-step units.
            tiles = mr.tile_means((jump_img * m)[None], TILE_ROWS, TILE_COLS)[0]
            weights = mr.tile_means(m[None], TILE_ROWS, TILE_COLS)[0]
            local = float((tiles / np.maximum(weights, 1e-6))[weights > 0.5].max(initial=0.0)) / median_step
            seam = float((np.abs(F[a] - F[b - 1]) * m).sum() / msum) / median_step
            shown = (F[a] - F[b - 1]).ravel()[flat_m > 0].astype(np.float64)
            natural = (F[b] - F[b - 1]).ravel()[flat_m > 0].astype(np.float64)
            denom = float(np.sqrt((shown * shown).sum() * (natural * natural).sum())) or 1e-9
            direction = float((shown * natural).sum()) / denom
            before = np.nanmean(lagged[max(lag, b - lag):b]) if b - lag > lag else np.nan
            after = np.nanmean(lagged[a + lag:min(T, a + 2 * lag)]) if a + 2 * lag <= T else np.nan
            speed = float(after / before) if before and before > 0 and np.isfinite(after) else float("nan")
            rows.append(dict(
                a=a, b=b, seconds=round((b - a) / fps, 3), start_s=round(a / fps, 3),
                jump=round(jump, 3), local_jump=round(local, 3), seam_step=round(seam, 3), direction=round(direction, 3),
                speed_ratio=round(speed, 3) if np.isfinite(speed) else None,
                exposure=round(abs(float(luma[a] - luma[b])), 3),
                rigid=round(float(jump_img[rigid].mean()), 3) if rsum else None))
    return rows, dict(median_step=median_step, frames=T)


def score(row):
    """Lower is better. Jump dominates; seam step far from 1, reversed direction and speed
    changes are penalised; exposure flicker and product jumps are hard to forgive."""
    s = row["jump"] + 0.5 * row["local_jump"]
    s += 0.5 * abs(np.log(max(row["seam_step"], 1e-3)))
    s += 0.5 * max(0.0, -row["direction"])
    if row["speed_ratio"]:
        s += 0.5 * abs(np.log(max(row["speed_ratio"], 1e-3)))
    s += row["exposure"] / 2.0
    if row["rigid"] is not None:
        s += row["rigid"]
    return s


def loop_gate(frames, a, b, args, regions):
    """motion_regions' own measurements for the loop [a, b) shown three times."""
    loop = frames[a:b]
    lag = max(1, int(round(args.fps * args.lag)))
    cycles = np.concatenate([loop, loop, loop])
    change, _, _, frac = mr.timeline(cycles, args, lag)
    steps = np.abs(np.diff(mr.blur(cycles), axis=0)).mean(axis=(1, 2))
    n = len(loop)
    median_step = float(np.median(steps[:n - 1]))
    seam_ratio = float(steps[n - 1] / max(median_step, 1e-6))
    h, w = cycles.shape[1:]
    region_report = {}
    fails = []
    if frac.min() < args.min_alive_fraction:
        fails.append(f"min window live share {frac.min():.0%} < {args.min_alive_fraction:.0%}")
    if np.median(frac) < args.min_median_fraction:
        fails.append(f"median live share {np.median(frac):.0%} < {args.min_median_fraction:.0%}")
    if not args.seam_ratio[0] <= seam_ratio <= args.seam_ratio[1] and median_step > 0.05:
        fails.append(f"seam step ×{seam_ratio:.2f}")
    for r in regions:
        ys, xs = mr.region_slice(r["rect"], h, w)
        series = change[:, ys, xs].mean(axis=(1, 2))
        per = mr.windows(series, int(round(args.fps * args.window)))
        region_report[r["name"]] = dict(kind=r["kind"], mean=round(float(series.mean()), 3),
                                        min_window=round(float(per.min()), 3))
        if r["kind"] == "rigid" and series.mean() > args.rigid_max:
            fails.append(f"rigid {r['name']} moves ({series.mean():.2f})")
        if r["kind"] == "alive" and per.min() < args.alive:
            fails.append(f"{r['name']} stalls ({per.min():.2f})")
    return dict(median_alive=round(float(np.median(frac)), 3), min_alive=round(float(frac.min()), 3),
                seam_ratio=round(seam_ratio, 3), regions=region_report, failures=fails)


def product_drift(frames, regions, anchor=0):
    """Mean |F[t] − F[anchor]| inside rigid regions over the take: slow product morphing that
    a 0.25 s lag cannot see. Reported per second (max over the second)."""
    h, w = frames.shape[1:]
    out = {}
    for r in regions:
        if r["kind"] != "rigid":
            continue
        ys, xs = mr.region_slice(r["rect"], h, w)
        ref = frames[anchor, ys, xs]
        d = np.abs(frames[:, ys, xs] - ref).mean(axis=(1, 2))
        out[r["name"]] = [round(float(v), 2) for v in d]
    return out


def edge_drift(frames, regions, step=4):
    """Max over the take of the high-pass (edge) difference to frame 0 inside rigid regions,
    from unblurred frames. Smooth light (caustics, sun) barely changes edges; a moving or
    morphing product does. Compare with a region that must be still (a cliff) as noise floor."""
    h, w = frames.shape[1:]
    out = {}
    for r in regions:
        if r["kind"] != "rigid":
            continue
        ys, xs = mr.region_slice(r["rect"], h, w)
        seg = frames[::step, ys, xs]
        hp = seg - mr.blur(seg)
        out[r["name"]] = round(float(np.abs(hp - hp[0]).mean(axis=(1, 2)).max()), 2)
    return out


def phase_shift(a, b):
    """Sub-pixel translation of b relative to a (phase correlation with parabolic refinement)."""
    A = np.fft.fft2(a - a.mean())
    B = np.fft.fft2(b - b.mean())
    R = A * np.conj(B)
    R /= np.abs(R) + 1e-9
    r = np.fft.ifft2(R).real
    i, j = np.unravel_index(r.argmax(), r.shape)

    def refine(v, k):
        n = len(v)
        l, c, rr = v[(k - 1) % n], v[k], v[(k + 1) % n]
        d = (l - rr) / (2 * (l - 2 * c + rr) + 1e-9)
        x = k + d
        return x - n if x > n / 2 else x

    return float(refine(r[:, j], i)), float(refine(r[i, :], j))


def rigid_shift(path, regions, card_aspect, step=24):
    """Largest sub-pixel displacement (full-resolution px) of each rigid region relative to frame 0,
    sampled every `step` frames. Light changes do not move the correlation peak; a sliding or
    breathing product does. Reported, not gated: judge against a still reference region."""
    w, h = probe_size(path)
    raw = subprocess.check_output(["ffmpeg", "-v", "error", "-i", path, "-vf", f"select='not(mod(n\\,{step}))'",
                                   "-vsync", "0", "-f", "rawvideo", "-pix_fmt", "gray", "-"])
    frames = np.frombuffer(raw, np.uint8).reshape(-1, h, w).astype(np.float32)
    visible = min(h, int(round(w * card_aspect)))
    top = (h - visible) // 2
    out = {}
    for r in regions:
        if r["kind"] != "rigid":
            continue
        x0, y0, x1, y1 = r["rect"]
        crop = frames[:, top + int(y0 * visible):top + int(y1 * visible), int(x0 * w):int(x1 * w)]
        shifts = [phase_shift(crop[0], c) for c in crop[1:]]
        out[r["name"]] = round(max((abs(dy) ** 2 + abs(dx) ** 2) ** 0.5 for dy, dx in shifts), 2) if shifts else 0.0
    return out


def tail_motion(frames, args):
    """Live share per 0.5 s window across the whole take: catches a final slow-down/freeze."""
    lag = max(1, int(round(args.fps * args.lag)))
    _, _, _, frac = mr.timeline(frames, args, lag)
    return [round(float(v), 3) for v in frac]


def prepare(args):
    info = mr.probe(args.take)
    args.fps = info["fps"]
    frames, _ = mr.decode(args.take, args.width, args.card_aspect)
    return info, frames


def scan(args):
    info, frames = prepare(args)
    F = mr.blur(frames)
    h, w = F.shape[1:]
    moving, rigid = masks(args.region, h, w)
    fps = info["fps"]
    a_range = (int(round(args.min_reveal * fps)), int(round(args.max_reveal * fps)))
    len_range = (int(round(args.min_loop * fps)), int(round(args.max_loop * fps)))
    lag = max(1, int(round(fps * args.lag)))
    rows, base = seam_table(F, moving, rigid, fps, a_range, len_range, lag)
    if not rows:
        raise SystemExit("no admissible interval: take too short for the requested reveal/loop lengths")
    for r in rows:
        r["score"] = round(score(r), 3)
    rows.sort(key=lambda r: r["score"])
    top = rows[:args.top]
    for r in top:
        r["gate"] = loop_gate(frames, r["a"], r["b"], args, args.region)
        r["passes"] = not r["gate"]["failures"] and r["jump"] <= args.max_jump \
            and r["local_jump"] <= args.max_local_jump \
            and r["direction"] >= args.min_direction and r["exposure"] <= args.max_exposure
    report = dict(
        take=args.take, sha256=sha256(args.take), **{k: info[k] for k in ("width", "height", "fps", "duration")},
        frames=base["frames"], median_step=round(base["median_step"], 3), candidates_scanned=len(rows),
        take_alive_by_window=tail_motion(frames, args),
        product_drift=product_drift(F, args.region),
        edge_drift_max=edge_drift(frames, args.region),
        rigid_shift_px_max=rigid_shift(args.take, args.region, args.card_aspect),
        gates=dict(max_jump=args.max_jump, max_local_jump=args.max_local_jump, min_direction=args.min_direction, max_exposure=args.max_exposure,
                   min_alive_fraction=args.min_alive_fraction, min_median_fraction=args.min_median_fraction,
                   seam_ratio=list(args.seam_ratio), rigid_max=args.rigid_max),
        best=next((r for r in top if r["passes"]), None), top=top)
    print(json.dumps(report, indent=2, ensure_ascii=False))
    if args.json:
        with open(args.json, "w") as f:
            json.dump(report, f, indent=2, ensure_ascii=False)
    return 0 if report["best"] else 1


# MARK: cutting


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def yuv_frames(path, w, h):
    size = w * h * 3 // 2
    p = subprocess.Popen(["ffmpeg", "-v", "error", "-i", path, "-f", "rawvideo", "-pix_fmt", "yuv420p", "-"],
                         stdout=subprocess.PIPE)
    frames = []
    while True:
        raw = p.stdout.read(size)
        if len(raw) < size:
            break
        frames.append(np.frombuffer(raw, np.uint8))
    p.wait()
    return frames


ENCODE = dict(codec="h264", crf=16)


def encode(frames, w, h, rate, path):
    if ENCODE["codec"] == "hevc":
        # hvc1 tag: what AVFoundation expects for HEVC in MP4. Closed GOP for gapless looping.
        video = ["-c:v", "libx265", "-preset", "slow", "-crf", str(ENCODE["crf"]), "-tag:v", "hvc1",
                 "-x265-params", "keyint=24:min-keyint=24:open-gop=0:log-level=error"]
    else:
        video = ["-c:v", "libx264", "-preset", "slow", "-crf", str(ENCODE["crf"]), "-g", "24", "-flags", "+cgop"]
    enc = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pixel_format", "yuv420p",
                            "-video_size", f"{w}x{h}", "-framerate", rate, "-i", "-", "-an", *video,
                            "-pix_fmt", "yuv420p", "-movflags", "+faststart", path],
                           stdin=subprocess.PIPE)
    for f in frames:
        enc.stdin.write(f.tobytes())
    enc.stdin.close()
    assert enc.wait() == 0, f"encode failed: {path}"


def poster(frame, w, h, path):
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pixel_format", "yuv420p",
                    "-video_size", f"{w}x{h}", "-i", "-", "-frames:v", "1", path],
                   input=frame.tobytes(), check=True)


def probe_size(path):
    m = json.loads(subprocess.check_output(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                                            "stream=width,height", "-of", "json", path]))["streams"][0]
    return int(m["width"]), int(m["height"])


def luma_small(frame, w, h, width=180):
    """Hero-scale-ish gray image of one YUV420 frame (for joint measurements)."""
    y = frame[:w * h].reshape(h, w).astype(np.float32)
    step = max(1, w // width)
    return mr.blur(y[::step, ::step][None])[0]


def tone_match_bridge(bridge, end_frame, start_frame, w, h, max_structure=4.0):
    """Correct only the bridge's slow tonal/colour drift toward the two real frames it joins: the
    low-passed residual (take frame − bridge endpoint) is ramped from head to tail with smoothstep.
    Structure is never transferred; a large high-frequency residual refuses (regenerate instead)."""
    radius = max(8, w // 50)
    head_full = end_frame.astype(np.float32) - bridge[0].astype(np.float32)
    tail_full = start_frame.astype(np.float32) - bridge[-1].astype(np.float32)
    head = lowpass_finish.join(lowpass_finish.lowpass(lowpass_finish.split(head_full, w, h), radius))
    tail = lowpass_finish.join(lowpass_finish.lowpass(lowpass_finish.split(tail_full, w, h), radius))
    structure = max(float(np.abs(head_full - head).mean()), float(np.abs(tail_full - tail).mean()))
    report = dict(radius=radius, head_lowpass_mae=round(float(np.abs(head).mean()), 3),
                  tail_lowpass_mae=round(float(np.abs(tail).mean()), 3), structure_mae=round(structure, 3))
    if structure > max_structure:
        raise SystemExit(f"bridge endpoints differ structurally ({structure:.2f} MAE): regenerate, do not mask")
    n = len(bridge)
    out = []
    for i, f in enumerate(bridge):
        t = i / max(n - 1, 1)
        s = t * t * (3 - 2 * t)
        out.append(np.clip(np.rint(f.astype(np.float32) + head * (1 - s) + tail * s), 0, 255).astype(np.uint8))
    return out, report


def trim_bridge(end_frame, start_frame, bridge, w, h):
    """A generated bridge starts on the loop's last frame and ends on its first. Drop a bridge
    endpoint when it duplicates that frame (difference below one typical bridge step), so no frame
    is shown twice; keep it otherwise and report the size of each joint."""
    small = [luma_small(f, w, h) for f in bridge]
    steps = [float(np.abs(small[i + 1] - small[i]).mean()) for i in range(len(small) - 1)]
    typical = max(float(np.median(steps)), STEP_FLOOR)
    head = float(np.abs(small[0] - luma_small(end_frame, w, h)).mean())
    tail = float(np.abs(small[-1] - luma_small(start_frame, w, h)).mean())
    first = 1 if head < typical else 0
    last = len(bridge) - 1 if tail < typical else len(bridge)
    report = dict(frames_in=len(bridge), frames_used=last - first, typical_step=round(typical, 3),
                  head_vs_loop_end=round(head, 3), tail_vs_loop_start=round(tail, 3),
                  dropped_head=bool(first), dropped_tail=last < len(bridge),
                  bridge_live_by_step=[round(v, 2) for v in steps])
    return bridge[first:last], report


def loop_joints(loop, args, w, h, fps):
    """Every displayed step of the finished loop (wrap included) relative to its median: the
    largest steps are the joints (seam, anchor, bridge ends). Also the slowest 0.5 s."""
    small = [luma_small(f, w, h) for f in loop]
    n = len(small)
    steps = np.array([float(np.abs(small[(i + 1) % n] - small[i]).mean()) for i in range(n)])
    med = max(float(np.median(steps)), STEP_FLOOR)
    order = np.argsort(-steps)[:4]
    win = max(1, int(round(fps * 0.5)))
    slow = min(float(steps[i:i + win].mean()) for i in range(0, n - win + 1)) / med
    return dict(median_step=round(med, 3), largest=[dict(after_frame=int(i), ratio=round(float(steps[i] / med), 2))
                                                    for i in order], slowest_half_second_ratio=round(slow, 2))


def high_freq(gray):
    return np.abs(gray - mr.blur(gray[None])[0])


def blend_tail(src, a, b, k, w, h, moving_full, rigid_full):
    """Crossfade the last k loop frames toward the k source frames that lead into a.
    Returns new loop frames and a doubling report (high-frequency energy dip in the moving
    area at the blended frames vs the unblended loop; product mismatch between the pairs)."""
    if a < k:
        raise SystemExit(f"--blend {k} needs a ≥ {k} (source frames leading into a)")
    loop = [f.astype(np.float32) for f in src[a:b]]
    dips, rigid_diff = [], []
    plane = w * h
    for i in range(k):
        j = (b - a) - k + i              # index inside the loop
        lead = src[a - k + i].astype(np.float32)
        t = (i + 1) / (k + 1)
        s = t * t * (3 - 2 * t)
        mixed = loop[j] * (1 - s) + lead * s
        y_mix = mixed[:plane].reshape(h, w)
        y_own = loop[j][:plane].reshape(h, w)
        hf_mix = high_freq(y_mix)[moving_full].mean()
        hf_own = high_freq(y_own)[moving_full].mean()
        dips.append(float(hf_mix / max(hf_own, 1e-6)))
        if rigid_full.any():
            rigid_diff.append(float(np.abs(y_own - lead[:plane].reshape(h, w))[rigid_full].mean()))
        loop[j] = mixed
    out = [np.clip(np.rint(f), 0, 255).astype(np.uint8) for f in loop]
    return out, dict(frames=k, hf_ratio_min=round(min(dips), 3), hf_ratio_by_frame=[round(d, 3) for d in dips],
                     rigid_pair_mae_max=round(max(rigid_diff), 2) if rigid_diff else None)


def cut(args):
    ENCODE.update(codec=args.codec, crf=args.crf)
    info, frames = prepare(args)
    w, h = info["width"], info["height"]
    rate = subprocess.check_output(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                                    "stream=avg_frame_rate", "-of", "csv=p=0", args.take]).decode().strip()
    src = yuv_frames(args.take, w, h)
    if sum(bool(x) for x in (args.closed, args.bridge, args.blend)) > 1:
        raise SystemExit("--closed, --bridge and --blend are alternatives")
    if not (0 <= args.a < args.b <= len(src) - (0 if args.closed else 1)):
        raise SystemExit(f"need 0 ≤ a < b ≤ {len(src) - 1} (frame b must exist for the seam measurement)")
    os.makedirs(args.out, exist_ok=True)
    v = f"v{args.version}"
    intro_name, loop_name = f"{args.name}-film-{v}", f"{args.name}-loop-{v}"
    paths = dict(intro=os.path.join(args.out, intro_name + ".mp4"), loop=os.path.join(args.out, loop_name + ".mp4"),
                 start_poster=os.path.join(args.out, f"{args.name}-start-{v}.png"),
                 final_poster=os.path.join(args.out, f"{args.name}-final-{v}.png"))
    loop = src[args.a:args.b]
    joints = None
    if args.closed:
        # start=end take: the loop is the whole closed cycle rotated to begin at a, so the reveal
        # [0, a) hands over by its own continuity and the loop wraps (a−1 → a) naturally too; the
        # only joint is the generation's own anchor (last frame b−1 → frame 0).
        loop = src[args.a:args.b] + src[0:args.a]
    bridge_report = None
    if args.bridge:
        bridge = yuv_frames(args.bridge, w, h) if probe_size(args.bridge) == (w, h) else None
        if bridge is None:
            raise SystemExit(f"bridge {args.bridge} is {probe_size(args.bridge)}, take is {(w, h)}: "
                             "regenerate at the take's size or scale it explicitly first (reported)")
        tone = None
        if args.bridge_tone:
            bridge, tone = tone_match_bridge(bridge, src[args.b - 1], src[args.a], w, h)
        bridge, bridge_report = trim_bridge(src[args.b - 1], src[args.a], bridge, w, h)
        bridge_report["tone_match"] = tone
        loop = src[args.a:args.b] + bridge
    blend_report = None
    if args.blend:
        hh, ww = int(round(h)), int(round(w))
        # Region masks at full resolution in the visible-crop coordinates the regions use.
        visible = int(round(w * args.card_aspect))
        top = (h - visible) // 2 if visible < h else 0
        crop_h = min(h, visible)
        moving_c, rigid_c = masks(args.region, crop_h, w)
        moving_full = np.zeros((hh, ww), bool)
        rigid_full = np.zeros((hh, ww), bool)
        moving_full[top:top + crop_h] = moving_c
        rigid_full[top:top + crop_h] = rigid_c
        loop, blend_report = blend_tail(src, args.a, args.b, args.blend, w, h, moving_full, rigid_full)
    if args.a > 0:
        encode(src[:args.a], w, h, rate, paths["intro"])
    else:
        paths["intro"] = None
    encode(loop, w, h, rate, paths["loop"])
    poster(src[0], w, h, paths["start_poster"])
    poster(loop[0], w, h, paths["final_poster"])
    # Re-measure the encoded result with the shipped analyzer (region gates, three cycles, handoff).
    cmd = [sys.executable, os.path.join(MOTION, "motion_regions.py"), "--loop", paths["loop"]]
    if paths["intro"]:
        cmd += ["--intro", paths["intro"]]
    for r in args.region:
        cmd += ["--region", f"{r['name']}=" + ",".join(str(x) for x in r["rect"]) + f":{r['kind']}"]
    cmd += ["--heatmap", os.path.join(args.out, f"{args.name}-heat-{v}.png")]
    audit = subprocess.run(cmd, capture_output=True, text=True)
    audit_report = json.loads(audit.stdout) if audit.stdout.strip().startswith("{") else dict(error=audit.stderr)
    F = mr.blur(frames)
    hh2, ww2 = F.shape[1:]
    moving, rigid = masks(args.region, hh2, ww2)
    # The artificial joint: b−1 → a for an interval, the generation's anchor b−1 → 0 for a closed
    # take (with a bridge the joints are reported by loop_joints instead).
    start = 0 if args.closed else args.a
    rows, base = seam_table(F, moving, rigid, info["fps"], (start, start), (args.b - start, args.b - start),
                            max(1, int(round(info["fps"] * args.lag))))
    if args.bridge:
        rows = []
    manifest = dict(
        collection=args.name, version=args.version, source=dict(file=os.path.basename(args.take), sha256=sha256(args.take),
        job=args.job, fps=info["fps"], frames=len(src), width=w, height=h),
        encode=dict(ENCODE),
        interval=dict(a=args.a, b=args.b, reveal_frames=args.a, loop_frames=len(loop),
                      reveal_seconds=round(args.a / info["fps"], 3), loop_seconds=round(len(loop) / info["fps"], 3),
                      mode="closed-rotated" if args.closed else "bridged" if args.bridge else "interval"),
        files={k: (os.path.basename(p) if p else None) for k, p in paths.items()},
        seam=rows[0] if rows else None, blend=blend_report, closed=args.closed, bridge=bridge_report,
        joints=loop_joints(loop, args, w, h, info["fps"]),
        audit=dict(result=audit_report.get("result"), failures=audit_report.get("failures"),
                   loop=audit_report.get("loop"), intro=audit_report.get("intro"), regions=audit_report.get("regions")))
    with open(os.path.join(args.out, f"{args.name}-{v}-manifest.json"), "w") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
    print(json.dumps(dict(files=manifest["files"], interval=manifest["interval"], seam=manifest["seam"],
                          blend=blend_report, audit_result=manifest["audit"]["result"],
                          audit_failures=manifest["audit"]["failures"]), indent=2, ensure_ascii=False))
    return 0 if manifest["audit"]["result"] == "PASS" else 1


def closure(args):
    """Whole-clip analysis of a start=end (closed) take: is the last frame a duplicate of the first,
    which loop end b to use, how the anchor joint (b−1 → 0) compares with the clip's own steps,
    and whether motion holds everywhere (no settling toward the anchors)."""
    info, frames = prepare(args)
    F = mr.blur(frames)
    h, w = F.shape[1:]
    moving, rigid = masks(args.region, h, w)
    m = moving.astype(np.float32)
    msum = max(m.sum(), 1.0)
    flat = m.ravel() > 0
    T = len(F)
    steps = np.array([float((np.abs(F[t + 1] - F[t]) * m).sum() / msum) for t in range(T - 1)])
    med = max(float(np.median(steps)), STEP_FLOOR)
    lag = max(1, int(round(info["fps"] * args.lag)))

    def corr(x, y):
        x = x.ravel()[flat].astype(np.float64)
        y = y.ravel()[flat].astype(np.float64)
        d = float(np.sqrt((x * x).sum() * (y * y).sum())) or 1e-9
        return float((x * y).sum()) / d

    def lagged(t0, t1):
        vals = [float((np.abs(F[t] - F[t - lag]) * m).sum() / msum) for t in range(max(lag, t0), min(T, t1))]
        return float(np.mean(vals)) if vals else float("nan")

    duplicate = float((np.abs(F[T - 1] - F[0]) * m).sum() / msum) / med
    options = []
    for b in (T - 1, T):
        last = F[b - 1]
        shown = F[0] - last
        options.append(dict(
            b=b, loop_frames=b, loop_seconds=round(b / info["fps"], 3),
            joint_step=round(float((np.abs(shown) * m).sum() / msum) / med, 3),
            direction_vs_incoming=round(corr(shown, last - F[b - 2]), 3),
            direction_vs_outgoing=round(corr(shown, F[1] - F[0]), 3),
            speed_ratio=round(lagged(lag, 2 * lag + lag) / max(lagged(b - lag, b), 1e-6), 3)))
    best = min(options, key=lambda o: abs(np.log(max(o["joint_step"], 1e-3))) + max(0.0, -o["direction_vs_incoming"]))
    if duplicate < 0.5:
        best = options[0]  # the last frame repeats the first: never show it twice
    loop = frames[:best["b"]]
    gate = loop_gate(frames, 0, best["b"], args, args.region)
    report = dict(take=args.take, sha256=sha256(args.take), **{k: info[k] for k in ("width", "height", "fps", "duration")},
                  frames=T, median_step=round(med, 3), last_vs_first=round(duplicate, 3),
                  last_is_duplicate=duplicate < 0.5, options=options, chosen_b=best["b"],
                  take_alive_by_window=tail_motion(frames, args),
                  slowest_half_second=round(min(float(steps[i:i + int(info["fps"] / 2)].mean())
                                                for i in range(0, len(steps) - int(info["fps"] / 2) + 1)) / med, 3),
                  rigid_shift_px_max=rigid_shift(args.take, args.region, args.card_aspect),
                  gate=gate)
    report["passes"] = (not [f for f in gate["failures"] if not f.startswith("rigid")]
                        and 0.5 <= best["joint_step"] <= 2.0 and best["direction_vs_incoming"] >= 0)
    print(json.dumps(report, indent=2, ensure_ascii=False))
    if args.json:
        with open(args.json, "w") as f:
            json.dump(report, f, indent=2, ensure_ascii=False)
    return 0 if report["passes"] else 1


def bridge_frames(args):
    """Full-resolution, lossless start/end PNGs for a generated bridge from the loop's last frame
    (b−1) back to its first (a), plus the request facts. Kling's minimum duration is 3 s."""
    w, h = probe_size(args.take)
    src = yuv_frames(args.take, w, h)
    if not (0 <= args.a < args.b <= len(src)):
        raise SystemExit("need 0 ≤ a < b ≤ frames")
    os.makedirs(args.out, exist_ok=True)
    start = os.path.join(args.out, f"{args.name}-bridge-start-f{args.b - 1}.png")
    end = os.path.join(args.out, f"{args.name}-bridge-end-f{args.a}.png")
    poster(src[args.b - 1], w, h, start)
    poster(src[args.a], w, h, end)
    info = mr.probe(args.take)
    facts = dict(take=os.path.basename(args.take), take_sha256=sha256(args.take), a=args.a, b=args.b,
                 start_image=os.path.basename(start), end_image=os.path.basename(end),
                 size=[w, h], fps=info["fps"], loop_seconds_without_bridge=round((args.b - args.a) / info["fps"], 3),
                 bridge_seconds_min=3, note="Generate at the take's size, silent, locked camera, the same steady "
                 "motion as the take (no new event, no slowdown toward the end frame). Then: cut --bridge.")
    with open(os.path.join(args.out, f"{args.name}-bridge-request.json"), "w") as f:
        json.dump(facts, f, indent=2, ensure_ascii=False)
    print(json.dumps(facts, indent=2, ensure_ascii=False))
    return 0


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    br = sub.add_parser("bridge-frames")
    br.add_argument("take"); br.add_argument("--a", type=int, required=True); br.add_argument("--b", type=int, required=True)
    br.add_argument("--out", required=True); br.add_argument("--name", required=True)
    for name in ("scan", "cut", "closure"):
        q = sub.add_parser(name)
        q.add_argument("take")
        q.add_argument("--region", type=mr.parse_region, action="append", default=[])
        q.add_argument("--width", type=int, default=360)
        q.add_argument("--card-aspect", type=float, default=1.30)
        q.add_argument("--rows", type=int, default=8)
        q.add_argument("--cols", type=int, default=6)
        q.add_argument("--lag", type=float, default=0.25)
        q.add_argument("--window", type=float, default=0.5)
        q.add_argument("--alive", type=float, default=1.5)
        q.add_argument("--min-alive-fraction", type=float, default=0.18)
        q.add_argument("--min-median-fraction", type=float, default=0.30)
        q.add_argument("--rigid-max", type=float, default=1.0)
        q.add_argument("--seam-ratio", type=float, nargs=2, default=(0.5, 2.0))
    s = sub.choices["scan"]
    s.add_argument("--min-reveal", type=float, default=1.5, help="seconds before the loop starts")
    s.add_argument("--max-reveal", type=float, default=4.0)
    s.add_argument("--min-loop", type=float, default=3.0)
    s.add_argument("--max-loop", type=float, default=6.0)
    s.add_argument("--top", type=int, default=8)
    s.add_argument("--max-jump", type=float, default=1.5, help="seam jump in median steps")
    s.add_argument("--max-local-jump", type=float, default=3.0, help="worst tile jump in median steps")
    s.add_argument("--min-direction", type=float, default=0.0)
    s.add_argument("--max-exposure", type=float, default=0.8, help="mean luma jump (0-255)")
    s.add_argument("--json")
    sub.choices["closure"].add_argument("--json")
    c = sub.choices["cut"]
    c.add_argument("--a", type=int, required=True, help="first loop frame (reveal is [0, a))")
    c.add_argument("--b", type=int, required=True, help="loop end, exclusive; frame b must exist")
    c.add_argument("--out", required=True)
    c.add_argument("--name", required=True, help="collection id: ninfea, aria, opera, greca")
    c.add_argument("--version", type=int, required=True)
    c.add_argument("--job", help="generation job id for provenance")
    c.add_argument("--blend", type=int, default=0, help="crossfade frames at the seam (reported; avoid)")
    c.add_argument("--closed", action="store_true",
                   help="start=end take: loop = take[a:b) + take[0:a) (b = last distinct frame)")
    c.add_argument("--bridge", help="generated bridge clip from frame b−1 to frame a (same size)")
    c.add_argument("--bridge-tone", action="store_true",
                   help="low-pass tonal/colour match of the bridge to the frames it joins (reported)")
    c.add_argument("--codec", choices=("h264", "hevc"), default="h264")
    c.add_argument("--crf", type=int, default=16, help="quality; water needs a visual check above 18")
    args = p.parse_args()
    if args.cmd == "bridge-frames":
        return bridge_frames(args)
    if args.cmd == "closure":
        return closure(args)
    return scan(args) if args.cmd == "scan" else cut(args)


if __name__ == "__main__":
    sys.exit(main())
