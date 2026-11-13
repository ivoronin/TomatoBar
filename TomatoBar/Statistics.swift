import Combine
import Foundation

struct TBStatsDuration {
    var focus: TimeInterval = 0
    var rest: TimeInterval = 0
    var total: TimeInterval { focus + rest }

    mutating func add(_ seconds: TimeInterval, kind: TBRecordedInterval.Kind) {
        switch kind {
        case .work: focus += seconds
        case .rest: rest += seconds
        }
    }
}

struct TBStatsDay: Identifiable {
    let date: Date
    let duration: TBStatsDuration
    let focusMinutes: Int
    let restMinutes: Int

    var id: Date { date }
    var totalMinutes: Int { focusMinutes + restMinutes }
}

struct TBStatsWeek {
    let number: Int
    let days: [TBStatsDay]

    var totalMinutes: Int { days.reduce(0) { $0 + $1.totalMinutes } }
}

struct TBStatistics {
    let calendar: Calendar
    private var durations: [Date: TBStatsDuration] = [:]

    init(intervals: [TBRecordedInterval] = [], timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = timeZone
        self.calendar = calendar

        for interval in intervals {
            var cursor = interval.start
            while cursor < interval.end, let day = calendar.dateInterval(of: .day, for: cursor) {
                let end = min(day.end, interval.end)
                guard end > cursor else { break }
                durations[day.start, default: TBStatsDuration()]
                    .add(end.timeIntervalSince(cursor), kind: interval.kind)
                cursor = end
            }
        }
    }

    func startOfWeek(containing date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)!.start
    }

    func day(containing date: Date) -> TBStatsDay {
        let start = calendar.startOfDay(for: date)
        return week(containing: start).days.first { $0.date == start }!
    }

    func week(containing date: Date) -> TBStatsWeek {
        let start = startOfWeek(containing: date)
        let dates = (0..<7).map {
            calendar.startOfDay(for: calendar.date(byAdding: .day, value: $0, to: start)!)
        }
        let values = dates.map { durations[$0, default: TBStatsDuration()] }
        let totals = values.map { $0.total / 60 }
        let dayMinutes = Self.distribute(totals, total: Int(totals.reduce(0, +).rounded()))
        let days = dates.indices.map { index in
            let duration = values[index]
            let minutes = Self.distribute([duration.focus / 60, duration.rest / 60], total: dayMinutes[index])
            return TBStatsDay(date: dates[index], duration: duration,
                              focusMinutes: minutes[0], restMinutes: minutes[1])
        }
        return TBStatsWeek(number: calendar.component(.weekOfYear, from: start), days: days)
    }

    // Keep the original order for equal remainders: Monday first, focus first.
    private static func distribute(_ values: [Double], total: Int) -> [Int] {
        var minutes = values.map { Int($0.rounded(.down)) }
        let remainder = total - minutes.reduce(0, +)
        let order = values.indices.sorted {
            let left = values[$0] - Double(minutes[$0])
            let right = values[$1] - Double(minutes[$1])
            return left == right ? $0 < $1 : left > right
        }
        for index in order.prefix(remainder) {
            minutes[index] += 1
        }
        return minutes
    }
}

struct TBStatsSelection {
    private(set) var today: Date
    private(set) var currentWeek: Date
    private(set) var visibleWeek: Date
    var pinnedDay: Date?
    var previewDay: Date?
    private var suppressedPreviewDay: Date?

    var selectedDay: Date { previewDay ?? pinnedDay ?? today }
    var canGoForward: Bool { visibleWeek < currentWeek }

    init(now: Date, statistics: TBStatistics) {
        today = statistics.calendar.startOfDay(for: now)
        currentWeek = statistics.startOfWeek(containing: now)
        visibleWeek = currentWeek
    }

    mutating func clickDay(_ day: Date) {
        if pinnedDay == day {
            pinnedDay = nil
            previewDay = nil
            suppressedPreviewDay = day
        } else {
            pinDay(day)
        }
    }

    mutating func pinDay(_ day: Date) {
        pinnedDay = day
        previewDay = nil
        suppressedPreviewDay = nil
    }

    mutating func hoverDay(_ day: Date, hovering: Bool) {
        if hovering {
            guard suppressedPreviewDay != day else { return }
            previewDay = day
        } else {
            if previewDay == day { previewDay = nil }
            if suppressedPreviewDay == day { suppressedPreviewDay = nil }
        }
    }

    mutating func moveWeek(by offset: Int, calendar: Calendar) {
        guard let next = calendar.date(byAdding: .weekOfYear, value: offset, to: visibleWeek),
              let week = calendar.dateInterval(of: .weekOfYear, for: next)?.start,
              week <= currentWeek else { return }
        visibleWeek = week
        previewDay = nil
        suppressedPreviewDay = nil
    }

