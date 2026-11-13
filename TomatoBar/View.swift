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
        }
        .padding(4)
    }
}

private struct GeneralSettingsView: View {
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
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            Toggle(isOn: $timer.showTimerInMenuBar) {
                Text(NSLocalizedString("SettingsView.showTimerInMenuBar.label",
                                       comment: "Show timer in menu bar label"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .onChange(of: timer.showTimerInMenuBar) { _ in
                timer.updateTimeLeft()
            }
            Toggle(isOn: $launchAtLogin.isEnabled) {
                Text(NSLocalizedString("SettingsView.launchAtLogin.label",
                                       comment: "Launch at login label"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
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
    }
}

private struct SettingsView: View {
    @EnvironmentObject var timer: TBTimer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            section(NSLocalizedString("SettingsView.general.label", comment: "General settings section")) {
                GeneralSettingsView()
            }
            Divider()
            section(NSLocalizedString("TBPopoverView.intervals.label", comment: "Intervals label")) {
                IntervalsView()
            }
            Divider()
            section(NSLocalizedString("TBPopoverView.sounds.label", comment: "Sounds label")) {
                SoundsView().environmentObject(timer.player)
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }
}

private struct TBPopoverSize: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

struct TBPopoverView: View {
    @ObservedObject var timer: TBTimer
    @ObservedObject var stats: TBStatsPanelModel
    let showCurrentStats: () -> Void
    let retryHistory: () -> Void
    let resize: (CGSize) -> Void

    @State private var buttonHovered = false

    init(timer: TBTimer, stats: TBStatsPanelModel, showCurrentStats: @escaping () -> Void,
         retryHistory: @escaping () -> Void, resize: @escaping (CGSize) -> Void) {
        self.timer = timer
        self.stats = stats
        self.showCurrentStats = showCurrentStats
        self.retryHistory = retryHistory
        self.resize = resize
    }

    private var startLabel = NSLocalizedString("TBPopoverView.start.label", comment: "Start label")
    private var stopLabel = NSLocalizedString("TBPopoverView.stop.label", comment: "Stop label")

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button {
                    timer.startStop()
                    TBStatusItem.shared.closePopover(nil)
                } label: {
                    Text(timer.canTogglePause ?
                         (buttonHovered && !timer.isPaused ? stopLabel : timer.timeLeftString) :
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
                .disabled(timer.isPaused)

                Button(action: timer.togglePause) {
                    Image(systemName: "pause.fill")
                        .frame(width: 26, height: 26)
                        .foregroundColor(timer.isPaused ? .black : .primary)
                        .background(timer.isPaused ? Color(TBTimer.pauseColor) : Color.primary.opacity(0.10))
                        .cornerRadius(6)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Pause"))
                .accessibilityAddTraits(timer.isPaused ? .isSelected : [])
                .disabled(!timer.canTogglePause)
                .opacity(timer.canTogglePause ? 1 : 0.5)

                Button(action: timer.skipInterval) {
                    Text("Skip")
                        .padding(.horizontal, 6)
                        .frame(minHeight: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!timer.canSkipInterval)
                .opacity(timer.canSkipInterval ? 1 : 0.5)
            }

            HStack(spacing: 2) {
                ForEach(TBPanelTab.allCases, id: \.self) { tab in
                    Button {
                        if tab == .stats {
                            showCurrentStats()
                        } else {
                            stats.selection.previewDay = nil
                            stats.tab = tab
                        }
                    } label: {
                        Text(tab.title)
                            .font(.callout)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 24)
                            .background(RoundedRectangle(cornerRadius: 5)
                                .fill(Color.primary.opacity(stats.tab == tab ? 0.16 : 0)))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(stats.tab == tab ? .isSelected : [])
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.07)))

            GroupBox {
                switch stats.tab {
                case .stats:
                    TBStatsView(model: stats, retry: retryHistory)
                case .settings:
                    SettingsView().environmentObject(timer)
                }
            }
            .frame(maxWidth: .infinity)

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
        .padding(12)
        .frame(width: 328)
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { geometry in
            Color.clear.preference(key: TBPopoverSize.self, value: geometry.size)
        })
        .onPreferenceChange(TBPopoverSize.self, perform: resize)
    }
}
