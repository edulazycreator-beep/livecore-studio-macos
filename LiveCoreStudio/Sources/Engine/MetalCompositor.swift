import Foundation
import Metal
import CoreImage
import CoreGraphics
import CoreVideo
import AppKit

public final class MetalCompositor: @unchecked Sendable {
    public let metalDevice: MTLDevice?
    public let commandQueue: MTLCommandQueue?
    private let ciContext: CIContext

    public init() {
        let device = MTLCreateSystemDefaultDevice()
        self.metalDevice = device
        self.commandQueue = device?.makeCommandQueue()
        if let device = device {
            self.ciContext = CIContext(mtlDevice: device, options: [
                .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
                .cacheIntermediates: false
            ])
        } else {
            self.ciContext = CIContext(options: nil)
        }
    }

    public var gpuHardwareName: String {
        metalDevice?.name ?? "CoreImage Software Fallback"
    }

    /// Blends Program and Preview CIImages according to active transition style and normalized progress [0, 1],
    /// then composites optional Lower-Third Text Overlay.
    public func composeProgramFrame(
        programImage: CIImage,
        previewImage: CIImage,
        transitionProgress: Double,
        transitionStyle: TransitionStyle,
        overlay: TextOverlayConfig,
        canvasSize: CGSize = CGSize(width: 1920, height: 1080)
    ) -> CIImage {
        let t = SwitcherMath.smoothStepProgress(elapsedMs: transitionProgress * 1000.0, durationMs: 1000.0)
        var composited: CIImage

        if t <= 0.001 {
            composited = programImage
        } else if t >= 0.999 {
            composited = previewImage
        } else {
            switch transitionStyle {
            case .crossDissolve:
                if let dissolve = CIFilter(name: "CIDissolveTransition") {
                    dissolve.setValue(programImage, forKey: kCIInputImageKey)
                    dissolve.setValue(previewImage, forKey: kCIInputTargetImageKey)
                    dissolve.setValue(NSNumber(value: t), forKey: kCIInputTimeKey)
                    composited = dissolve.outputImage ?? previewImage
                } else {
                    composited = previewImage
                }
            case .dipToBlack:
                let blackFrame = CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: canvasSize))
                if t < 0.5 {
                    let phase = t * 2.0
                    if let dissolve = CIFilter(name: "CIDissolveTransition") {
                        dissolve.setValue(programImage, forKey: kCIInputImageKey)
                        dissolve.setValue(blackFrame, forKey: kCIInputTargetImageKey)
                        dissolve.setValue(NSNumber(value: phase), forKey: kCIInputTimeKey)
                        composited = dissolve.outputImage ?? blackFrame
                    } else {
                        composited = blackFrame
                    }
                } else {
                    let phase = (t - 0.5) * 2.0
                    if let dissolve = CIFilter(name: "CIDissolveTransition") {
                        dissolve.setValue(blackFrame, forKey: kCIInputImageKey)
                        dissolve.setValue(previewImage, forKey: kCIInputTargetImageKey)
                        dissolve.setValue(NSNumber(value: phase), forKey: kCIInputTimeKey)
                        composited = dissolve.outputImage ?? previewImage
                    } else {
                        composited = previewImage
                    }
                }
            case .wipeHorizontal:
                let splitX = canvasSize.width * CGFloat(t)
                let leftCrop = previewImage.cropped(to: CGRect(x: 0, y: 0, width: splitX, height: canvasSize.height))
                composited = leftCrop.composited(over: programImage)
            }
        }

        if overlay.isEnabled && (!overlay.headline.isEmpty || !overlay.subtitle.isEmpty) {
            if let overlayCI = renderOverlayImage(config: overlay, canvasSize: canvasSize) {
                composited = overlayCI.composited(over: composited)
            }
        }

        return composited.cropped(to: CGRect(origin: .zero, size: canvasSize))
    }

    public func renderToPixelBuffer(image: CIImage, width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferMetalCompatibilityKey: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        ciContext.render(image, to: buffer)
        return buffer
    }

    private func renderOverlayImage(config: TextOverlayConfig, canvasSize: CGSize) -> CIImage? {
        let width = Int(canvasSize.width)
        let height = Int(canvasSize.height)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
              ) else {
            return nil
        }

        let boxWidth: CGFloat = min(canvasSize.width - 120, 820)
        let boxHeight: CGFloat = 104
        let origin: CGPoint
        switch config.position {
        case .bottomLeft:
            origin = CGPoint(x: 64, y: 64)
        case .bottomCenter:
            origin = CGPoint(x: (canvasSize.width - boxWidth) / 2.0, y: 64)
        case .topLeft:
            origin = CGPoint(x: 64, y: canvasSize.height - boxHeight - 64)
        case .topRight:
            origin = CGPoint(x: canvasSize.width - boxWidth - 64, y: canvasSize.height - boxHeight - 64)
        }

        if config.showBackgroundScrim {
            ctx.setFillColor(CGColor(red: 0.05, green: 0.07, blue: 0.12, alpha: 0.86))
            let rect = CGRect(origin: origin, size: CGSize(width: boxWidth, height: boxHeight))
            let path = CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil)
            ctx.addPath(path)
            ctx.fillPath()
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

        let headlineFont = NSFont.systemFont(ofSize: CGFloat(config.fontSize), weight: .bold)
        let subtitleFont = NSFont.monospacedSystemFont(ofSize: max(13, CGFloat(config.fontSize * 0.62)), weight: .medium)

        let headlineAttrs: [NSAttributedString.Key: Any] = [
            .font: headlineFont,
            .foregroundColor: NSColor.white
        ]
        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: subtitleFont,
            .foregroundColor: NSColor(calibratedRed: 0.72, green: 0.80, blue: 0.94, alpha: 1.0)
        ]

        let headlineString = NSAttributedString(string: config.headline, attributes: headlineAttrs)
        let subtitleString = NSAttributedString(string: config.subtitle, attributes: subtitleAttrs)

        headlineString.draw(at: CGPoint(x: origin.x + 24, y: origin.y + 52))
        subtitleString.draw(at: CGPoint(x: origin.x + 24, y: origin.y + 20))

        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = ctx.makeImage() else { return nil }
        return CIImage(cgImage: cgImage)
    }
}
