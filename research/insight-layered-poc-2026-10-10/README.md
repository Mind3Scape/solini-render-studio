# Salini Insight — fixed-camera 2.5D experiment

This is an isolated graphics alternative for David to assess before replacing any existing Insight implementation. It is not a new TestFlight release and does not change the shipping app.

## What is implemented

- Three raster layers generated with the built-in OpenAI `image_gen`: workshop, loaded carrier, empty carrier. The camera and light are fixed. The official Salini wordmark and existing app icon are reused unchanged.
- Native SpriteKit proof in `native/`, separate bundle `design.salini.insight-lab` / display name **Salini 2.5D**. Native controls provide pause, timeline, stage/object selection, bounded 100–115% zoom, translation-only follow, and a layer comparison sheet.
- One 42-second loop: carrier emerges from behind a foreground mask, stops at inspection, carries two products out of frame, returns empty, and waits behind the station. Cargo state changes only while outside view or hidden. Unloading/loading themselves are not shown.
- Native wheel spokes are phase-driven by travelled distance, not by wall-clock time. They stop with the platform and reverse on the return trip. Contact shadow, station occlusion, inspection light and a beacon are independent layers.
- Browser implementation and self-contained offline `preview.html` are also prepared. `python3 package_preview.py` bundles the three PNGs without image modification or external dependencies.
- `motion-proof.mp4` is a 42-second offline CoreGraphics motion render at 1280×854 / 30 fps. **It is not a recording of the iOS app or browser.** The camera/UI framing differs from the native view.

## Sources and limits

`prompts.json`, `empty-carrier-prompt.txt` and `asset-manifest.json` retain prompts and checksums. Built-in image generation was used, not Higgsfield. The worker atlas was rejected because the poses did not form a convincing walk cycle. No frozen people were placed in the scene.

The workshop, transport robot, process and product shapes are illustrative. They are not a measured Salini factory or exact official product meshes. The prototype deliberately does not yet establish people animation, machine articulation, unloading, dynamic relighting, a multi-zone campus, or sustained device performance. The source art resembles an interior architectural render more than the original aerial campus concept.

Generated layers retain alpha; no raster background removal or generative cleanup was performed with scripts. The CoreGraphics and SpriteKit code composite and animate the supplied layers.

## Validation and current status

- Native arm64 iOS 27 build: **BUILD SUCCEEDED**, exit0. The separate app is installed and launched on **Salini AR — QA, BC58C81F-D28D-4E26-A59E-F8689EED523F**, bundle `design.salini.insight-lab` (display name **Salini 2.5D**). The released Salini app is preserved.
- Shared native timeline checks passed: continuous phase boundaries/loop, bounded 120Hz movement, hidden cargo state changes, stopped inspection and empty return. Run `sh native/Checks/run.sh`.
- Browser proof visually checked at 1280×720. Pause/resume, stage selection, 115% zoom limit, object details → action, layer comparison and restart work. [Actual browser screenshot](evidence/browser-motion.jpg). Browser proof is not iOS acceptance.
- JavaScript syntax passed. Asset dimensions/alpha/checksums and offline movie frames checked.
- **Native visual acceptance remains pending:** Computer Use explicitly denied access to Device Hub (`com.apple.dt.Devices`). The user was asked once to enable that app. No alternate UI access was attempted. Native install/launch through the authorized developer CLI succeeded; no physical device or runtime performance claim is made.
- Only the designated Salini simulator may be used. Do not interact with another simulator or another project.

## Run

From `native/`, run `xcodegen generate`, then build scheme `SaliniInsightLab` for the simulator. Resources and source are self-contained. Generated build files are ignored. Open **Salini 2.5D** in the designated simulator.

The optional web companion is served at <http://127.0.0.1:8795/> during this session. To restart it, run `python3 -m http.server 8795 --bind 127.0.0.1` from this directory. Its UI/framing differs from the native proof.

## Release separation

The existing released app **1.0 (12) is Approved in Salini Public Beta**; proof is in `../../ios/release/build-12-distribution-2026-10-10/`. Its obsolete `opus-salini-insight` monitor was deleted on 10 October 2026. Do not upload build12 again.

This graphics lab and the release receipt are saved on **codex/salini-room-ar**. The lab is for David's assessment, not approval to replace Insight or distribute another build. Next: native visual acceptance after Device Hub access, then user evaluation.
