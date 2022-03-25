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
            .keyboardShortcut(.defaultAction)
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
            Text("Sounds:")
            HStack {
                Toggle("Windup", isOn: $timer.isWindupEnabled)
                Spacer()
                Toggle("Ringing", isOn: $timer.isRingingEnabled)
                Spacer()
                Toggle("Ticking", isOn: $timer.isTickingEnabled)
                    .onChange(of: timer.isTickingEnabled) { _ in
                        timer.toggleTickingAction()
                    }
            }
        }.padding(12)
    }
}

#if DEBUG
    public struct TomatoBarView_Previews: PreviewProvider {
        public static var previews: some View {
            TomatoBarView()
        }
    }
#endif
