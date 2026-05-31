import KeyboardShortcuts
import LaunchAtLogin
import SwiftUI

extension KeyboardShortcuts.Name {
    static let startStopTimer = Self("startStopTimer")
}

private struct IntervalsView: View {
    @EnvironmentObject var timer: TBTimer
    private var minStr = NSLocalizedString("IntervalsView.min", comment: "min")

    var body: some View {
        VStack {
            Stepper(value: $timer.workIntervalLength, in: 1 ... 60) {
                HStack {
                    Text(NSLocalizedString("IntervalsView.workIntervalLength.label",
                                           comment: "Work interval label"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(String.localizedStringWithFormat(minStr, timer.workIntervalLength))
                }
            }
            Stepper(value: $timer.shortRestIntervalLength, in: 1 ... 60) {
                HStack {
                    Text(NSLocalizedString("IntervalsView.shortRestIntervalLength.label",
                                           comment: "Short rest interval label"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(String.localizedStringWithFormat(minStr, timer.shortRestIntervalLength))
                }
            }
            Stepper(value: $timer.longRestIntervalLength, in: 1 ... 60) {
                HStack {
                    Text(NSLocalizedString("IntervalsView.longRestIntervalLength.label",
                                           comment: "Long rest interval label"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(String.localizedStringWithFormat(minStr, timer.longRestIntervalLength))
                }
            }
            .help(NSLocalizedString("IntervalsView.longRestIntervalLength.help",
                                    comment: "Long rest interval hint"))
            Stepper(value: $timer.workIntervalsInSet, in: 1 ... 10) {
                HStack {
                    Text(NSLocalizedString("IntervalsView.workIntervalsInSet.label",
                                           comment: "Work intervals in a set label"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(timer.workIntervalsInSet)")
                }
            }
            .help(NSLocalizedString("IntervalsView.workIntervalsInSet.help",
                                    comment: "Work intervals in set hint"))
            Spacer().frame(minHeight: 0)
        }
        .padding(4)
    }
}

private struct SettingsView: View {
    @EnvironmentObject var timer: TBTimer
    @ObservedObject private var launchAtLogin = LaunchAtLogin.observable

    var body: some View {
        VStack {
            KeyboardShortcuts.Recorder(for: .startStopTimer) {
                Text(NSLocalizedString("SettingsView.shortcut.label",
                                       comment: "Shortcut label"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Toggle(isOn: $timer.stopAfterBreak) {
                Text(NSLocalizedString("SettingsView.stopAfterBreak.label",
                                       comment: "Stop after break label"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.toggleStyle(.switch)
            Toggle(isOn: $timer.showTimerInMenuBar) {
                Text(NSLocalizedString("SettingsView.showTimerInMenuBar.label",
                                       comment: "Show timer in menu bar label"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.toggleStyle(.switch)
                .onChange(of: timer.showTimerInMenuBar) { _ in
                    timer.updateTimeLeft()
                }
            Toggle(isOn: $launchAtLogin.isEnabled) {
                Text(NSLocalizedString("SettingsView.launchAtLogin.label",
                                       comment: "Launch at login label"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.toggleStyle(.switch)
            Spacer().frame(minHeight: 0)
        }
        .padding(4)
    }
}

private struct VolumeSlider: View {
    @Binding var volume: Double

    var body: some View {
        Slider(value: $volume, in: 0...2) {
            Text(String(format: "%.1f", volume))
        }.gesture(TapGesture(count: 2).onEnded({
            volume = 1.0
        }))
    }
}

private struct SoundsView: View {
    @EnvironmentObject var player: TBPlayer

    private var columns = [
        GridItem(.flexible()),
        GridItem(.fixed(110))
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
            Text(NSLocalizedString("SoundsView.isWindupEnabled.label",
                                   comment: "Windup label"))
            VolumeSlider(volume: $player.windupVolume)
            Text(NSLocalizedString("SoundsView.isDingEnabled.label",
                                   comment: "Ding label"))
            VolumeSlider(volume: $player.dingVolume)
            Text(NSLocalizedString("SoundsView.isTickingEnabled.label",
                                   comment: "Ticking label"))
            VolumeSlider(volume: $player.tickingVolume)
        }.padding(4)
        Spacer().frame(minHeight: 0)
    }
}

private func tbColor(_ kind: TBIntervalKind) -> Color {
    switch kind {
    case .work: return .accentColor
    case .shortRest: return .blue
    case .longRest: return .orange
    }
}

private func tbKindLabel(_ kind: TBIntervalKind) -> String {
    switch kind {
    case .work:
        return NSLocalizedString("StatsView.work.label", comment: "Work")
    case .shortRest:
        return NSLocalizedString("StatsView.shortRest.label", comment: "Short break")
    case .longRest:
        return NSLocalizedString("StatsView.longRest.label", comment: "Long break")
    }
}

private let tbHMFormatter: DateComponentsFormatter = {
    let f = DateComponentsFormatter()
    f.unitsStyle = .abbreviated
    f.allowedUnits = [.hour, .minute]
    return f
}()

private func tbFormatHM(_ seconds: TimeInterval) -> String {
    if seconds < 60 { return "0m" }
    return tbHMFormatter.string(from: seconds) ?? "0m"
}

private let tbClockFormatter: DateFormatter = {
    let f = DateFormatter()
    f.timeStyle = .short
    f.dateStyle = .none
    return f
}()

private let tbDayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.setLocalizedDateFormatFromTemplate("MMMd")
    return f
}()

/* Anything under a minute is treated as "no data" so a just-started or
 * idle day renders as an empty track instead of a full bar. */
private let tbMinTracked: TimeInterval = 60
private let tbTrackColor = Color.primary.opacity(0.08)
private let tbBarRadius: CGFloat = 3

/* Stacked colored bar over a faint track. The overall fill width is scaled
 * by `scaleMax` (the busiest recent day) so short days look short and the
 * longest day fills the bar - they are never normalised to themselves. */
private struct TBBar: View {
    /* (color, seconds) in draw order. */
    let segments: [(Color, TimeInterval)]
    let scaleMax: TimeInterval

    var body: some View {
        let total = segments.reduce(0) { $0 + $1.1 }
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: tbBarRadius).fill(tbTrackColor)
                if total >= tbMinTracked, scaleMax >= tbMinTracked {
                    let fillW = geo.size.width
                        * CGFloat(min(1, total / scaleMax))
                    HStack(spacing: 0) {
                        ForEach(Array(segments.enumerated()), id: \.offset) { _, s in
                            Rectangle().fill(s.0)
                                .frame(width: total > 0
                                       ? fillW * CGFloat(s.1 / total) : 0)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: tbBarRadius))
                }
            }
        }
    }
}

private struct TBRecentRow: View {
    let summary: TBDaySummary
    let scaleMax: TimeInterval
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(tbDayFormatter.string(from: summary.day))
                .font(.caption.monospacedDigit())
                .foregroundColor(isSelected ? .primary : .secondary)
                .frame(width: 46, alignment: .leading)
            TBBar(segments: [(.accentColor, summary.workSeconds)],
                  scaleMax: scaleMax)
                .frame(height: 6)
            Text(tbFormatHM(summary.workSeconds))
                .font(.caption.monospacedDigit())
                .foregroundColor(summary.workSeconds >= tbMinTracked
                                 ? .primary : .secondary)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : .clear)
        )
        .contentShape(Rectangle())
    }
}

private struct StatsView: View {
    @EnvironmentObject var timer: TBTimer
    @StateObject private var store = TBStatsStore()
    @State private var selectedDate = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DatePicker("", selection: $selectedDate,
                       in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.field)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)

            if store.loadError {
                placeholder("StatsView.error.label")
            } else if store.days.isEmpty {
                placeholder("StatsView.empty.label")
            } else {
                content
            }

            Spacer().frame(minHeight: 0)
        }
        .padding(6)
        .onAppear {
            store.load(workLen: timer.workIntervalLength,
                       shortLen: timer.shortRestIntervalLength,
                       longLen: timer.longRestIntervalLength)
        }
    }

    private func placeholder(_ key: String) -> some View {
        VStack {
            Spacer()
            Text(NSLocalizedString(key, comment: ""))
                .font(.caption).foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
            Spacer()
        }
    }

    @ViewBuilder private var content: some View {
        let recent = store.recentDays(7)
        let scaleMax = recent
            .map { $0.workSeconds + $0.shortRestSeconds + $0.longRestSeconds }
            .max() ?? 0
        let workScale = recent.map(\.workSeconds).max() ?? 0
        let summary = store.summary(for: selectedDate)
        let selectedDay = Calendar.current.startOfDay(for: selectedDate)

        // Selected day summary
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(NSLocalizedString("StatsView.worked.label",
                                       comment: "Worked"))
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                Text(tbFormatHM(summary.workSeconds))
                    .font(.system(.title3).monospacedDigit())
            }
            TBBar(segments: [(.accentColor, summary.workSeconds),
                             (.blue, summary.shortRestSeconds),
                             (.orange, summary.longRestSeconds)],
                  scaleMax: scaleMax)
                .frame(height: 7)
        }

        if summary.intervals.isEmpty {
            Text(NSLocalizedString("StatsView.noData.label",
                                   comment: "No activity"))
                .font(.caption).foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(summary.intervals) { iv in
                        intervalRow(iv)
                    }
                }
                .padding(.trailing, 2)
            }
            .frame(maxHeight: 90)
        }

        Divider()

        Text(NSLocalizedString("StatsView.recent.label",
                               comment: "Recent days"))
            .font(.caption).foregroundColor(.secondary)
        VStack(spacing: 1) {
            ForEach(recent) { day in
                TBRecentRow(summary: day, scaleMax: workScale,
                            isSelected: day.day == selectedDay)
                    .onTapGesture { selectedDate = day.day }
            }
        }
    }

    private func intervalRow(_ iv: TBInterval) -> some View {
        HStack(spacing: 6) {
            Circle().fill(tbColor(iv.kind)).frame(width: 6, height: 6)
            Text(tbClockFormatter.string(from: iv.start)
                 + " – "
                 + (iv.continuesToNextDay ? "00:00"
                    : tbClockFormatter.string(from: iv.end)))
                .font(.caption.monospacedDigit())
                .fixedSize()
            Text(tbKindLabel(iv.kind))
                .font(.caption).foregroundColor(.secondary)
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            if iv.continuesFromPrevDay {
                Text("↰").font(.caption2).foregroundColor(.secondary)
            }
            if iv.continuesToNextDay {
                Text("↴").font(.caption2).foregroundColor(.secondary)
            }
            if iv.isOpenEnded {
                Text("…").font(.caption2).foregroundColor(.secondary)
            }
            Text(tbFormatHM(iv.duration))
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 42, alignment: .trailing)
        }
    }
}

private enum ChildView {
    case intervals, settings, sounds, stats
}

struct TBPopoverView: View {
    @ObservedObject var timer = TBTimer()
    @State private var buttonHovered = false
    @State private var activeChildView = ChildView.intervals

    private var startLabel = NSLocalizedString("TBPopoverView.start.label", comment: "Start label")
    private var stopLabel = NSLocalizedString("TBPopoverView.stop.label", comment: "Stop label")

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                timer.startStop()
                TBStatusItem.shared.closePopover(nil)
            } label: {
                Text(timer.timer != nil ?
                     (buttonHovered ? stopLabel : timer.timeLeftString) :
                        startLabel)
                    /*
                      When appearance is set to "Dark" and accent color is set to "Graphite"
                      "defaultAction" button label's color is set to the same color as the
                      button, making the button look blank. #24
                     */
                    .foregroundColor(Color.white)
                    .font(.system(.body).monospacedDigit())
                    .frame(maxWidth: .infinity)
            }
            .onHover { over in
                buttonHovered = over
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            Picker("", selection: $activeChildView) {
                Text(NSLocalizedString("TBPopoverView.intervals.label",
                                       comment: "Intervals label")).tag(ChildView.intervals)
                Text(NSLocalizedString("TBPopoverView.settings.label",
                                       comment: "Settings label")).tag(ChildView.settings)
                Text(NSLocalizedString("TBPopoverView.sounds.label",
                                       comment: "Sounds label")).tag(ChildView.sounds)
                Text(NSLocalizedString("TBPopoverView.stats.label",
                                       comment: "Stats label")).tag(ChildView.stats)
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .pickerStyle(.segmented)

            GroupBox {
                switch activeChildView {
                case .intervals:
                    IntervalsView().environmentObject(timer)
                case .settings:
                    SettingsView().environmentObject(timer)
                case .sounds:
                    SoundsView().environmentObject(timer.player)
                case .stats:
                    StatsView().environmentObject(timer)
                }
            }

            Group {
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.orderFrontStandardAboutPanel()
                } label: {
                    Text(NSLocalizedString("TBPopoverView.about.label",
                                           comment: "About label"))
                    Spacer()
                    Text("⌘ A").foregroundColor(Color.gray)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("a")
                Button {
                    NSApplication.shared.terminate(self)
                } label: {
                    Text(NSLocalizedString("TBPopoverView.quit.label",
                                           comment: "Quit label"))
                    Spacer()
                    Text("⌘ Q").foregroundColor(Color.gray)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q")
            }
        }
        #if DEBUG
            /*
             After several hours of Googling and trying various StackOverflow
             recipes I still haven't figured a reliable way to auto resize
             popover to fit all it's contents (pull requests are welcome!).
             The following code block is used to determine the optimal
             geometry of the popover.
             */
            .overlay(
                GeometryReader { proxy in
                    debugSize(proxy: proxy)
                }
            )
        #endif
            /* Use values from GeometryReader */
//            .frame(width: 240, height: 276)
            .padding(12)
    }
}

#if DEBUG
    func debugSize(proxy: GeometryProxy) -> some View {
        print("Optimal popover size:", proxy.size)
        return Color.clear
    }
#endif
