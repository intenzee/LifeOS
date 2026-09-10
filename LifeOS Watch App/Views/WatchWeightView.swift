import SwiftUI
import WatchKit

/// Log body weight from the wrist. Turn the Digital Crown to adjust, tap Save —
/// it syncs to the phone (and Apple Health via the phone).
struct WatchWeightView: View {
    @ObservedObject var session: WatchSessionManager

    @State private var weight: Double = 0
    @State private var didInit = false
    @State private var justSaved = false

    private var target: Double { session.snapshot.targetWeight }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Weight").font(.headline)

                ZStack {
                    Circle().stroke(WatchTheme.card, lineWidth: 8)
                    VStack(spacing: 0) {
                        Text(String(format: "%.1f", weight))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("kg").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 110, height: 110)
                .focusable(true)
                .digitalCrownRotation($weight, from: 30, through: 250, by: 0.1,
                                      sensitivity: .medium, isContinuous: false)

                if target > 0 {
                    Text("Target \(String(format: "%.1f", target)) kg")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Button { weight = max(30, weight - 0.1) } label: {
                        Image(systemName: "minus")
                    }
                    Button { weight = min(250, weight + 0.1) } label: {
                        Image(systemName: "plus")
                    }
                }
                .buttonStyle(.bordered)

                Button {
                    session.setWeight(weight)
                    justSaved = true
                    WKInterfaceDevice.current().play(.success)
                } label: {
                    Label(justSaved ? "Saved" : "Save", systemImage: justSaved ? "checkmark" : "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchTheme.accent)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
        }
        .navigationTitle("Weight")
        .onAppear {
            guard !didInit else { return }
            let snap = session.snapshot.currentWeight
            weight = snap > 0 ? snap : 70
            didInit = true
        }
        .onChange(of: weight) { _, _ in justSaved = false }
    }
}
