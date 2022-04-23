import KeyboardShortcuts
import LaunchAtLogin
import SwiftUI

extension KeyboardShortcuts.Name {
    static let startStopTimer = Self("startStopTimer")
}

private struct IntervalsView: View {
    @EnvironmentObject var timer: TBTimer

    var body: some View {
        VStack {
            Stepper(value: $timer.workIntervalLength, in: 1 ... 60) {
                Text("Work interval:")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(timer.workIntervalLength) min")
            }
            Stepper(value: $timer.shortRestIntervalLength, in: 1 ... 60) {
                Text("Short rest interval:")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(timer.shortRestIntervalLength) min")
            }
            Stepper(value: $timer.longRestIntervalLength, in: 1 ... 60) {
                Text("Long rest interval:")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(timer.longRestIntervalLength) min")
            }
            .help("Duration of the lengthy break, taken after finishing work interval set")
            Stepper(value: $timer.workIntervalsInSet, in: 1 ... 10) {
                Text("Work intervals in a set:")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(timer.workIntervalsInSet)")
            }
            .help("Number of working intervals in the set, after which a lengthy break taken")
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
                Text("Shortcut")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Toggle(isOn: $timer.stopAfterBreak) {
                Text("Stop after break")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.toggleStyle(.switch)
            Toggle(isOn: $timer.showTimerInMenuBar) {
                Text("Show timer in menu bar")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.toggleStyle(.switch)
                .onChange(of: timer.showTimerInMenuBar) { _ in
                    timer.renderTimeLeft()
                }
            Toggle(isOn: $launchAtLogin.isEnabled) {
                Text("Launch at login")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.toggleStyle(.switch)
            Spacer().frame(minHeight: 0)
        }
        .padding(4)
    }
}

private struct SoundsView: View {
    @EnvironmentObject var timer: TBTimer

    var body: some View {
        VStack {
            Toggle(isOn: $timer.isWindupEnabled) {
                Text("Windup")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            Toggle(isOn: $timer.isDingEnabled) {
                Text("Ding")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            Toggle(isOn: $timer.isTickingEnabled) {
                Text("Ticking")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .onChange(of: timer.isTickingEnabled) { _ in
                timer.toggleTickingAction()
            }
            Spacer().frame(minHeight: 0)
        }
        .padding(4)
    }
}

private enum ChildView {
    case intervals, settings, sounds
}

struct TBPopoverView: View {
    @ObservedObject var timer = TBTimer()
    @State private var buttonHovered = false
    @State private var activeChildView = ChildView.intervals

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                timer.startStopAction()
                TBStatusItem.shared.closePopover(nil)
            } label: {
                Text(timer.timer != nil ? (buttonHovered ? "Stop" : timer.timeLeftString) : "Start")
                    .font(.system(.body).monospacedDigit())
                    .frame(maxWidth: .infinity)
            }
            .onHover { over in
                buttonHovered = over
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            Picker("", selection: $activeChildView) {
                Text("Intervals").tag(ChildView.intervals)
                Text("Settings").tag(ChildView.settings)
                Text("Sounds").tag(ChildView.sounds)
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
                    SoundsView().environmentObject(timer)
                }
            }

            Group {
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.orderFrontStandardAboutPanel()
                } label: {
                    Text("About")
                    Spacer()
                    Text("⌘ A").foregroundColor(Color.gray)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("a")
                Button {
                    NSApplication.shared.terminate(self)
                } label: {
                    Text("Quit")
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
            .frame(width: 240, height: 247)
            .padding(12)
    }
}

#if DEBUG
    func debugSize(proxy: GeometryProxy) -> some View {
        print("Optimal popover size:", proxy.size)
        return Color.clear
    }
#endif
