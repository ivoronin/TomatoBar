import Foundation
import SwiftUI

protocol TBLogEvent: Encodable {
    var type: String { get }
    var timestamp: Date { get }
}

class TBLogEventAppStart: TBLogEvent {
    internal let type = "appstart"
    internal let timestamp: Date = Date()
}

class TBLogEventTransition: TBLogEvent {
    internal let type = "transition"
    internal let timestamp: Date = Date()

    private let event: String
    private let fromState: String
    private let toState: String

    init(fromContext ctx: TBStateMachine.Context) {
        event = "\(ctx.event!)"
        fromState = "\(ctx.fromState)"
        toState = "\(ctx.toState)"
    }
}

private let logFileName = "TomatoBar.log"
private let lineEnd = "\n".data(using: .utf8)!

internal let logger = TBLogger()

class TBLogger {
    private let encoder = JSONEncoder()

    init() {
        encoder.outputFormatting = .sortedKeys
        encoder.dateEncodingStrategy = .secondsSince1970
    }
    
    func openFileHandle() -> FileHandle? {
        let logHandle: FileHandle?
        let fileManager = FileManager.default
        let logPath = fileManager
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent(logFileName)
            .path

        if !fileManager.fileExists(atPath: logPath) {
            guard fileManager.createFile(atPath: logPath, contents: nil) else {
                print("cannot create log file")
                logHandle = nil
                return nil
            }
        }

        logHandle = FileHandle(forUpdatingAtPath: logPath)
        guard logHandle != nil else {
            print("cannot open log file")
            return nil
        }

        return logHandle
    }

    func append(event: TBLogEvent) {
        let logHandle = openFileHandle()
        guard let logHandle = logHandle else {
            return
        }
        
        do {
            let jsonData = try encoder.encode(event)
            try logHandle.seekToEnd()
            try logHandle.write(contentsOf: jsonData + lineEnd)
            try logHandle.synchronize()
        } catch {
            print("cannot write to log file: \(error)")
        }
    }
}
