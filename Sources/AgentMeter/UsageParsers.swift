import Foundation

enum UsageParsers {
    static func parse(provider: AgentProvider, text: String, fetchedAt: Date) throws -> UsageSnapshot {
        switch provider {
        case .claude: try parseClaude(text: text, fetchedAt: fetchedAt)
        case .copilot: try parseCopilot(text: text, fetchedAt: fetchedAt)
        case .codex: try parseCodex(text: text, fetchedAt: fetchedAt)
        }
    }

    static func parseClaude(text: String, fetchedAt: Date) throws -> UsageSnapshot {
        let pageLines = lines(from: text)
        let meters = [
            meter(id: "current_session", title: "Current session", lines: pageLines, window: 8),
            meter(id: "all_models", title: "All models", lines: pageLines, window: 8)
        ].compactMap { $0 }
        guard !meters.isEmpty else { throw UsageParseError.unparseablePayload }
        return UsageSnapshot(provider: .claude, planName: planName(from: pageLines), meters: meters, fetchedAt: fetchedAt)
    }

    static func parseCopilot(text: String, fetchedAt: Date) throws -> UsageSnapshot {
        let normalized = text.replacingOccurrences(of: "\u{00a0}", with: " ")
        guard normalized.localizedCaseInsensitiveContains("copilot") else { throw UsageParseError.unparseablePayload }
        let numericText = normalized.replacingOccurrences(of: ",", with: "")
        let usage = firstTwoNumbers(in: numericText)
        let percent = usage.flatMap { used, limit in limit > 0 ? used / limit * 100 : nil } ?? firstPercentage(in: numericText)
        guard usage != nil || percent != nil else { throw UsageParseError.unparseablePayload }
        let resetAt = nextMonthlyReset(after: fetchedAt)
        let meter = UsageMeter(
            id: "github_copilot_premium_requests",
            title: "Copilot premium requests",
            resetDescription: countdown(to: resetAt, from: fetchedAt),
            percentage: percent,
            used: usage?.used,
            limit: usage?.limit
        )
        return UsageSnapshot(provider: .copilot, planName: planName(from: lines(from: text)), meters: [meter], fetchedAt: fetchedAt)
    }

    static func parseCodex(text: String, fetchedAt: Date) throws -> UsageSnapshot {
        let normalized = text.replacingOccurrences(of: "\u{00a0}", with: " ")
        let pageLines = lines(from: normalized)
        if normalized.localizedCaseInsensitiveContains("log in") && !normalized.localizedCaseInsensitiveContains("usage") {
            throw UsageParseError.needsSignIn("ChatGPT")
        }

        let meters = [
            codexMeter(id: "codex_5_hour", title: "5-hour usage", anchors: ["5 stunden", "5 hours", "5-hour"], lines: pageLines, fetchedAt: fetchedAt),
            codexMeter(id: "codex_weekly", title: "Weekly usage", anchors: ["wöchentliche", "woechentliche", "weekly"], lines: pageLines, fetchedAt: fetchedAt)
        ].compactMap { $0 }

        if !meters.isEmpty {
            return UsageSnapshot(provider: .codex, planName: "ChatGPT", meters: meters, fetchedAt: fetchedAt)
        }

        let percent = usagePercentage(in: normalized)
        let usage = firstTwoNumbers(in: normalized.replacingOccurrences(of: ",", with: ""))
        guard usage != nil || percent != nil else { throw UsageParseError.unparseablePayload }
        let resetText = pageLines.first { isResetLine($0) }
        let meter = UsageMeter(
            id: "chatgpt_codex_cloud_usage",
            title: "Codex Cloud usage",
            resetDescription: codexResetDescription(from: resetText, fetchedAt: fetchedAt),
            percentage: percent ?? usage.flatMap { used, limit in limit > 0 ? used / limit * 100 : nil },
            used: usage?.used,
            limit: usage?.limit
        )
        return UsageSnapshot(provider: .codex, planName: "ChatGPT", meters: [meter], fetchedAt: fetchedAt)
    }

    private static func codexMeter(id: String, title: String, anchors: [String], lines: [String], fetchedAt: Date) -> UsageMeter? {
        guard let index = lines.firstIndex(where: { line in
            let folded = fold(line)
            return anchors.contains { folded.localizedCaseInsensitiveContains(fold($0)) }
        }) else { return nil }
        let nextLines = lines[index..<min(lines.endIndex, index + 8)]
        let joined = nextLines.joined(separator: " ")
        guard let percentage = usagePercentage(in: joined) else { return nil }
        let resetText = nextLines.first(where: isResetLine)
        return UsageMeter(id: id, title: title, resetDescription: codexResetDescription(from: resetText, fetchedAt: fetchedAt), percentage: percentage, used: nil, limit: nil)
    }

