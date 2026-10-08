# TestFlight release

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
