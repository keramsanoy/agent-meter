import XCTest
@testable import AgentMeter

final class UsageParsersTests: XCTestCase {
    func testParsesClaudeUsagePageText() throws {
        let text = """
        Plan usage limits
        Pro
        Current session
        Resets in 4 hr 26 min
        100% used
        All models
        Resets in 3 hr 26 min
        66% used
        """
        let snapshot = try UsageParsers.parse(provider: .claude, text: text, fetchedAt: Date())
        XCTAssertEqual(snapshot.compactLabel, "100/66%")
        XCTAssertEqual(snapshot.meters.count, 2)
    }

    func testParsesCopilotUsage() throws {
        let fetchedAt = ISO8601DateFormatter().date(from: "2026-04-13T12:00:00Z")!
        let text = """
        GitHub Copilot
        Premium requests
        123 of 300 premium requests used
        """
        let snapshot = try UsageParsers.parse(provider: .copilot, text: text, fetchedAt: fetchedAt)
        XCTAssertEqual(snapshot.compactLabel, "41%")
        XCTAssertEqual(snapshot.meters.first?.resetDescription, "Resets in 17 d 12 hr")
    }

    func testParsesCodexRemainingUsageAsUsedUsage() throws {
        let text = """
        Nutzungssaldo
        5 Stunden Nutzungsgrenze
        4 % verbleibend
        Zurücksetzungen 20:31
        Wöchentliche Nutzungsgrenze
        84 % verbleibend
        Zurücksetzungen 16.04.2026 17:22
        """
        let fetchedAt = ISO8601DateFormatter().date(from: "2026-04-13T18:00:00Z")!
        let snapshot = try UsageParsers.parse(provider: .codex, text: text, fetchedAt: fetchedAt)
        XCTAssertEqual(snapshot.provider, .codex)
        XCTAssertEqual(snapshot.meters.map(\.title), ["5-hour usage", "Weekly usage"])
        XCTAssertEqual(snapshot.meters.map { Int($0.percentage ?? -1) }, [96, 16])
        XCTAssertEqual(snapshot.compactLabel, "96/16%")
        XCTAssertTrue(snapshot.meters.allSatisfy { $0.resetDescription?.hasPrefix("Resets in ") == true })
        XCTAssertFalse(snapshot.meters.contains { $0.resetDescription?.localizedCaseInsensitiveContains("Zurücksetzungen") == true })
    }
}
