import Foundation
import XCTest

final class StatisticsTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!
    private let madrid = TimeZone(identifier: "Europe/Madrid")!

    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    func testSplitsSundayMidnightAndRedistributesInAnotherTimeZone() {
        let start = date("2026-11-01T22:50:00Z")
        let end = date("2026-11-01T23:20:00Z")
        let intervals = [TBRecordedInterval(kind: .work, start: start, end: end)]
        let local = TBStatistics(intervals: intervals, timeZone: madrid)
        XCTAssertEqual(local.week(containing: start).totalMinutes, 10)
        XCTAssertEqual(local.week(containing: end).totalMinutes, 20)
        XCTAssertEqual(local.day(containing: end).duration.focus, 1200)
        XCTAssertEqual(TBStatistics(intervals: intervals, timeZone: utc).day(containing: end).totalMinutes, 30)
    }

    func testUsesActualSecondsAcrossTheSpringClockChange() {
        let start = date("2026-03-28T23:00:00Z")
        let end = date("2026-03-29T22:05:00Z")
        let statistics = TBStatistics(intervals: [
            TBRecordedInterval(kind: .rest, start: start, end: end),
        ], timeZone: madrid)
        XCTAssertEqual(statistics.day(containing: start).restMinutes, 23 * 60)
        XCTAssertEqual(statistics.day(containing: end).restMinutes, 5)
    }

    func testRoundingKeepsWeekAndDayTotalsConsistentWithStableTies() {
        let monday = date("2026-11-02T12:00:00Z")
        let tuesday = date("2026-11-03T12:00:00Z")
        let intervals = [monday, tuesday].flatMap { start in
            [
                TBRecordedInterval(kind: .work, start: start, end: start.addingTimeInterval(20)),
                TBRecordedInterval(kind: .rest, start: start.addingTimeInterval(20), end: start.addingTimeInterval(40)),
            ]
        }
        let statistics = TBStatistics(intervals: intervals, timeZone: utc)
        let week = statistics.week(containing: tuesday)
        XCTAssertEqual(week.totalMinutes, 1)
        XCTAssertEqual(week.days.map(\.totalMinutes), [1, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(statistics.day(containing: monday).focusMinutes, 1)
        XCTAssertEqual(statistics.day(containing: monday).restMinutes, 0)
        XCTAssertEqual(TBStatsFormat.percentage(20, of: 40), "50.0%")
        XCTAssertEqual(TBStatsFormat.percentage(0, of: 0), "—")
    }

    func testEnglishDatesAndISOWeekAcrossYearBoundary() {
        let statistics = TBStatistics(timeZone: utc)
        let format = TBStatsFormat(calendar: statistics.calendar)
        let newYear = date("2027-01-01T12:00:00Z")
        XCTAssertEqual(format.week(statistics.week(containing: newYear)), "W53 · 28 Dec 2026–3 Jan 2027")
        XCTAssertEqual(format.week(statistics.week(containing: date("2026-11-01T12:00:00Z"))), "W44 · 26 Oct–1 Nov 2026")
        XCTAssertEqual(format.week(statistics.week(containing: date("2026-11-04T12:00:00Z"))), "W45 · 2–8 Nov 2026")
        XCTAssertEqual(format.day(date("2026-11-04T12:00:00Z"), today: newYear), "4 Nov 2026")
        XCTAssertEqual(TBStatsFormat.chartMinutes(85), "85 min")
        XCTAssertEqual(TBStatsFormat.chartMinutes(0), "0 min")
        XCTAssertEqual(TBStatsFormat.duration(205), "3 h 25 min")
    }

    func testSavedCloseUpdatesStatsWithoutChangingTheSelectedDayOrWeek() {
        let now = date("2026-11-04T12:00:00Z")
        let model = TBStatsPanelModel(now: now, timeZone: utc)
        model.selection.moveWeek(by: -1, calendar: model.statistics.calendar)
        let week = model.selection.visibleWeek
        let pinned = model.selection.today
        model.selection.pinnedDay = pinned
        let start = now.timeIntervalSince1970
        let opening = #"{"type":"transition","timestamp":\#(start),"event":"startStop","fromState":"idle","toState":"work"}"# + "\n"
        let closing = #"{"type":"transition","timestamp":\#(start + 1500),"event":"pause","fromState":"work","toState":"paused"}"# + "\n"

        model.updateHistory(TBHistory.parse(Data(opening.utf8)))
        XCTAssertEqual(model.statistics.day(containing: pinned).totalMinutes, 0)

        model.failReading(CocoaError(.fileReadUnknown))
        XCTAssertNotNil(model.historyError)
        model.updateHistory(TBHistory.parse(Data((opening + closing).utf8)))
        XCTAssertNil(model.historyError)
        XCTAssertEqual(model.statistics.day(containing: pinned).focusMinutes, 25)
        XCTAssertEqual(model.selection.visibleWeek, week)
        XCTAssertEqual(model.selection.selectedDay, pinned)

        model.reset(now: now, timeZone: utc)
        XCTAssertEqual(model.tab, .stats)
        XCTAssertNil(model.selection.pinnedDay)
        XCTAssertEqual(model.selection.visibleWeek, model.selection.currentWeek)
    }

    func testTimeZoneChangeRebuildsTotalsAndKeepsThePinnedCivilDate() {
        let now = date("2026-11-02T00:10:00Z")
        let model = TBStatsPanelModel(now: now, timeZone: utc)
        let start = date("2026-11-01T23:50:00Z")
        model.updateHistory(TBHistorySnapshot(intervals: [
            TBRecordedInterval(kind: .rest, start: start, end: now),
        ], damagedLines: []))
        model.selection.pinnedDay = model.selection.today
        XCTAssertEqual(model.statistics.day(containing: model.selection.selectedDay).restMinutes, 10)

        model.refreshTimeZone(to: madrid)
        XCTAssertEqual(model.statistics.calendar.component(.day, from: model.selection.selectedDay), 2)
        XCTAssertEqual(model.statistics.day(containing: model.selection.selectedDay).restMinutes, 20)
    }

    func testSecondClickClearsSelectionUntilThePointerReenters() {
        let statistics = TBStatistics(timeZone: utc)
        let now = date("2026-11-04T12:00:00Z")
        var selection = TBStatsSelection(now: now, statistics: statistics)
        let days = statistics.week(containing: now).days
        let monday = days[0].date
        let tuesday = days[1].date

        selection.hoverDay(monday, hovering: true)
        selection.clickDay(monday)
        XCTAssertEqual(selection.pinnedDay, monday)
        selection.clickDay(monday)
        selection.hoverDay(monday, hovering: true)
        XCTAssertNil(selection.pinnedDay)
        XCTAssertEqual(selection.selectedDay, selection.today)

        selection.hoverDay(monday, hovering: false)
        selection.hoverDay(monday, hovering: true)
        XCTAssertEqual(selection.selectedDay, monday)
        selection.clickDay(tuesday)
        XCTAssertEqual(selection.pinnedDay, tuesday)
        XCTAssertEqual(selection.selectedDay, tuesday)

        selection.pinDay(tuesday)
        XCTAssertEqual(selection.pinnedDay, tuesday)
    }

    func testPreviewAndWeekNavigationKeepThePinnedDay() {
        let statistics = TBStatistics(timeZone: utc)
        let now = date("2026-11-04T12:00:00Z")
        var selection = TBStatsSelection(now: now, statistics: statistics)
        let week = statistics.week(containing: now)
        selection.moveWeek(by: 1, calendar: statistics.calendar)
        XCTAssertEqual(selection.visibleWeek, week.days[0].date)
        selection.previewDay = week.days[0].date
        XCTAssertEqual(selection.selectedDay, week.days[0].date)
        selection.previewDay = nil
        XCTAssertEqual(selection.selectedDay, selection.today)
        selection.pinnedDay = week.days[1].date
        selection.previewDay = week.days[2].date
        XCTAssertEqual(selection.selectedDay, week.days[2].date)
        selection.moveWeek(by: -1, calendar: statistics.calendar)
        XCTAssertEqual(selection.selectedDay, week.days[1].date)
        XCTAssertTrue(selection.canGoForward)
    }
}
