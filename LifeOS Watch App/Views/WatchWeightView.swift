import SwiftUI
import WatchKit

/// Watch Weight (UI/UX Phase 5 §2): the Digital Crown picks in 0.1 kg steps,
/// with a trend arrow against the last weigh-in. Syncs to the iPhone.
struct WatchWeightView: View {
    @ObservedObject var session: WatchSessionManager

    @State private var weight: Double = 0
    @State private var didInit = false
    @State private var justSaved = false

    private var last: Double { session.snapshot.currentWeight }
    private var target: Double { session.snapshot.targetWeight }
    private var delta: Double { last > 0 ? weight - last : 0 }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                VStack(spacing: 0) {
                    Text(String(format: "%.1f", weight)).font(WatchTheme.number(40))
                    Text("kg").font(.system(size: 12)).foregroundStyle(WatchTheme.secondary)
                    if abs(delta) >= 0.05 {
                        Label(String(format: "%.1f since last", abs(delta)), systemImage: delta > 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(WatchTheme.weight)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 96)
                .background(WatchTheme.card, in: RoundedRectangle(cornerRadius: 16))
                .focusable(true)
                .digitalCrownRotation($weight, from: 30, through: 250, by: 0.1, sensitivity: .medium, isContinuous: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(format: "Weight %.1f kilograms", weight))
                .accessibilityAdjustableAction { d in
                    weight = d == .increment ? min(250, weight + 0.1) : max(30, weight - 0.1)
                }

                if target > 0 {
                    Text("Target \(String(format: "%.1f", target)) kg").font(.system(size: 11)).foregroundStyle(WatchTheme.secondary)
                }

                Button {
                    session.setWeight((weight * 10).rounded() / 10)
                    justSaved = true
                    WKInterfaceDevice.current().play(.success)
                } label: {
                    Label(justSaved ? "Saved" : "Save", systemImage: justSaved ? "checkmark" : "square.and.arrow.down")
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchTheme.accent)
                .disabled(justSaved)

                Text("Turn the Crown to adjust").font(.system(size: 10)).foregroundStyle(WatchTheme.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
        }
        .navigationTitle("Weight")
        .onAppear {
            guard !didInit else { return }
            weight = last > 0 ? last : 70
            didInit = true
        }
        .onChange(of: weight) { _, _ in justSaved = false }
    }
}
