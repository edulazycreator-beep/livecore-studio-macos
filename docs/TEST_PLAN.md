# Test Plan & Verification Report — LiveCore Studio for macOS

## 1. Automated Unit Tests (`LiveCoreStudioTests/LiveCoreStudioTests.swift`)

Executed on macOS via `swift test --parallel` and mirrored in TypeScript via `npx --yes tsx --test src/utils/broadcastEngine.test.ts`:

| Test ID | Test Case | Target Component | Expected Outcome |
| :--- | :--- | :--- | :--- |
| `UT-01` | `testCutTransitionSwapsPreviewAndProgram` | `ProductionController.performCut()` | Immediately swaps `previewSourceID` and `programSourceID` with `isTransitioning == false` and `transitionProgress == 0.0`. |
| `UT-02` | `testSmoothStepProgressCurveBounds` | `SwitcherMath.smoothStepProgress` | Returns `0.0` at `t=0`, `0.5` at midpoint `t=0.5`, and clamps to `1.0` at `t>=duration`. |
| `UT-03` | `testAudioChannelLinearGainAndSoloMuteLogic` | `AudioChannelState` & `SwitcherMath.effectiveGain` | 0 dB yields `1.0` linear gain; soloing another channel zeroes non-soloed channels; muting forces `0.0` gain regardless of solo state. |
| `UT-04` | `testRTMPEndpointParsingAndValidation` | `RTMPEndpointDescriptor.parse` | Parses `rtmp://` (default port 1935) and `rtmps://` (default port 443, TLS enabled), extracts host and app path, and throws structured errors on invalid schemes or empty stream keys. |

---

## 2. Static & Structural Integrity Verification (Executed in Current Environment)

Because the AI Studio runtime container runs Linux (`x86_64 GNU/Linux`) without physical Apple Silicon hardware or macOS `xcodebuild`/`hdiutil` binaries, the following verifications are executed directly in this environment:

1. **Swift Source & Xcode Project Audit**:
   - Verifies all 9 Swift source files, `LiveCoreStudioTests.swift`, `Package.swift`, `Info.plist`, `LiveCoreStudio.entitlements`, `LiveCoreStudio.xcodeproj/project.pbxproj`, and `LiveCoreStudio.xcscheme` exist on disk and are non-empty.
   - Checks balanced braces, valid bundle identifier `com.livecore.studio`, and framework imports (`SwiftUI`, `AVFoundation`, `Metal`, `CoreImage`, `AVFAudio`, `CoreAudio`, `VideoToolbox`, `Network`).
2. **GitHub Actions Workflow & DMG Script Audit**:
   - Verifies `.github/workflows/build-macos-dmg.yml` pins actions to commit SHAs, uses `macos-15`, executes `swift test`, runs `xcodebuild -project LiveCoreStudio.xcodeproj -scheme LiveCoreStudio -configuration Release`, invokes `scripts/package-dmg.sh`, computes SHA-256, and uploads `LiveCore-Studio.dmg`.
3. **Interactive Broadcast Engine Unit Tests**:
   - Executes deterministic unit tests via `node:test` (`src/utils/broadcastEngine.test.ts`) verifying switcher state transitions, AUTO transition curves, audio dBFS mixer calculations, RTMP/RTMPS validation, and repository bundle integrity.

---

## 3. Hardware Verification Checklist (To Run on Physical Mac after GitHub Actions Build)

- [ ] Mount `LiveCore-Studio.dmg` on Apple Silicon Mac (`macOS 14+`) and verify `/Applications` drag-and-drop symlink.
- [ ] Launch `LiveCoreStudio.app` and grant Camera and Microphone permissions when prompted by macOS TCC.
- [ ] Select FaceTime HD Camera or external USB/HDMI capture card in **Settings & Devices**.
- [ ] Trigger **CUT** (`Cmd+K`) and **AUTO** (`Cmd+T`) transitions and verify 60fps Metal composition.
- [ ] Toggle **Record MP4** and inspect the generated H.264 `.mp4` file in `~/Movies/LiveCoreStudio/` using QuickTime Player.
- [ ] Enter a live `rtmp://` or `rtmps://` ingest URL and stream key and verify network connection telemetry.
