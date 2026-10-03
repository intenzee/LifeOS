import SwiftUI

/// Start/stop for the Health strength workout, with live heart rate and energy
/// (WCH-12). Shown at the top of the Workout tab.
struct WorkoutSessionControls: View {
    @ObservedObject var workout: StrengthWorkoutSession = .shared

    var body: some View {
        switch workout.state {
        case .idle, .failed:
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    Task { await workout.start() }
                } label: {
                    Label("Start Strength Workout", systemImage: "figure.strengthtraining.traditional")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchTheme.accent)
                .foregroundStyle(.black)
                if case .failed(let message) = workout.state {
                    Text(message).font(.system(size: 10)).foregroundStyle(WatchTheme.over)
                } else {
                    Text("Keeps counting with your wrist down and saves to Apple Health.")
                        .font(.system(size: 10)).foregroundStyle(WatchTheme.secondary)
                }
            }
        case .starting, .ending:
            ProgressView()
        case .running:
            VStack(alignment: .leading, spacing: 6) {
                if let start = workout.startDate {
                    Text(timerInterval: start...Date.distantFuture, countsDown: false)
                        .font(WatchTheme.number(24))
                        .foregroundStyle(WatchTheme.accent)
                }
                HStack(spacing: 12) {
                    Label(workout.heartRate.map { "\(Int($0))" } ?? "--", systemImage: "heart.fill")
                        .foregroundStyle(.red)
                    Label("\(Int(workout.activeKcal))", systemImage: "flame.fill")
                        .foregroundStyle(WatchTheme.burn)
                    Text("\(workout.setsRecorded) sets").foregroundStyle(WatchTheme.secondary)
                }
                .font(WatchTheme.number(12, weight: .medium))
                Button(role: .destructive) {
                    Task { await workout.end() }
                } label: {
                    Label("End Workout", systemImage: "stop.fill")
                }
            }
        }
    }
}
