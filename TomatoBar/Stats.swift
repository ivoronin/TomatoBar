import Foundation
import SwiftUI

/*
 * Read-only stats layer.
 *
 * It reconstructs work/rest intervals by replaying the transition events that
 * TBLogger (Log.swift) already appends to TomatoBar.log - the timer and the
 * state machine are never touched. Intervals are paired from state
 * transitions, split at local midnight and aggregated per day.
 */

/* Minimal decodable view of a single TBLogEventTransition line.
 * Other event types (e.g. "appstart") decode too but are filtered by `type`. */
private struct TBRawEvent: Decodable {
    let type: String
    let timestamp: Date
    let fromState: String?
    let toState: String?
}

enum TBIntervalKind {
    case work, shortRest, longRest
}

struct TBInterval: Identifiable {
    let id = UUID()
    let kind: TBIntervalKind
    let start: Date
    let end: Date
    /* No closing transition was found (timer still running or app crashed). */
    let isOpenEnded: Bool
    /* Set during the midnight split for the boundary segments. */
    let continuesFromPrevDay: Bool
    let continuesToNextDay: Bool

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

struct TBDaySummary: Identifiable {
    var id: Date { day }
    let day: Date // start of day, local time
    let workSeconds: TimeInterval
    let shortRestSeconds: TimeInterval
    let longRestSeconds: TimeInterval
    let intervals: [TBInterval] // ordered by start, already day-local
}

enum TBStatsParser {
    /* Same caches-dir resolution as TBLogger in Log.swift (source of truth).
     * Under the App Sandbox this is the container path, not ~/Library/Caches,
     * so it must match exactly to read the file the logger writes.
     * `logFileName` is private in Log.swift, hence the repeated literal. */
    static var logFileURL: URL? {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("TomatoBar.log")
    }

    struct ParseResult {
        let days: [TBDaySummary]
        let fileMissing: Bool
        let readFailed: Bool
    }

    static func parse(workLen: Int, shortLen: Int, longLen: Int,
                      now: Date = Date(),
                      calendar: Calendar = .current) -> ParseResult {
        guard let url = logFileURL else {
            return ParseResult(days: [], fileMissing: true, readFailed: false)
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            return ParseResult(days: [], fileMissing: true, readFailed: false)
        }
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return ParseResult(days: [], fileMissing: false, readFailed: true)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970 // mirrors TBLogger

        var transitions: [TBRawEvent] = []
        for line in contents.split(separator: "\n") {
            /* Decode each line independently so a partial trailing line
             * (crash mid-write) or any bad line is skipped, not fatal. */
            guard let data = line.data(using: .utf8),
                  let event = try? decoder.decode(TBRawEvent.self, from: data),
                  event.type == "transition" else { continue }
            transitions.append(event)
        }
        transitions.sort { $0.timestamp < $1.timestamp }

        let intervals = reconstruct(transitions: transitions,
                                    workLen: workLen, shortLen: shortLen,
                                    longLen: longLen, now: now)
        let split = intervals.flatMap { splitAtMidnight($0, calendar: calendar) }
        let days = aggregate(split, calendar: calendar)
        return ParseResult(days: days, fileMissing: false, readFailed: false)
    }

    /* Forward pass: any new toState transition closes the interval that was
     * open (its fromState), implementing "pair with the next fromState==…". */
    private static func reconstruct(transitions: [TBRawEvent],
                                    workLen: Int, shortLen: Int, longLen: Int,
                                    now: Date) -> [TBInterval] {
        var result: [TBInterval] = []
        var openState: String? // "work" or "rest"
        var openStart: Date?

        func close(at end: Date, openEnded: Bool) {
            guard let state = openState, let start = openStart, end > start else {
                openState = nil; openStart = nil; return
            }
            let kind = classify(state: state, duration: end.timeIntervalSince(start),
                                shortLen: shortLen, longLen: longLen)
            result.append(TBInterval(kind: kind, start: start, end: end,
                                     isOpenEnded: openEnded,
                                     continuesFromPrevDay: false,
                                     continuesToNextDay: false))
            openState = nil; openStart = nil
        }

        for t in transitions {
            guard let to = t.toState else { continue }
            close(at: t.timestamp, openEnded: false)
            if to == "work" || to == "rest" {
                openState = to
                openStart = t.timestamp
            }
        }

        /* Unclosed trailing interval: cap so a quit-without-stop or crash
         * cannot produce a runaway multi-day bar. */
        if let state = openState, let start = openStart {
            let len = state == "work" ? workLen : longLen
            let cap = start.addingTimeInterval(TimeInterval(len * 60 + 90))
            close(at: min(now, cap), openEnded: true)
        }
        return result
    }

    private static func classify(state: String, duration: TimeInterval,
                                 shortLen: Int, longLen: Int) -> TBIntervalKind {
        guard state == "rest" else { return .work }
        let dShort = abs(duration - Double(shortLen * 60))
        let dLong = abs(duration - Double(longLen * 60))
        return dShort <= dLong ? .shortRest : .longRest
    }

    /* Expand an interval into day-local segments at local midnight. */
    private static func splitAtMidnight(_ iv: TBInterval,
                                        calendar: Calendar) -> [TBInterval] {
        var segments: [TBInterval] = []
        var cursor = iv.start
        while cursor < iv.end {
            let dayStart = calendar.startOfDay(for: cursor)
            let nextMidnight = calendar.date(byAdding: .day, value: 1,
                                             to: dayStart) ?? iv.end
            let segEnd = min(nextMidnight, iv.end)
            let fromPrev = cursor != iv.start
            let toNext = segEnd != iv.end
            segments.append(TBInterval(
                kind: iv.kind, start: cursor, end: segEnd,
                isOpenEnded: iv.isOpenEnded && !toNext,
                continuesFromPrevDay: fromPrev,
                continuesToNextDay: toNext))
            cursor = segEnd
        }
        return segments
    }

    private static func aggregate(_ intervals: [TBInterval],
                                  calendar: Calendar) -> [TBDaySummary] {
        let grouped = Dictionary(grouping: intervals) {
            calendar.startOfDay(for: $0.start)
        }
        return grouped.map { day, ivs in
            let sorted = ivs.sorted { $0.start < $1.start }
            var work = 0.0, short = 0.0, long = 0.0
            for iv in sorted {
                switch iv.kind {
                case .work: work += iv.duration
                case .shortRest: short += iv.duration
                case .longRest: long += iv.duration
                }
            }
            return TBDaySummary(day: day, workSeconds: work,
                                shortRestSeconds: short, longRestSeconds: long,
                                intervals: sorted)
        }
        .sorted { $0.day > $1.day }
    }
}

final class TBStatsStore: ObservableObject {
    @Published var days: [TBDaySummary] = []
    @Published var isLoading = false
    @Published var loadError = false

    func load(workLen: Int, shortLen: Int, longLen: Int) {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = TBStatsParser.parse(workLen: workLen,
                                             shortLen: shortLen,
                                             longLen: longLen)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.days = result.days
                self.loadError = result.readFailed
                self.isLoading = false
            }
        }
    }

    func summary(for date: Date, calendar: Calendar = .current) -> TBDaySummary {
        let day = calendar.startOfDay(for: date)
        return days.first { $0.day == day }
            ?? TBDaySummary(day: day, workSeconds: 0, shortRestSeconds: 0,
                            longRestSeconds: 0, intervals: [])
    }

    /* Most recent days that have any activity, newest first. */
    func recentDays(_ count: Int) -> [TBDaySummary] {
        Array(days.prefix(count))
    }
}