    mutating func changeTimeZone(from oldCalendar: Calendar, to statistics: TBStatistics) {
        let newCalendar = statistics.calendar
        func moved(_ date: Date) -> Date {
            let components = oldCalendar.dateComponents([.year, .month, .day], from: date)
            return newCalendar.startOfDay(for: newCalendar.date(from: components) ?? date)
        }
        today = moved(today)
        currentWeek = statistics.startOfWeek(containing: today)
        visibleWeek = statistics.startOfWeek(containing: moved(visibleWeek))
        pinnedDay = pinnedDay.map(moved)
        previewDay = nil
        suppressedPreviewDay = nil
    }
}

struct TBStatsFormat {
    let calendar: Calendar
    private static let english = Locale(identifier: "en_US_POSIX")

    static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(remainder) min" }
        return remainder == 0 ? "\(hours) h" : "\(hours) h \(remainder) min"
    }

    static func chartMinutes(_ minutes: Int) -> String {
        "\(minutes) min"
    }

    static func percentage(_ seconds: TimeInterval, of total: TimeInterval) -> String {
        guard total > 0 else { return "—" }
        return String(format: "%.1f%%", locale: english, 100 * seconds / total)
    }

    func day(_ date: Date, today: Date) -> String {
        if calendar.isDate(date, inSameDayAs: today) { return "Today" }
        let sameYear = calendar.isDate(date, equalTo: today, toGranularity: .year)
        return format(date, as: sameYear ? "d MMM" : "d MMM yyyy")
    }

    func week(_ week: TBStatsWeek) -> String {
        let start = week.days[0].date
        let end = week.days[6].date
        let startFormat: String
        if !calendar.isDate(start, equalTo: end, toGranularity: .year) {
            startFormat = "d MMM yyyy"
        } else if calendar.isDate(start, equalTo: end, toGranularity: .month) {
            startFormat = "d"
        } else {
            startFormat = "d MMM"
        }
        return "W\(week.number) · \(format(start, as: startFormat))–\(format(end, as: "d MMM yyyy"))"
    }

    private func format(_ date: Date, as pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Self.english
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

enum TBPanelTab: CaseIterable {
    case stats, settings

    var title: String {
        switch self {
        case .stats: return "Stats"
        case .settings: return NSLocalizedString("TBPopoverView.settings.label", comment: "Settings label")
        }
    }
}

final class TBStatsPanelModel: ObservableObject {
    @Published var tab: TBPanelTab = .stats
    @Published var selection: TBStatsSelection
    @Published private(set) var statistics: TBStatistics
    @Published private(set) var historyError: Error?
    @Published private(set) var resetCount = 0
    @Published private(set) var showsDayFocus = false
    @Published private(set) var firstDayFocusRequest = 0
    private var awaitsFirstDayTab = true

    private var intervals: [TBRecordedInterval] = []

    init(now: Date = Date(), timeZone: TimeZone = .current) {
        let statistics = TBStatistics(timeZone: timeZone)
        self.statistics = statistics
        selection = TBStatsSelection(now: now, statistics: statistics)
    }

    func reset(now: Date = Date(), timeZone: TimeZone = .current) {
        refreshTimeZone(to: timeZone)
        selection = TBStatsSelection(now: now, statistics: statistics)
        tab = .stats
        showsDayFocus = false
        awaitsFirstDayTab = true
        resetCount += 1
    }

    func clickDay(_ day: Date) {
        showsDayFocus = false
        awaitsFirstDayTab = false
        selection.clickDay(day)
    }

    func handleDayTab(backward: Bool) -> Bool {
        if !showsDayFocus { showsDayFocus = true }
        let startAtMonday = awaitsFirstDayTab && !backward
        awaitsFirstDayTab = false
        if startAtMonday {
            firstDayFocusRequest += 1
        }
        return startAtMonday
    }

    func updateHistory(_ snapshot: TBHistorySnapshot) {
        intervals = snapshot.intervals
        statistics = TBStatistics(intervals: intervals, timeZone: statistics.calendar.timeZone)
        historyError = nil
    }

    func failReading(_ error: Error) {
        historyError = error
    }

    func refreshTimeZone(to timeZone: TimeZone = .current) {
        let calendar = statistics.calendar
        guard calendar.timeZone != timeZone else { return }
        let updated = TBStatistics(intervals: intervals, timeZone: timeZone)
        selection.changeTimeZone(from: calendar, to: updated)
        statistics = updated
    }
}
