# Build, Packaging, Code Signing & Release Guide

## 1. Toolchain & System Requirements

- **Target OS**: macOS 14.0 (Sonoma) or newer (macOS 15 Sequoia recommended).
- **Architecture**: Native Apple Silicon (`arm64`) primary target; universal compatibility (`arm64` + `x86_64`) supported by all frameworks (`SwiftUI`, `AVFoundation`, `Metal`, `CoreAudio`, `VideoToolbox`, `Network`).
- **Xcode**: Xcode 15.4 or Xcode 16.x.
- **Bundle Identifier**: `com.livecore.studio`

---

## 2. Exact Build Commands

### Step 1: Verify Toolchain
```bash
sw_vers
xcodebuild -version
swift --version
```

### Step 2: Run Unit Tests
```bash
swift test --parallel
```

### Step 3: Build Release `.app` Bundle via `xcodebuild`
```bash
xcodebuild \
  -project LiveCoreStudio.xcodeproj \
  -scheme LiveCoreStudio \
  -configuration Release \
  -sdk macosx \
  -derivedDataPath build/DerivedData \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The resulting application bundle is created at:
```text
build/DerivedData/Build/Products/Release/LiveCoreStudio.app
```

### Step 4: Package `LiveCore-Studio.dmg`
```bash
chmod +x scripts/package-dmg.sh
./scripts/package-dmg.sh "build/DerivedData/Build/Products/Release/LiveCoreStudio.app"
```

This script performs 7 automated checks:
1. Verifies Darwin (`macOS`) host and `hdiutil`.
2. Checks `LiveCoreStudio.app`, `Contents/MacOS/LiveCoreStudio` executable permissions, and `Contents/Info.plist`.
3. Creates a clean staging directory at `build/dmg-staging`.
4. Copies `LiveCoreStudio.app` using `ditto` and creates the `/Applications` symlink.
5. Generates a compressed `UDZO` disk image at `dist/LiveCore-Studio.dmg`.
6. Verifies the DMG with `hdiutil verify`, mounts it read-only via `hdiutil attach`, confirms `LiveCoreStudio.app` is present inside the mounted volume, and detaches cleanly.
7. Outputs the SHA-256 checksum to `dist/LiveCore-Studio.dmg.sha256`.

---

## 3. Code Signing & Notarization Tiers

### Tier 1: Unsigned / Ad-Hoc Development DMG (Default in CI)
- **What it is**: Built with `CODE_SIGN_IDENTITY="-"`. No Apple Developer certificate or secret is required.
- **Security behavior**: macOS Gatekeeper will warn that the app is from an unidentified developer when downloaded from the internet.
- **How to run locally**: Run `xattr -d com.apple.quarantine /Applications/LiveCoreStudio.app` or Control-click -> Open.

### Tier 2: Developer ID Signed Application
- **What it is**: Signed using an Apple `Developer ID Application: <Team Name> (<Team ID>)` certificate with Hardened Runtime enabled (`--options runtime`).
- **Required GitHub Secrets**:
  - `MACOS_CERTIFICATE_P12_BASE64`: Base64-encoded Developer ID `.p12` certificate.
  - `MACOS_CERTIFICATE_PASSWORD`: Password for the `.p12` file.
  - `MACOS_SIGNING_IDENTITY`: Full identity string, e.g. `Developer ID Application: Example Corp (TEAMID1234)`.
- **Signing Command**:
  ```bash
  codesign --force --deep --options runtime \
    --entitlements LiveCoreStudio/LiveCoreStudio.entitlements \
    --sign "$MACOS_SIGNING_IDENTITY" \
    "build/DerivedData/Build/Products/Release/LiveCoreStudio.app"
  codesign --verify --deep --strict --verbose=2 \
    "build/DerivedData/Build/Products/Release/LiveCoreStudio.app"
  ```

### Tier 3: Apple Notarized Distribution DMG
- **What it is**: Submitted to Apple Notary Service after Developer ID signing and stapled with a notarization ticket.
- **Required GitHub Secrets**:
  - `APPLE_ID`: Apple Developer account email.
  - `APPLE_TEAM_ID`: 10-character Apple Team ID.
  - `APPLE_APP_SPECIFIC_PASSWORD`: App-specific password generated at `appleid.apple.com`.
- **Notarization & Stapling Commands**:
  ```bash
  xcrun notarytool submit dist/LiveCore-Studio.dmg \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --wait

  xcrun stapler staple dist/LiveCore-Studio.dmg
  spctl -a -t open --context context:primary-signature -v dist/LiveCore-Studio.dmg
  ```

---

## 4. Tag-Based GitHub Releases

When you push a semantic version tag matching `v*.*.*`:
```bash
git tag -a v0.1.0 -m "LiveCore Studio v0.1.0 Initial macOS Release"
git push origin v0.1.0
```
The `build-macos-dmg.yml` workflow automatically creates a GitHub Release for `v0.1.0` and attaches both `dist/LiveCore-Studio.dmg` and `dist/LiveCore-Studio.dmg.sha256` using the built-in `GITHUB_TOKEN` (`permissions: contents: write`).
