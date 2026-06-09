import AppKit
import SwiftUI

struct TBRestOverlayView: View {
    @ObservedObject var viewModel: TBRestOverlayViewModel
    let skipHandler: () -> Void
    let backgroundImage: NSImage?

    var body: some View {
        ZStack {
            // Background layer: image or gradient fallback
            if let image = backgroundImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            } else {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.1, green: 0.15, blue: 0.25),
                        Color(red: 0.05, green: 0.08, blue: 0.15),
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            // Semi-transparent dark overlay for text readability
            Color.black.opacity(0.5)

            // Centered content
            VStack(spacing: 16) {
                Text(viewModel.restType == .shortRest
                    ? NSLocalizedString("TBRestOverlayView.shortRest.label", comment: "Short rest label")
                    : NSLocalizedString("TBRestOverlayView.longRest.label", comment: "Long rest label"))
                    .font(.system(size: 48, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)

                Text(viewModel.countdown)
                    .font(.system(size: 96, weight: .thin, design: .monospaced))
                    .foregroundColor(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onTapGesture(count: 2) {
            skipHandler()
        }
    }
}
