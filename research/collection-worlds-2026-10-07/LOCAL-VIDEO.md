# Local video feasibility — LTX-2.3 on MLX (Greca I2V)

7 October 2026 · Opus. Internal research only: not a production asset, pending license and quality review. No changes to the native app, bundled films or Balance.

## Status: preparation frozen; inference not started — two concrete blockers

| | State |
|---|---|
| Code | `dgrauet/ltx-2-mlx` **v0.16.1**, commit `f0c12418afd601807199eaa1366584a2a53edcf0`, MIT |
| Environment | `uv 0.9.5` → `uv sync --frozen` from the repo's `uv.lock`, Python 3.12; mlx 0.32.2 on `Device(gpu, 0)`; ffmpeg 8.1 present; CLI `ltx-2-mlx` runs |
| Weights | downloading, public, not gated, no token (`token=False`): `dgrauet/ltx-2.3-mlx-q4` @ `56a5866d638ecfe37c54d348e88938235185c2d4` (only the 14 files the distilled I2V path loads, ≈ 21 GB of 60 GB); `mlx-community/gemma-3-12b-it-4bit` @ `86cc6a8dedbc456dd0e4af01a9d09f396f77e558` (≈ 8 GB) |
| Isolation | everything under `tmp/local-video/`, which has its own `.gitignore` (`*`); `git check-ignore` confirms. The repository's `tmp/` itself is **not** ignored (it shows as untracked), so nothing was put directly in `tmp/` and the repo `.gitignore` was not touched. HF cache and uv cache are inside the same folder |

**No local video exists yet.** Installed dependencies and a prepared command are not evidence of working inference, timing, peak memory or quality.

**Blocker 1 — incomplete weights.** The download is slow (< 1 MB/s at first, unauthenticated HF; the network was shared with the App Store Connect upload). At 19:54 it had 1.7 GB on disk of ≈ 29 GB. It keeps running in the background (`tmp/local-video/download.log`) and can be stopped without side effects.

**Blocker 2 — current memory pressure.** Observed during preparation: pressure level 4, then 2; swap nearly full at the time (Codex measured 35,779 / 36,864 MB after the archive). This describes the machine's state at the time, not its capacity: macOS grows swap on demand, and a 24 GB M4 Pro is not categorically unable to run this. Nothing was closed. **No inference starts automatically.**

## The single bounded take — prepared, not run

**Start conditions** (`tmp/local-video/run-greca-01.sh`); the script refuses to run unless all of these hold:
1. explicit approval: `LTX_RUN_APPROVED=1`, given by Codex when the resource window is open;
2. every weight file the distilled I2V path loads is present;
3. `kern.memorystatus_vm_pressure_level` is 1 (normal) at start; the precheck is logged.

Without approval it prints `not approved` and exits 2 — verified.

**Supervision** — `tmp/local-video/supervise.py`. This replaces the first draft, which put `/usr/bin/time` in front of the command and so watched and signalled only the wrapper's PID: the renderer child could have been orphaned, and its RSS was not measured.
- The renderer starts with `start_new_session=True`: it leads its own session and process group, and everything it spawns belongs to that group.
- Every 5 s the log `runs/greca-01/memory.log` records the pressure level, free %, swap and the **summed RSS of the group's processes**.
- Stop conditions:
  - 30 s of sustained critical pressure (level ≥ 4);
  - a hard **wall-time cap** of 3,600 s (`WALL_CAP`).
- Stopping:
  - SIGTERM to the **process group**, 15 s grace, then SIGKILL to the group;
  - then it verifies that the group is gone (`killpg(pgid, 0)` → `ProcessLookupError`, and no process left with that PGID);
  - a leader that exits normally but leaves processes in the group triggers the same cleanup;
  - nothing outside this group is ever signalled.
- After the run: max RSS of the child tree (`getrusage(RUSAGE_CHILDREN)`), wall time, reason and `group_cleaned_up` in `result.json`.
- Limit: a descendant that calls `setsid()` itself would leave the group. Neither the CLI nor ffmpeg does this, but it is not proven for every library path.

