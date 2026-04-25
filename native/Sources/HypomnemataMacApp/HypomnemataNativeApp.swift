import SwiftUI

@main
struct HypomnemataNativeApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 680)
                .onChange(of: model.query) { _, _ in
                    model.recordUserActivity()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    model.prepareForQuit()
                }
                .onOpenURL { url in
                    _ = model.openExternalCapture(url)
                }
        }
        .handlesExternalEvents(matching: ["capture"])
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Nova captura") {
                    model.openCapture()
                }
                .keyboardShortcut("k", modifiers: [.command])

                Button("Bloquear vault") {
                    model.lock()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(!model.isUnlocked)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}
