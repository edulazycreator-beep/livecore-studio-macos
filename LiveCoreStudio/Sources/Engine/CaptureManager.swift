import Foundation
import AVFoundation
import CoreVideo
import CoreImage

public struct HardwareDeviceDescriptor: Identifiable, Equatable, Sendable {
    public let id: String
    public let localizedName: String
    public let modelID: String
    public let isAudio: Bool

    public init(id: String, localizedName: String, modelID: String, isAudio: Bool) {
        self.id = id
        self.localizedName = localizedName
        self.modelID = modelID
        self.isAudio = isAudio
    }
}

public final class CaptureManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    public let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.livecore.studio.capture.session")
    private let videoOutputQueue = DispatchQueue(label: "com.livecore.studio.capture.videoOutput")
    private let videoOutput = AVCaptureVideoDataOutput()

    public var onFrameCaptured: ((CVPixelBuffer, CMTime) -> Void)?
    public private(set) var activeVideoDeviceID: String?
    public private(set) var isRunning: Bool = false

    public override init() {
        super.init()
        configureDefaultVideoOutput()
    }

    private func configureDefaultVideoOutput() {
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)
    }

    public static func discoverVideoDevices() -> [HardwareDeviceDescriptor] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        return discovery.devices.map { device in
            HardwareDeviceDescriptor(
                id: device.uniqueID,
                localizedName: device.localizedName,
                modelID: device.modelID,
                isAudio: false
            )
        }
    }

    public static func discoverAudioDevices() -> [HardwareDeviceDescriptor] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        return discovery.devices.map { device in
            HardwareDeviceDescriptor(
                id: device.uniqueID,
                localizedName: device.localizedName,
                modelID: device.modelID,
                isAudio: true
            )
        }
    }

    public func selectVideoDevice(uniqueID: String, completion: @escaping (Result<String, Error>) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            guard let device = AVCaptureDevice(uniqueID: uniqueID) else {
                let err = NSError(
                    domain: "com.livecore.studio.capture",
                    code: 404,
                    userInfo: [NSLocalizedDescriptionKey: "Video capture device not found: \(uniqueID)"]
                )
                completion(.failure(err))
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: device)
                self.session.beginConfiguration()
                for existing in self.session.inputs {
                    self.session.removeInput(existing)
                }
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                }
                if !self.session.outputs.contains(self.videoOutput) && self.session.canAddOutput(self.videoOutput) {
                    self.session.addOutput(self.videoOutput)
                }
                if self.session.canSetSessionPreset(.hd1920x1080) {
                    self.session.sessionPreset = .hd1920x1080
                }
                self.session.commitConfiguration()
                self.activeVideoDeviceID = uniqueID
                completion(.success(device.localizedName))
            } catch {
                self.session.commitConfiguration()
                completion(.failure(error))
            }
        }
    }

    public func startCapture() {
        sessionQueue.async { [weak self] in
            guard let self = self, !self.session.isRunning else { return }
            self.session.startRunning()
            self.isRunning = self.session.isRunning
        }
    }

    public func stopCapture() {
        sessionQueue.async { [weak self] in
            guard let self = self, self.session.isRunning else { return }
            self.session.stopRunning()
            self.isRunning = false
        }
    }

    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        onFrameCaptured?(pixelBuffer, pts)
    }
}
