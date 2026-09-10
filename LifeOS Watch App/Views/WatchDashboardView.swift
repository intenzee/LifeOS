import SwiftUI

struct WatchDashboardView: View {
    @ObservedObject var session: WatchSessionManager

    private var snapshot: WatchSnapshot { session.snapshot }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if !session.hasReceivedData {
                    connectingState
                } else {
                    calorieRing
                    statsRow
                    streakChip
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
        .navigationTitle("Today")
    }

    private var connectingState: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Syncing with iPhone…")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 24)
    }

    private var calorieRing: some View {
        RingView(progress: snapshot.calorieProgress, color: WatchTheme.accent, lineWidth: 10) {
            VStack(spacing: 0) {
                Text("\(Int(snapshot.caloriesConsumed))")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("/ \(Int(snapshot.calorieLimit)) kcal")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 120, height: 120)
        .padding(.top, 4)
    }

    private var statsRow: some View {
        HStack(spacing: 8) {
            statTile(value: "\(snapshot.waterCount)/\(snapshot.waterTarget)",
                     label: "Water", systemImage: "drop.fill", color: WatchTheme.water)
            statTile(value: "\(Int(snapshot.caloriesBurned))",
                     label: "Burned", systemImage: "flame.fill", color: WatchTheme.burn)
        }
    }

    private func statTile(value: String, label: String, systemImage: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage).foregroundStyle(color)
            Text(value).font(.system(size: 15, weight: .semibold, design: .rounded))
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(WatchTheme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private var streakChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill").foregroundStyle(WatchTheme.accent)
            Text("\(snapshot.perfectStreak)-day streak")
                .font(.system(size: 13, weight: .medium))
            Spacer()
            Text("\(snapshot.todosCompleted)/\(snapshot.todos.count) todos")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(WatchTheme.card, in: RoundedRectangle(cornerRadius: 12))
    }
}
