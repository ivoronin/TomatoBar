import Foundation
import XCTest

final class TimerTests: XCTestCase {
    private var directory: URL!
    private var url: URL { directory.appendingPathComponent("TomatoBar.log") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testStartAndStopPersistOneCompletedFocus() throws {
        let log = TBLogger(fileURL: url)
        let timer = TBTimer(log: log, registerSystemHandlers: false)
        timer.startStop()
        XCTAssertNotNil(timer.timer)
        timer.startStop()
        XCTAssertNil(timer.timer)
        let history = try TBHistory.read(from: url)
        XCTAssertEqual(history.intervals.map(\.kind), [.work])
        XCTAssertTrue(history.damagedLines.isEmpty)
    }

    func testRepeatedFinalizationDoesNotStartOrCloseAnotherInterval() throws {
        let log = TBLogger(fileURL: url)
        let timer = TBTimer(log: log, registerSystemHandlers: false)
        timer.startStop()
        timer.finishActiveInterval()
        timer.finishActiveInterval()
        XCTAssertNil(timer.timer)
        XCTAssertEqual(try TBHistory.read(from: url).intervals.count, 1)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8).split(separator: "\n").count, 2)
    }

    func testFailedStartStopsAndRetryKeepsTheTimerStopped() throws {
        var failOnce = true
        let log = TBLogger(fileURL: url, write: { handle, data in
            if failOnce {
                failOnce = false
                throw CocoaError(.fileWriteUnknown)
            }
            try handle.write(contentsOf: data)
        })
        let timer = TBTimer(log: log, registerSystemHandlers: false)
        var alerts = 0
        timer.onLogFailure = { _ in alerts += 1 }
        timer.startStop()
        XCTAssertNil(timer.timer)
        XCTAssertEqual(alerts, 1)
        timer.startStop()
        XCTAssertNil(timer.timer)
        XCTAssertTrue(log.retryPending())
        timer.didRecoverLog()
        XCTAssertNil(timer.timer)
        let intervals = try TBHistory.read(from: url).intervals
        XCTAssertEqual(intervals.count, 1)
        XCTAssertEqual(intervals.first?.duration, 0)
        timer.startStop()
        XCTAssertNotNil(timer.timer)
        timer.finishActiveInterval()
    }

    func testFailedStopRetainsOriginalEndTime() throws {
        var failNext = false
        let log = TBLogger(fileURL: url, write: { handle, data in
            if failNext {
                failNext = false
                throw CocoaError(.fileWriteUnknown)
            }
            try handle.write(contentsOf: data)
        })
        let timer = TBTimer(log: log, registerSystemHandlers: false)
        timer.startStop()
        failNext = true
        timer.finishActiveInterval()
        let beforeRetry = Date()
        XCTAssertNil(timer.timer)
        XCTAssertTrue(log.hasPendingEvents)
        XCTAssertTrue(log.retryPending())
        timer.didRecoverLog()
        let interval = try XCTUnwrap(TBHistory.read(from: url).intervals.first)
        XCTAssertLessThanOrEqual(interval.end, beforeRetry)
        XCTAssertNil(timer.timer)
    }

    private func tick(_ timer: TBTimer) {
        let done = expectation(description: "Main queue processed the timer tick")
        timer.onTimerTick()
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 2)
    }

    func testAutomaticFocusFinishAndSkippedRestUseElapsedSeconds() throws {
        var clock = Date(timeIntervalSince1970: 1000)
        let log = TBLogger(fileURL: url)
        let timer = TBTimer(log: log, registerSystemHandlers: false, now: { clock })
        XCTAssertFalse(timer.isResting)
        timer.startStop()
        XCTAssertFalse(timer.isResting)
        let focusSeconds = Double(timer.workIntervalLength * 60)
        clock = clock.addingTimeInterval(focusSeconds)
        tick(timer)
        XCTAssertTrue(timer.isResting)
        clock = clock.addingTimeInterval(10)
        timer.skipInterval()
        XCTAssertFalse(timer.isResting)
        clock = clock.addingTimeInterval(12)
        timer.finishActiveInterval()
        let history = try TBHistory.read(from: url)
        XCTAssertEqual(history.intervals.map(\.kind), [.work, .rest, .work])
        XCTAssertEqual(history.intervals.map(\.duration), [focusSeconds, 10, 12])
    }

    func testSkippingFocusRecordsElapsedTimeAndStartsTheScheduledRest() throws {
        var clock = Date(timeIntervalSince1970: 1000)
        let log = TBLogger(fileURL: url)
        let timer = TBTimer(log: log, registerSystemHandlers: false, now: { clock })
        let previousSet = timer.workIntervalsInSet
        let previousStop = timer.stopAfterBreak
        timer.workIntervalsInSet = 1
        timer.stopAfterBreak = true
        defer {
            timer.workIntervalsInSet = previousSet
            timer.stopAfterBreak = previousStop
        }

        XCTAssertFalse(timer.canSkipInterval)
        timer.skipInterval()
        timer.startStop()
        XCTAssertTrue(timer.canSkipInterval)
        clock = clock.addingTimeInterval(10)
        timer.skipInterval()
        XCTAssertTrue(timer.isResting)
        XCTAssertTrue(timer.canSkipInterval)
        XCTAssertEqual(try TBHistory.read(from: url).intervals.map(\.duration), [10])

        let restSeconds = Double(timer.longRestIntervalLength * 60)
        clock = clock.addingTimeInterval(restSeconds)
        tick(timer)
        XCTAssertFalse(timer.canSkipInterval)
        let history = try TBHistory.read(from: url)
        XCTAssertEqual(history.intervals.map(\.kind), [.work, .rest])
        XCTAssertEqual(history.intervals.map(\.duration), [10, restSeconds])
        XCTAssertEqual(history.intervals.first?.end, history.intervals.last?.start)
        XCTAssertTrue(history.damagedLines.isEmpty)
    }

    func testAutomaticBreakCompletionRespectsStopAfterBreak() throws {
        var clock = Date(timeIntervalSince1970: 1000)
        let log = TBLogger(fileURL: url)
        let timer = TBTimer(log: log, registerSystemHandlers: false, now: { clock })
        let previous = timer.stopAfterBreak
        timer.stopAfterBreak = true
        defer { timer.stopAfterBreak = previous }
        timer.startStop()
        clock = clock.addingTimeInterval(Double(timer.workIntervalLength * 60))
        tick(timer)
        let restMinutes = timer.workIntervalsInSet <= 1
            ? timer.longRestIntervalLength : timer.shortRestIntervalLength
        clock = clock.addingTimeInterval(Double(restMinutes * 60))
        tick(timer)
        XCTAssertNil(timer.timer)
        let history = try TBHistory.read(from: url)
        XCTAssertEqual(history.intervals.map(\.kind), [.work, .rest])
        XCTAssertEqual(history.intervals.last?.duration, Double(restMinutes * 60))
    }

    func testFailedAutomaticTransitionClosesNewRestAtFailureInstant() throws {
        var clock = Date(timeIntervalSince1970: 1000)
        var failNext = false
        let log = TBLogger(fileURL: url, write: { handle, data in
            if failNext {
                failNext = false
                throw CocoaError(.fileWriteUnknown)
            }
            try handle.write(contentsOf: data)
        })
        let timer = TBTimer(log: log, registerSystemHandlers: false, now: { clock })
        timer.startStop()
        let focusSeconds = Double(timer.workIntervalLength * 60)
        clock = clock.addingTimeInterval(focusSeconds)
        failNext = true
        tick(timer)
        XCTAssertNil(timer.timer)
        clock = clock.addingTimeInterval(600)
        XCTAssertTrue(log.retryPending())
        timer.didRecoverLog()
        let history = try TBHistory.read(from: url)
        XCTAssertEqual(history.intervals.map(\.kind), [.work, .rest])
        XCTAssertEqual(history.intervals.map(\.duration), [focusSeconds, 0])
    }

    func testManualStopDuringRestCountsOnlyElapsedRest() throws {
        var clock = Date(timeIntervalSince1970: 1000)
        let log = TBLogger(fileURL: url)
        let timer = TBTimer(log: log, registerSystemHandlers: false, now: { clock })
        timer.startStop()
        let focusSeconds = Double(timer.workIntervalLength * 60)
        clock = clock.addingTimeInterval(focusSeconds)
        tick(timer)
        clock = clock.addingTimeInterval(3)
        timer.startStop()
        XCTAssertNil(timer.timer)
        let history = try TBHistory.read(from: url)
        XCTAssertEqual(history.intervals.map(\.kind), [.work, .rest])
        XCTAssertEqual(history.intervals.map(\.duration), [focusSeconds, 3])
    }

    func testPauseFreezesFocusAndResumeKeepsTheRemainingTime() throws {
        var clock = Date(timeIntervalSince1970: 1000)
        let log = TBLogger(fileURL: url)
        let timer = TBTimer(log: log, registerSystemHandlers: false, now: { clock })
        XCTAssertFalse(timer.canTogglePause)
        timer.startStop()
        let focusSeconds = Double(timer.workIntervalLength * 60)
        clock = clock.addingTimeInterval(20)
        timer.togglePause()
        XCTAssertTrue(timer.isPaused)
        XCTAssertNil(timer.timer)
        let frozenTime = timer.timeLeftString
        XCTAssertFalse(frozenTime.isEmpty)

        clock = clock.addingTimeInterval(3600)
        tick(timer)
        timer.startStop()
        XCTAssertFalse(timer.canSkipInterval)
        timer.skipInterval()
        XCTAssertTrue(timer.isPaused)
        XCTAssertEqual(timer.timeLeftString, frozenTime)
        XCTAssertEqual(try TBHistory.read(from: url).intervals.map(\.duration), [20])

        timer.togglePause()
        XCTAssertFalse(timer.isPaused)
        XCTAssertEqual(timer.timeLeftString, frozenTime)
        clock = clock.addingTimeInterval(focusSeconds - 20)
        tick(timer)
        XCTAssertTrue(timer.isResting)
        let history = try TBHistory.read(from: url)
        XCTAssertEqual(history.intervals.map(\.kind), [.work, .work])
        XCTAssertEqual(history.intervals.map(\.duration), [20, focusSeconds - 20])
        XCTAssertTrue(history.damagedLines.isEmpty)
        timer.finishActiveInterval()
    }

    func testFinishingPausedRestDiscardsContinuationAndPreservesElapsedRest() throws {
        var clock = Date(timeIntervalSince1970: 1000)
        let log = TBLogger(fileURL: url)
        let timer = TBTimer(log: log, registerSystemHandlers: false, now: { clock })
        timer.startStop()
        let focusSeconds = Double(timer.workIntervalLength * 60)
        clock = clock.addingTimeInterval(focusSeconds)
        tick(timer)
        clock = clock.addingTimeInterval(20)
        timer.togglePause()
        XCTAssertTrue(timer.isPaused)
        XCTAssertFalse(timer.isResting)
        clock = clock.addingTimeInterval(3600)
        timer.finishActiveInterval()
        timer.finishActiveInterval()
        XCTAssertFalse(timer.canTogglePause)
        XCTAssertNil(timer.timer)
        XCTAssertTrue(timer.timeLeftString.isEmpty)

        let history = try TBHistory.read(from: url)
        XCTAssertEqual(history.intervals.map(\.kind), [.work, .rest])
        XCTAssertEqual(history.intervals.map(\.duration), [focusSeconds, 20])
        XCTAssertTrue(history.damagedLines.isEmpty)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8).split(separator: "\n").count, 4)
    }

    func testResumingLongRestKeepsItsRemainingTime() throws {
        var clock = Date(timeIntervalSince1970: 1000)
        let log = TBLogger(fileURL: url)
        let timer = TBTimer(log: log, registerSystemHandlers: false, now: { clock })
        let previousSet = timer.workIntervalsInSet
        let previousLong = timer.longRestIntervalLength
        let previousShort = timer.shortRestIntervalLength
        timer.workIntervalsInSet = 1
        timer.longRestIntervalLength = 5
        timer.shortRestIntervalLength = 1
        defer {
            timer.workIntervalsInSet = previousSet
            timer.longRestIntervalLength = previousLong
            timer.shortRestIntervalLength = previousShort
        }

        timer.startStop()
        clock = clock.addingTimeInterval(Double(timer.workIntervalLength * 60))
        tick(timer)
        clock = clock.addingTimeInterval(20)
        timer.togglePause()
        let frozenTime = timer.timeLeftString
        clock = clock.addingTimeInterval(300)
        timer.togglePause()
        XCTAssertTrue(timer.isResting)
        XCTAssertEqual(timer.timeLeftString, frozenTime)

        clock = clock.addingTimeInterval(279)
        tick(timer)
        XCTAssertTrue(timer.isResting)
        clock = clock.addingTimeInterval(1)
        tick(timer)
        XCTAssertFalse(timer.isResting)
        let history = try TBHistory.read(from: url)
        XCTAssertEqual(history.intervals.filter { $0.kind == .rest }.map(\.duration), [20, 280])
        XCTAssertTrue(history.damagedLines.isEmpty)
        timer.finishActiveInterval()
    }

    func testFailedPauseDiscardsContinuationAndRetriesAtOriginalTime() throws {
        var clock = Date(timeIntervalSince1970: 1000)
        var failNext = false
        let log = TBLogger(fileURL: url, write: { handle, data in
            if failNext {
                failNext = false
                throw CocoaError(.fileWriteUnknown)
            }
            try handle.write(contentsOf: data)
        })
        let timer = TBTimer(log: log, registerSystemHandlers: false, now: { clock })
        timer.startStop()
        clock = clock.addingTimeInterval(20)
        failNext = true
        timer.togglePause()
        XCTAssertFalse(timer.canTogglePause)
        XCTAssertTrue(log.hasPendingEvents)
        clock = clock.addingTimeInterval(3600)
        XCTAssertTrue(log.retryPending())
        timer.didRecoverLog()

        let history = try TBHistory.read(from: url)
        XCTAssertEqual(history.intervals.map(\.duration), [20])
        XCTAssertTrue(history.damagedLines.isEmpty)
        XCTAssertFalse(timer.canTogglePause)
    }

    func testUnavailableLogPreventsStarting() throws {
        let blocker = directory.appendingPathComponent("blocker")
        try Data().write(to: blocker)
        let log = TBLogger(fileURL: blocker.appendingPathComponent("log"))
        XCTAssertFalse(log.append(event: TBLogEventAppStart()))
        let timer = TBTimer(log: log, registerSystemHandlers: false)
        timer.startStop()
        XCTAssertNil(timer.timer)
        XCTAssertNotNil(log.lastError)
    }
}
