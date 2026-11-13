import Foundation
import XCTest

final class HistoryTests: XCTestCase {
    private func transition(_ from: String, _ to: String, _ time: Double,
                            action: String = "startStop") -> String {
        "{\"type\":\"transition\",\"timestamp\":\(time),\"event\":\"\(action)\",\"fromState\":\"\(from)\",\"toState\":\"\(to)\"}"
    }

    private func parse(_ lines: [String]) -> TBHistorySnapshot {
        TBHistory.parse(Data((lines.joined(separator: "\n") + "\n").utf8))
    }

    func testCompletedFocusSkippedRestAndInterruptedFocus() {
        let history = parse([
            "{\"type\":\"appstart\",\"timestamp\":0}",
            transition("idle", "work", 0),
            transition("work", "rest", 1500, action: "timerFired"),
            transition("rest", "work", 1680, action: "skipRest"),
            transition("work", "idle", 2400),
        ])
        XCTAssertEqual(history.intervals.map(\.kind), [.work, .rest, .work])
        XCTAssertEqual(history.intervals.map(\.duration), [1500, 180, 720])
        XCTAssertTrue(history.damagedLines.isEmpty)
    }

    func testReadsMixedHistoryUsingUnixTimestamps() {
        let history = parse([
            transition("idle", "work", 10),
            #"{"type":"transition","timestamp":30,"event":"startStop","fromState":"work","toState":"idle","localTime":"1970-01-01T01:00:30+01:00"}"#,
        ])
        XCTAssertEqual(history.intervals.map(\.duration), [20])
        XCTAssertTrue(history.damagedLines.isEmpty)
    }

    func testAppStartDiscardsOnlyUnfinishedPreviousInterval() {
        let history = parse([
            transition("idle", "work", 0), transition("work", "idle", 12),
            transition("idle", "work", 20),
            "{\"type\":\"appstart\",\"timestamp\":1000}",
            transition("idle", "work", 1001), transition("work", "idle", 1013),
        ])
        XCTAssertEqual(history.intervals.map(\.duration), [12, 12])
    }

    func testOpenIntervalsAndIdleTimeAreNotCounted() {
        let history = parse([
            transition("idle", "work", 100), transition("work", "idle", 112),
            transition("idle", "work", 1000),
        ])
        XCTAssertEqual(history.intervals.count, 1)
        XCTAssertEqual(history.intervals.first?.duration, 12)
    }

    func testDamagedLineBreaksPairingAndLaterValidIntervalsAreRecovered() {
        let history = parse([
            transition("idle", "work", 0), "broken JSON",
            transition("work", "rest", 1500, action: "timerFired"),
            transition("rest", "idle", 1680),
        ])
        XCTAssertEqual(history.damagedLines, [2])
        XCTAssertEqual(history.intervals.map(\.kind), [.rest])
        XCTAssertEqual(history.intervals.map(\.duration), [180])
    }

    func testPartialFinalLineIsNotACompletedInterval() {
        let text = transition("idle", "work", 0) + "\n" + transition("work", "idle", 12)
        let history = TBHistory.parse(Data(text.utf8))
        XCTAssertTrue(history.intervals.isEmpty)
        XCTAssertEqual(history.damagedLines, [2])
    }

    func testStopAfterBreakProducesNoNewFocus() {
        let history = parse([
            transition("idle", "work", 0),
            transition("work", "rest", 1500, action: "timerFired"),
            transition("rest", "idle", 1800, action: "timerFired"),
        ])
        XCTAssertEqual(history.intervals.map(\.kind), [.work, .rest])
        XCTAssertEqual(history.intervals.map(\.duration), [1500, 300])
    }

    func testMissingFileRepresentsFirstUse() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let history = try TBHistory.read(from: url)
        XCTAssertTrue(history.intervals.isEmpty)
        XCTAssertTrue(history.damagedLines.isEmpty)
    }

    func testReadFailureIsNotAnEmptyHistory() {
        XCTAssertThrowsError(try TBHistory.read(from: FileManager.default.temporaryDirectory))
    }

    func testUnknownTransitionBreaksTheCurrentInterval() {
        let history = parse([
            transition("idle", "work", 0), transition("work", "other", 12),
            transition("idle", "work", 20), transition("work", "idle", 30),
        ])
        XCTAssertEqual(history.damagedLines, [2])
        XCTAssertEqual(history.intervals.map(\.duration), [10])
    }

    func testInvalidActionForKnownStatesIsNotCounted() {
        let history = parse([
            transition("idle", "work", 0),
            transition("work", "idle", 12, action: "skipRest"),
        ])
        XCTAssertEqual(history.damagedLines, [2])
        XCTAssertTrue(history.intervals.isEmpty)
    }

    func testEmptyHistoryHasNoDamage() {
        let history = TBHistory.parse(Data())
        XCTAssertTrue(history.intervals.isEmpty)
        XCTAssertTrue(history.damagedLines.isEmpty)
    }
}
