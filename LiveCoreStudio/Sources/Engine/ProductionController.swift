import Foundation
import SwiftUI
import Combine
import CoreMedia

@MainActor
public final class ProductionController: ObservableObject {
    @Published public var sources: [ProductionSource]
    @Published public var previewSourceID: String
    @Published public var programSourceID: String

    @Published public var transitionStyle: TransitionStyle = .crossDissolve
    @Published public var autoTransitionDurationMs: Double = 600.0
    @Published public var transitionProgress: Double = 0.0
    @Published public var isTransitioning: Bool = false

    @Published public var overlayConfig: TextOverlayConfig = TextOverlayConfig()
    @Published public var audioChannels: [AudioChannelState]
    @Published public var streamSettings: StreamSettings = StreamSettings()

    @Published public var streamState: StreamConnectionState = .idle
    @Published public var recordingState: RecordingState = .idle
    @Published public var lastRecordedFilePath: String?
    @Published public var statusBannerMessage: String = "Metal & VideoToolbox Hardware Pipeline Ready"
    @Published public var lastErrorMessage: String?

    @Published public var telemetry: PerformanceTelemetry = PerformanceTelemetry()
    @Published public var discoveredVideoDevices: [HardwareDeviceDescriptor] = []
    @Published public var discoveredAudioDevices: [HardwareDeviceDescriptor] = []

    public let captureManager = CaptureManager()
    public let metalCompositor = MetalCompositor()
    public let audioMixer = AudioMixerEngine()
    public let videoEncoder = VideoToolboxEncoder()
    public let rtmpEngine = RTMPStreamEngine()

    private var transitionTimer: Timer?
    private var telemetryTimer: Timer?

    public init() {
        let initialSources: [ProductionSource] = [
            ProductionSource(
                id: "cam-main",
                name: "Camera 1 · Studio Wide (AVCapture)",
                kind: .camera,
                resolutionLabel: "1920x1080",
                frameRate: 60,
                accentHex: "#2563EB"
            ),
            ProductionSource(
                id: "cam-overhead",
                name: "Camera 2 · Overhead Desk",
                kind: .camera,
                resolutionLabel: "1920x1080",
                frameRate: 60,
                accentHex: "#0891B2"
            ),
            ProductionSource(
                id: "media-intro",
                name: "Video Clip · Show Opener Loop.mp4",
                kind: .videoFile,
                filePath: "~/Movies/ShowOpener.mp4",
                resolutionLabel: "1920x1080",
                frameRate: 60,
                accentHex: "#4F46E5"
            ),
            ProductionSource(
                id: "slate-standby",
                name: "Static Slate · Technical Standby.png",
                kind: .imageStatic,
                filePath: "~/Pictures/StandbySlate.png",
                resolutionLabel: "1920x1080",
                frameRate: 60,
                accentHex: "#0D9488"
            )
        ]

        self.sources = initialSources
        self.programSourceID = initialSources[0].id
        self.previewSourceID = initialSources[1].id

        self.audioChannels = [
            AudioChannelState(id: "mic-1", name: "Mic / Aux 1 (CoreAudio)", gainDB: 0.0, peakDBFS: -12.4, rmsDBFS: -18.2),
            AudioChannelState(id: "desk-audio", name: "macOS System Audio", gainDB: -6.0, peakDBFS: -19.0, rmsDBFS: -25.5),
            AudioChannelState(id: "media-bus", name: "Media Player Bus", gainDB: -3.0, peakDBFS: -15.8, rmsDBFS: -21.0),
            AudioChannelState(id: "master-pgm", name: "Master Program Mix", gainDB: 0.0, peakDBFS: -9.6, rmsDBFS: -14.8)
        ]

        setupCallbacks()
        refreshHardwareDevices()
    }

    private func setupCallbacks() {
        rtmpEngine.onStateChange = { [weak self] newState, message in
            Task { @MainActor in
                guard let self = self else { return }
                self.streamState = newState
                if let message = message {
                    if newState == .error {
                        self.lastErrorMessage = message
                    } else {
                        self.statusBannerMessage = message
                    }
                }
            }
        }

        audioMixer.onMasterMeterUpdate = { [weak self] peak, rms in
            Task { @MainActor in
                guard let self = self else { return }
                if !self.audioChannels.isEmpty {
                    self.audioChannels[0].peakDBFS = peak
                    self.audioChannels[0].rmsDBFS = rms
                }
            }
        }
    }

