import KeyboardShortcuts
import LaunchAtLogin
import SwiftUI
import UniformTypeIdentifiers

extension KeyboardShortcuts.Name {
    static let startStopTimer = Self("startStopTimer")
}

private extension Binding where Value == Int {
    func clamped(to range: ClosedRange<Int>) -> Binding<Int> {
        Binding {
            wrappedValue
        } set: { newValue in
            wrappedValue = Swift.min(Swift.max(newValue, range.lowerBound), range.upperBound)
        }
    }
}

private struct NumericStepperRow: View {
    let title: String
    let suffix: String?
    let range: ClosedRange<Int>
    @Binding var value: Int

    private var formatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.allowsFloats = false
        formatter.minimum = NSNumber(value: range.lowerBound)
        formatter.maximum = NSNumber(value: range.upperBound)
        formatter.numberStyle = .none
        return formatter
    }

    private var validatedValue: Binding<Int> {
        $value.clamped(to: range)
    }

    var body: some View {
        Stepper(value: validatedValue, in: range) {
            HStack {
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 3) {
                    TextField("", value: validatedValue, formatter: formatter)
                        .multilineTextAlignment(.trailing)
                        .font(.system(.body).monospacedDigit())
                        .frame(width: 32)
                    if let suffix {
                        Text(suffix)
                    }
                }
                .accessibilityLabel(title)
            }
        }
    }
}