**Verified with harmless fixtures** (`/bin/sh` and `sleep`; no model load). All five left no process behind (`pgrep` empty afterwards):

| Fixture | Reason | Exit | Group cleaned |
|---|---|---|---|
| two background children, wall cap 3 s | `wall_time_cap` | SIGTERM | yes |
| simulated critical pressure (`SUPERVISE_FAKE_LEVEL=4`), 2 s | `critical_memory_pressure` | SIGTERM | yes |
| children that ignore SIGTERM | `wall_time_cap` → escalated | SIGKILL | yes |
| normal command | `exit` | 0 | yes |
| leader exits, background child left | `leader_exited_children_left` | 0 | yes |

**Exact command** (also written to `runs/greca-01/command.txt` at start):

```
.venv/bin/ltx-2-mlx generate --distilled \
  --model tmp/local-video/weights/ltx-2.3-mlx-q4 --gemma tmp/local-video/weights/gemma-3-12b-it-4bit \
  --prompt "$PROMPT" --image research/collection-worlds-2026-10-07/greca-tidal-keyframe-v2.png 0 1.0 \
  -H 512 -W 384 -f 97 --frame-rate 24 --seed 42 --low-ram --no-audio \
  -o tmp/local-video/runs/greca-01/greca-01-384x512-97f.mp4
```

Run through: `LTX_RUN_APPROVED=1 tmp/local-video/run-greca-01.sh`. The supervisor wraps the command, with `HF_HUB_OFFLINE=1` (no network, no credentials).

**Prompt** (verbatim):
> A locked-off static camera shot. A pale turquoise freestanding bathtub with an ivory rim stands perfectly still on a flat sandstone island in the open sea at golden hour. All around it the clear turquoise sea water moves continuously: small waves roll toward the island, ripples cross the shallow water, bright sun glints sparkle and drift on the surface, and water gently washes over the edges of the stone. The bathtub, the stone island and the distant cliffs stay rigid and unchanged. No camera movement, no zoom, no cuts.

**Parameters:**
- `--distilled`: 8 + 3 steps, no CFG; a half-resolution stage at 192 × 256, then ×2 latent upsample and refine at 384 × 512.
- The keyframe is exactly 3:4 (1086 × 1448): no distortion.
- 97 frames at 24 fps = 4.0 s; frame 0 is the keyframe at strength 1.0.

No timing or memory estimate is claimed for this machine before a real run.

## Licences — need a decision before any use beyond this research

- **Code** (`ltx-2-mlx`): MIT.
- **LTX-2.3 weights** (the q4 pack is a derivative): *LTX-2 Community License Agreement* (copy in the pack, upstream `Lightricks/LTX-2.3/LICENSE`). Entities with **annual revenue ≥ $10,000,000** must obtain a **paid commercial licence** to use LTX-2 or derivatives. Use and outputs are also bound by the agreement's restrictions and acceptable-use policy. Licensor claims no rights in outputs. Whether that threshold applies here, and whether any use counts as permitted, is unresolved: it is not a legal conclusion, and no research exemption is assumed. To be decided by David before any use of a result.
- **Gemma 3 text encoder**: Gemma Terms of Use and Prohibited Use Policy. The mlx-community repo is not gated, so no acceptance UI was used.
- No licence was accepted in any UI, no account or credential was touched.

## Known quality limits (no promise of production quality)

- The keyframe's bath is AI-generated, not the official Greca USDZ: identity is whatever the keyframe shows.
- q4 + distilled at 384 × 512 is the lowest-cost tier; the README itself rates distilled slightly below dev + CFG. Water motion might come out weak or warp-like; rigidity of the bath is not guaranteed.
- Acceptance would use the existing protocol (`research/collection-motion-2026-10-07`: `motion_regions.py`, live area per 0.5 s window, `rigid` bath region) and a real-size look on device.
