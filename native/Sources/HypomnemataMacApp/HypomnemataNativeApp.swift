import SwiftUI

@main
struct HypomnemataNativeApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 680)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Nova captura") {
                    model.showCapture = true
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
