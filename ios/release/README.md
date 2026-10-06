# TestFlight release

The current release is Salini **1.0 (2)**, bundle `design.salini.experience`, App Store Connect app `6819688748`.

Build 2 includes the final bundled Ninfea film from commit `80ba1b0` and the enlarged Salini Inside campus. Release source is commit `57423b1`. Signing credentials and provisioning profiles remain in the local Xcode account and keychain; they are not stored in Git.

## Verification

- Release configuration on iPad mini (A17 Pro), iPadOS 27: **31 tests passed, 0 failures, 0 skipped**.
- Result bundle: `ios/build/testflight/release-2-iPad-tests.xcresult`.
- Signed archive: `ios/build/testflight/Salini-1.0-2-final.xcarchive`.
- Archived `CFBundleVersion` verified as `2`; privacy manifest present.
- Bundled `ninfea-film-v3.mp4` matches the source asset, SHA-256 `e5ee4ae033f0dc6e528ae7094c5c82d92d4f1a098cd3b0ca97f8d29bb8e06e65`.

## Release commands

Run from the repository root. Increment `CURRENT_PROJECT_VERSION` in both `ios/project.yml` and `ios/Salini.xcodeproj/project.pbxproj` before another upload. Use a unique archive path for every build.

```sh
xcodebuild -project ios/Salini.xcodeproj -scheme Salini \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath ios/build/testflight/DerivedData \
  -archivePath ios/build/testflight/Salini-1.0-2-final.xcarchive \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY='Apple Distribution' DEVELOPMENT_TEAM=TQ5SCF3KQZ \
  PROVISIONING_PROFILE_SPECIFIER='Salini TestFlight' archive

xcodebuild -exportArchive \
  -archivePath ios/build/testflight/Salini-1.0-2-final.xcarchive \
  -exportPath ios/build/testflight/upload-1.0-2 \
  -exportOptionsPlist ios/release/UploadOptions.plist
```

The upload options send the archive to App Store Connect and permit external testing. Publishing to the App Store is a separate workflow. Current server status and the public invitation link are recorded in `preflight-status.json`; build-specific testing and review notes are in `testflight-metadata.json`.
