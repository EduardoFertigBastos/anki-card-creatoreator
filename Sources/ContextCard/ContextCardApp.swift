import SwiftUI
import AppKit
import CoreFoundation

@main
struct ContextCardApp: App {
    @NSApplicationDelegateAdaptor(ContextCardAppDelegate.self) private var appDelegate
    @StateObject private var model = CardComposerModel.shared

    var body: some Scene {
        WindowGroup("ContextCard Project Build") {
            ContentView(model: model)
                .frame(minWidth: 520, idealWidth: 560, minHeight: 700, idealHeight: 760)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit ContextCard") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }

        MenuBarExtra {
            Button("Open ContextCard") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first(where: { $0.title == "ContextCard" })?.makeKeyAndOrderFront(nil)
            }
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
        } label: {
            Image(nsImage: ContextCardIcon.menuBarImage)
        }

        Settings {
            SettingsView(model: model)
        }
    }
}

@MainActor
private final class ContextCardAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            contextCardSyncQueueCallback,
            contextCardSyncQueueNotificationName.rawValue,
            nil,
            .deliverImmediately
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            contextCardSyncQueueNotificationName,
            nil
        )
    }

    func handleSyncQueueRequest() {
        CardComposerModel.shared.syncPendingCards(waitForAnki: true)
    }
}

private let contextCardSyncQueueNotificationName = CFNotificationName(
    rawValue: "com.contextcard.syncQueueRequested" as CFString
)

private let contextCardSyncQueueCallback: CFNotificationCallback = { _, observer, _, _, _ in
    guard let observer else { return }
    let appDelegate = Unmanaged<ContextCardAppDelegate>.fromOpaque(observer).takeUnretainedValue()
    Task { @MainActor in
        appDelegate.handleSyncQueueRequest()
    }
}

private enum ContextCardIcon {
    static let menuBarImage: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()

        NSColor.black.setFill()

        let backCard = NSBezierPath(roundedRect: NSRect(x: 3.1, y: 8.6, width: 11.4, height: 6.7), xRadius: 1.4, yRadius: 1.4)
        backCard.fill()

        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 5.2, y: 12.2, width: 7.2, height: 0.9)).fill()
        NSColor.black.setFill()

        let middleCard = NSBezierPath(roundedRect: NSRect(x: 2.3, y: 5.7, width: 12.6, height: 7.2), xRadius: 1.5, yRadius: 1.5)
        middleCard.fill()

        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 4.7, y: 9.6, width: 7.5, height: 0.95)).fill()
        NSColor.black.setFill()

        let frontCard = NSBezierPath(roundedRect: NSRect(x: 1.6, y: 2.5, width: 13.7, height: 7.7), xRadius: 1.6, yRadius: 1.6)
        frontCard.fill()

        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 4.3, y: 6.7, width: 7.7, height: 1.0)).fill()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }()
}
