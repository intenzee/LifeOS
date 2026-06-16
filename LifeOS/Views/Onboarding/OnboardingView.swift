import SwiftUI
import UIKit

// MARK: - Onboarding Steps

private enum OnboardingStep: Int, CaseIterable {
    case units
    case sex
    case age
    case height
    case weight
    case targetWeight
    case goal
    case exercise
    case diet
    case smoking
    case water
    case sleep

    var title: String {
        switch self {
        case .units: return "Choose your units"
        case .sex: return "What's your sex?"
        case .age: return "How old are you?"
        case .height: return "Your height"
        case .weight: return "Your current weight"
        case .targetWeight: return "Your target weight"
        case .goal: return "What's your goal?"
        case .exercise: return "How often do you train?"
        case .diet: return "How's your diet?"
        case .smoking: return "Do you smoke?"
        case .water: return "Daily water goal"
        case .sleep: return "Your sleep schedule"
        }
    }

    var subtitle: String {
        switch self {
        case .units: return "We'll use this everywhere in the app."
        case .sex: return "Used to fine-tune your calorie needs."
        case .age: return "This helps us estimate your metabolism."
        case .height: return "Slide to set your height."
        case .weight: return "Where you are right now."
        case .targetWeight: return "Where you'd like to be."
        case .goal: return "We'll tailor your targets to this."
        case .exercise: return "Sessions per week."
        case .diet: return "So we can suggest the right foods."
        case .smoking: return "Helps us track healthier habits."
        case .water: return "Glasses of water per day."
        case .sleep: return "When you usually wake and rest."
        }
    }

