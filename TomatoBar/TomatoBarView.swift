import SwiftUI

public struct TomatoBarView: View {
    @ObservedObject var timer = TomatoBarTimer()
    @State private var buttonHovered = false

    private var showButtonTimer: Bool {
        timer.isActive() && !buttonHovered
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                timer.startStopAction()
                AppDelegate.shared.closePopover(nil)
            } label: {
                Text(showButtonTimer ? timer.timeLeftString : timer.startStopString)
                    .font(.system(.body).monospacedDigit())
                    .frame(maxWidth: .infinity)
            }
            .onHover { over in
                buttonHovered = over
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            Divider()
            Group {
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
                Stepper(value: $timer.workIntervalsInSet, in: 1 ... 10) {
                    Text("Work intervals in set:")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(timer.workIntervalsInSet)")
                }
            }
            Divider()
            Group {
                Text("Sounds:")
                HStack {
                    Toggle("Windup", isOn: $timer.isWindupEnabled)
                    Spacer()
                    Toggle("Ding", isOn: $timer.isDingEnabled)
                    Spacer()
                    Toggle("Ticking", isOn: $timer.isTickingEnabled)
                        .onChange(of: timer.isTickingEnabled) { _ in
                            timer.toggleTickingAction()
                        }
                }
            }
            Divider()
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
            .frame(width: 226, height: 323)
            .padding(12)
    }
}

#if DEBUG
    func debugSize(proxy: GeometryProxy) -> some View {
        print("Optimal popover size:", proxy.size)
        return Color.clear
    }
#endif
