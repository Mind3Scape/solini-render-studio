# TestFlight release — build 12

Salini **1.0 (12)**, bundle `design.salini.experience`, App Store Connect app `6819688748`.
Source: `def568a65e8246093a6093ff9f07c2fdcd312bf7`, branch `codex/salini-room-ar`, pushed to GitHub.

The signed archive includes native room AR for 13 official models, the new animated **«Камень изнутри»** Home block with six generated fragments, and the accepted Insight loading/material improvements. Home selections carry into the existing full 3D studio.

**Upload succeeded on 9 October 2026, 16:08:15 UTC+7**, after renewed account sign-in. Xcode returned `Upload succeeded` and `EXPORT SUCCEEDED`, exit0; Apple started processing. The earlier 12:05 credentials failure is preserved in the [upload receipt](build-12-upload-receipt.txt). **Distribution verified on 10 October 2026:** processing complete; build12 attached to Salini Internal; Salini Public Beta explicitly shows **1.0 (12) Approved**. The [public invitation](https://testflight.apple.com/join/mUb5H7bZ) is enabled and its anonymous landing page was verified. [Distribution proof](build-12-distribution-2026-10-10/distribution-status.json).

- Final focused integration tests: **13 passed, 0 failed**, normal command exit0. Earlier AR+Insight full suite: **141 passed**, with a separately recorded post-test runner finalization interruption.
- Signed archive verified; all195 audited assets verified. Six PNGs were losslessly re-encoded by Xcode; decoded pixels and alpha are identical.
- [Home reveal in the running app](../../research/room-ar-2026-10-09/evidence/essence/home-reveal.mp4) · [Material selection](../../research/room-ar-2026-10-09/evidence/essence/home-selection.mp4).
- [Validation and limits](build-12-validation.txt). Real room AR still requires physical-iPhone verification; simulator fallback is not a camera AR test.

Build12 distribution is complete; do not upload or submit it again. Build-specific What to Test was saved. Prepared app-wide description/review-note replacements were not saved; the existing metadata remains. The obsolete `opus-salini-insight` monitor was deleted on 10 October 2026. The new [2.5D graphics lab](../../research/insight-layered-poc-2026-10-10/README.md) is a separate simulator experiment for user evaluation and is not part of build12.

---

# TestFlight release — build 11

Salini **1.0 (11)**, bundle `design.salini.experience`, App Store Connect app `6819688748`.

Source: `bfccb0082c7234c8bab5e0a8d20a163b35b762c8`, branch `codex/salini-native-materials`, pushed to GitHub.
Upload completion was rejected by Apple on **9 October 2026 at 02:10 (UTC+7)** because Xcode account credentials expired. **Build 11 is not yet successfully uploaded.** [Upload attempt and retry instructions](build-11-upload-receipt.txt). Processing, internal testing and public beta availability are unverified.

This release replaces the shipping/QC graphics proof with interactive RealityKit rendering: textured materials,
baked Cycles lighting, interior environment captures, soft shadows, calibrated day/night exposure, and more detailed
workstations, services, planting and trailer geometry. The source product meshes are Salini assets.
Imported pallet orientation and loading clearance are corrected. Cargo following opens at a useful scale;
a labelled trailer cutaway reveals the selected load while the truck is docked, and truck selection fits the full vehicle.

Open **Profile → Salini Inside → Участок отгрузки**. Pan, zoom and orbit enter manual exploration;
**К действию** restores following. Day/night, zones, object selection and pause are available.
Business activity remains explicitly simulated. The scene is an improved architectural proof, still simpler than
concepts 01/02; it is not a photoreal final campus or real-time path tracer.

Opus 5.5 implemented the Swift and Blender changes. Codex directed repeated visual passes, researched/downloaded
assets, reviewed the code, built and checked the running app.

## Verification

- **133 tests passed, 0 failed**, 225.296 seconds on iPhone 18 Pro / iOS 27 simulator.
- Visual checks cover ordinary entry, day/night QC lighting, follow/manual controls, cutaway and truck framing.
- [60-second loading/departure recording](../../research/insight-poc-2026-10-08/qa-build11/ios-loading-motion.mp4).
- Release archive is signed and all **177 resource files** match their source SHA-256 hashes.
- [Validation and limits](build-11-validation.txt). Direct touch gestures and physical-device performance remain device QA.

## Distribution

[Public invitation](https://testflight.apple.com/join/mUb5H7bZ) currently has previously approved build 10.
Build 11 requires renewed Xcode Apple Account sign-in before retrying the verified archive upload. Browser verification also awaits renewed
App Store Connect sign-in; the Safari session expired. Do not infer build 11 approval from build 10 approval.

---

# Previous release — build 10

Salini **1.0 (10)**, bundle `design.salini.experience`, App Store Connect app `6819688748`.

Uploaded successfully on **8 October 2026 at 22:16:19 (UTC+7)**. Apple upload service returned
`Upload succeeded` and `EXPORT SUCCEEDED`. Processing completed, the internal group is attached,
and **Salini Public Beta shows build 1.0 (10) Approved** after submission.
[Upload and distribution receipt](build-10-upload-receipt.txt).

Source: `509dc3024796460e53a2bc79ff4da007a7fcc65f`, branch `codex/salini-native-materials`, pushed before upload.

Build 10 adds an interactive shipping/quality-control scene accessible from **Profile → Salini Inside → Участок отгрузки**.
It includes fixed isometric pan/zoom, day/night lighting, real Salini product geometry, downloadable industrial props,
selectable batches/forklift/truck, and a continuous loading/departure demonstration. Opus 5.5 implemented the scene and
Blender pipeline; Codex researched and downloaded source assets, directed multiple visual passes, reviewed and tested.

## Verification

- Full suite: **119 passed, 0 failed, 0 skipped**, 236.913 seconds.
- iPhone 18 Pro / iOS 27 simulator: normal entry, day/night, zoom, pause, accessible object selection and cards checked.
- A 279.77-second recording shows the live loading/departure cycle. [42-second excerpt](../../research/insight-poc-2026-10-08/qa/ios-departure.mp4).
- Release archive signed with the existing Salini TestFlight profile; signature verified.
- All 71 files of the new 3D resource kit match their accepted source SHA-256 hashes in the archive.
- [Validation and limitations](build-10-validation.txt): direct pinch/drag still require device QA, no physical-device frame-rate or thermal measurement.
- This is a bounded graphics proof with simulated industrial data, not a measured digital twin or live production control.

## Distribution

[Public invitation](https://testflight.apple.com/join/mUb5H7bZ).
Build 10 has cleared external Beta App Review and was added to Salini Public Beta with automatic
tester notification enabled. [App Store Connect proof](../../research/insight-poc-2026-10-08/qa/testflight-build10-approved.png).

Prior release evidence: [build 9](build-9-upload-receipt.txt), [build 8](build-8-upload-receipt.txt), [build 7](build-7-upload-receipt.txt).
Publishing to the App Store is separate from TestFlight.
