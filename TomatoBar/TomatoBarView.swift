import SwiftUI

public struct TomatoBarView: View {
    @ObservedObject var timer = TomatoBarTimer()

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                timer.startStopAction()
                AppDelegate.shared.closePopover(nil)
            } label: {
                Text(timer.startStopString)
                    .frame(maxWidth: .infinity)
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