    public var previewSource: ProductionSource {
        sources.first(where: { $0.id == previewSourceID }) ?? sources[0]
    }

    public var programSource: ProductionSource {
        sources.first(where: { $0.id == programSourceID }) ?? sources[0]
    }

    public func refreshHardwareDevices() {
        discoveredVideoDevices = CaptureManager.discoverVideoDevices()
        discoveredAudioDevices = CaptureManager.discoverAudioDevices()
    }

    /// Executes an immediate frame-accurate CUT swap between Preview and Program.
    public func performCut() {
        transitionTimer?.invalidate()
        isTransitioning = false
        transitionProgress = 0.0

        let previousProgram = programSourceID
        programSourceID = previewSourceID
        previewSourceID = previousProgram
        statusBannerMessage = "CUT executed -> Program: \(programSource.name)"
    }

    /// Executes a timed AUTO transition (Cross Dissolve, Dip to Black, or Wipe) from Preview to Program.
    public func performAutoTransition() {
        guard !isTransitioning else { return }
        isTransitioning = true
        transitionProgress = 0.0
        let durationMs = max(100.0, autoTransitionDurationMs)
        let startTime = Date()

        transitionTimer?.invalidate()
        transitionTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self = self else {
                    timer.invalidate()
                    return
                }
                let elapsedMs = Date().timeIntervalSince(startTime) * 1000.0
                if elapsedMs >= durationMs {
                    timer.invalidate()
                    self.transitionProgress = 0.0
                    self.isTransitioning = false
                    let oldPgm = self.programSourceID
                    self.programSourceID = self.previewSourceID
                    self.previewSourceID = oldPgm
                    self.statusBannerMessage = "AUTO (\(self.transitionStyle.rawValue)) completed -> Program: \(self.programSource.name)"
                } else {
                    self.transitionProgress = SwitcherMath.smoothStepProgress(elapsedMs: elapsedMs, durationMs: durationMs)
                }
            }
        }
    }

    public func toggleStream() {
        lastErrorMessage = nil
        if streamState == .streaming || streamState == .connecting {
            rtmpEngine.disconnect()
            telemetry.encodedBitrateKbps = recordingState == .recording ? streamSettings.videoBitrateKbps : 0
            return
        }

        guard streamSettings.isValidRTMPTarget else {
            lastErrorMessage = "Invalid RTMP/RTMPS configuration: Provide a valid rtmp:// or rtmps:// server URL and non-empty stream key."
            streamState = .error
            return
        }

        do {
            try videoEncoder.configureHardwareEncoder(
                width: Int32(streamSettings.width),
                height: Int32(streamSettings.height),
                bitrateKbps: streamSettings.videoBitrateKbps,
                fps: streamSettings.fps
            )
            telemetry.encodedBitrateKbps = streamSettings.videoBitrateKbps
            rtmpEngine.connectAndPublish(settings: streamSettings)
        } catch {
            lastErrorMessage = error.localizedDescription
            streamState = .error
        }
    }

    public func toggleLocalRecording() {
        lastErrorMessage = nil
        if recordingState == .recording {
            recordingState = .stopping
            videoEncoder.stopLocalRecording { [weak self] result in
                Task { @MainActor in
                    guard let self = self else { return }
                    switch result {
                    case .success(let url):
                        self.recordingState = .idle
                        self.lastRecordedFilePath = url.path
                        self.statusBannerMessage = "Saved recording: \(url.lastPathComponent)"
                    case .failure(let error):
                        self.recordingState = .error
                        self.lastErrorMessage = error.localizedDescription
                    }
                }
            }
        } else {
            do {
                recordingState = .starting
                let url = try videoEncoder.startLocalRecording(
                    outputDirectory: streamSettings.recordingDirectoryPath,
                    width: streamSettings.width,
                    height: streamSettings.height,
                    bitrateKbps: streamSettings.videoBitrateKbps
                )
                recordingState = .recording
                lastRecordedFilePath = url.path
                telemetry.encodedBitrateKbps = streamSettings.videoBitrateKbps
                statusBannerMessage = "Recording active -> \(url.path)"
            } catch {
                recordingState = .error
                lastErrorMessage = "Failed to start local recording: \(error.localizedDescription)"
            }
        }
    }
}
