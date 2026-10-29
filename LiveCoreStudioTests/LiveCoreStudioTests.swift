import XCTest
@testable import LiveCoreStudio

final class LiveCoreStudioTests: XCTestCase {

    @MainActor
    func testCutTransitionSwapsPreviewAndProgram() {
        let controller = ProductionController()
        let initialPreview = controller.previewSourceID
        let initialProgram = controller.programSourceID

        XCTAssertNotEqual(initialPreview, initialProgram)
        controller.performCut()

        XCTAssertEqual(controller.programSourceID, initialPreview)
        XCTAssertEqual(controller.previewSourceID, initialProgram)
        XCTAssertFalse(controller.isTransitioning)
    }

    func testSmoothStepProgressCurveBounds() {
        XCTAssertEqual(SwitcherMath.smoothStepProgress(elapsedMs: 0, durationMs: 500), 0.0, accuracy: 0.0001)
        XCTAssertEqual(SwitcherMath.smoothStepProgress(elapsedMs: 250, durationMs: 500), 0.5, accuracy: 0.0001)
        XCTAssertEqual(SwitcherMath.smoothStepProgress(elapsedMs: 500, durationMs: 500), 1.0, accuracy: 0.0001)
        XCTAssertEqual(SwitcherMath.smoothStepProgress(elapsedMs: 750, durationMs: 500), 1.0, accuracy: 0.0001)
    }

    func testAudioChannelLinearGainAndSoloMuteLogic() {
        var channel = AudioChannelState(id: "ch1", name: "Mic 1", gainDB: 0.0, isMuted: false, isSolo: false)
        XCTAssertEqual(channel.linearGain, 1.0, accuracy: 0.001)

        // When another channel is soloed, non-soloed channel effective gain is 0
        XCTAssertEqual(SwitcherMath.effectiveGain(for: channel, anyChannelSoloed: true), 0.0, accuracy: 0.0001)

        // When soloed itself, effective gain matches linearGain
        channel.isSolo = true
        XCTAssertEqual(SwitcherMath.effectiveGain(for: channel, anyChannelSoloed: true), 1.0, accuracy: 0.001)

        // When muted, effective gain is always 0
        channel.isMuted = true
        XCTAssertEqual(SwitcherMath.effectiveGain(for: channel, anyChannelSoloed: true), 0.0, accuracy: 0.0001)
    }

    func testRTMPEndpointParsingAndValidation() throws {
        let descriptor = try RTMPEndpointDescriptor.parse(
            rtmpURL: "rtmps://a.rtmp.youtube.com/live2",
            streamKey: "live_987654321_secret"
        )
        XCTAssertTrue(descriptor.useTLS)
        XCTAssertEqual(descriptor.host, "a.rtmp.youtube.com")
        XCTAssertEqual(descriptor.port, 443)
        XCTAssertEqual(descriptor.appName, "live2")
        XCTAssertEqual(descriptor.streamKey, "live_987654321_secret")

        XCTAssertThrowsError(
            try RTMPEndpointDescriptor.parse(rtmpURL: "https://invalid.example.com/live", streamKey: "key123")
        )
        XCTAssertThrowsError(
            try RTMPEndpointDescriptor.parse(rtmpURL: "rtmp://ingest.example.com/app", streamKey: "   ")
        )
    }
}
