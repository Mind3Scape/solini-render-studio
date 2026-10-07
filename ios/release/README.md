# TestFlight release

Salini **1.0 (7)**, bundle `design.salini.experience`, App Store Connect app `6819688748`.

**Signed archive ready; upload blocked by expired Xcode account credentials.** On 7 October 2026 at 19:43:55 (UTC+7), Apple rejected the export after transmission with `Account credentials have expired` (`EXPORT FAILED`, exit 70). This is not a successful upload. See [attempt 1](build-7-upload-attempt-1.txt).

Source: `bf357d5947a5744323cc675880fafaea5df78ed9`, branch `codex/salini-native-materials`, pushed before archive/upload.

Build 7 improves the native material studio: real bundled HDR radiance, finish-specific microstructure, separate Gelcoat, softer shadows, restrained product exposure and Khronos PBR Neutral. Opus 5.5 implemented; Codex reviewed and returned visual/engineering corrections. Official product geometry is retained; fitting assignments are explicit. This is artistic visualization, not measured BRDF or calibrated RAL. PDF retains the accepted print lighting. New collection environments remain research; bundled films have not been replaced.

## Verification and availability

- Full final suite: **97 passed, 0 failed, 0 skipped**, 76.7 seconds. `/tmp/salini-material-realism-accepted.xcresult`.
- A preceding full run exposed a test-only USDZ polygon/index reader crash. It was fixed without removing geometry assertions; focused and full reruns passed.
- Native iPhone 18 Pro / iOS 27 UI: white comparison, RAL 6005, macro view. Noemi and Greca A/B renders cover white / green / anthracite and finishes. [QA](../QA.md).
- Archive: `ios/build/testflight/Salini-1.0-7.xcarchive`, Release arm64, manual existing Salini TestFlight profile. Version/build **1.0 / 7**, signature, privacy manifest, HDRI and third-party notices verified.
- Simulator build 7 installed and launched, saved projects preserved.
- **Upload:** failed (expired account credentials). **Processing/internal testing/external Beta App Review:** not established for build 7. App Store Connect browser is separately signed out; the user was asked to sign in.
- The existing [public invitation](https://testflight.apple.com/join/mUb5H7bZ) does not prove availability of build 7. Previous build 6 upload succeeded: [receipt](build-6-upload-receipt.txt).

## Resume after Apple sign-in

Xcode > Settings > Apple Accounts: refresh the existing account. The prepared archive can be sent again without rebuilding:

```sh
xcodebuild -exportArchive \
  -archivePath ios/build/testflight/Salini-1.0-7.xcarchive \
  -exportPath ios/build/testflight/upload-1.0-7-retry \
  -exportOptionsPlist ios/release/UploadOptions.plist
```

After confirmed upload, verify processing in App Store Connect, add to the existing internal group as needed, and select build 7 for the existing external group/review. Keep upload, internal availability and external approval distinct. Test text is prepared in [testflight-metadata.json](testflight-metadata.json).

Every implementation delivery must be committed and pushed. The TestFlight delivery remains incomplete until a successful upload; publishing to the App Store is a separate action.
