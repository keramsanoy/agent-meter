import Foundation

struct UsageSnapshot: Equatable, Sendable {
    let provider: AgentProvider
    let planName: String?
    let meters: [UsageMeter]
    let fetchedAt: Date

    var compactLabel: String {
        let values = meters.compactMap(\.percentage).prefix(2).map { "\(Int($0.rounded()))" }
        return values.isEmpty ? "--" : "\(values.joined(separator: "/"))%"
    }
}

struct UsageMeter: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let resetDescription: String?
    let percentage: Double?
    let used: Double?
    let limit: Double?
}

enum MenuBarDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case text
    case bar

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .text: "Text percentages"
        case .bar: "Low-space bar"
        }
    }

    static let defaultsKey = "menuBar.displayMode"
}


enum AgentProvider: String, CaseIterable, Identifiable, Sendable {
    case claude
    case copilot
    case codex

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .claude: "C"
        case .copilot: "GH"
        case .codex: "GPT"
        }
    }

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .copilot: "GitHub Copilot"
        case .codex: "Codex Cloud"
        }
    }

    var defaultMeterTitle: String {
        switch self {
        case .claude: "Current session"
        case .copilot: "Premium requests"
        case .codex: "Codex usage"
        }
    }

    var usageURL: URL {
        switch self {
        case .claude: URL(string: "https://claude.ai/settings/usage")!
        case .copilot: URL(string: "https://github.com/settings/copilot/features")!
        case .codex: URL(string: "https://chatgpt.com/codex/cloud/settings/usage")!
        }
    }

    var enabledDefaultsKey: String { "provider.\(rawValue).enabled" }
}

enum UsageParseError: LocalizedError {
    case unparseablePayload
    case emptyPageText
    case needsSignIn(String)

    var errorDescription: String? {
        switch self {
        case .unparseablePayload: "Usage page did not include recognizable usage values"
        case .emptyPageText: "Usage page loaded, but no readable text was found"
        case .needsSignIn(let provider): "Sign in to \(provider) in the app browser"
        }
    }
}
