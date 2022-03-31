import SwiftUI

public struct TomatoBarView: View {
    @ObservedObject var timer = TomatoBarTimer()
    @State private var buttonHovered = false

    private var showButtonTimer: Bool {
        [.work, .rest].contains(timer.stateMachine.state) && !buttonHovered
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
            Toggle(isOn: $timer.stopAfterBreak) {
                Text("Stop after break").frame(maxWidth: .infinity, alignment: .leading)
            }.toggleStyle(.switch)
            Stepper(value: $timer.workIntervalLength, in: 1 ... 60) {
                Text("Work interval:").frame(maxWidth: .infinity, alignment: .leading)
                Text("\(timer.workIntervalLength) min")
            }
            Stepper(value: $timer.restIntervalLength, in: 1 ... 60) {
                Text("Rest interval:").frame(maxWidth: .infinity, alignment: .leading)
                Text("\(timer.restIntervalLength) min")
            }
            Divider()
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
        .padding(12)
    }
}
