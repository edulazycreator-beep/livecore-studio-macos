import SwiftUI

@main
struct LiveCoreStudioApp: App {
    @StateObject private var productionController = ProductionController()

    var body: some Scene {
        WindowGroup("LiveCore Studio — Broadcast Production") {
            MainWorkspaceView(controller: productionController)
                .frame(minWidth: 1240, minHeight: 760)
        }
        .commands {
            CommandMenu("Production") {
                Button("Execute CUT Transition") {
                    productionController.performCut()
                }
                .keyboardShortcut("k", modifiers: [.command])

                Button("Execute AUTO Transition") {
                    productionController.performAutoTransition()
                }
                .keyboardShortcut("t", modifiers: [.command])

                Divider()

                Button("Toggle Lower-Third Overlay") {
                    productionController.overlayConfig.isEnabled.toggle()
                }
                .keyboardShortcut("l", modifiers: [.command])
            }
        }
    }
}
