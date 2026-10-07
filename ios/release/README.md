# TestFlight release

Salini **1.0 (4)**, bundle `design.salini.experience`, App Store Connect app `6819688748`.

**Uploaded successfully on 7 October 2026 at 15:24:46 (UTC+7).** Xcode returned `Upload succeeded`, `Uploaded Salini` and `EXPORT SUCCEEDED`; Apple confirmed the package was processing. See [upload receipt](build-4-upload-receipt.txt).

Source: `7420ff7dcd00081fdaee9fe3231a95347aaeccab`, branch `codex/salini-native-materials`, pushed to GitHub. Application implementation: `fe0265e`. This release adds the full offline catalog, official material models, personal project proposals, designer/showroom tools and the expanded two-complex factory demo.

## Testing availability

Upload and processing have been confirmed. Processing completion, internal testing availability and external Beta App Review for **build 4** have not yet been verified: App Store Connect in Chrome requires the account owner to sign in again. Existing groups and the existing public invitation are retained. Do not describe build 4 as externally approved or currently installable until the server confirms that state.

Existing public invitation: https://testflight.apple.com/join/mUb5H7bZ . The last recorded external review state for build 3 was Waiting for Review; that is historical evidence, not the current status of build 4.

Testing/review text for build 4 is prepared in [testflight-metadata.json](testflight-metadata.json). After sign-in, verify processing, add the new build to the existing internal group if needed, then select it in the existing external group and submit Beta App Review if Apple requires review. Do not send separate messages to testers unless requested.

## Verification

- iPhone 18 Pro / iOS 27: full functional suite **69 passed, 0 failed, 0 skipped**.
- Last PDF pagination change: **3 targeted tests passed**, including the real four-page proposal and 40-position proposal.
- All four pages of the small proposal and 22 pages of the large proposal visually reviewed. Screens, catalog photographs, material lighting and factory operation cycles reviewed on the Simulator.
- Archive: `ios/build/testflight/Salini-1.0-4.xcarchive`, Release / arm64, manually signed with the existing Salini TestFlight profile.
- Archived version/build verified as **1.0 / 4**. Privacy manifest present. `codesign --verify --deep --strict` passed.
- SHA-256 verification: all **318 CatalogMedia files** and all **eight film/loop files** match source. Archive contains **305 cards and 539 executions**.
- The source delta after testing consists only of the build number and release documentation. Physical-device AR, frame rates and full accessibility coverage remain documented in [QA.md](../QA.md).

## Reproduce archive and upload

Increment `CURRENT_PROJECT_VERSION` in `ios/project.yml` and `ios/Salini.xcodeproj/project.pbxproj` before another upload. Use a fresh archive path. Credentials and signing profiles remain in Xcode and the keychain, never Git.

```sh
xcodebuild -project ios/Salini.xcodeproj -scheme Salini \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath ios/build/testflight/DerivedData-4 \
  -archivePath ios/build/testflight/Salini-1.0-4.xcarchive \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY='Apple Distribution' DEVELOPMENT_TEAM=TQ5SCF3KQZ \
  PROVISIONING_PROFILE_SPECIFIER='Salini TestFlight' archive

xcodebuild -exportArchive \
  -archivePath ios/build/testflight/Salini-1.0-4.xcarchive \
  -exportPath ios/build/testflight/upload-1.0-4 \
  -exportOptionsPlist ios/release/UploadOptions.plist
```

Every implementation delivery must be committed and pushed. A requested TestFlight delivery also requires a successful upload and a precise report of the server processing/testing state; a local build alone is insufficient. Publishing to the App Store remains a separate action.
