# TestFlight release

Salini **1.0 (7)**, bundle `design.salini.experience`, App Store Connect app `6819688748`.

**Uploaded successfully on 7 October 2026 at 21:01:03 (UTC+7).** After the user refreshed the Xcode Apple Account, the same signed archive was accepted: `Upload succeeded`, `Uploaded Salini`, `EXPORT SUCCEEDED`, exit 0. App Store Connect in authenticated Safari also showed build 7 **Processing**. See [upload receipt](build-7-upload-receipt.txt). The expired-credentials failure is retained as [attempt 1](build-7-upload-attempt-1.txt).

Source: `bf357d5947a5744323cc675880fafaea5df78ed9`, branch `codex/salini-native-materials`, pushed before archive/upload.

Build 7 improves the native material studio: real bundled HDR radiance, finish-specific microstructure, separate Gelcoat, softer shadows, restrained product exposure and Khronos PBR Neutral. Opus 5.5 implemented; Codex reviewed and returned visual/engineering corrections. Official product geometry is retained; fitting assignments are explicit. This is artistic visualization, not measured BRDF or calibrated RAL. PDF retains the accepted print lighting. New collection environments remain research; bundled films have not been replaced.

## Verification and availability

- Full final suite: **97 passed, 0 failed, 0 skipped**, 76.7 seconds. `/tmp/salini-material-realism-accepted.xcresult`.
- A preceding full run exposed a test-only USDZ polygon/index reader crash. It was fixed without removing geometry assertions; focused and full reruns passed.
- Native iPhone 18 Pro / iOS 27 UI: white comparison, RAL 6005, macro view. Noemi and Greca A/B renders cover white / green / anthracite and finishes. [QA](../QA.md).
- Archive: `ios/build/testflight/Salini-1.0-7.xcarchive`, Release arm64, manual existing Salini TestFlight profile. Version/build **1.0 / 7**, signature, privacy manifest, HDRI and third-party notices verified.
- Simulator build 7 installed and launched, saved projects preserved.
- **Upload:** succeeded. **Apple processing:** started, confirmed in App Store Connect. **Internal testing / external Beta App Review:** not yet confirmed for build 7. The authenticated Safari session is available, but user tab changes interrupted the follow-up operations; coordination was requested before further browser actions.
- The existing [public invitation](https://testflight.apple.com/join/mUb5H7bZ) does not prove availability of build 7. Previous build 6 upload succeeded: [receipt](build-6-upload-receipt.txt).

## Next server steps

Verify processing completion in App Store Connect, add to the existing internal group as needed, and select build 7 for the existing external group/review. Test text is prepared in [testflight-metadata.json](testflight-metadata.json). Existing build 3 was shown as Approved for Salini Public Beta; that is not evidence of build 7 approval.

Every implementation delivery must be committed and pushed. Upload is now complete; internal availability and external review remain separately tracked. Publishing to the App Store is a separate action.
