import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private weak var model: AgentMeterModel?
    private var window: NSWindow?

    init(model: AgentMeterModel) {
        self.model = model
    }

    func show() {
        guard let model else { return }
        let window = window ?? makeWindow(model: model)
        self.window = window
        dismissMenuExtraWindow(except: window)
        NSApp.activate(ignoringOtherApps: true)
        window.level = .modalPanel
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func dismissMenuExtraWindow(except settingsWindow: NSWindow) {
        for candidate in NSApp.windows where candidate !== settingsWindow {
            guard candidate.isVisible, candidate.title.isEmpty else { continue }
            candidate.orderOut(nil)
        }
    }

    private func makeWindow(model: AgentMeterModel) -> NSWindow {
        let controller = NSHostingController(rootView: PreferencesView(model: model))
        let window = SettingsWindow(contentViewController: controller)
        window.title = "Agent Meter Settings"
        window.setContentSize(NSSize(width: 560, height: 520))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.level = .modalPanel
        window.isReleasedWhenClosed = false
        return window
    }
}

final class SettingsWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
