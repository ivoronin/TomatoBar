import Foundation

struct TBRecordedInterval {
    enum Kind: String {
        case work, rest
    }

    let kind: Kind
    let start: Date
    let end: Date
    var duration: TimeInterval { end.timeIntervalSince(start) }
}

struct TBHistorySnapshot {
    let intervals: [TBRecordedInterval]
    let damagedLines: [Int]
}

enum TBHistory {
    private struct Event: Decodable {
        let type: String
        let timestamp: Date
        let event: String?
        let fromState: String?
        let toState: String?
    }

    static func read(from url: URL) throws -> TBHistorySnapshot {
        do {
            return parse(try Data(contentsOf: url))
        } catch CocoaError.fileReadNoSuchFile {
            return TBHistorySnapshot(intervals: [], damagedLines: [])
        }
    }

    static func parse(_ data: Data) -> TBHistorySnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        var intervals: [TBRecordedInterval] = []
        var damaged: [Int] = []
        var open: (kind: TBRecordedInterval.Kind, start: Date)?
        let validTransitions = [
            "idle:work": ["startStop"],
            "work:rest": ["timerFired", "skipWork"],
            "work:idle": ["startStop"],
            "rest:work": ["timerFired", "skipRest"],
            "rest:idle": ["timerFired", "startStop"],
            "work:paused": ["pause"],
            "rest:paused": ["pause"],
            "paused:work": ["resume"],
            "paused:rest": ["resume"],
            "paused:idle": ["discardPause"],
        ]
        let lines = data.split(separator: 10, omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            if index == lines.count - 1, line.isEmpty { continue }
            guard index < lines.count - 1,
                  let event = try? decoder.decode(Event.self, from: Data(line)) else {
                damaged.append(index + 1)
                open = nil
                continue
            }
            if event.type == "appstart" {
                open = nil
                continue
            }
            guard event.type == "transition",
                  let action = event.event,
                  let from = event.fromState, let to = event.toState,
                  validTransitions[from + ":" + to]?.contains(action) == true else {
                damaged.append(index + 1)
                open = nil
                continue
            }
            if let current = open {
                if current.kind.rawValue == from, event.timestamp >= current.start {
                    intervals.append(TBRecordedInterval(kind: current.kind,
                                                        start: current.start, end: event.timestamp))
                } else {
                    damaged.append(index + 1)
                }
            }
            open = TBRecordedInterval.Kind(rawValue: to).map { ($0, event.timestamp) }
        }
        return TBHistorySnapshot(intervals: intervals, damagedLines: damaged)
    }
}
