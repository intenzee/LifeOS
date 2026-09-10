import SwiftUI

struct WatchWaterView: View {
    @ObservedObject var session: WatchSessionManager

    private var snapshot: WatchSnapshot { session.snapshot }

    var body: some View {
        VStack(spacing: 10) {
            RingView(progress: snapshot.waterProgress, color: WatchTheme.water, lineWidth: 10) {
                VStack(spacing: 0) {
                    Text("\(snapshot.waterCount)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("of \(snapshot.waterTarget)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 96, height: 96)

            HStack(spacing: 12) {
                stepButton(system: "minus", disabled: snapshot.waterCount <= 0) {
                    session.setWater(snapshot.waterCount - 1)
                }
                stepButton(system: "plus", disabled: false) {
                    session.setWater(snapshot.waterCount + 1)
                }
            }
        }
        .padding(.vertical, 6)
        .navigationTitle("Water")
    }

    private func stepButton(system: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 20, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .tint(WatchTheme.water)
        .disabled(disabled)
    }
}