private struct IntervalsView: View {
    @EnvironmentObject var timer: TBTimer
    private var minStr = NSLocalizedString("IntervalsView.min", comment: "min")
    private var minSuffix: String {
        String.localizedStringWithFormat(minStr, 0).replacingOccurrences(of: "0", with: "").trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        VStack {
            NumericStepperRow(title: NSLocalizedString("IntervalsView.workIntervalLength.label",
                                                       comment: "Work interval label"),
                              suffix: minSuffix,
                              range: 1 ... 60,
                              value: $timer.workIntervalLength)
            NumericStepperRow(title: NSLocalizedString("IntervalsView.shortRestIntervalLength.label",
                                                       comment: "Short rest interval label"),
                              suffix: minSuffix,
                              range: 1 ... 60,
                              value: $timer.shortRestIntervalLength)
            NumericStepperRow(title: NSLocalizedString("IntervalsView.longRestIntervalLength.label",
                                                       comment: "Long rest interval label"),
                              suffix: minSuffix,
                              range: 1 ... 60,
                              value: $timer.longRestIntervalLength)
            .help(NSLocalizedString("IntervalsView.longRestIntervalLength.help",
                                    comment: "Long rest interval hint"))
            NumericStepperRow(title: NSLocalizedString("IntervalsView.workIntervalsInSet.label",
                                                       comment: "Work intervals per set label"),
                              suffix: nil,
                              range: 1 ... 10,
                              value: $timer.workIntervalsInSet)
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
            Toggle(isOn: $timer.showSecondsInMenuBar) {
                Text(NSLocalizedString("SettingsView.showSecondsInMenuBar.label",
                                       comment: "Show seconds in menu bar label"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.toggleStyle(.switch)
                .padding(.leading, 16)
                .disabled(!timer.showTimerInMenuBar)
                .onChange(of: timer.showSecondsInMenuBar) { _ in
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

    private var level: Int {
        Int((volume * 5).rounded())
    }

    var body: some View {
        /* Shown as 0-10; 5 is the sound's natural loudness */
        HStack(spacing: 4) {
            /* Fixed widths so the track doesn't shift with the icon or between 9 and 10 */
            Image(systemName: level == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .foregroundColor(.secondary)
                .frame(width: 20, alignment: .leading)
                .accessibilityHidden(true)
            Text("\(level)")
                .frame(width: 20, alignment: .center)
            Slider(value: $volume, in: 0...2, step: 0.2)
                .labelsHidden()
                .gesture(TapGesture(count: 2).onEnded({
                    volume = 1.0
                }))
        }
    }
}

private struct SoundRow: View {
    @EnvironmentObject var player: TBPlayer
    let sound: TBSound
    let label: String
    @Binding var volume: Double

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.directoryURL = player.customSoundURL(sound)?.deletingLastPathComponent()
            ?? URL(fileURLWithPath: "/System/Library/Sounds")
        if TBStatusItem.shared.runModalKeepingPopover(panel) == .OK, let url = panel.url {
            player.setCustomSound(sound, url: url)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                Spacer()
                Text(player.customSoundNames[sound] ??
                     NSLocalizedString("SoundsView.defaultSound.label", comment: "Default sound name"))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(.secondary)
                if player.customSoundNames[sound] != nil {
                    Button {
                        player.resetSound(sound)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderless)
                    .help(NSLocalizedString("SoundsView.resetSound.help", comment: "Use default sound hint"))
                    .accessibilityLabel(NSLocalizedString("SoundsView.resetSound.help",
                                                          comment: "Use default sound hint"))
                }
                Button {
                    chooseFile()
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help(NSLocalizedString("SoundsView.chooseSound.help", comment: "Choose sound file hint"))
                .accessibilityLabel(NSLocalizedString("SoundsView.chooseSound.help",
                                                      comment: "Choose sound file hint"))
            }
            VolumeSlider(volume: $volume)
        }
    }
}

private struct SoundsView: View {
    @EnvironmentObject var player: TBPlayer

    var body: some View {
        VStack(spacing: 8) {
            SoundRow(sound: .windup,
                     label: NSLocalizedString("SoundsView.isWindupEnabled.label",
                                              comment: "Windup label"),
                     volume: $player.windupVolume)
            SoundRow(sound: .ding,
                     label: NSLocalizedString("SoundsView.isDingEnabled.label",
                                              comment: "Ding label"),
                     volume: $player.dingVolume)
            SoundRow(sound: .ticking,
                     label: NSLocalizedString("SoundsView.isTickingEnabled.label",
                                              comment: "Ticking label"),
                     volume: $player.tickingVolume)
        }
        .padding(4)
        .onDisappear {
            player.stopPreview()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSPopover.didCloseNotification)) { _ in
            player.stopPreview()
        }
        Spacer().frame(minHeight: 0)
    }
}

private enum ChildView {
    case intervals, settings, sounds
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
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .pickerStyle(.segmented)

            GroupBox {
                if #available(macOS 13.0, *) {
                    childView(activeChildView)
                } else {
                    /*
                     Popover can't resize before macOS 13, so keep every tab in
                     the layout to size it to the tallest, showing only the active one
                     */
                    ZStack(alignment: .top) {
                        ForEach([ChildView.intervals, .settings, .sounds], id: \.self) { child in
                            childView(child)
                                .opacity(child == activeChildView ? 1 : 0)
                                .allowsHitTesting(child == activeChildView)
                                .accessibilityHidden(child != activeChildView)
                        }
                    }
                }
            }

            Group {
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.orderFrontStandardAboutPanel()
                } label: {
                    HStack {
                        Text(NSLocalizedString("TBPopoverView.about.label",
                                               comment: "About label"))
                        Spacer()
                        Text("⌘ A").foregroundColor(Color.gray)
                    }
                    /* Plain buttons only hit-test drawn content; include the Spacer gap */
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("a")
                Button {
                    NSApplication.shared.terminate(self)
                } label: {
                    HStack {
                        Text(NSLocalizedString("TBPopoverView.quit.label",
                                               comment: "Quit label"))
                        Spacer()
                        Text("⌘ Q").foregroundColor(Color.gray)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q")
            }
        }
        .padding(12)
        .frame(width: popoverWidth)
    }

    /* macOS 26 controls are larger; at 240pt rows overflow and labels truncate */
    private var popoverWidth: CGFloat {
        if #available(macOS 26.0, *) {
            return 280
        }
        return 240
    }

    @ViewBuilder
    private func childView(_ child: ChildView) -> some View {
        switch child {
        case .intervals:
            IntervalsView().environmentObject(timer)
        case .settings:
            SettingsView().environmentObject(timer)
        case .sounds:
            SoundsView().environmentObject(timer.player)
        }
    }
}
