import Foundation
import VideoToolbox
import AVFoundation
import CoreVideo
import CoreMedia

public final class VideoToolboxEncoder: @unchecked Sendable {
    private var compressionSession: VTCompressionSession?
    private var assetWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    private let encoderQueue = DispatchQueue(label: "com.livecore.studio.videotoolbox.encoder")
    public var onEncodedNALUnit: ((Data, Bool, CMTime) -> Void)?
    public private(set) var isRecording: Bool = false
    public private(set) var activeRecordingURL: URL?

    public init() {}

    public func configureHardwareEncoder(width: Int32, height: Int32, bitrateKbps: Int, fps: Int) throws {
        tearDownCompressionSession()

        var session: VTCompressionSession?
        let encoderSpec: [CFString: Any] = [
            kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true
        ]

        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: encoderSpec as CFDictionary,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session
        )

        guard status == noErr, let vtSession = session else {
            throw NSError(
                domain: "com.livecore.studio.videotoolbox",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Failed to initialize VideoToolbox H.264 session (OSStatus \(status))"]
            )
        }

        VTSessionSetProperty(vtSession, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(vtSession, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_High_AutoLevel)
        VTSessionSetProperty(vtSession, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)

        let averageBitrate = bitrateKbps * 1000
        VTSessionSetProperty(vtSession, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: averageBitrate))
        VTSessionSetProperty(vtSession, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: NSNumber(value: fps))
        VTSessionSetProperty(vtSession, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: NSNumber(value: fps * 2))

        VTCompressionSessionPrepareToEncodeFrames(vtSession)
        self.compressionSession = vtSession
    }

    public func encodeFrame(pixelBuffer: CVPixelBuffer, presentationTimeStamp: CMTime, duration: CMTime) {
        encoderQueue.async { [weak self] in
            guard let self = self else { return }

            if self.isRecording,
               let writerInput = self.videoWriterInput,
               let adaptor = self.pixelBufferAdaptor,
               writerInput.isReadyForMoreMediaData {
                adaptor.append(pixelBuffer, withPresentationTime: presentationTimeStamp)
            }

            guard let vtSession = self.compressionSession else { return }
            var flags: VTEncodeInfoFlags = []
            VTCompressionSessionEncodeFrameWithOutputHandler(
                vtSession,
                imageBuffer: pixelBuffer,
                presentationTimeStamp: presentationTimeStamp,
                duration: duration,
                frameProperties: nil,
                infoFlagsOut: &flags
            ) { [weak self] status, _, sampleBuffer in
                guard status == noErr,
                      let sampleBuffer = sampleBuffer,
                      CMSampleBufferDataIsReady(sampleBuffer),
                      let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                    return
                }
                var length: Int = 0
                var dataPointer: UnsafeMutablePointer<Int8>?
                let result = CMBlockBufferGetDataPointer(
                    dataBuffer,
                    atOffset: 0,
                    lengthAtOffsetOut: nil,
                    totalLengthOut: &length,
                    dataPointerOut: &dataPointer
                )
                if result == kCMBlockBufferNoErr, let ptr = dataPointer, length > 0 {
                    let payload = Data(bytes: ptr, count: length)
                    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    self?.onEncodedNALUnit?(payload, true, pts)
                }
            }
        }
    }

    public func startLocalRecording(outputDirectory: String, width: Int, height: Int, bitrateKbps: Int) throws -> URL {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: outputDirectory) {
            try fileManager.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate]
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let fileURL = URL(fileURLWithPath: outputDirectory).appendingPathComponent("LiveCore-\(timestamp).mp4")

        let writer = try AVAssetWriter(outputURL: fileURL, fileType: .mp4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrateKbps * 1000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true

        let sourcePixelAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: sourcePixelAttrs
        )

        guard writer.canAdd(input) else {
            throw NSError(
                domain: "com.livecore.studio.recorder",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "AVAssetWriter cannot add H.264 video input"]
            )
        }
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        self.assetWriter = writer
        self.videoWriterInput = input
        self.pixelBufferAdaptor = adaptor
        self.activeRecordingURL = fileURL
        self.isRecording = true

        return fileURL
    }

    public func stopLocalRecording(completion: @escaping (Result<URL, Error>) -> Void) {
        encoderQueue.async { [weak self] in
            guard let self = self,
                  let writer = self.assetWriter,
                  let url = self.activeRecordingURL else {
                let err = NSError(
                    domain: "com.livecore.studio.recorder",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "No active local recording session"]
                )
                completion(.failure(err))
                return
            }

            self.isRecording = false
            self.videoWriterInput?.markAsFinished()
            writer.finishWriting {
                if let error = writer.error {
                    completion(.failure(error))
                } else {
                    completion(.success(url))
                }
            }
        }
    }

    public func tearDownCompressionSession() {
        if let vtSession = compressionSession {
            VTCompressionSessionCompleteFrames(vtSession, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(vtSession)
            compressionSession = nil
        }
    }
}