    var icon: String {
        switch self {
        case .units: return "ruler.fill"
        case .sex: return "person.fill"
        case .age: return "calendar"
        case .height: return "ruler"
        case .weight: return "scalemass.fill"
        case .targetWeight: return "target"
        case .goal: return "flag.checkered"
        case .exercise: return "figure.run"
        case .diet: return "fork.knife"
        case .smoking: return "lungs.fill"
        case .water: return "drop.fill"
        case .sleep: return "bed.double.fill"
        }
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @Environment(\.colorScheme) private var colorScheme

    /// Called once the questionnaire is complete with the assembled profile.
    let onComplete: (UserProfile) -> Void

    @State private var stepIndex: Int = 0
    @State private var draft = UserProfile()
    @Namespace private var animation

    private var palette: ThemePalette { ThemePalette(colorScheme: colorScheme) }
    private var steps: [OnboardingStep] { OnboardingStep.allCases }
    private var step: OnboardingStep { steps[stepIndex] }
    private var progress: CGFloat { CGFloat(stepIndex + 1) / CGFloat(steps.count) }
    private var isLastStep: Bool { stepIndex == steps.count - 1 }

    var body: some View {
        ZStack {
            palette.screenBackground.ignoresSafeArea()

            VStack(spacing: DesignSystem.Spacing.large) {
                header

                ScrollView(showsIndicators: false) {
                    VStack(spacing: DesignSystem.Spacing.large) {
                        iconBadge
                        titleBlock
                        questionContent
                    }
                    .padding(.top, DesignSystem.Spacing.medium)
                    .padding(.horizontal, DesignSystem.Spacing.large)
                }

                footer
            }
            .padding(.top, DesignSystem.Spacing.large)
        }
    }

    // MARK: Header (progress + back)

    private var header: some View {
        VStack(spacing: DesignSystem.Spacing.small) {
            HStack {
                Button(action: goBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(palette.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(palette.surface))
                }
                .opacity(stepIndex == 0 ? 0 : 1)
                .disabled(stepIndex == 0)

                Spacer()

                Text("\(stepIndex + 1) of \(steps.count)")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(palette.textSecondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.surface)
                    Capsule()
                        .fill(palette.primaryAccent)
                        .frame(width: max(8, geo.size.width * progress))
                        .shadow(color: palette.primaryAccent.opacity(0.5), radius: 6)
                }
            }
            .frame(height: 8)
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: progress)
        }
        .padding(.horizontal, DesignSystem.Spacing.large)
    }

    // MARK: Animated icon badge

    private var iconBadge: some View {
        ZStack {
            Circle()
                .fill(palette.primaryAccent.opacity(0.15))
                .frame(width: 110, height: 110)
            Image(systemName: step.icon)
                .font(.system(size: 44, weight: .semibold))
                .foregroundColor(palette.primaryAccent)
                .id("icon-\(step.rawValue)")
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.5).combined(with: .opacity),
                    removal: .scale(scale: 0.8).combined(with: .opacity)
                ))
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: stepIndex)
    }

    private var titleBlock: some View {
        VStack(spacing: DesignSystem.Spacing.xSmall) {
            Text(step.title)
                .font(DesignSystem.Typography.h1)
                .foregroundColor(palette.textPrimary)
                .multilineTextAlignment(.center)
            Text(step.subtitle)
                .font(DesignSystem.Typography.callout)
                .foregroundColor(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .id("title-\(step.rawValue)")
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: stepIndex)
    }

    // MARK: Per-step content

    @ViewBuilder
    private var questionContent: some View {
        Group {
            switch step {
            case .units:
                chipGrid(MeasurementUnits.allCases, selected: draft.units) { draft.units = $0 }
            case .sex:
                chipGrid(BiologicalSex.allCases, selected: draft.sex, icon: { $0.icon }) { draft.sex = $0 }
            case .age:
                stepperCard(value: $draft.age, range: 13...100, suffix: "years")
            case .height:
                heightPicker
            case .weight:
                weightPicker(value: $draft.currentWeightKg)
            case .targetWeight:
                weightPicker(value: $draft.targetWeightKg)
            case .goal:
                chipGrid(FitnessGoal.allCases, selected: draft.goal, icon: { $0.icon }) { draft.goal = $0 }
            case .exercise:
                stepperCard(value: $draft.exerciseDaysPerWeek, range: 0...7, suffix: "days / week")
            case .diet:
                chipGrid(DietType.allCases, selected: draft.diet, icon: { $0.icon }) { draft.diet = $0 }
            case .smoking:
                booleanChips
            case .water:
                stepperCard(value: $draft.waterGoalGlasses, range: 1...20, suffix: "glasses")
            case .sleep:
                sleepPickers
            }
        }
        .id("content-\(step.rawValue)")
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: stepIndex)
    }

    // MARK: Reusable controls

    private func chipGrid<T: Identifiable & Equatable & RawRepresentable>(
        _ options: [T],
        selected: T,
        icon: ((T) -> String)? = nil,
        onSelect: @escaping (T) -> Void
    ) -> some View where T.RawValue == String {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DesignSystem.Spacing.small) {
            ForEach(options) { option in
                let isSelected = option == selected
                Button {
                    selectionHaptic()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { onSelect(option) }
                } label: {
                    VStack(spacing: DesignSystem.Spacing.xSmall) {
                        if let icon {
                            Image(systemName: icon(option))
                                .font(.system(size: 26, weight: .semibold))
                        }
                        Text(option.rawValue)
                            .font(DesignSystem.Typography.callout.weight(.semibold))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 96)
                    .padding(DesignSystem.Spacing.small)
                    .foregroundColor(isSelected ? .black : palette.textPrimary)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(isSelected ? palette.primaryAccent : palette.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(palette.primaryAccent.opacity(isSelected ? 0 : 0.0), lineWidth: 2)
                    )
                    .shadow(color: isSelected ? palette.primaryAccent.opacity(0.4) : .clear, radius: 10)
                    .scaleEffect(isSelected ? 1.03 : 1.0)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var booleanChips: some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            ForEach([false, true], id: \.self) { value in
                let isSelected = draft.smokes == value
                Button {
                    selectionHaptic()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { draft.smokes = value }
                } label: {
                    VStack(spacing: DesignSystem.Spacing.xSmall) {
                        Image(systemName: value ? "lungs.fill" : "checkmark.seal.fill")
                            .font(.system(size: 28, weight: .semibold))
                        Text(value ? "Yes" : "No")
                            .font(DesignSystem.Typography.h3)
                    }
                    .frame(maxWidth: .infinity, minHeight: 110)
                    .foregroundColor(isSelected ? .black : palette.textPrimary)
                    .background(RoundedRectangle(cornerRadius: 20).fill(isSelected ? palette.primaryAccent : palette.surface))
                    .shadow(color: isSelected ? palette.primaryAccent.opacity(0.4) : .clear, radius: 10)
                    .scaleEffect(isSelected ? 1.03 : 1.0)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func stepperCard(value: Binding<Int>, range: ClosedRange<Int>, suffix: String) -> some View {
        VStack(spacing: DesignSystem.Spacing.medium) {
            Text("\(value.wrappedValue)")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundColor(palette.primaryAccent)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: value.wrappedValue)
            Text(suffix)
                .font(DesignSystem.Typography.callout)
                .foregroundColor(palette.textSecondary)

            HStack(spacing: DesignSystem.Spacing.xLarge) {
                roundStepButton(symbol: "minus") {
                    if value.wrappedValue > range.lowerBound { value.wrappedValue -= 1; selectionHaptic() }
                }
                roundStepButton(symbol: "plus") {
                    if value.wrappedValue < range.upperBound { value.wrappedValue += 1; selectionHaptic() }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.large)
        .background(RoundedRectangle(cornerRadius: 28).fill(palette.surface))
    }

    private func roundStepButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.black)
                .frame(width: 56, height: 56)
                .background(Circle().fill(palette.primaryAccent))
        }
        .buttonStyle(.plain)
    }

    private var heightPicker: some View {
        let isMetric = draft.units == .metric
        let display = isMetric ? draft.heightCm : (draft.heightCm / 2.54)
        let unit = draft.units.heightUnit
        return VStack(spacing: DesignSystem.Spacing.medium) {
            Text("\(Int(display)) \(unit)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundColor(palette.primaryAccent)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: draft.heightCm)
            Slider(
                value: $draft.heightCm,
                in: 120...220,
                step: 1,
                onEditingChanged: { _ in selectionHaptic() }
            )
            .tint(palette.primaryAccent)
        }
        .padding(DesignSystem.Spacing.large)
        .background(RoundedRectangle(cornerRadius: 28).fill(palette.surface))
    }

    private func weightPicker(value: Binding<Double>) -> some View {
        let isMetric = draft.units == .metric
        let display = isMetric ? value.wrappedValue : (value.wrappedValue * 2.20462)
        let unit = draft.units.weightUnit
        return VStack(spacing: DesignSystem.Spacing.medium) {
            Text("\(String(format: "%.1f", display)) \(unit)")
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .foregroundColor(palette.primaryAccent)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: value.wrappedValue)
            Slider(
                value: value,
                in: 35...200,
                step: 0.5,
                onEditingChanged: { _ in selectionHaptic() }
            )
            .tint(palette.primaryAccent)
        }
        .padding(DesignSystem.Spacing.large)
        .background(RoundedRectangle(cornerRadius: 28).fill(palette.surface))
    }

    private var sleepPickers: some View {
        VStack(spacing: DesignSystem.Spacing.medium) {
            timeRow(label: "Wake up", icon: "sunrise.fill", selection: $draft.wakeTime)
            timeRow(label: "Sleep", icon: "moon.stars.fill", selection: $draft.sleepTime)
        }
    }

    private func timeRow(label: String, icon: String, selection: Binding<Date>) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(palette.primaryAccent)
            Text(label)
                .font(DesignSystem.Typography.h3)
                .foregroundColor(palette.textPrimary)
            Spacer()
            DatePicker("", selection: selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .tint(palette.primaryAccent)
        }
        .padding(DesignSystem.Spacing.medium)
        .background(RoundedRectangle(cornerRadius: 20).fill(palette.surface))
    }

    // MARK: Footer

    private var footer: some View {
        Button(action: advance) {
            Text(isLastStep ? "Get Started" : "Continue")
                .font(DesignSystem.Typography.h3)
                .foregroundColor(.black)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(RoundedRectangle(cornerRadius: 18).fill(palette.primaryAccent))
                .shadow(color: palette.primaryAccent.opacity(0.4), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DesignSystem.Spacing.large)
        .padding(.bottom, DesignSystem.Spacing.large)
    }

    // MARK: Actions

    private func advance() {
        impactHaptic()
        if isLastStep {
            draft.completedAt = Date()
            onComplete(draft)
        } else {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                stepIndex += 1
            }
        }
    }

    private func goBack() {
        guard stepIndex > 0 else { return }
        impactHaptic()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            stepIndex -= 1
        }
    }

    private func selectionHaptic() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func impactHaptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
