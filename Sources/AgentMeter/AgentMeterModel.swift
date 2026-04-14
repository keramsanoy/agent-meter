import AppKit
import Combine
import Foundation

@MainActor
final class AgentMeterModel: ObservableObject {
    @Published private(set) var snapshots: [AgentProvider: UsageSnapshot] = [:]
    @Published private(set) var lastErrors: [AgentProvider: String] = [:]
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastSuccessfulRefresh: Date?

    @Published var enabledProviders: Set<AgentProvider> {
        didSet { saveEnabledProviders(); restartAutoRefresh() }
    }

    @Published var displayMode: MenuBarDisplayMode {
        didSet { UserDefaults.standard.set(displayMode.rawValue, forKey: MenuBarDisplayMode.defaultsKey) }
    }

    private let browsers: [AgentProvider: ProviderBrowser]
    private var refreshTask: Task<Void, Never>?
    private var settingsWindowController: SettingsWindowController?
    private let refreshInterval: TimeInterval = 600

    var menuBarTitle: String {
        let parts = AgentProvider.allCases.filter { enabledProviders.contains($0) }.compactMap { provider -> String? in
            guard let snapshot = snapshots[provider] else { return nil }
            return "\(provider.shortLabel) \(snapshot.compactLabel)"
        }
        if !parts.isEmpty { return parts.joined(separator: "  ") }
        return isRefreshing ? "..." : "--"
    }

    var menuBarBarValues: [(provider: AgentProvider, percentage: Double?)] {
        AgentProvider.allCases.filter { enabledProviders.contains($0) }.map { provider in
            let percentage = snapshots[provider]?.meters.compactMap(\.percentage).max()
            return (provider, percentage)
        }
    }

    init() {
        self.enabledProviders = Self.loadEnabledProviders()
        self.displayMode = Self.loadDisplayMode()
        var browserMap: [AgentProvider: ProviderBrowser] = [:]
        for provider in AgentProvider.allCases { browserMap[provider] = ProviderBrowser(provider: provider) }
        self.browsers = browserMap
        self.settingsWindowController = SettingsWindowController(model: self)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            self.restartAutoRefresh()
        }
    }

    deinit { refreshTask?.cancel() }

    func isEnabled(_ provider: AgentProvider) -> Bool { enabledProviders.contains(provider) }

    func setEnabled(_ provider: AgentProvider, enabled: Bool) {
        if enabled { enabledProviders.insert(provider) } else { enabledProviders.remove(provider); snapshots.removeValue(forKey: provider); lastErrors.removeValue(forKey: provider) }
    }

    func refresh() { Task { await refreshNow() } }

    func refreshNow() async {
        isRefreshing = true
        defer { isRefreshing = false }
        for provider in AgentProvider.allCases where enabledProviders.contains(provider) {
            do {
                guard let browser = browsers[provider] else { continue }
                let snapshot = try await browser.fetchUsage()
                snapshots[provider] = snapshot
                lastErrors.removeValue(forKey: provider)
                lastSuccessfulRefresh = snapshot.fetchedAt
            } catch {
                lastErrors[provider] = error.localizedDescription
            }
        }
    }

    func openBrowser(for provider: AgentProvider) { browsers[provider]?.openInteractiveBrowser() }
    func openUsagePage(for provider: AgentProvider) { NSWorkspace.shared.open(provider.usageURL) }
    func openSettings() { settingsWindowController?.show() }

    func format(_ date: Date) -> String {
        Self.dateFormatter.string(from: date)
    }

    private func restartAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshNow()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.refreshInterval * 1_000_000_000))
                if !Task.isCancelled { await self.refreshNow() }
            }
        }
    }

    private func saveEnabledProviders() {
        for provider in AgentProvider.allCases { UserDefaults.standard.set(enabledProviders.contains(provider), forKey: provider.enabledDefaultsKey) }
    }

    private static func loadEnabledProviders() -> Set<AgentProvider> {
        var enabled = Set<AgentProvider>()
        for provider in AgentProvider.allCases {
            if UserDefaults.standard.object(forKey: provider.enabledDefaultsKey) == nil {
                enabled.insert(provider)
            } else if UserDefaults.standard.bool(forKey: provider.enabledDefaultsKey) {
                enabled.insert(provider)
            }
        }
        return enabled
    }

    private static func loadDisplayMode() -> MenuBarDisplayMode {
        guard let rawValue = UserDefaults.standard.string(forKey: MenuBarDisplayMode.defaultsKey),
              let mode = MenuBarDisplayMode(rawValue: rawValue) else { return .text }
        return mode
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}
