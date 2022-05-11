import Defaults
import KeyboardShortcuts
import LaunchAtLogin
import SwiftUI

extension KeyboardShortcuts.Name {
    static let startStopTimer = Self("startStopTimer")
}

private struct IntervalsView: View {
    @EnvironmentObject var viewModel: TBViewModel
    @Default(.currentPresetId) var currentPresetId

    var body: some View {
        VStack {}
        /*
         VStack {
             Picker("Preset", selection: currentPresetId) {
                 ForEach(viewModel.presets, id: \.id) {
                     Text($0.name)
                 }
             }.onChange(of: currentPresetId) { id in
                 timer.preset = presetStore.getById(id: id)!
             }
             Stepper(value: $timer.preset.work, in: 1 ... 60) {
                 Text("Work interval:")
                     .frame(maxWidth: .infinity, alignment: .leading)
                 // TextField("Value", value: $timer.preset.work, formatter: NumberFormatter())
                 //    .frame(minWidth: 15, maxWidth: 40)
                 Text("\(timer.preset.work) min")
             }
             Stepper(value: $timer.preset.shortRest, in: 1 ... 60) {
                 Text("Short rest interval:")
                     .frame(maxWidth: .infinity, alignment: .leading)
                 Text("\(timer.preset.shortRest) min")
             }
             Stepper(value: $timer.preset.longRest, in: 1 ... 60) {
                 Text("Long rest interval:")
                     .frame(maxWidth: .infinity, alignment: .leading)
                 Text("\(timer.preset.longRest) min")
             }
             .help("Duration of the lengthy break, taken after finishing work interval set")
             Stepper(value: $timer.preset.setSize, in: 1 ... 10) {
                 Text("Work intervals in a set:")
                     .frame(maxWidth: .infinity, alignment: .leading)
                 Text("\(timer.preset.setSize)")
             }
             .help("Number of working intervals in the set, after which a lengthy break taken")
             Spacer().frame(minHeight: 0)
         }
         .padding(4)
          */
    }
}

private struct SettingsView: View {
    @EnvironmentObject var viewModel: TBViewModel
    @ObservedObject private var launchAtLogin = LaunchAtLogin.observable
    @Default(.stopAfterBreak) var stopAfterBreak
    @Default(.showTimerInMenuBar) var showTimerInMenuBar

    var body: some View {
        VStack {
            KeyboardShortcuts.Recorder(for: .startStopTimer) {
                Text("Shortcut")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Toggle(isOn: $stopAfterBreak) {
                Text("Stop after break")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.toggleStyle(.switch)
            Toggle(isOn: $showTimerInMenuBar) {
                Text("Show timer in menu bar")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.toggleStyle(.switch)
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
    @EnvironmentObject var viewModel: TBViewModel
    @Default(.isWindupEnabled) var isWindupEnabled
    @Default(.isDingEnabled) var isDingEnabled
    @Default(.isTickingEnabled) var isTickingEnabled

    var body: some View {
        VStack {
            Toggle(isOn: $isWindupEnabled) {
                Text("Windup")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            Toggle(isOn: $isDingEnabled) {
                Text("Ding")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            Toggle(isOn: $isTickingEnabled) {
                Text("Ticking")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            Spacer().frame(minHeight: 0)
        }
        .padding(4)
    }
}

private enum ChildView {
    case intervals, settings, sounds
}

struct TBPopoverView: View {
    @ObservedObject var viewModel = TBViewModel()
    @State private var buttonHovered = false
    @State private var activeChildView = ChildView.intervals

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                viewModel.startStop()
                TBStatusItem.shared.closePopover(nil)
            } label: {
                Text(viewModel.timerActive ? (buttonHovered ? "Stop" : viewModel.timeLeftString) : "Start")
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
                    IntervalsView().environmentObject(viewModel)
                case .settings:
                    SettingsView().environmentObject(viewModel)
                case .sounds:
                    SoundsView().environmentObject(viewModel)
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
            .frame(width: 240, height: 264)
            .padding(12)
    }
}

#if DEBUG
    func debugSize(proxy: GeometryProxy) -> some View {
        print("Optimal popover size:", proxy.size)
        return Color.clear
    }
#endif
