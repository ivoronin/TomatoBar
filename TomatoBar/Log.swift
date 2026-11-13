import Foundation
import SwiftUI

protocol TBLogEvent: Encodable {
    var type: String { get }
    var timestamp: Date { get }
}

class TBLogEventAppStart: TBLogEvent {
    internal let type = "appstart"
    internal let timestamp: Date
    private let localTime: String

    init(timestamp: Date = Date(), timeZone: TimeZone = .current) {
        self.timestamp = timestamp
        localTime = formatLocalTime(timestamp, timeZone: timeZone)
    }
}

class TBLogEventTransition: TBLogEvent {
    internal let type = "transition"
    internal let timestamp: Date

    private let localTime: String
    private let event: String
    private let fromState: String
    private let toState: String

    init(fromContext ctx: TBStateMachine.Context, timestamp: Date = Date(),
         timeZone: TimeZone = .current) {
        self.timestamp = timestamp
        localTime = formatLocalTime(timestamp, timeZone: timeZone)
        event = "\(ctx.event!)"
        fromState = "\(ctx.fromState)"
        toState = "\(ctx.toState)"
    }
}

private func formatLocalTime(_ timestamp: Date, timeZone: TimeZone) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = timeZone
    return formatter.string(from: timestamp)
}

private let logFileName = "TomatoBar.log"
private let lineEnd = "\n".data(using: .utf8)!

internal let logger = TBLogger()

extension Notification.Name {
    static let tbLogDidAppend = Notification.Name("TBLogDidAppend")
}

class TBLogger {
    static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Pomodoro", isDirectory: true)
            .appendingPathComponent(logFileName)
    }

    private struct PendingWrite {
        let data: Data
        var offset: UInt64?
    }

    let fileURL: URL
    private let lock = NSLock()
    private let encoder = JSONEncoder()
    private var pending: [PendingWrite] = []
    private var failure: Error?
    private let writeData: (FileHandle, Data) throws -> Void
    private let synchronize: (FileHandle) throws -> Void

    var lastError: Error? {
        lock.lock()
        defer { lock.unlock() }
        return failure
    }

    var hasPendingEvents: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !pending.isEmpty
    }

    init(fileURL: URL? = nil,
         write: @escaping (FileHandle, Data) throws -> Void = { try $0.write(contentsOf: $1) },
         synchronize: @escaping (FileHandle) throws -> Void = { try $0.synchronize() }) {
        self.fileURL = fileURL ?? Self.defaultFileURL
        writeData = write
        self.synchronize = synchronize
        encoder.outputFormatting = .sortedKeys
        encoder.dateEncodingStrategy = .secondsSince1970
        do {
            try openLog().close()
        } catch {
            failure = error
        }
    }

    @discardableResult
    func append(event: TBLogEvent) -> Bool {
        lock.lock()
        let succeeded: Bool
        do {
            pending.append(PendingWrite(data: try encoder.encode(event) + lineEnd))
            succeeded = failure == nil && flush()
        } catch {
            failure = error
            succeeded = false
        }
        lock.unlock()
        if succeeded {
            NotificationCenter.default.post(name: .tbLogDidAppend, object: self)
        }
        return succeeded
    }

    @discardableResult
    func retryPending() -> Bool {
        lock.lock()
        failure = nil
        let succeeded = flush()
        lock.unlock()
        if succeeded {
            NotificationCenter.default.post(name: .tbLogDidAppend, object: self)
        }
        return succeeded
    }

    private func openLog() throws -> FileHandle {
        let manager = FileManager.default
        try manager.createDirectory(at: fileURL.deletingLastPathComponent(),
                                    withIntermediateDirectories: true)
        if !manager.fileExists(atPath: fileURL.path) {
            try Data().write(to: fileURL, options: .withoutOverwriting)
        }
        return try FileHandle(forUpdating: fileURL)
    }

    // Only this process writes the log. Retry checks the attempted tail before
    // replacing a partial line; it never truncates previously committed events.
    private func flush() -> Bool {
        do {
            // Resolve the path again if the log was restored or replaced.
            let handle = try openLog()
            defer { try? handle.close() }
            while !pending.isEmpty {
                let end = try handle.seekToEnd()
                if pending[0].offset == nil {
                    pending[0].offset = end
                }
                let offset = pending[0].offset!
                guard end >= offset else { throw CocoaError(.fileWriteUnknown) }
                try handle.seek(toOffset: offset)
                let existing = try handle.readToEnd() ?? Data()
                let data = pending[0].data
                guard existing.count <= data.count,
                      existing == data.prefix(existing.count) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                if existing != data {
                    try handle.truncate(atOffset: offset)
                    try handle.seek(toOffset: offset)
                    try writeData(handle, data)
                }
                try synchronize(handle)
                pending.removeFirst()
            }
            failure = nil
            return true
        } catch {
            failure = error
            return false
        }
    }
}
