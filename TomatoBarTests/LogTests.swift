import Foundation
import SwiftState
import XCTest

private struct ExampleEvent: TBLogEvent {
    let type = "appstart"
    let timestamp: Date
}

final class LogTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TomatoBarTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory,
                                                withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    private func file(_ name: String = "TomatoBar.log") -> URL {
        temporaryDirectory.appendingPathComponent(name)
    }

    func testDefaultLocationUsesApplicationSupportAndPomodoroFolder() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first!
        XCTAssertEqual(TBLogger.defaultFileURL,
                       support.appendingPathComponent("Pomodoro", isDirectory: true)
                           .appendingPathComponent("TomatoBar.log"))
    }

    func testCreatesMissingParentDirectories() throws {
        let url = temporaryDirectory.appendingPathComponent("nested/Pomodoro/TomatoBar.log")
        let log = TBLogger(fileURL: url)
        log.append(event: ExampleEvent(timestamp: Date(timeIntervalSince1970: 10)))
        XCTAssertFalse(try Data(contentsOf: url).isEmpty)
    }

    func testCreatesEmptyFileAtInjectedLocation() throws {
        let url = file()
        let log = TBLogger(fileURL: url)
        withExtendedLifetime(log) {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }
        XCTAssertEqual(try Data(contentsOf: url), Data())
    }

    func testOpeningAndAppendingPreservesExistingEvents() throws {
        let url = file()
        let previous = Data("{\"timestamp\":1791108000,\"type\":\"appstart\"}\n".utf8)
        try previous.write(to: url)
        let log = TBLogger(fileURL: url)
        XCTAssertEqual(try Data(contentsOf: url), previous)

        log.append(event: ExampleEvent(timestamp: Date(timeIntervalSince1970: 1791108010)))

        let contents = try Data(contentsOf: url)
        XCTAssertEqual(contents.prefix(previous.count), previous)
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        for line in lines {
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(line.utf8)))
        }
    }

    func testWritesOneJSONLinePerEventWithUnixSecondsAndFractionalPrecision() throws {
        let url = file()
        let log = TBLogger(fileURL: url)
        let seconds = [1791108000.125, 1791108012.75]
        for timestamp in seconds {
            log.append(event: ExampleEvent(timestamp: Date(timeIntervalSince1970: timestamp)))
        }

        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.hasSuffix("\n"))
        let lines = contents.split(separator: "\n")
        XCTAssertEqual(lines.count, seconds.count)
        for (line, timestamp) in zip(lines, seconds) {
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8))
                as? [String: Any])
            XCTAssertEqual(Set(json.keys), Set(["type", "timestamp"]))
            XCTAssertEqual(json["type"] as? String, "appstart")
            XCTAssertEqual(try XCTUnwrap(json["timestamp"] as? Double), timestamp,
                           accuracy: 0.000001)
        }
    }

    func testTransitionKeepsExistingEventAndStateFields() throws {
        let url = file()
        let log = TBLogger(fileURL: url)
        let machine = TBStateMachine(state: .idle)
        machine.addRoutes(event: .startStop, transitions: [.idle => .work])
        machine.addAnyHandler(.any => .any) { context in
            log.append(event: TBLogEventTransition(fromContext: context,
                                                  timestamp: Date(timeIntervalSince1970: 0.25),
                                                  timeZone: TimeZone(secondsFromGMT: -18_000)!))
        }
        machine <-! .startStop

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url))
            as? [String: Any])
        XCTAssertEqual(Set(json.keys), Set(["type", "timestamp", "localTime", "event", "fromState", "toState"]))
        XCTAssertEqual(json["type"] as? String, "transition")
        XCTAssertEqual(json["event"] as? String, "startStop")
        XCTAssertEqual(json["fromState"] as? String, "idle")
        XCTAssertEqual(json["toState"] as? String, "work")
        XCTAssertEqual(json["timestamp"] as? Double, 0.25)
        XCTAssertEqual(json["localTime"] as? String, "1969-12-31T19:00:00-05:00")
    }

    func testRetryPreservesAppStartTimestampAndLocalOffset() throws {
        let url = file()
        var failedWrite: Data?
        let log = TBLogger(fileURL: url, write: { handle, data in
            if failedWrite == nil {
                failedWrite = data
                throw CocoaError(.fileWriteUnknown)
            }
            try handle.write(contentsOf: data)
        })
        let event = TBLogEventAppStart(timestamp: Date(timeIntervalSince1970: 12.5),
                                      timeZone: TimeZone(secondsFromGMT: 5_400)!)
        XCTAssertFalse(log.append(event: event))
        XCTAssertTrue(log.retryPending())

        let stored = try Data(contentsOf: url)
        XCTAssertEqual(stored, failedWrite)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: stored) as? [String: Any])
        XCTAssertEqual(json["timestamp"] as? Double, 12.5)
        XCTAssertEqual(json["localTime"] as? String, "1970-01-01T01:30:12+01:30")
    }

    func testCreationFailureCanBeRetriedWithoutLosingPendingAppStart() throws {
        let blocker = file("blocker")
        try Data("existing file".utf8).write(to: blocker)
        let url = blocker.appendingPathComponent("TomatoBar.log")
        let log = TBLogger(fileURL: url)
        XCTAssertNotNil(log.lastError)
        XCTAssertFalse(log.append(event: ExampleEvent(timestamp: Date(timeIntervalSince1970: 1))))
        try FileManager.default.removeItem(at: blocker)
        XCTAssertTrue(log.retryPending())
        XCTAssertNil(log.lastError)
        XCTAssertFalse(log.hasPendingEvents)
        XCTAssertEqual(TBHistory.parse(try Data(contentsOf: url)).damagedLines, [])
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8).split(separator: "\n").count, 1)
    }

    func testPartialWriteRetryPreservesPreviousEventsAndFlushesInOrder() throws {
        let url = file()
        let prefix = Data("{\"timestamp\":0,\"type\":\"appstart\"}\n".utf8)
        try prefix.write(to: url)
        var failOnce = true
        let log = TBLogger(fileURL: url, write: { handle, data in
            if failOnce {
                failOnce = false
                try handle.write(contentsOf: data.prefix(data.count / 2))
                throw CocoaError(.fileWriteUnknown)
            }
            try handle.write(contentsOf: data)
        })
        XCTAssertFalse(log.append(event: ExampleEvent(timestamp: Date(timeIntervalSince1970: 1))))
        XCTAssertFalse(log.append(event: ExampleEvent(timestamp: Date(timeIntervalSince1970: 2))))
        XCTAssertTrue(log.retryPending())
        XCTAssertTrue(log.retryPending())
        let data = try Data(contentsOf: url)
        XCTAssertEqual(data.prefix(prefix.count), prefix)
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        let times = try lines.map { line -> Double in
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
            return try XCTUnwrap(object["timestamp"] as? Double)
        }
        XCTAssertEqual(times, [0, 1, 2])
    }

    func testRetryWritesToRestoredLogAndSubsequentEventsKeepUsingIt() throws {
        let url = file()
        let replaced = file("replaced.log")
        let prefix = Data("{\"timestamp\":0,\"type\":\"appstart\"}\n".utf8)
        try prefix.write(to: url)
        var failOnce = true
        let log = TBLogger(fileURL: url, write: { handle, data in
            if failOnce {
                failOnce = false
                throw CocoaError(.fileWriteUnknown)
            }
            try handle.write(contentsOf: data)
        })
        XCTAssertFalse(log.append(event: ExampleEvent(timestamp: Date(timeIntervalSince1970: 1))))

        // Restore the same saved history at the original path as a different file.
        try FileManager.default.moveItem(at: url, to: replaced)
        try prefix.write(to: url)

        XCTAssertTrue(log.retryPending())
        XCTAssertTrue(log.append(event: ExampleEvent(timestamp: Date(timeIntervalSince1970: 2))))
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        let times = try lines.map { line -> Double in
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
            return try XCTUnwrap(object["timestamp"] as? Double)
        }
        XCTAssertEqual(times, [0, 1, 2])
        XCTAssertEqual(try Data(contentsOf: replaced), prefix)
    }

    func testSyncFailureRetryDoesNotWriteTheEventTwice() throws {
        let url = file()
        var writes = 0
        var failOnce = true
        let log = TBLogger(fileURL: url, write: { handle, data in
            writes += 1
            try handle.write(contentsOf: data)
        }, synchronize: { handle in
            if failOnce {
                failOnce = false
                throw CocoaError(.fileWriteUnknown)
            }
            try handle.synchronize()
        })
        XCTAssertFalse(log.append(event: ExampleEvent(timestamp: Date(timeIntervalSince1970: 1))))
        XCTAssertTrue(log.retryPending())
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8).split(separator: "\n").count, 1)
    }

    func testRetryDoesNotDeleteAnUnexpectedTail() throws {
        let url = file()
        let log = TBLogger(fileURL: url, write: { handle, _ in
            try handle.write(contentsOf: Data("unexpected content".utf8))
            throw CocoaError(.fileWriteUnknown)
        })
        XCTAssertFalse(log.append(event: ExampleEvent(timestamp: Date(timeIntervalSince1970: 1))))
        let before = try Data(contentsOf: url)
        XCTAssertFalse(log.retryPending())
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    func testConcurrentAppendsProduceCompleteDistinctLines() throws {
        let url = file()
        let log = TBLogger(fileURL: url)
        DispatchQueue.concurrentPerform(iterations: 30) { index in
            XCTAssertTrue(log.append(event: ExampleEvent(timestamp: Date(timeIntervalSince1970: Double(index)))))
        }
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        let times = try lines.map { line -> Double in
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
            return try XCTUnwrap(json["timestamp"] as? Double)
        }
        XCTAssertEqual(Set(times), Set((0..<30).map(Double.init)))
        XCTAssertEqual(lines.count, 30)
    }

    func testSeparateInjectedFilesDoNotShareEvents() throws {
        let firstURL = file("first.log")
        let secondURL = file("second.log")
        let first = TBLogger(fileURL: firstURL)
        let second = TBLogger(fileURL: secondURL)
        first.append(event: ExampleEvent(timestamp: Date(timeIntervalSince1970: 10)))
        second.append(event: ExampleEvent(timestamp: Date(timeIntervalSince1970: 20)))

        let firstJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: firstURL))
            as? [String: Any])
        let secondJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: secondURL))
            as? [String: Any])
        XCTAssertEqual(firstJSON["timestamp"] as? Double, 10)
        XCTAssertEqual(secondJSON["timestamp"] as? Double, 20)
    }
}
