# LiveCore Studio for macOS (`com.livecore.studio`)

Native macOS live broadcast switcher, compositor, multi-channel audio mixer, VideoToolbox hardware H.264 encoder, local MP4 recorder, and RTMP/RTMPS streaming application built with **Swift 5.10**, **SwiftUI**, **AVFoundation**, **Metal**, **CoreAudio / AVAudioEngine**, and **VideoToolbox**.

---

## 1. Project Structure

```text
livecore-studio-macos/
├── .github/
│   └── workflows/
│       └── build-macos-dmg.yml        # GitHub Actions CI/CD workflow (macos-15 runner)
├── LiveCoreStudio/
│   ├── Info.plist                     # Bundle metadata (com.livecore.studio)
│   ├── LiveCoreStudio.entitlements    # Camera, Audio Input, Network Client entitlements
│   └── Sources/
│       ├── LiveCoreStudioApp.swift    # @main SwiftUI application & Production menu shortcuts
│       ├── Models/
│       │   └── BroadcastModels.swift  # Sources, Transitions, Overlays, Audio, RTMP & Math
│       ├── Engine/
│       │   ├── CaptureManager.swift   # AVFoundation camera/microphone discovery & capture
│       │   ├── MetalCompositor.swift  # Metal + CoreImage transitions & Lower-Third overlay
│       │   ├── AudioMixerEngine.swift # AVAudioEngine + CoreAudio peak/RMS dBFS mixer
│       │   ├── VideoToolboxEncoder.swift # VTCompressionSession H.264 HW encoder & AVAssetWriter
│       │   ├── RTMPStreamEngine.swift # Network.framework TCP/TLS RTMP/RTMPS publisher
│       │   └── ProductionController.swift # @MainActor state coordinator
│       └── Views/
│           └── MainWorkspaceView.swift # Native macOS dual-monitor Preview/Program UI
├── LiveCoreStudioTests/
│   └── LiveCoreStudioTests.swift      # XCTest unit test suite
├── LiveCoreStudio.xcodeproj/          # Native Xcode project & shared scheme
│   ├── project.pbxproj
│   └── xcshareddata/xcschemes/LiveCoreStudio.xcscheme
├── Package.swift                      # Swift Package Manager manifest
├── scripts/
│   └── package-dmg.sh                 # Reproducible hdiutil UDZO DMG packager & validator
└── docs/
    ├── BUILD_AND_RELEASE.md           # Build, Code Signing, Notarization & Release guide
    └── TEST_PLAN.md                   # Unit test & hardware verification matrix
```

---

## 2. Feature Implementation Status

| Feature Module | Native macOS Implementation (`LiveCoreStudio/`) | Web Companion Workspace (`src/`) | Verification Status |
| :--- | :--- | :--- | :--- |
| **Main Production Workspace** | `MainWorkspaceView.swift` (SwiftUI split monitor & mixer deck) | Full interactive 1440px production switcher | Unit-tested & UI-verified |
| **Video Input Discovery & Capture** | `CaptureManager.swift` (`AVCaptureSession`, `.builtInWideAngleCamera`, `.external`) | WebRTC `getUserMedia` live camera + procedural 60fps feeds | Source & logic verified; physical macOS camera requires macOS hardware |
| **Preview (PVW) & Program (PGM)** | Dual bus architecture in `ProductionController.swift` | Dual HTML5 60fps `<canvas>` monitors with tally & safe guides | Verified |
| **CUT Transition** | Immediate zero-frame swap (`Cmd+K` / Spacebar) | Instant bus swap with tally update | Unit-tested (`testCutTransitionSwapsPreviewAndProgram`) |
| **AUTO Transition** | `MetalCompositor.swift` (`CIDissolveTransition`, Dip to Black, Horizontal Wipe) | Smooth ease-in-out interpolated cross-dissolve, dip-to-black & wipe | Unit-tested (`testSmoothStepProgressCurveBounds`) |
| **Video & Image Sources** | Camera, local video loop, static image slate, SMPTE generator | Live camera, uploaded image/video files, procedural studio sources | Verified |
| **Basic Text Overlay** | CoreGraphics / AppKit Lower-Third compositor with scrim & position | Live lower-third headline/subtitle overlay rendered on Program canvas | Verified |
| **Audio Input & Mixer** | `AudioMixerEngine.swift` (`AVAudioEngine` tap, peak/RMS dBFS, Mute, Solo) | Multi-channel faders (-60dB to +6dB), Mute, Solo, live dBFS meters | Unit-tested (`testAudioChannelLinearGainAndSoloMuteLogic`) |
| **Local Recording** | `VideoToolboxEncoder.swift` (`AVAssetWriter` `.mp4` H.264 output) | Real `MediaRecorder` canvas capture with downloadable `.webm` file | Verified |
| **RTMP / RTMPS Streaming** | `RTMPStreamEngine.swift` (`NWConnection` TCP/TLS + C0/C1 handshake & chunking; full AMF0 command negotiation requires live ingest server) | Endpoint parser, validation & transport telemetry | URL & handshake parser unit-tested (`testRTMPEndpointParsingAndValidation`) |
| **Settings & Device Selection** | `SettingsSheetView` in `MainWorkspaceView.swift` | Hardware device & VideoToolbox encoder configuration modal | Verified |

---

## 3. Quick Start: Building on macOS & Triggering GitHub Actions

### Option A: Automated Build via GitHub Actions (Recommended)

Push this repository to GitHub named `livecore-studio-macos`:

```bash
git remote add origin https://github.com/<YOUR_GITHUB_USERNAME>/livecore-studio-macos.git
git branch -M main
git push -u origin main
```

GitHub Actions will automatically trigger `.github/workflows/build-macos-dmg.yml` on `macos-15`, run `swift test`, build `LiveCoreStudio.app` via `xcodebuild`, package `dist/LiveCore-Studio.dmg` via `scripts/package-dmg.sh`, verify mountability, print the SHA-256 checksum in the Job Summary, and upload `LiveCore-Studio-macOS-DMG` to GitHub Actions Artifacts.

### Option B: Local Build on macOS (Apple Silicon / Intel)

```bash
# 1. Run XCTest unit test suite
swift test

# 2. Build Release .app bundle with Xcode
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

# 3. Package into dist/LiveCore-Studio.dmg and compute SHA-256
chmod +x scripts/package-dmg.sh
./scripts/package-dmg.sh "build/DerivedData/Build/Products/Release/LiveCoreStudio.app"
```

---

## 4. Code Signing & macOS Gatekeeper Notice

- **Default CI Output (Unsigned / Ad-Hoc Signed Development DMG)**: By default, `build-macos-dmg.yml` produces an ad-hoc signed development DMG (`CODE_SIGN_IDENTITY="-"`) so any developer can build and test without a paid Apple Developer ID certificate.
- **Opening an Unsigned DMG on macOS**: Because the default artifact is not notarized by Apple, macOS Gatekeeper will display an unverified developer prompt on first launch. To open for personal testing:
  1. Drag `LiveCoreStudio.app` to `/Applications`.
  2. Run `xattr -cr /Applications/LiveCoreStudio.app` in Terminal (or Control-click the app in Finder and choose **Open**).
- For production **Developer ID Application signing** and **Apple Notarization (`xcrun notarytool`)**, see [`docs/BUILD_AND_RELEASE.md`](docs/BUILD_AND_RELEASE.md).
