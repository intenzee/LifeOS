import SwiftUI

/// Review and manage what the meal scanner has learned from the user's
/// corrections. Every entry is a lesson fed back into future scans; deleting one
/// makes the scanner forget it.
struct LearnedCorrectionsView: View {
    @Binding var isPresented: Bool

    @State private var corrections: [MealCorrection] = []
    @State private var showResetConfirm = false

    private let engine = MealLearningEngine.shared

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.4).ignoresSafeArea())

            VStack(spacing: 0) {
                header

                if corrections.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            infoBanner
                            ForEach(corrections) { correction in
                                row(correction)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 8)
                        .padding(.bottom, 30)
                    }
                }
            }
        }
        .onAppear(perform: reload)
        .confirmationDialog("Forget all learned corrections?",
                            isPresented: $showResetConfirm,
                            titleVisibility: .visible) {
            Button("Forget everything", role: .destructive) {
                engine.reset()
                reload()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The scanner will start fresh and lose every correction you've taught it.")
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [ThemePalette.accent, ThemePalette.accentSecondary],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 42, height: 42)
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.black.opacity(0.8))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Learned Corrections")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundColor(.white)
                Text(corrections.isEmpty ? "Nothing learned yet"
                                         : "\(corrections.count) lesson\(corrections.count == 1 ? "" : "s") taught")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Spacer()

            if !corrections.isEmpty {
                Button { showResetConfirm = true } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.red.opacity(0.9))
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }

            Button { isPresented = false } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.gray)
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private var infoBanner: some View {
        Text("Each time you fix a scan, it's saved here and used to teach future scans of similar meals.")
            .font(.caption2)
            .foregroundColor(.gray)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .background(ThemePalette.accent.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "brain.head.profile")
                .font(.system(size: 52))
                .foregroundColor(.gray.opacity(0.7))
            Text("No corrections learned yet")
                .font(.headline)
                .foregroundColor(.white)
            Text("When a scan is off, tap \"Tell the AI what's off\" or fix the numbers — your correction shows up here and improves future scans.")
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private func row(_ c: MealCorrection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(c.correctedName)
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.white)
                    if c.originalName.caseInsensitiveCompare(c.correctedName) != .orderedSame {
                        Text("was \u{201C}\(c.originalName)\u{201D}")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
                Spacer()
                if c.reinforcement > 1 {
                    Text("×\(c.reinforcement)")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(ThemePalette.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(ThemePalette.accent.opacity(0.15), in: Capsule())
                }
                Button { delete(c) } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.red.opacity(0.85))
                        .frame(width: 30, height: 30)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }

            Text("\(Int(c.calories)) kcal · P\(Int(c.protein)) / C\(Int(c.carbs)) / F\(Int(c.fat)) · \(c.servingSize)")
                .font(.caption2)
                .foregroundColor(.gray)

            if let note = c.note, !note.isEmpty {
                Label(note, systemImage: "text.bubble")
                    .font(.caption2)
                    .foregroundColor(ThemePalette.accent.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.15, green: 0.15, blue: 0.17),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Actions

    private func reload() {
        corrections = engine.allCorrections
    }

    private func delete(_ c: MealCorrection) {
        engine.delete(id: c.id)
        withAnimation { corrections.removeAll { $0.id == c.id } }
    }
}
