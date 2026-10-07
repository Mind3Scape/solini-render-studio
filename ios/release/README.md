# TestFlight release

Salini **1.0 (6)**, bundle `design.salini.experience`, App Store Connect app `6819688748`.

**Uploaded successfully on 7 October 2026 at 17:00:30 (UTC+7).** Xcode returned `Upload succeeded`, `Uploaded Salini` and `EXPORT SUCCEEDED`; Apple confirmed the package had begun processing. See [build 6 upload receipt](build-6-upload-receipt.txt).

Source: `139570df456e9275bce1249df1e94d96344fe265`, branch `codex/salini-native-materials`, pushed to GitHub before upload.

Build 6 refines the Salini Inside board after review with Opus 5.5: the active event comes first, followed by model-driven stages and compact metrics with semantic color and SF Symbols. Marea's progress follows inspection, packing and loading; accepted decisions retain their identity but show the live current status. Narrow layouts wrap stages, and large text scrolls without compression. Reference imagery and branding are not bundled.

Build 5 introduced event-focused entry and order/truck camera tracking; build 4 introduced catalog, materials, proposals and the expanded factory. Their upload receipts are retained: [build 5](build-5-upload-receipt.txt), [build 4](build-4-upload-receipt.txt).

## Testing availability

- **Upload:** succeeded. **Apple package processing:** started, confirmed by Xcode.
- **Processing completion / internal testing:** not yet verified.
- **External Beta App Review for build 6:** not submitted in this session. A fresh App Store Connect check in the in-app browser returned the login page. The account owner must sign in to verify availability and manage review. Upload succeeded through Xcode's existing account independently.

Existing groups and [public invitation](https://testflight.apple.com/join/mUb5H7bZ) are retained. Do not describe build 6 as externally approved or currently installable until the server confirms that state. Historical review states are not the current status of this build.

Testing/review text is prepared in [testflight-metadata.json](testflight-metadata.json). After sign-in, verify processing, add build 6 to the existing internal group if needed, then select it in the existing external group and submit Beta App Review if required. Separate tester messages were not sent.

## Verification

- Final complete suite checkpoint 7.3: **89 passed, 0 failed, 0 skipped**, 68.1 seconds. `/tmp/salini-insight-reference-final-20261007.xcresult`.
- The first run exposed a largest-text compression/ambiguity regression; it was fixed without weakening the test, and the full suite rerun passed.
- Model stages, typed progress, pause, live status after a taken decision, narrow 320/402 pt layouts, maximum text, read-only routes and the existing camera/manual-return behavior covered.
- UI checked on iPhone 18 Pro / iOS 27: held Marea, loading progress, teal active stage, dispatch 02, cobalt road status and selected metric, camera following and pause. [QA and screenshots](../QA.md).
- Archive: `ios/build/testflight/Salini-1.0-6.xcarchive`, Release / arm64, manually signed with the existing Salini TestFlight profile.
- Archived version/build verified as **1.0 / 6**. Privacy manifest present; `codesign --verify --deep --strict` passed.
- Catalog, material models, proposals, film assets and the campus scene are unchanged in this iteration. Saved projects are preserved. Physical-device FPS and full VoiceOver remain unverified.
- Changes after tests are limited to build number and documentation. The simulator has build 6 installed and open on the initial priority event.

## Reproduce archive and upload

Increment `CURRENT_PROJECT_VERSION` in `ios/project.yml` and `ios/Salini.xcodeproj/project.pbxproj` before another upload. Use a fresh archive path. Credentials and signing profiles remain in Xcode and the keychain, never Git.

```sh
xcodebuild -project ios/Salini.xcodeproj -scheme Salini \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath ios/build/testflight/DerivedData-6 \
  -archivePath ios/build/testflight/Salini-1.0-6.xcarchive \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY='Apple Distribution' DEVELOPMENT_TEAM=TQ5SCF3KQZ \
  PROVISIONING_PROFILE_SPECIFIER='Salini TestFlight' archive

xcodebuild -exportArchive \
  -archivePath ios/build/testflight/Salini-1.0-6.xcarchive \
  -exportPath ios/build/testflight/upload-1.0-6 \
  -exportOptionsPlist ios/release/UploadOptions.plist
```

Every implementation delivery must be committed and pushed. A requested TestFlight delivery also requires a successful upload and a precise report of the server processing/testing state; a local build alone is insufficient. Publishing to the App Store remains a separate action.
