# Collection motion — 7 October 2026

## Delivery status

**Partial. The requested four finished living scenes are not delivered.**

The application still uses the existing collection movies. The new Ninfea loop was
generated and rejected in review: its motion is stronger, but remains concentrated
behind the tub, the water is too quiet, and the repeat boundary is still detectable.
It is retained here as evidence, not as an approved resource.

Higgsfield rejected the new 12-second Ninfea reveal (quoted 18 credits) when the
regular balance was 7. A 4-second Ninfea loop consumed 6; the remaining regular
balance is 1. The provider reported 100 trial credits but did not accept them for
the reveal request. No purchase or subscription change was made.

## Completed

- Opus 5.5 reviewed the player, the media and the earlier acceptance checks.
- The player keeps playback intent while the next queued item is loading, and
  resumes its current scene after an app interruption instead of replaying the reveal.
- A simulator regression observes three complete loop cycles, checks playback
  progress, and verifies interruption/resume. The existing offscreen/re-entry test
  also passes.
- All 35 iPhone 18 Pro / iOS 27 simulator tests passed after the final code changes.
- A region-based motion audit checks the actual phone-sized crop. Its thresholds
  are heuristics and do not replace visual review or prove that a clip is literally
  static. Existing movies and the new candidate fail these stricter targets.
- `ninfea-perimeter-keyframe.png` is a generated direction reference: developed
  greenery around the perimeter, bare tub, partially filled water. It is not used
  as a dissolving intermediate frame in the app.

## Remaining work

1. Ninfea: regenerate the reveal with overlapping perimeter growth, rising water,
   and mature leafy vines arriving at the tub late; regenerate a clearly living loop.
2. Aria: retain the reveal and generate a continuously moving fabric loop.
3. Opera: generate overlapping water rings and their reflections on the stone niche,
   with moving light during the reveal; then a steady cyclic ending.
4. Greca: show water advancing through the carved meander while the sea already
   moves; continue with travelling glints, current and caustics in the ending.
5. Inspect each take at the actual hero size for three repeats, including the
   intro-to-loop join. Integrate only accepted takes, then publish the completed build.

The direction and prompt drafts are in `OPUS-MOTION-REVIEW.md`; submitted prompts,
job ID and generation result are in `generation.json`. The rejected source and
candidate stay in this research folder. No new TestFlight build was uploaded for
this partial change; the previously uploaded 1.0 (3) is separate.

## Reproduce checks

From the repository root:

```sh
research/collection-motion-2026-10-07/audit_collections.sh
xcodebuild -project ios/Salini.xcodeproj -scheme Salini -configuration Debug \
  -destination 'platform=iOS Simulator,id=1917B285-7063-4C68-8096-8EB4F7318E2D' \
  -derivedDataPath ios/.build CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO -collect-test-diagnostics never test
```

The media audit currently returns failure, intentionally. Passing the app tests
confirms playback mechanics, not the visual quality of the source movies.
