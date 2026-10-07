# TestFlight release

Salini **1.0 (5)**, bundle `design.salini.experience`, App Store Connect app `6819688748`.

**Uploaded successfully on 7 October 2026 at 16:21:41 (UTC+7).** Xcode returned `Upload succeeded`, `Uploaded Salini` and `EXPORT SUCCEEDED`; Apple confirmed the package had begun processing. See [build 5 upload receipt](build-5-upload-receipt.txt).

Source: `c4138127e5116617443c6e78100ff710c970462b`, branch `codex/salini-native-materials`, pushed to GitHub before upload. Build 5 adds an event-focused Salini Inside entry, a swipeable glass business board and camera tracking of the selected order through inspection, packing, transfer and dispatch. Manual map exploration stays in place until the user returns to the current event.

Build 4 was also uploaded in this session before the Insight follow-up: [receipt](build-4-upload-receipt.txt). It added the full offline catalog, official material models, personal PDF proposals, designer/showroom tools and the expanded factory demo; all are retained in build 5.

## Testing availability

- **Upload:** succeeded. **Apple package processing:** started, confirmed by Xcode.
- **Processing completion / internal testing:** not yet verified.
- **External Beta App Review for build 5:** not submitted in this session. App Store Connect required the account owner to sign in again; Chrome then became unavailable to browser automation. Upload succeeded through Xcode's existing account independently.

Existing groups and [public invitation](https://testflight.apple.com/join/mUb5H7bZ) are retained. Do not describe build 5 as externally approved or currently installable until the server confirms that state. Historical build 3 was recorded as Waiting for Review; that is not the current state of builds 4 or 5.

Testing/review text is prepared in [testflight-metadata.json](testflight-metadata.json). After browser sign-in, verify processing, add build 5 to the existing internal group if needed, then select it in the existing external group and submit Beta App Review if required. Separate tester messages were not sent.

## Verification

- Full functional suite checkpoint 6.2: **79 passed, 0 failed**.
- Board polish checkpoint 6.4: **9 targeted tests passed**, including narrow-screen maximum text layout.
- Final checkpoint 6.6: **7 targeted tests passed**, including pan, fixed isometry, stable manual exploration, current-event return, order and trip following. Temporary camera tracing was removed before this run.
- UI reviewed on iPhone 18 Pro / iOS 27 Simulator: priority entry, metric swiping and selection, the Marea inspection → packing → forklift → truck 02 sequence, both trip releases, truck following, pause and manual return. Build 5 is installed and open in the simulator; saved projects were preserved.
- Archive: `ios/build/testflight/Salini-1.0-5.xcarchive`, Release / arm64, manually signed with the existing Salini TestFlight profile.
- Archived version/build verified as **1.0 / 5**. Privacy manifest present; `codesign --verify --deep --strict` passed.
- Catalog, material models, PDF features and collection-film assets are unchanged from build 4. Its receipt and Git history retain previous asset integrity and PDF validation evidence.
- Source changes after final tests are limited to build number and documentation. Physical-device frame rates and full accessibility coverage remain unverified; see [QA.md](../QA.md).

## Reproduce archive and upload

Increment `CURRENT_PROJECT_VERSION` in `ios/project.yml` and `ios/Salini.xcodeproj/project.pbxproj` before another upload. Use a fresh archive path. Credentials and signing profiles remain in Xcode and the keychain, never Git.

```sh
xcodebuild -project ios/Salini.xcodeproj -scheme Salini \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath ios/build/testflight/DerivedData-5 \
  -archivePath ios/build/testflight/Salini-1.0-5.xcarchive \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY='Apple Distribution' DEVELOPMENT_TEAM=TQ5SCF3KQZ \
  PROVISIONING_PROFILE_SPECIFIER='Salini TestFlight' archive

xcodebuild -exportArchive \
  -archivePath ios/build/testflight/Salini-1.0-5.xcarchive \
  -exportPath ios/build/testflight/upload-1.0-5 \
  -exportOptionsPlist ios/release/UploadOptions.plist
```

Every implementation delivery must be committed and pushed. A requested TestFlight delivery also requires a successful upload and a precise report of the server processing/testing state; a local build alone is insufficient. Publishing to the App Store remains a separate action.
