import SwiftUI

struct TBStatsView: View {
    @ObservedObject var model: TBStatsPanelModel
    let retry: () -> Void

    private let weekdays = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
    private let focusColor = Color(NSColor.systemRed)
    private let restColor = Color(NSColor.systemGray)

    var body: some View {
        Group {
            if model.historyError != nil {
                VStack(spacing: 10) {
                    Text("Could not load the activity log")
                    Button("Retry", action: retry)
                }
                .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                let selection = model.selection
                let statistics = model.statistics
                let format = TBStatsFormat(calendar: statistics.calendar)
                let week = statistics.week(containing: selection.visibleWeek)
                let selectedDay = week.days.first { $0.date == selection.selectedDay }
                    ?? statistics.day(containing: selection.selectedDay)

                VStack(alignment: .leading, spacing: 12) {
                    dailySummary(selectedDay, title: format.day(selectedDay.date, today: selection.today))
                    Divider()
                    weekHeader(week, format: format)
                    weekChart(week, format: format)
                        .id(model.resetCount)
                }
            }
        }
        .padding(6)
    }

    private func dailySummary(_ day: TBStatsDay, title: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(TBStatsFormat.duration(day.totalMinutes))
                    .font(.title2.monospacedDigit())
                    .fixedSize()
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 4) {
                breakdown("Rest", minutes: day.restMinutes, seconds: day.duration.rest,
                          total: day.duration.total, color: restColor)
                breakdown("Focus", minutes: day.focusMinutes, seconds: day.duration.focus,
                          total: day.duration.total, color: focusColor)
            }
        }
    }

    private func breakdown(_ title: String, minutes: Int, seconds: TimeInterval,
                           total: TimeInterval, color: Color) -> some View {
        HStack(spacing: 5) {
            legend(title, color: color)
                .frame(width: 47, alignment: .leading)
            Text(TBStatsFormat.duration(minutes))
                .frame(minWidth: 58, alignment: .trailing)
            Text(TBStatsFormat.percentage(seconds, of: total))
                .foregroundColor(.secondary)
                .frame(minWidth: 42, alignment: .trailing)
        }
        .font(.caption.monospacedDigit())
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
    }

    private func legend(_ title: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(title)
        }
    }

    private func weekHeader(_ week: TBStatsWeek, format: TBStatsFormat) -> some View {
        HStack(spacing: 6) {
            weekArrow("chevron.left", label: "Previous week", offset: -1)
            Text("\(format.week(week))  ·  \(TBStatsFormat.duration(week.totalMinutes))")
                .font(.caption.monospacedDigit())
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            weekArrow("chevron.right", label: "Next week", offset: 1)
                .disabled(!model.selection.canGoForward)
        }
    }

    private func weekArrow(_ icon: String, label: String, offset: Int) -> some View {
        Button {
            model.selection.moveWeek(by: offset, calendar: model.statistics.calendar)
        } label: {
            Image(systemName: icon).frame(width: 15, height: 16)
        }
        .accessibilityLabel(Text(label))
    }

    private func weekChart(_ week: TBStatsWeek, format: TBStatsFormat) -> some View {
        let peak = week.days.map { $0.duration.total }.max() ?? 0
        return HStack(spacing: 2) {
            ForEach(Array(week.days.enumerated()), id: \.element.id) { index, day in
                dayColumn(day, weekday: weekdays[index], peak: peak, format: format)
            }
        }
    }

    private func dayColumn(_ day: TBStatsDay, weekday: String, peak: TimeInterval,
                           format: TBStatsFormat) -> some View {
        let isPinned = model.selection.pinnedDay == day.date
        let isPreviewed = model.selection.previewDay == day.date
        let scale = peak > 0 ? 82 / peak : 0
        let button = Button {
            model.clickDay(day.date)
        } label: {
            VStack(spacing: 4) {
                Spacer(minLength: 0)
                Text(TBStatsFormat.chartMinutes(day.totalMinutes))
                    .font(.caption2.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                VStack(spacing: 0) {
                    if day.duration.total == 0 {
                        Capsule().fill(restColor.opacity(0.5)).frame(height: 2)
                    } else {
                        Rectangle().fill(restColor).frame(height: day.duration.rest * scale)
                        Rectangle().fill(focusColor).frame(height: day.duration.focus * scale)
                    }
                }
                .frame(width: 17)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                Text(weekday)
                    .font(.caption2.weight(isPinned ? .bold : .regular))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor.opacity(isPinned ? 0.23 : 0)))
            }
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .background(RoundedRectangle(cornerRadius: 4)
                .fill(Color.primary.opacity(isPinned || isPreviewed ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        let focusRequest = weekday == weekdays[0] ? model.firstDayFocusRequest : 0
        return button.modifier(TBDayKeyboardFocus(visible: model.showsDayFocus, request: focusRequest) {
            model.selection.pinDay(day.date)
        })
            .onHover { hovering in
                model.selection.hoverDay(day.date, hovering: hovering)
            }
            .accessibilityLabel(Text(format.day(day.date, today: model.selection.today)))
            .accessibilityValue(Text(TBStatsFormat.chartMinutes(day.totalMinutes)))
            .accessibilityAddTraits(isPinned ? .isSelected : [])
    }
}

private struct TBDayKeyboardFocus: ViewModifier {
    let visible: Bool
    let request: Int
    let pin: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.modifier(TBDayFocusRing(visible: visible, request: request, pin: pin))
        } else {
            content
        }
    }
}

@available(macOS 14.0, *)
private struct TBDayFocusRing: ViewModifier {
    let visible: Bool
    let request: Int
    let pin: () -> Void
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .overlay {
                if focused && visible {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .onChange(of: request) { _, _ in
                DispatchQueue.main.async { focused = true }
            }
            .onKeyPress(.space) {
                pin()
                return .handled
            }
    }
}
