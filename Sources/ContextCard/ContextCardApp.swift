import SwiftUI
import AppKit

@main
struct ContextCardApp: App {
    @StateObject private var model = CardComposerModel()

    var body: some Scene {
        WindowGroup("ContextCard") {
            ContentView(model: model)
                .frame(minWidth: 820, minHeight: 640)
        }
        .windowResizability(.contentSize)

        MenuBarExtra("ContextCard", systemImage: "character.book.closed") {
            Button("Open ContextCard") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first(where: { $0.title == "ContextCard" })?.makeKeyAndOrderFront(nil)
            }
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
        }

        Settings {
            SettingsView(model: model)
        }
    }
}
