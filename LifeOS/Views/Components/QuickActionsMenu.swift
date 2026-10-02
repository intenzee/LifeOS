import SwiftUI

struct QuickActionsMenu: View {
    @Binding var isPresented: Bool
    let onAction: (QuickActionType) -> Void
    @Environment(\.colorScheme) private var colorScheme

    /// When true, the four meal bubbles are revealed (from a long-press on Add Meal).
    @State private var showMealBubbles = false
    @State private var appear = false

    private var palette: ThemePalette { ThemePalette(colorScheme: colorScheme) }

    /// Meal type inferred from the current time of day, used as the smart default
    /// when the user taps "Add Meal" without long-pressing.
    private var timeBasedMeal: QuickActionType {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<11: return .breakfast
        case 11..<16: return .lunch
        case 16..<22: return .dinner
        default: return .snacks
        }
    }

    private var timeBasedMealLabel: String {
        switch timeBasedMeal {
        case .breakfast: return "Breakfast"
        case .lunch: return "Lunch"
        case .dinner: return "Dinner"
        default: return "Snacks"
        }
    }

    private let mealBubbles: [(title: String, icon: String, action: QuickActionType, tint: Color)] = [
        ("Breakfast", "sunrise.fill", .breakfast, Color(red: 1.0, green: 0.78, blue: 0.35)),
        ("Lunch", "sun.max.fill", .lunch, Color(red: 1.0, green: 0.62, blue: 0.40)),
        ("Dinner", "moon.stars.fill", .dinner, Color(red: 0.55, green: 0.60, blue: 0.98)),
        ("Snacks", "takeoutbag.and.cup.and.straw.fill", .snacks, Color(red: 0.44, green: 0.93, blue: 0.78))
    ]

    private let secondaryActions: [(title: String, icon: String, action: QuickActionType)] = [
        ("Scan Meal", "camera.viewfinder", .aiMealScan),
        ("Barcode", "barcode.viewfinder", .barcodeScan),
        ("Water", "drop.fill", .water),
        ("Weight", "scalemass.fill", .weight),
        ("Exercise", "figure.run", .exercise),
        ("Rest Timer", "timer", .restTimer),
        ("Strength", "figure.strengthtraining.traditional", .strengthTools),
        ("Macros", "chart.pie.fill", .macros),
        ("Trends", "chart.xyaxis.line", .trends)
    ]

    var body: some View {
        ZStack {
            // Dimmed, blurred scrim.
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.35).ignoresSafeArea())
                .onTapGesture { dismiss() }

            VStack(spacing: 20) {
                header
                addMealHero
                secondaryGrid
            }
            .padding(22)
            .glassCard(cornerRadius: 30, elevation: 1.2)
            .padding(.horizontal, 18)
            .scaleEffect(appear ? 1 : 0.92)
            .opacity(appear ? 1 : 0)

            if showMealBubbles {
                mealBubbleOverlay
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { appear = true }
        }
    }

    private var header: some View {
        HStack {
            Text("Quick Actions")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundColor(palette.textPrimary)
            Spacer()
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(palette.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
    }

    // MARK: Add Meal hero (tap = smart default, long-press = choose)

    private var addMealHero: some View {
        Button {
            onAction(timeBasedMeal)
            dismiss()
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(colors: [ThemePalette.accent, ThemePalette.accentSecondary],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 54, height: 54)
                        .shadow(color: ThemePalette.accent.opacity(0.5), radius: 12, y: 6)
                    Image(systemName: "fork.knife")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.black.opacity(0.8))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Add Meal")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundColor(palette.textPrimary)
                    Text("Tap for \(timeBasedMealLabel) · hold to choose")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                }
                Spacer()
                Image(systemName: "hand.tap.fill")
                    .font(.footnote)
                    .foregroundColor(palette.textSecondary.opacity(0.6))
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .glassCard(cornerRadius: 22, tint: ThemePalette.accent, elevation: 0.6)
        }
        .pressableGlass()
        .onLongPressGesture(minimumDuration: 0.28) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                showMealBubbles = true
            }
        }
    }

    // MARK: Secondary actions grid

    private var secondaryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(secondaryActions, id: \.title) { item in
                Button {
                    onAction(item.action)
                    dismiss()
                } label: {
                    VStack(spacing: 9) {
                        Image(systemName: item.icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(ThemePalette.accent)
                        Text(item.title)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(palette.textPrimary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 78)
                    .glassCard(cornerRadius: 18, elevation: 0.4)
                }
                .pressableGlass()
            }
        }
    }

    // MARK: Meal bubble chooser

    private var mealBubbleOverlay: some View {
        ZStack {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showMealBubbles = false }
                }

            VStack(spacing: 18) {
                Text("Which meal?")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundColor(.white)

                HStack(spacing: 16) {
                    ForEach(Array(mealBubbles.enumerated()), id: \.element.title) { index, bubble in
                        bubbleButton(bubble, index: index)
                    }
                }
            }
            .padding(26)
            .glassCard(cornerRadius: 28, elevation: 1.4)
            .padding(.horizontal, 24)
        }
        .transition(.opacity)
    }

    private func bubbleButton(_ bubble: (title: String, icon: String, action: QuickActionType, tint: Color), index: Int) -> some View {
        Button {
            onAction(bubble.action)
            dismiss()
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(colors: [bubble.tint, bubble.tint.opacity(0.6)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 58, height: 58)
                        .shadow(color: bubble.tint.opacity(0.55), radius: 12, y: 6)
                    Image(systemName: bubble.icon)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.black.opacity(0.8))
                }
                Text(bubble.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
        }
        .pressableGlass()
        .scaleEffect(showMealBubbles ? 1 : 0.3)
        .opacity(showMealBubbles ? 1 : 0)
        .animation(.spring(response: 0.45, dampingFraction: 0.65).delay(Double(index) * 0.05), value: showMealBubbles)
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.2)) { appear = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { isPresented = false }
    }
}
