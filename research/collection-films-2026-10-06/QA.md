# Delivered collection films and detailed campus

## Scope and collaboration

The user selected the three remaining Home stories (Aria, Opera, Greca) plus a living Ninfea ending. Opus 5.5 in the user's Claude Code session wrote the concepts and the FactoryScene / InsideVisuals / CampusOverview changes. Codex created the reference renders, generated the seven videos, implemented and tested playback, reviewed the Swift changes and verified the running app. No replacement of the catalog or new account integration is implied.

## Film delivery

| Story | Reveal | Living ending | Final edit |
|---|---:|---:|---|
| Ninfea | 12.04 s (existing v3) | 4.00 s | Existing garden reveal preserved; mature garden breathes without regrowth. |
| Aria | 8.04 s | 4.00 s | Coastal limestone pavilion; linen opens in a sea breeze. |
| Opera | 8.04 s | 4.00 s | Generated curtain closing was reversed during mastering to become the requested opening; final velvet and water retain very small movement. Playback itself is forward-only. |
| Greca | 5.00 s | 4.00 s | First 120 source frames selected before water overflows the channel. The final scene retains the partially filled right-hand channel, with sea shimmer and water reflections. |

All films are 1176 × 1764, native 24 fps, silent. Each ending was generated from the actual selected reveal endpoint as both reference anchors. Inputs were official product photographs saved in Resources; environments are generated interpretations, not real installations or CAD-verified product geometry. The app's Sources and Data screen describes this distinction.

`generation-results.json` contains the seven Higgsfield job IDs and original result URLs. The three generated still anchors, `STILL-PROMPTS.json`, `OPUS-CONCEPTS.md`, `reveal-jobs.json` and `loop-jobs.json` preserve the direction and generation inputs. Aria's still direction: preserve the actual white bowl and black petal wings, in a luminous limestone coastal pavilion with two ivory veils, a quiet sea horizon, fixed elevated frontal camera and generous upper negative space.

Kling generated slight endpoint texture/exposure differences even with identical anchors. `finish_loop.py` removes the small endpoint residual in native YUV, smoothly across the generated motion; it does not spatially warp, reverse, or replace the movie with dissolving stills. The duplicate endpoint is omitted. Each loop is exactly 96 frames. There are no player crossfades or seek-based loop resets.

The delivered reveal-to-loop SSIM is **0.9942–0.9958**. Per-frame difference checks confirm continuing motion and no identical adjacent frames. `asset-manifest.json` records dimensions, movement/seam measurements and SHA-256 hashes. These numerical checks complement visual review; they do not establish a pixel-perfect CAD reconstruction or guarantee every viewer will perceive the loop seam identically.

Generation used **60 credits**, from 67 to a verified balance of **7**. No extra credits purchased.

## Native playback

- One AVQueuePlayer surface plays the reveal and then an AVPlayerLooper ending.
- No Play control, progress bar, automatic collection paging or final frozen frame.
- A new visit restarts the reveal; repeated visibility updates do not restart it.
- Only the selected visible collection owns an active decoder. Offscreen views release video resources; background playback pauses.
- Reduce Motion uses the final composition. The source aspect ratio is preserved with aspect fill, never stretched.
- A test attaches the actual cinema view to an iOS window, waits for the reveal and a completed ambient cycle, then verifies offscreen release and a fresh visit.

## Inside review and correction

The production map now distinguishes mixing, moulds, curing, extraction/polishing, inspection, packing and warehouse equipment, with stage-specific architectural details and stronger accents. Furniture and mirrors remain kitting items, not an assertion of Salini's manufacturing process. Equipment is illustrative.

The first visual check found static merged buildings displaced from their lots while animated nodes stayed correctly positioned. Opus corrected `consolidate` to flatten detached identity-space subtrees and preserve local coordinates. A regression test now checks the rendered bounds of every building against its lot. It also checks that live machinery survives merging and responds to pause/resume.

Final iPhone screenshots cover the whole site, casting, finishing and warehouse. Fixed isometry, generous roads, open selected roofs, stage labels and map controls were retained. Warehouse colour remains restrained; the rack rows and loading docks are legible. Simulator screenshots are in `ios/evidence/*-collections-v1.png`.

## Validation

- iPhone 18 Pro, iOS 27, Debug: **34 tests passed, 0 failures**.
- iPad mini A17 Pro, iOS 27, Release with `ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES`: **34 tests passed, 0 failures**. The first Release test attempt omitted enable-testing and could not import the app from the test target; the corrected test invocation passed without changing production settings.
- No geometry, camera, dispatch or existing business-scenario regressions in the suite.
- `git diff --check` passed.
- Physical-device rendering performance has not been profiled in this change. The existing simulator SceneKit FloorPass diagnostic remains; the reviewed scene renders correctly.

This change was delivered in the simulator and GitHub branch, then published in TestFlight build **1.0 (3)** on 7 October 2026 (Asia/Bangkok). Build 3 is available internally and awaiting external Beta App Review; it replaces build 2 in the review queue. See `ios/release/preflight-status.json` for the release checkpoint.
