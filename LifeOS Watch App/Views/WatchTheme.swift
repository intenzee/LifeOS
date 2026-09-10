import SwiftUI

/// Small shared style helpers for the watch app, echoing the phone's accent.
enum WatchTheme {
    static let accent = Color(red: 0.36, green: 0.92, blue: 0.55)   // mint green
    static let water = Color(red: 0.30, green: 0.68, blue: 1.0)
    static let burn = Color(red: 1.0, green: 0.55, blue: 0.25)
    static let card = Color.white.opacity(0.08)
}

/// A thin circular progress ring with a centered label.
struct RingView<Label: View>: View {
    var progress: Double
    var color: Color
    var lineWidth: CGFloat = 8
    @ViewBuilder var label: () -> Label

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(progress, 1)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: progress)
            label()
        }
    }
}
