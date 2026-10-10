# Salini Insight — architectural 2.5D proof v2

The user rejected v1. This revision returns to reference01: distant fixed isometric architecture, a detailed roof cutaway, quality/packing/warehouse context and a road. A small tow tractor replaces the large mismatched indoor platform. Large promotional text and automatic following were removed.

Built-in OpenAI image generation produced the master, empty background and transport. The first vehicle faced across the road; a targeted edit aligned it with the lane. Two extraction attempts had halos and were rejected. The accepted sprite was regenerated from the corrected master as a style/design reference; it is not a pixel-identical extraction. No scripted raster cleanup was used. Prompts and asset hashes are retained here.

## Implemented

- Same architecture art and vehicle in native SpriteKit and the browser companion.
- One40-second convoy cycle: stopped, forward departure, offscreen wrap, next arrival. Reset occurs only with the full vehicle outside the image. No visible backward towing or cargo teleport.
- Contact shadow, distance-driven wheel hubs, restrained beacon. No frozen people.
- Fixed camera and100–110% user zoom; no automatic zoom. Whole district remains visible.
- Quality/dispatch metrics open details and seek to the matching action. Pause, layer controls and timeline are available.
- Prototype data and architecture are explicitly illustrative.

## Verification

Native arm64 iOS27 build returned BUILD SUCCEEDED, exit0. Timeline invariant checks passed. Installed/launched as **Salini2.5D** (`design.salini.insight-lab`) on **Salini AR — QA / BC58C81F-D28D-4E26-A59E-F8689EED523F** only.

Native visual acceptance remains pending: Computer Use previously denied Device Hub access, and the user has not enabled it. Installation/process launch do not establish native UI quality.

Browser scene visually checked at402×874 and default viewport. Pause was stable at20.32s across observations; details/action, zoom cap, timeline and layer controls checked. [Actual browser screenshot](evidence/browser-iphone.jpg). This screenshot is not iOS evidence.

Open <http://127.0.0.1:8795/v2/> while the companion server is running. Native source is in `../native/`; run `sh Checks/run.sh` and build scheme `SaliniInsightLab`. Current branch: `codex/salini-insight-layered-v2`.

The user has not accepted this direction. It remains a separate simulator graphics experiment; TestFlight12 and the main app are separate.
