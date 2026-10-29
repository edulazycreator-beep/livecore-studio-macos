import Foundation
import CoreGraphics

public enum SourceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case camera = "AVCapture Camera"
    case videoFile = "Video File"
    case imageStatic = "Static Image"
    case testPattern = "SMPTE Generator"

    public var id: String { rawValue }
}

public enum TransitionStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case crossDissolve = "Cross Dissolve"
    case dipToBlack = "Dip to Black"
    case wipeHorizontal = "Horizontal Wipe"

    public var id: String { rawValue }
}

public struct ProductionSource: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public var name: String
    public var kind: SourceKind
    public var deviceUniqueID: String?
    public var filePath: String?
    public var resolutionLabel: String
    public var frameRate: Int
    public var accentHex: String

    public init(
        id: String,
        name: String,
        kind: SourceKind,
        deviceUniqueID: String? = nil,
        filePath: String? = nil,
        resolutionLabel: String = "1920x1080",
        frameRate: Int = 60,
        accentHex: String = "#2563EB"
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.deviceUniqueID = deviceUniqueID
        self.filePath = filePath
        self.resolutionLabel = resolutionLabel
        self.frameRate = frameRate
        self.accentHex = accentHex
    }
}

public enum OverlayPosition: String, Codable, CaseIterable, Identifiable, Sendable {
    case bottomLeft = "Bottom Left"
    case bottomCenter = "Bottom Center"
    case topLeft = "Top Left"
    case topRight = "Top Right"

    public var id: String { rawValue }
}

public struct TextOverlayConfig: Equatable, Codable, Sendable {
    public var isEnabled: Bool
    public var headline: String
    public var subtitle: String
    public var position: OverlayPosition
    public var fontSize: Double
    public var showBackgroundScrim: Bool

    public init(
        isEnabled: Bool = true,
        headline: String = "LIVECORE STUDIO — APPLE SILICON BROADCAST",
        subtitle: String = "Live Feed · 1080p60 VideoToolbox H.264",
        position: OverlayPosition = .bottomLeft,
        fontSize: Double = 24.0,
        showBackgroundScrim: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.headline = headline
        self.subtitle = subtitle
        self.position = position
        self.fontSize = fontSize
        self.showBackgroundScrim = showBackgroundScrim
    }
}

public struct AudioChannelState: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public var name: String
    public var gainDB: Double        // Range: -60.0 to +6.0 dB
    public var isMuted: Bool
    public var isSolo: Bool
    public var peakDBFS: Double      // Range: -60.0 to 0.0 dBFS
    public var rmsDBFS: Double

    public init(
        id: String,
        name: String,
        gainDB: Double = 0.0,
        isMuted: Bool = false,
        isSolo: Bool = false,
        peakDBFS: Double = -18.0,
        rmsDBFS: Double = -24.0
    ) {
        self.id = id
        self.name = name
        self.gainDB = gainDB
        self.isMuted = isMuted
        self.isSolo = isSolo
        self.peakDBFS = peakDBFS
        self.rmsDBFS = rmsDBFS
    }

    public var linearGain: Float {
        if isMuted || gainDB <= -59.5 {
            return 0.0
        }
        return powf(10.0, Float(gainDB) / 20.0)
    }
}

public enum StreamConnectionState: String, Codable, Equatable, Sendable {
    case idle = "Disconnected"
    case connecting = "Connecting Handshake"
    case streaming = "Live Streaming"
    case reconnecting = "Reconnecting"
    case error = "Transport Error"
}

public enum RecordingState: String, Codable, Equatable, Sendable {
    case idle = "Ready"
    case starting = "Initializing Writer"
    case recording = "Recording"
    case stopping = "Finalizing MP4"
    case error = "Write Error"
}

public struct StreamSettings: Equatable, Codable, Sendable {
    public var rtmpURL: String
    public var streamKey: String
    public var videoBitrateKbps: Int
    public var audioBitrateKbps: Int
    public var keyframeIntervalSeconds: Int
    public var width: Int
    public var height: Int
    public var fps: Int
    public var useHardwareEncoding: Bool
    public var recordingDirectoryPath: String

    public init(
        rtmpURL: String = "rtmps://live.example.com/app",
        streamKey: String = "",
        videoBitrateKbps: Int = 6000,
        audioBitrateKbps: Int = 160,
        keyframeIntervalSeconds: Int = 2,
        width: Int = 1920,
        height: Int = 1080,
        fps: Int = 60,
        useHardwareEncoding: Bool = true,
        recordingDirectoryPath: String = (NSHomeDirectory() as NSString).appendingPathComponent("Movies/LiveCoreStudio")
    ) {
        self.rtmpURL = rtmpURL
        self.streamKey = streamKey
        self.videoBitrateKbps = videoBitrateKbps
        self.audioBitrateKbps = audioBitrateKbps
        self.keyframeIntervalSeconds = keyframeIntervalSeconds
        self.width = width
        self.height = height
        self.fps = fps
        self.useHardwareEncoding = useHardwareEncoding
        self.recordingDirectoryPath = recordingDirectoryPath
    }

    public var isValidRTMPTarget: Bool {
        let trimmed = rtmpURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.hasPrefix("rtmp://") || trimmed.hasPrefix("rtmps://") else {
            return false
        }
        guard let url = URL(string: rtmpURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host,
              !host.isEmpty else {
            return false
        }
        return !streamKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public struct PerformanceTelemetry: Equatable, Codable, Sendable {
    public var activeFPS: Double
    public var frameDropCount: Int
    public var cpuLoadPercent: Double
    public var encodedBitrateKbps: Int
    public var uptimeSeconds: Int
    public var encoderBackendName: String

    public init(
        activeFPS: Double = 60.0,
        frameDropCount: Int = 0,
        cpuLoadPercent: Double = 8.4,
        encodedBitrateKbps: Int = 0,
        uptimeSeconds: Int = 0,
        encoderBackendName: String = "Apple VideoToolbox H.264 HW"
    ) {
        self.activeFPS = activeFPS
        self.frameDropCount = frameDropCount
        self.cpuLoadPercent = cpuLoadPercent
        self.encodedBitrateKbps = encodedBitrateKbps
        self.uptimeSeconds = uptimeSeconds
        self.encoderBackendName = encoderBackendName
    }
}

public enum SwitcherMath {
    /// Calculates normalized progress [0, 1] and smoothed ease-in-out curve for AUTO transitions.
    public static func smoothStepProgress(elapsedMs: Double, durationMs: Double) -> Double {
        guard durationMs > 0 else { return 1.0 }
        let clamped = min(max(elapsedMs / durationMs, 0.0), 1.0)
        return clamped * clamped * (3.0 - 2.0 * clamped)
    }

    /// Computes effective channel linear gain taking Solo and Mute states across bus into account.
    public static func effectiveGain(for channel: AudioChannelState, anyChannelSoloed: Bool) -> Float {
        if channel.isMuted { return 0.0 }
        if anyChannelSoloed && !channel.isSolo { return 0.0 }
        return channel.linearGain
    }
}