    private static func codexResetDescription(from line: String?, fetchedAt: Date) -> String? {
        guard let line else { return nil }
        guard let resetAt = codexResetDate(from: line, relativeTo: fetchedAt) else { return "Resets in unavailable" }
        return countdown(to: resetAt, from: fetchedAt)
    }

    private static func codexResetDate(from line: String, relativeTo fetchedAt: Date) -> Date? {
        let normalized = line.replacingOccurrences(of: "\u{00a0}", with: " ")
        let locale = Locale(identifier: "en_US_POSIX")

        if let date = firstDateMatch(in: normalized, pattern: #"\b(\d{1,2}\.\d{1,2}\.\d{4}\s+\d{1,2}:\d{2})\b"#, format: "d.M.yyyy H:mm", locale: locale) {
            return date
        }

        guard let time = firstDateMatch(in: normalized, pattern: #"\b(\d{1,2}:\d{2})\b"#, format: "H:mm", locale: locale) else { return nil }
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        let fetchedComponents = calendar.dateComponents([.year, .month, .day], from: fetchedAt)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        guard var resetAt = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: fetchedComponents.year,
            month: fetchedComponents.month,
            day: fetchedComponents.day,
            hour: timeComponents.hour,
            minute: timeComponents.minute
        )) else { return nil }
        if resetAt < fetchedAt {
            resetAt = calendar.date(byAdding: .day, value: 1, to: resetAt) ?? resetAt
        }
        return resetAt
    }

    private static func firstDateMatch(in text: String, pattern: String, format: String, locale: Locale) -> Date? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), let matchRange = Range(match.range(at: 1), in: text) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = format
        return formatter.date(from: String(text[matchRange]))
    }

    private static func usagePercentage(in text: String) -> Double? {
        guard let percentage = firstPercentage(in: text) else { return nil }
        let folded = fold(text)
        if folded.localizedCaseInsensitiveContains("remaining") || folded.localizedCaseInsensitiveContains("verbleibend") {
            return max(0, min(100, 100 - percentage))
        }
        return percentage
    }

    private static func isResetLine(_ line: String) -> Bool {
        let folded = fold(line)
        return folded.localizedCaseInsensitiveContains("reset") || folded.localizedCaseInsensitiveContains("zurucksetzung")
    }

    private static func fold(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    private static func meter(id: String, title: String, lines: [String], window: Int) -> UsageMeter? {
        guard let index = lines.firstIndex(where: { $0.caseInsensitiveCompare(title) == .orderedSame }) else { return nil }
        let nextLines = lines[(index + 1)..<min(lines.endIndex, index + window)]
        let resetText = nextLines.first { $0.localizedCaseInsensitiveContains("resets in") || $0.localizedCaseInsensitiveContains("reset") }
        let percentage = nextLines.compactMap(firstPercentage).first
        guard resetText != nil || percentage != nil else { return nil }
        return UsageMeter(id: id, title: title, resetDescription: resetText, percentage: percentage, used: nil, limit: nil)
    }

    private static func lines(from text: String) -> [String] {
        text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private static func planName(from lines: [String]) -> String? {
        lines.first { line in ["Free", "Pro", "Max", "Team", "Enterprise", "Copilot"].contains { line.localizedCaseInsensitiveContains($0) } }
    }

    private static func firstPercentage(in text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*%"#, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), let numberRange = Range(match.range(at: 1), in: text) else { return nil }
        return Double(text[numberRange])
    }

    private static func firstTwoNumbers(in text: String) -> (used: Double, limit: Double)? {
        let patterns = [#"(\d+(?:\.\d+)?)\s*(?:of|/)\s*(\d+(?:\.\d+)?)\s*(?:premium\s+requests?|requests?|used)?"#, #"used\s*(\d+(?:\.\d+)?)\s*(?:of|/)\s*(\d+(?:\.\d+)?)"#]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges >= 3 else { continue }
            guard let firstRange = Range(match.range(at: 1), in: text), let secondRange = Range(match.range(at: 2), in: text), let first = Double(text[firstRange]), let second = Double(text[secondRange]) else { continue }
            return (first, second)
        }
        return nil
    }

    private static func nextMonthlyReset(after date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let components = calendar.dateComponents([.year, .month], from: date)
        let start = calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: components.year, month: components.month, day: 1)) ?? date
        return calendar.date(byAdding: .month, value: 1, to: start) ?? date
    }

    private static func countdown(to resetAt: Date, from fetchedAt: Date) -> String {
        let seconds = max(0, Int(resetAt.timeIntervalSince(fetchedAt)))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "Resets in \(days) d \(hours) hr" }
        if hours > 0 { return "Resets in \(hours) hr \(minutes) min" }
        return "Resets in \(minutes) min"
    }
}
