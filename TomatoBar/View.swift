import KeyboardShortcuts
import LaunchAtLogin
import SwiftUI

extension KeyboardShortcuts.Name {
    static let startStopTimer = Self("startStopTimer")
}

private struct LiquidGlassPanel: ViewModifier {
    var cornerRadius: CGFloat = 14
    var interactive = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if interactive {
                content.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            content
                .background(Color(NSColor.controlBackgroundColor).opacity(0.86))
                .cornerRadius(cornerRadius)
        }
    }
}

private extension View {
    func liquidGlassPanel(cornerRadius: CGFloat = 14, interactive: Bool = false) -> some View {
        modifier(LiquidGlassPanel(cornerRadius: cornerRadius, interactive: interactive))
    }
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
        VStack(spacing: 8) {
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
                                                       comment: "Work intervals in a set label"),
                              suffix: nil,
                              range: 1 ... 10,
                              value: $timer.workIntervalsInSet)
            .help(NSLocalizedString("IntervalsView.workIntervalsInSet.help",
                                    comment: "Work intervals in set hint"))
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .center)
    }
}

private struct SettingsView: View {
    @EnvironmentObject var timer: TBTimer
    @ObservedObject private var launchAtLogin = LaunchAtLogin.observable

    var body: some View {
        VStack(spacing: 8) {
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
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .center)
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
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            Text(NSLocalizedString("SoundsView.isWindupEnabled.label",
                                   comment: "Windup label"))
            VolumeSlider(volume: $player.windupVolume)
            Text(NSLocalizedString("SoundsView.isDingEnabled.label",
                                   comment: "Ding label"))
            VolumeSlider(volume: $player.dingVolume)
            Text(NSLocalizedString("SoundsView.isTickingEnabled.label",
                                   comment: "Ticking label"))
            VolumeSlider(volume: $player.tickingVolume)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 18)
        .frame(maxHeight: .infinity, alignment: .center)
    }
}

private enum ChildView {
    case intervals, settings, sounds
}

private struct GlassTabBar: View {
    @Binding var selection: ChildView
    @Namespace private var selectionNamespace

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer {
                tabs
            }
        } else {
            tabs
        }
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            tab(.intervals, title: NSLocalizedString("TBPopoverView.intervals.label",
                                                     comment: "Intervals label"))
            tab(.settings, title: NSLocalizedString("TBPopoverView.settings.label",
                                                    comment: "Settings label"))
            tab(.sounds, title: NSLocalizedString("TBPopoverView.sounds.label",
                                                  comment: "Sounds label"))
        }
        .padding(4)
        .frame(maxWidth: .infinity)
        .liquidGlassPanel(cornerRadius: 18, interactive: true)
        .animation(.snappy(duration: 0.18), value: selection)
    }

    private func tab(_ childView: ChildView, title: String) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.18)) {
                selection = childView
            }
        } label: {
            ZStack {
                if selection == childView {
                    selectedTabBackground
                        .matchedGeometryEffect(id: "selectedTab", in: selectionNamespace)
                }

                Text(title)
                    .font(.system(size: 12, weight: selection == childView ? .semibold : .regular))
                    .foregroundColor(selection == childView ? .primary : .primary.opacity(0.82))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.18), value: selection)
    }

    private var selectedTabBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(red: 0.55, green: 0.18, blue: 0.16).opacity(0.24))
            .modifier(ActiveTabGlass())
    }
}

private struct ActiveTabGlass: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
        } else {
            content.cornerRadius(14)
        }
    }
}

struct TBPopoverView: View {
    @ObservedObject var timer = TBTimer()
    @State private var buttonHovered = false
    @State private var activeChildView = ChildView.intervals

    private var startLabel = NSLocalizedString("TBPopoverView.start.label", comment: "Start label")
    private var stopLabel = NSLocalizedString("TBPopoverView.stop.label", comment: "Stop label")

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                timer.startStop()
                TBStatusItem.shared.closePopover(nil)
            } label: {
                Text(timer.timer != nil ?
                     (buttonHovered ? stopLabel : timer.timeLeftString) :
                        startLabel)
                    .font(.system(.body).monospacedDigit())
                    .frame(maxWidth: .infinity)
            }
            .onHover { over in
                buttonHovered = over
            }
            .controlSize(.large)
            .modifier(PrimaryActionButton())
            .keyboardShortcut(.defaultAction)

            GlassTabBar(selection: $activeChildView)

            Group {
                switch activeChildView {
                case .intervals:
                    IntervalsView().environmentObject(timer)
                case .settings:
                    SettingsView().environmentObject(timer)
                case .sounds:
                    SoundsView().environmentObject(timer.player)
                }
            }
            .frame(height: 150)
            .liquidGlassPanel()

            VStack(spacing: 2) {
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.orderFrontStandardAboutPanel()
                } label: {
                    Label(NSLocalizedString("TBPopoverView.about.label",
                                            comment: "About label"),
                          systemImage: "info.circle")
                    Spacer()
                    Text("⌘ A").foregroundColor(.gray)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("a")
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                Button {
                    NSApplication.shared.terminate(self)
                } label: {
                    Label(NSLocalizedString("TBPopoverView.quit.label",
                                            comment: "Quit label"),
                          systemImage: "power")
                    Spacer()
                    Text("⌘ Q").foregroundColor(.gray)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q")
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .liquidGlassPanel(cornerRadius: 12, interactive: true)
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
            .frame(height: 308)
            .padding(12)
    }
}

private struct PrimaryActionButton: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.buttonStyle(.glassProminent)
        } else if #available(macOS 12.0, *) {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(DefaultButtonStyle())
        }
    }
}

#if DEBUG
    func debugSize(proxy: GeometryProxy) -> some View {
        print("Optimal popover size:", proxy.size)
        return Color.clear
    }
#endif
