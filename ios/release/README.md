# TestFlight release

The current TestFlight release is Salini **1.0 (3)**, bundle `design.salini.experience`, App Store Connect app `6819688748`.

Build 3 adds Aria, Opera and Greca films, four seamless living endings, and more detailed Salini Inside production areas. Release source is commit `29484ca`; app implementation is in `08d3da1`. Signing credentials and provisioning profiles remain in the local Xcode account and keychain; they are not stored in Git.

Build 3 is available to the internal group and submitted for external Beta App Review (**Waiting for Review**). The existing public link is https://testflight.apple.com/join/mUb5H7bZ; testers can join after Apple approves the build. Build 2 was removed from review and replaced with build 3.

## Verification

- iPhone 18 Pro, iOS 27, Debug: **34 tests passed, 0 failures**.
- iPad mini (A17 Pro), iPadOS 27, Release with testability enabled: **34 tests passed, 0 failures**.
- Release result bundle: `ios/.build-ipad/Logs/Test/Test-Salini-2026.10.06_23-43-15-+0700.xcresult`.
- Functional source is unchanged since these tests; release preparation only increments the build number.
- Signed archive: `ios/build/testflight/Salini-1.0-3-final.xcarchive`.
- Archived `CFBundleVersion` verified as `3`; privacy manifest present.
- Code signature verified with `codesign --verify --deep --strict`.
- SHA-256 checks confirm that all four intros and four ambient loops in the signed archive match the source resources. Asset hashes are recorded in `preflight-status.json`.

## Release commands

Run from the repository root. Increment `CURRENT_PROJECT_VERSION` in both `ios/project.yml` and `ios/Salini.xcodeproj/project.pbxproj` before another upload. Use a unique archive path for every build.

```sh
xcodebuild -project ios/Salini.xcodeproj -scheme Salini \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath ios/build/testflight/DerivedData \
  -archivePath ios/build/testflight/Salini-1.0-3-final.xcarchive \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY='Apple Distribution' DEVELOPMENT_TEAM=TQ5SCF3KQZ \
  PROVISIONING_PROFILE_SPECIFIER='Salini TestFlight' archive

xcodebuild -exportArchive \
  -archivePath ios/build/testflight/Salini-1.0-3-final.xcarchive \
  -exportPath ios/build/testflight/upload-1.0-3 \
  -exportOptionsPlist ios/release/UploadOptions.plist
```

The upload options send the archive to App Store Connect and permit external testing. Publishing to the App Store is a separate workflow. Current server status and the public invitation link are recorded in `preflight-status.json`; build-specific testing and review notes are in `testflight-metadata.json`.
