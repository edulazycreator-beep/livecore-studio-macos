import SwiftUI

public struct MainWorkspaceView: View {
    @ObservedObject var controller: ProductionController
    @State private var showSettingsModal: Bool = false

    public init(controller: ProductionController) {
        self.controller = controller
    }

    public var body: some View {
        VStack(spacing: 0) {
            topHeaderBar
            Divider()
            if let err = controller.lastErrorMessage {
                errorBanner(message: err)
            }
            HStack(spacing: 16) {
                MonitorDeckView(
                    label: "PREVIEW (PVW)",
                    badgeColor: .teal,
                    source: controller.previewSource,
                    overlay: controller.overlayConfig,
                    showOverlay: false
                )
                transitionCenterColumn
                MonitorDeckView(
                    label: "PROGRAM (PGM)",
                    badgeColor: .red,
                    source: controller.programSource,
                    overlay: controller.overlayConfig,
                    showOverlay: controller.overlayConfig.isEnabled
                )
            }
            .padding(16)
            .frame(minHeight: 340)

            Divider()

            HStack(alignment: .top, spacing: 16) {
                sourcesPanel
                overlayInspectorPanel
                audioMixerPanel
                outputTransportPanel
            }
            .padding(16)
            .frame(minHeight: 280)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showSettingsModal) {
            SettingsSheetView(controller: controller)
        }
    }

