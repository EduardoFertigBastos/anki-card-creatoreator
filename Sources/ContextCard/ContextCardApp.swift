import SwiftUI

@main
struct ContextCardApp: App {
    @StateObject private var model = CardComposerModel()

    var body: some Scene {
        WindowGroup("ContextCard") {
            ContentView(model: model)
                .frame(minWidth: 820, minHeight: 640)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView(model: model)
        }
    }
}
