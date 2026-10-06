# Ninfea — local film renderer

Offline Apple Silicon pipeline for the Salini iOS collection film. Swift + Metal compose independent generated botanical layers; **RifeMetal / Practical-RIFE 4.26 HQ** synthesizes intermediate water states and the in-between frame of every adjacent pair of composited frames. No cloud inference is used during rendering. Image creation was done earlier with built-in imagegen.

## Reproduce

Requirements: Apple Silicon Mac, Xcode with command line tools and Metal Toolchain, macOS 14+. SwiftPM downloads the pinned open-source dependency and bundled model on first use. The iOS app has no RIFE dependency; it contains the finished MP4.

From the repository root:

```sh
swift run -c release --package-path scripts/ninfea-render \
  --scratch-path ios/.build/ninfea-render NinfeaRender "$PWD" --preview

swift run -c release --package-path scripts/ninfea-render \
  --scratch-path ios/.build/ninfea-render NinfeaRender "$PWD"
```

Preview mode writes nine checkpoint PNGs. Full mode writes a timestamped `ninfea-film-*.mp4`, `poster-v2.png` and `render.json` into `ios/.build/ninfea-v2/`. Existing movies are preserved. Check previews before a complete render. The committed app resources are `ios/Salini/Resources/ninfea-film-v2.mp4` and `ninfea-poster-v2.png`; the renderer deliberately does not replace them automatically.

Input paths and generation prompts: [V2 assets](../../research/ninfea-cinema-2026-10-06/v2/), [prompts](../../research/ninfea-cinema-2026-10-06/v2/PROMPTS.md). The dry background comes from `ios/Salini/Resources/ninfea-interior.png`.

## Composition

- 0–2 s: locked empty pavilion.
- 2–10 s: empty / low / middle / high / full water states. RIFE computes the requested interpolation fraction; a cavity mask protects the original bathtub exterior from generated shape drift.
- 8.6–14 s: a shallow reflecting pool spreads from the tub foot. The product silhouette stays in front of the floor pass.
- 10–22 s: rear canopy, foreground planting and lilies unfold independently. Edge-rooted transforms keep all cropped layer boundaries outside the visible frame. The alpha pass is cleaned and explicitly premultiplied.
- 15–25 s: the vine tip follows a registered stem path up the body and over the rim. Leaf width grows behind the tip, with contact shadow on the product.
- 25–30 s: quiet garden; subtle leaf and water movement. The app holds the last frame, with deliberate replay.

The master is composed at 15 fps and RIFE synthesizes one flow-based intermediate per pair for 30 fps delivery. Water states also use RIFE at arbitrary timesteps. A 2.5% camera move is applied consistently to the entire composition. Output: H.264 High, 1024 × 1536, 30 fps, 30 seconds, 900 frames, silent.

The supplied growth paths and layer geometry direct the action. This is a 2.5D film, not a full 3D botanical/fluid simulation; frame interpolation cannot infer a convincing entire growth sequence from two unrelated pictures alone.

## Measured run

6 October 2026, Apple M4 Pro / 24 GB: **48.96 s**, 567 RIFE inferences, 22,476,609-byte film. Initial isolated HQ midpoint benchmark: approximately 120 ms at 1024 × 1536. End-to-end time includes composition, model inference and video encoding and varies with machine load. Exact run: [render.json](../../research/ninfea-cinema-2026-10-06/v2/render.json).

Sources are pinned in `Package.swift` and `Package.resolved`. The separately built CLI is also available locally at `.tools/rife-metal/.build/release/rife-metal`; that checkout is ignored by Git. The SwiftPM renderer is sufficient for reproduction and does not depend on that checkout.

## Open source

[RifeMetal](https://github.com/cinemore/rife-metal), revision `1fef4869a44fca32848102b9f6a774a20eb50db6`: Apache-2.0. Native Swift / Metal / MPSGraph inference, bundled Practical-RIFE 4.26 model. [Practical-RIFE](https://github.com/hzwer/Practical-RIFE): MIT, copyright (c) 2021 hzwer. The model and upstream code are downloaded by SwiftPM, not vendored or shipped in the iOS application. Retain upstream `LICENSE` and `THIRD-PARTY.md` when redistributing a built renderer or dependency. [Apple swift-argument-parser](https://github.com/apple/swift-argument-parser) is a transitive package dependency, Apache-2.0.