    private var topHeaderBar: some View {
        HStack {
            Text("LiveCore Studio")
                .font(.system(size: 16, weight: .bold))
            Spacer()
            HStack(spacing: 20) {
                Text("GPU: \(controller.metalCompositor.gpuHardwareName)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                Text("FPS: \(String(format: "%.1f", controller.telemetry.activeFPS))")
                    .font(.system(size: 12, design: .monospaced))
                Text("Drops: \(controller.telemetry.frameDropCount)")
                    .font(.system(size: 12, design: .monospaced))
            }
            Spacer()
            Button("Settings & Devices") {
                controller.refreshHardwareDevices()
                showSettingsModal = true
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func errorBanner(message: String) -> some View {
        HStack {
            Text("Alert: \(message)")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
            Spacer()
            Button("Dismiss") {
                controller.lastErrorMessage = nil
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.85))
    }

    private var transitionCenterColumn: some View {
        VStack(spacing: 12) {
            Text("TRANSITION")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)

            Button(action: { controller.performCut() }) {
                Text("CUT")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .frame(width: 110, height: 42)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .keyboardShortcut(.space, modifiers: [])

            Button(action: { controller.performAutoTransition() }) {
                Text(controller.isTransitioning ? "TRANSITIONING" : "AUTO")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .frame(width: 110, height: 42)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .disabled(controller.isTransitioning)

            Picker("Style", selection: $controller.transitionStyle) {
                ForEach(TransitionStyle.allCases) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            .labelsHidden()
            .frame(width: 130)

            HStack(spacing: 4) {
                Text("Duration:")
                    .font(.system(size: 11))
                Text("\(Int(controller.autoTransitionDurationMs)) ms")
                    .font(.system(size: 11, design: .monospaced))
            }

            ProgressView(value: controller.transitionProgress, total: 1.0)
                .frame(width: 110)
        }
        .frame(width: 140)
    }

    private var sourcesPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("01. Video & Image Sources")
                .font(.system(size: 13, weight: .semibold))
            ForEach(controller.sources) { source in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Text("\(source.kind.rawValue) · \(source.resolutionLabel) · \(source.frameRate)fps")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("PVW") {
                        controller.previewSourceID = source.id
                    }
                    .buttonStyle(.bordered)
                    .tint(controller.previewSourceID == source.id ? .teal : .gray)

                    Button("PGM") {
                        controller.programSourceID = source.id
                    }
                    .buttonStyle(.bordered)
                    .tint(controller.programSourceID == source.id ? .red : .gray)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var overlayInspectorPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("02. Lower-Third Text Overlay")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Toggle("On Air", isOn: $controller.overlayConfig.isEnabled)
                    .toggleStyle(.switch)
            }
            TextField("Headline", text: $controller.overlayConfig.headline)
                .textFieldStyle(.roundedBorder)
            TextField("Subtitle", text: $controller.overlayConfig.subtitle)
                .textFieldStyle(.roundedBorder)
            Picker("Position", selection: $controller.overlayConfig.position) {
                ForEach(OverlayPosition.allCases) { pos in
                    Text(pos.rawValue).tag(pos)
                }
            }
            Toggle("Contrast Background Scrim", isOn: $controller.overlayConfig.showBackgroundScrim)
                .font(.system(size: 12))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var audioMixerPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("03. CoreAudio Mixer (dBFS)")
                .font(.system(size: 13, weight: .semibold))
            ForEach($controller.audioChannels) { $channel in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(channel.name)
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Text(String(format: "%.1f dB", channel.gainDB))
                            .font(.system(size: 11, design: .monospaced))
                        Button(channel.isMuted ? "MUTED" : "MUTE") {
                            channel.isMuted.toggle()
                        }
                        .font(.system(size: 10, weight: .bold))
                    }
                    Slider(value: $channel.gainDB, in: -60.0...6.0)
                }
                .padding(6)
                .background(Color.secondary.opacity(0.06))
                .cornerRadius(6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var outputTransportPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("04. Stream & Local Recording")
                .font(.system(size: 13, weight: .semibold))

            VStack(alignment: .leading, spacing: 4) {
                Text("RTMP/RTMPS Endpoint:")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                TextField("rtmps://...", text: $controller.streamSettings.rtmpURL)
                    .textFieldStyle(.roundedBorder)
                SecureField("Stream Key", text: $controller.streamSettings.streamKey)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 8) {
                Button(action: { controller.toggleStream() }) {
                    Text(controller.streamState == .streaming ? "Stop Stream" : "Start RTMP Stream")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(controller.streamState == .streaming ? .red : .blue)

                Button(action: { controller.toggleLocalRecording() }) {
                    Text(controller.recordingState == .recording ? "Stop Rec" : "Record MP4")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(controller.recordingState == .recording ? .red : .secondary)
            }

            Text("Stream Status: \(controller.streamState.rawValue)")
                .font(.system(size: 11, design: .monospaced))
            Text("Recorder Status: \(controller.recordingState.rawValue)")
                .font(.system(size: 11, design: .monospaced))
        }
        .frame(width: 260)
    }
}

struct MonitorDeckView: View {
    let label: String
    let badgeColor: Color
    let source: ProductionSource
    let overlay: TextOverlayConfig
    let showOverlay: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(badgeColor)
                Spacer()
                Text("\(source.resolutionLabel) · \(source.frameRate)fps")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black)

                VStack(spacing: 6) {
                    Text(source.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    Text(source.kind.rawValue)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showOverlay && (!overlay.headline.isEmpty || !overlay.subtitle.isEmpty) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(overlay.headline)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                        Text(overlay.subtitle)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(10)
                    .background(Color.black.opacity(0.78))
                    .cornerRadius(6)
                    .padding(14)
                }
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
        }
        .frame(maxWidth: .infinity)
    }
}

struct SettingsSheetView: View {
    @ObservedObject var controller: ProductionController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Hardware Devices & VideoToolbox Encoder Settings")
                .font(.system(size: 16, weight: .bold))

            GroupBox("Discovered AVFoundation Video Inputs (\(controller.discoveredVideoDevices.count))") {
                if controller.discoveredVideoDevices.isEmpty {
                    Text("No physical camera detected or permission pending. Built-in test & media sources remain operational.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(controller.discoveredVideoDevices) { dev in
                        Text("\(dev.localizedName) (\(dev.id))")
                            .font(.system(size: 12, design: .monospaced))
                    }
                }
            }

            GroupBox("VideoToolbox Encoder & Local Output") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Hardware Acceleration (Apple Silicon VideoToolbox H.264)", isOn: $controller.streamSettings.useHardwareEncoding)
                    HStack {
                        Text("Video Bitrate (Kbps):")
                        TextField("Bitrate", value: $controller.streamSettings.videoBitrateKbps, format: .number)
                            .frame(width: 100)
                    }
                    HStack {
                        Text("Recording Directory:")
                        TextField("Path", text: $controller.streamSettings.recordingDirectoryPath)
                    }
                }
                .padding(6)
            }

            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 560)
    }
}
