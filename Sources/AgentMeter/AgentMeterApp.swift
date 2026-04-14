import AppKit
import SwiftUI

@main
struct AgentMeterApp: App {
    @StateObject private var model = AgentMeterModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model)
        } label: {
            MenuBarStatusLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}


private struct MenuBarStatusLabel: View {
    @ObservedObject var model: AgentMeterModel

    var body: some View {
        switch model.displayMode {
        case .text:
            Text(model.menuBarTitle)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
        case .bar:
            MenuBarCompactUsageBar(values: model.menuBarBarValues, isRefreshing: model.isRefreshing)
        }
    }
}

private struct MenuBarCompactUsageBar: View {
    let values: [(provider: AgentProvider, percentage: Double?)]
    let isRefreshing: Bool

    var body: some View {
        Image(nsImage: Self.image(values: values, isRefreshing: isRefreshing))
            .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let parts = values.map { value in
            let label = value.percentage.map { "\(Int($0.rounded())) percent used" } ?? "unavailable"
            return "\(value.provider.displayName) \(label)"
        }
        return parts.isEmpty ? "Agent Meter usage unavailable" : parts.joined(separator: ", ")
    }

    private static func image(values: [(provider: AgentProvider, percentage: Double?)], isRefreshing: Bool) -> NSImage {
        let percentages = values.isEmpty ? [nil] : values.map(\.percentage)
        let segmentWidth: CGFloat = 18
        let segmentHeight: CGFloat = 9
        let spacing: CGFloat = 2
        let imageSize = NSSize(width: CGFloat(percentages.count) * segmentWidth + CGFloat(max(percentages.count - 1, 0)) * spacing, height: 12)
        let image = NSImage(size: imageSize)

        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: imageSize).fill()

        let hasValues = percentages.contains { $0 != nil }
        let alpha: CGFloat = hasValues || isRefreshing ? 1 : 0.55

        for (index, percentage) in percentages.enumerated() {
            let x = CGFloat(index) * (segmentWidth + spacing)
            let y = (imageSize.height - segmentHeight) / 2
            let backgroundRect = NSRect(x: x, y: y, width: segmentWidth, height: segmentHeight)
            let backgroundPath = NSBezierPath(roundedRect: backgroundRect, xRadius: 3, yRadius: 3)
            NSColor.separatorColor.withAlphaComponent(0.35 * alpha).setFill()
            backgroundPath.fill()

            let progress = max(0, min((percentage ?? 0) / 100, 1))
            let fillWidth = max(1, segmentWidth * CGFloat(progress))
            let fillRect = NSRect(x: x, y: y, width: fillWidth, height: segmentHeight)
            let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 3, yRadius: 3)
            fillColor(percentage: percentage, progress: progress, alpha: alpha).setFill()
            fillPath.fill()

            NSColor.separatorColor.withAlphaComponent(0.55 * alpha).setStroke()
            backgroundPath.lineWidth = 0.5
            backgroundPath.stroke()
        }

        image.isTemplate = false
        return image
    }

    private static func fillColor(percentage: Double?, progress: Double, alpha: CGFloat) -> NSColor {
        guard percentage != nil else { return NSColor.secondaryLabelColor.withAlphaComponent(0.5 * alpha) }
        return NSColor(calibratedHue: CGFloat(0.34 * (1 - progress)), saturation: 0.82, brightness: 0.9, alpha: alpha)
    }
}

private struct MenuContentView: View {
    @ObservedObject var model: AgentMeterModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Agent Meter")
                    .font(.headline)
                Spacer()
                Text("Auto-updates every 10 min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(AgentProvider.allCases.filter { model.isEnabled($0) }) { provider in
                ProviderSection(
                    provider: provider,
                    snapshot: model.snapshots[provider],
                    error: model.lastErrors[provider],
                    format: model.format
                )
                if provider != AgentProvider.allCases.filter({ model.isEnabled($0) }).last { Divider() }
            }

            if model.enabledProviders.isEmpty {
                Text("Enable at least one provider in Settings.")
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Button("Refresh Now") { model.refresh() }
                    .disabled(model.isRefreshing || model.enabledProviders.isEmpty)
                Button("Settings...") { model.openSettings() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(18)
        .frame(width: 580)
    }
}

private struct ProviderSection: View {
    let provider: AgentProvider
    let snapshot: UsageSnapshot?
    let error: String?
    let format: (Date) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(provider.displayName).font(.headline)
                Spacer()
            }

            if let snapshot {
                ForEach(snapshot.meters) { meter in
                    UsageMeterRow(meter: meter)
                }
                DetailRow(label: "Fetched", value: format(snapshot.fetchedAt))
            } else {
                UsageMeterRow(meter: UsageMeter(
                    id: provider.id,
                    title: provider.defaultMeterTitle,
                    resetDescription: "Sign in with the app browser once if needed, then usage refreshes in the background.",
                    percentage: nil,
                    used: nil,
                    limit: nil
                ))
            }

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct UsageMeterRow: View {
    let meter: UsageMeter

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(meter.title)
                    .font(.system(size: 14, weight: .semibold))
                Text(meter.resetDescription ?? "Reset time unavailable")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(width: 190, alignment: .leading)

            UsageProgressBar(value: meter.percentage)
                .frame(height: 10)

            Text(meter.percentage.map { "\(Int($0.rounded()))% used" } ?? "--")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 82, alignment: .trailing)
        }
    }
}

private struct UsageProgressBar: View {
    let value: Double?
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: .separatorColor).opacity(0.35))
                RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: .systemBlue)).frame(width: proxy.size.width * clampedProgress)
            }
            .overlay { RoundedRectangle(cornerRadius: 3).stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 0.5) }
        }
    }
    private var clampedProgress: Double { max(0, min((value ?? 0) / 100, 1)) }
}

private struct DetailRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.caption)
    }
}

struct PreferencesView: View {
    @ObservedObject var model: AgentMeterModel

    var body: some View {
        Form {
            Section("Providers") {
                ForEach(AgentProvider.allCases) { provider in
                    Toggle(provider.displayName, isOn: Binding(
                        get: { model.isEnabled(provider) },
                        set: { model.setEnabled(provider, enabled: $0) }
                    ))
                }
            }

            Section("Menu Bar") {
                Picker("Display", selection: $model.displayMode) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Text("Low-space bar mode uses one tiny segment per enabled provider. The fill level is the highest current usage for that provider, shifting from green toward red as it fills.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Browser Access") {
                Text("Agent Meter uses app-owned WebKit browser sessions to load enabled provider usage pages in the background and read visible usage values.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(AgentProvider.allCases) { provider in
                    HStack {
                        Text(provider.displayName)
                        Spacer()
                        Button("Open Meter Page") { model.openBrowser(for: provider) }
                    }
                }

                Text("Sign in once per service if needed. Passwords are not stored by the app; WebKit keeps session cookies like a normal browser.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Status") {
                DetailRow(label: "Last success", value: model.lastSuccessfulRefresh.map(model.format) ?? "Never")
                DetailRow(label: "Refresh", value: "Every 10 minutes")
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 560)
    }
}
