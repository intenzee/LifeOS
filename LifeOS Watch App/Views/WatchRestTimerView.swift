import SwiftUI
import WatchKit

/// Watch Rest timer (UI/UX Phase 5 §2): a full-screen ring countdown with a
/// haptic at 10 s and at 0 s. Runs on the watch only.
struct WatchRestTimerView: View {
    @State private var total = 90
    @State private var endsAt: Date?
    @State private var pausedRemaining: Int?
    @State private var warned = false

    private let presets = [30, 60, 90, 120, 180]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let remaining = remaining(at: context.date)
            ScrollView {
                VStack(spacing: 10) {
                    RingView(progress: total > 0 ? Double(remaining) / Double(total) : 0,
                             color: remaining <= 10 && endsAt != nil ? WatchTheme.over : WatchTheme.energy, lineWidth: 11) {
                        VStack(spacing: 0) {
                            Text(timeString(remaining)).font(WatchTheme.number(34))
                            Text(endsAt != nil ? "resting" : (pausedRemaining != nil ? "paused" : "ready"))
                                .font(.system(size: 11)).foregroundStyle(WatchTheme.secondary)
                        }
                    }
                    .frame(width: 140, height: 140)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Rest timer, \(remaining / 60) minutes \(remaining % 60) seconds left")

                    HStack(spacing: 8) {
                        Button { endsAt != nil ? pause(remaining) : start(from: pausedRemaining ?? total) } label: {
                            Image(systemName: endsAt != nil ? "pause.fill" : "play.fill").frame(maxWidth: .infinity, minHeight: 36)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(WatchTheme.energy)
                        .accessibilityLabel(endsAt != nil ? "Pause" : "Start")

                        Button { reset() } label: {
                            Image(systemName: "arrow.counterclockwise").frame(maxWidth: .infinity, minHeight: 36)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Reset")
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(presets, id: \.self) { p in
                                Button {
                                    total = p
                                    if endsAt != nil { start(from: p) } else { pausedRemaining = nil }
                                } label: {
                                    Text(p < 60 ? "\(p)s" : (p % 60 == 0 ? "\(p / 60)m" : "\(p / 60)m\(p % 60)"))
                                        .font(.system(size: 13, weight: total == p ? .bold : .regular))
                                        .frame(minWidth: 40, minHeight: 32)
                                }
                                .buttonStyle(.bordered)
                                .tint(total == p ? WatchTheme.accent : .gray)
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .onChange(of: remaining) { _, r in tick(r) }
        }
        .navigationTitle("Rest")
    }

    private func remaining(at now: Date) -> Int {
        if let endsAt { return max(0, Int(endsAt.timeIntervalSince(now).rounded(.up))) }
        return pausedRemaining ?? total
    }

    private func tick(_ r: Int) {
        guard endsAt != nil else { return }
        if r == 10, !warned, total > 10 {
            warned = true
            WKInterfaceDevice.current().play(.directionUp)
        }
        if r == 0 {
            endsAt = nil
            pausedRemaining = nil
            WKInterfaceDevice.current().play(.notification)
        }
    }

    private func timeString(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }

    private func start(from seconds: Int) {
        endsAt = Date().addingTimeInterval(TimeInterval(seconds))
        pausedRemaining = nil
        warned = seconds <= 10
    }

    private func pause(_ r: Int) {
        endsAt = nil
        pausedRemaining = r
    }

    private func reset() {
        endsAt = nil
        pausedRemaining = nil
        warned = false
    }
}
