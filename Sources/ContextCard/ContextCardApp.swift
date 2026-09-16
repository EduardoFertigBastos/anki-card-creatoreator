import SwiftUI
import AppKit
import CoreFoundation

@main
struct ContextCardApp: App {
    @NSApplicationDelegateAdaptor(ContextCardAppDelegate.self) private var appDelegate
    @StateObject private var model = CardComposerModel.shared

    var body: some Scene {
        Settings {
            SettingsView(model: model)
        }
    }
}

private struct MenuBarPanel: View {
    @ObservedObject var model: CardComposerModel

    var body: some View {
        VStack(spacing: 0) {
            ContentView(model: model)

            Divider()

            HStack(spacing: 12) {
                Button {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
                }
                .buttonStyle(.plain)
            }
            .font(.callout)
            .padding(.horizontal, 18)
            .frame(height: 44)
        }
        .frame(width: MenuBarPanelLayout.width, height: MenuBarPanelLayout.height)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 0.5)
        }
    }
}

private enum MenuBarPanelLayout {
    static let width: CGFloat = 340
    static let height: CGFloat = 720
    static let screenMargin: CGFloat = 8
    static let menuBarGap: CGFloat = 4
}

private final class ContextCardPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53 {
            onCancel?()
            return
        }

        super.sendEvent(event)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

@MainActor
private final class ContextCardAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var panel: ContextCardPanel?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        configurePanel()

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
        removeEventMonitors()
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

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "rectangle.stack.fill", accessibilityDescription: "ContextCard")
        button.image?.isTemplate = true
        button.target = self
        button.action = #selector(togglePanel)
        self.statusItem = statusItem
    }

    private func configurePanel() {
        let panel = ContextCardPanel(
            contentRect: NSRect(
                origin: .zero,
                size: NSSize(width: MenuBarPanelLayout.width, height: MenuBarPanelLayout.height)
            ),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.onCancel = { [weak self] in
            self?.hidePanel()
        }
        panel.contentViewController = NSHostingController(
            rootView: MenuBarPanel(model: CardComposerModel.shared)
        )
        self.panel = panel
    }

    @objc private func togglePanel() {
        guard let panel else { return }
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let panel,
              let button = statusItem?.button,
              let buttonWindow = button.window,
              let screen = buttonWindow.screen ?? NSScreen.main else { return }

        let statusFrame = buttonWindow.convertToScreen(button.frame)
        let visibleFrame = screen.visibleFrame
        let panelOrigin = NSPoint(
            x: visibleFrame.maxX - MenuBarPanelLayout.width - MenuBarPanelLayout.screenMargin,
            y: min(
                statusFrame.minY - MenuBarPanelLayout.height - MenuBarPanelLayout.menuBarGap,
                visibleFrame.maxY - MenuBarPanelLayout.height
            )
        )

        panel.setFrameOrigin(panelOrigin)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installEventMonitors()
    }

    private func hidePanel() {
        CardComposerModel.shared.stopVoiceInput()
        panel?.orderOut(nil)
        removeEventMonitors()
    }

    private func installEventMonitors() {
        removeEventMonitors()
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                self.hidePanel()
                return nil
            }
            if event.window !== self.panel, event.window !== self.statusItem?.button?.window {
                self.hidePanel()
            }
            return event
        }
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return }
            if event.type == .keyDown, event.keyCode == 53 {
                self.hidePanel()
            } else if event.type == .leftMouseDown || event.type == .rightMouseDown {
                self.hidePanel()
            }
        }
    }

    private func removeEventMonitors() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
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
