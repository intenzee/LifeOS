import SwiftUI
import UIKit

/// Lets the user review and edit the profile gathered during onboarding.
/// On save it persists the profile and re-syncs the derived values
/// (calorie goal, weight, target weight, smoking) into the existing settings.
struct ProfileDetailsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var profile: UserProfile

    init(profile: UserProfile? = nil) {
        _profile = State(initialValue: profile ?? PersistenceManager.shared.loadUserProfile() ?? UserProfile())
    }

    private var palette: ThemePalette { ThemePalette(colorScheme: colorScheme) }

    private var estimatedCalories: Int {
        Int(CalorieGoalCalculator.dailyCalorieGoal(profile: profile))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                palette.screenBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: DesignSystem.Spacing.medium) {
                        calorieSummaryCard
                        unitsCard
                        bodyCard
                        goalCard
                        dietCard
                        lifestyleCard
                    }
                    .padding(DesignSystem.Spacing.medium)
                    .padding(.bottom, DesignSystem.Spacing.xLarge)
                }
            }
            .navigationTitle("Health Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(palette.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .foregroundColor(palette.primaryAccent)
                }
            }
        }
    }

    // MARK: Cards

    private var calorieSummaryCard: some View {
        VStack(spacing: DesignSystem.Spacing.xSmall) {
            Text("Recommended Daily Target")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(palette.textSecondary)
            Text("\(estimatedCalories)")
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .foregroundColor(palette.primaryAccent)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: estimatedCalories)
            Text("calories / day")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.large)
        .background(RoundedRectangle(cornerRadius: 24).fill(palette.surface))
    }

    private var unitsCard: some View {
        card(title: "Units", icon: "ruler.fill") {
            segmented(MeasurementUnits.allCases, selected: profile.units) { profile.units = $0 }
        }
    }

    private var bodyCard: some View {
        card(title: "Body", icon: "figure.stand") {
            VStack(spacing: DesignSystem.Spacing.small) {
                segmented(BiologicalSex.allCases, selected: profile.sex) { profile.sex = $0 }
                stepperRow(label: "Age", value: $profile.age, range: 13...100, unit: "yrs")
                heightRow
                weightRow(label: "Current", value: $profile.currentWeightKg)
                weightRow(label: "Target", value: $profile.targetWeightKg)
            }
        }
    }

    private var goalCard: some View {
        card(title: "Goal & Activity", icon: "flag.checkered") {
            VStack(spacing: DesignSystem.Spacing.small) {
                chipFlow(FitnessGoal.allCases, selected: profile.goal, icon: { $0.icon }) { profile.goal = $0 }
                stepperRow(label: "Training", value: $profile.exerciseDaysPerWeek, range: 0...7, unit: "days/wk")
            }
        }
    }

    private var dietCard: some View {
        card(title: "Diet", icon: "fork.knife") {
            chipFlow(DietType.allCases, selected: profile.diet, icon: { $0.icon }) { profile.diet = $0 }
        }
    }

    private var lifestyleCard: some View {
        card(title: "Lifestyle", icon: "heart.fill") {
            VStack(spacing: DesignSystem.Spacing.small) {
                Toggle(isOn: $profile.smokes) {
                    Text("I am a smoker")
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(palette.textPrimary)
                }
                .tint(palette.primaryAccent)

                stepperRow(label: "Water goal", value: $profile.waterGoalGlasses, range: 1...20, unit: "glasses")

                timeRow(label: "Wake up", icon: "sunrise.fill", selection: $profile.wakeTime)
                timeRow(label: "Sleep", icon: "moon.stars.fill", selection: $profile.sleepTime)
            }
        }
    }

    // MARK: Building blocks

    private func card<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            HStack(spacing: DesignSystem.Spacing.xSmall) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(palette.primaryAccent)
                Text(title)
                    .font(DesignSystem.Typography.h3)
                    .foregroundColor(palette.textPrimary)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.medium)
        .background(RoundedRectangle(cornerRadius: 20).fill(palette.surface))
    }

    private func segmented<T: Identifiable & Equatable & RawRepresentable>(
        _ options: [T],
        selected: T,
        onSelect: @escaping (T) -> Void
    ) -> some View where T.RawValue == String {
        HStack(spacing: DesignSystem.Spacing.xSmall) {
            ForEach(options) { option in
                let isSelected = option == selected
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { onSelect(option) }
                } label: {
                    Text(option.rawValue)
                        .font(DesignSystem.Typography.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .foregroundColor(isSelected ? .black : palette.textPrimary)
                        .background(RoundedRectangle(cornerRadius: 12).fill(isSelected ? palette.primaryAccent : palette.elevatedSurface))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func chipFlow<T: Identifiable & Equatable & RawRepresentable>(
        _ options: [T],
        selected: T,
        icon: @escaping (T) -> String,
        onSelect: @escaping (T) -> Void
    ) -> some View where T.RawValue == String {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DesignSystem.Spacing.xSmall) {
            ForEach(options) { option in
                let isSelected = option == selected
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { onSelect(option) }
                } label: {
                    HStack(spacing: DesignSystem.Spacing.xSmall) {
                        Image(systemName: icon(option))
                            .font(.system(size: 15, weight: .semibold))
                        Text(option.rawValue)
                            .font(DesignSystem.Typography.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.horizontal, DesignSystem.Spacing.small)
                    .foregroundColor(isSelected ? .black : palette.textPrimary)
                    .background(RoundedRectangle(cornerRadius: 12).fill(isSelected ? palette.primaryAccent : palette.elevatedSurface))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func stepperRow(label: String, value: Binding<Int>, range: ClosedRange<Int>, unit: String) -> some View {
        HStack {
            Text(label)
                .font(DesignSystem.Typography.body)
                .foregroundColor(palette.textPrimary)
            Spacer()
            Button {
                if value.wrappedValue > range.lowerBound { value.wrappedValue -= 1; UISelectionFeedbackGenerator().selectionChanged() }
            } label: {
                Image(systemName: "minus").font(.system(size: 14, weight: .bold)).foregroundColor(.black)
                    .frame(width: 32, height: 32).background(Circle().fill(palette.primaryAccent))
            }
            .buttonStyle(.plain)
            Text("\(value.wrappedValue) \(unit)")
                .font(DesignSystem.Typography.callout.weight(.semibold))
                .foregroundColor(palette.textPrimary)
                .frame(minWidth: 84)
                .contentTransition(.numericText())
            Button {
                if value.wrappedValue < range.upperBound { value.wrappedValue += 1; UISelectionFeedbackGenerator().selectionChanged() }
            } label: {
                Image(systemName: "plus").font(.system(size: 14, weight: .bold)).foregroundColor(.black)
                    .frame(width: 32, height: 32).background(Circle().fill(palette.primaryAccent))
            }
            .buttonStyle(.plain)
        }
    }

    private var heightRow: some View {
        let isMetric = profile.units == .metric
        let display = isMetric ? profile.heightCm : (profile.heightCm / 2.54)
        return VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
            HStack {
                Text("Height").font(DesignSystem.Typography.body).foregroundColor(palette.textPrimary)
                Spacer()
                Text("\(Int(display)) \(profile.units.heightUnit)")
                    .font(DesignSystem.Typography.callout.weight(.semibold))
                    .foregroundColor(palette.primaryAccent)
            }
            Slider(value: $profile.heightCm, in: 120...220, step: 1).tint(palette.primaryAccent)
        }
    }

    private func weightRow(label: String, value: Binding<Double>) -> some View {
        let isMetric = profile.units == .metric
        let display = isMetric ? value.wrappedValue : (value.wrappedValue * 2.20462)
        return VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
            HStack {
                Text(label).font(DesignSystem.Typography.body).foregroundColor(palette.textPrimary)
                Spacer()
                Text("\(String(format: "%.1f", display)) \(profile.units.weightUnit)")
                    .font(DesignSystem.Typography.callout.weight(.semibold))
                    .foregroundColor(palette.primaryAccent)
            }
            Slider(value: value, in: 35...200, step: 0.5).tint(palette.primaryAccent)
        }
    }

    private func timeRow(label: String, icon: String, selection: Binding<Date>) -> some View {
        HStack {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundColor(palette.primaryAccent)
            Text(label).font(DesignSystem.Typography.body).foregroundColor(palette.textPrimary)
            Spacer()
            DatePicker("", selection: selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .tint(palette.primaryAccent)
        }
    }

    // MARK: Save

    private func save() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        PersistenceManager.shared.saveUserProfile(profile)
        PersistenceManager.shared.saveCurrentWeight(profile.currentWeightKg)
        PersistenceManager.shared.saveTargetWeight(profile.targetWeightKg)
        SmokingSettings.shared.saveSmokingEnabled(profile.smokes)
        CalorieLimitSettings.shared.saveLimit(CalorieGoalCalculator.dailyCalorieGoal(profile: profile))
        dismiss()
    }
}
