import SwiftUI
import WatchKit

/// A local rest timer for between sets. Runs entirely on the watch; buzzes when
/// the rest period ends.
struct WatchRestTimerView: View {
    @State private var total = 90
    @State private var remaining = 90
    @State private var running = false
    @State private var timer: Timer?

    private let presets = [30, 60, 90, 120, 180]

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ZStack {
                    RingView(progress: total > 0 ? Double(remaining) / Double(total) : 0,
                             color: WatchTheme.burn, lineWidth: 8) {
                        VStack(spacing: 0) {
                            Text(timeString(remaining))
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            Text(running ? "resting" : "ready")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: 104, height: 104)

                HStack(spacing: 6) {
                    ForEach(presets, id: \.self) { p in
                        Button {
                            total = p; remaining = p
                            if running { restart() }
                        } label: {
                            Text("\(p)")
                                .font(.system(size: 12, weight: total == p ? .bold : .regular))
                        }
                        .buttonStyle(.bordered)
                        .tint(total == p ? WatchTheme.accent : .gray)
                    }
                }

                HStack(spacing: 8) {
                    Button { running ? pause() : start() } label: {
                        Image(systemName: running ? "pause.fill" : "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(running ? .orange : WatchTheme.accent)

                    Button { reset() } label: {
                        Image(systemName: "arrow.counterclockwise").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
        }
        .navigationTitle("Rest")
        .onDisappear { timer?.invalidate() }
    }

    private func timeString(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }

    private func start() {
        running = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            guard remaining > 0 else { finish(); return }
            remaining -= 1
            if remaining == 0 { finish() }
        }
    }
    private func restart() { pause(); start() }
    private func pause() { running = false; timer?.invalidate() }
    private func reset() { pause(); remaining = total }
    private func finish() {
        pause()
        remaining = 0
        WKInterfaceDevice.current().play(.notification)
    }
}
