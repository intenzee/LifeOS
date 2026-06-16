import SwiftUI
import HealthKit
import Combine
import UIKit

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
// MARK: - Main App with TabView
struct ContentView: View {
    let dependencies: AppDependencies
    @State private var selectedTab = 0
    @AppStorage("appTheme") private var appThemeRaw = AppTheme.system.rawValue
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var scrollOffset: CGFloat = 0

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        Self.configureTabBarAppearance(theme: AppTheme(rawValue: UserDefaults.standard.string(forKey: "appTheme") ?? AppTheme.system.rawValue) ?? .system)
    }

    private var preferredColorScheme: ColorScheme? {
        (AppTheme(rawValue: appThemeRaw) ?? .system).preferredColorScheme
    }

    private var topScrimProgress: CGFloat {
        let raw = -scrollOffset / 120
        let clamped = min(max(raw, 0), 1)
        return clamped * clamped
    }

    private static func configureTabBarAppearance(theme: AppTheme) {
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = nil
        appearance.shadowColor = .clear
        appearance.backgroundImage = UIImage()
        appearance.shadowImage = UIImage()

        switch theme {
        case .system:
            appearance.backgroundColor = UIColor.clear
            appearance.stackedLayoutAppearance.normal.iconColor = UIColor.secondaryLabel
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.secondaryLabel]
            appearance.stackedLayoutAppearance.selected.iconColor = ThemePalette.primaryAccentUIColor
            appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: ThemePalette.primaryAccentUIColor]
        case .light:
            appearance.backgroundColor = UIColor.clear
            appearance.stackedLayoutAppearance.normal.iconColor = UIColor.gray
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.gray]
            appearance.stackedLayoutAppearance.selected.iconColor = ThemePalette.primaryAccentUIColor
            appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: ThemePalette.primaryAccentUIColor]
        case .dark:
            appearance.backgroundColor = UIColor.clear
            appearance.stackedLayoutAppearance.normal.iconColor = UIColor.lightGray
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.lightGray]
            appearance.stackedLayoutAppearance.selected.iconColor = ThemePalette.primaryAccentUIColor
            appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: ThemePalette.primaryAccentUIColor]
        }

        UITabBar.appearance().standardAppearance = appearance
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }
    
    @Environment(\.colorScheme) private var colorScheme



    var body: some View {
        let palette = ThemePalette(colorScheme: colorScheme)

        ZStack {
            mainContent(palette: palette)

            if !hasCompletedOnboarding {
                OnboardingView(onComplete: completeOnboarding)
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .scale(scale: 1.05).combined(with: .opacity)
                    ))
                    .zIndex(1)
            }
        }
        .preferredColorScheme(preferredColorScheme)
        .animation(.spring(response: 0.55, dampingFraction: 0.85), value: hasCompletedOnboarding)
    }

    private func completeOnboarding(with profile: UserProfile) {
        dependencies.persistence.saveUserProfile(profile)
        dependencies.persistence.saveCurrentWeight(profile.currentWeightKg)
        dependencies.persistence.saveTargetWeight(profile.targetWeightKg)
        SmokingSettings.shared.saveSmokingEnabled(profile.smokes)
        CalorieLimitSettings.shared.saveLimit(CalorieGoalCalculator.dailyCalorieGoal(profile: profile))
        withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
            hasCompletedOnboarding = true
        }
    }

    private func mainContent(palette: ThemePalette) -> some View {
        ZStack {
            palette.screenBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Main Content
                ZStack {
                    switch selectedTab {
                    case 0:
                        HomeView(dependencies: dependencies)
                    case 1:
                        StreaksView()
                    case 2:
                        TodoTabView()
                    case 3:
                        ProfileHubView(isPresented: .constant(true), embeddedAsTab: true)
                    default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Custom Tab Bar Space
                Color.clear.frame(height: 90)
            }
            .ignoresSafeArea(edges: .bottom)

            // Floating Custom Tab Bar
            VStack {
                Spacer()
                customTabBar(palette: palette)
            }
        }
        .preferredColorScheme(preferredColorScheme)
        .overlay(alignment: .top) {
            TopStatusBarScrim(palette: palette, progress: topScrimProgress)
                .ignoresSafeArea(edges: .top)
        }
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
            scrollOffset = value
        }
    }

    // MARK: - Custom Tab Bar
    private func customTabBar(palette: ThemePalette) -> some View {
        HStack(spacing: 0) {
            tabButton(icon: "square.grid.2x2", tabIndex: 0, palette: palette)
            Spacer()
            // Placeholder second tab for Dumbbell showing streaks for now, until gym tab logic exists
            tabButton(icon: "dumbbell", tabIndex: 1, palette: palette)
            Spacer()
            tabButton(icon: "doc.text", tabIndex: 2, palette: palette)
            Spacer()
            // Placeholder fourth tab for profile/settings if needed
            tabButton(icon: "person", tabIndex: 3, palette: palette)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 32)
                .fill(palette.surface)
                .shadow(color: Color.black.opacity(0.3), radius: 10, y: 5)
        )
        .padding(.horizontal, 24)
        .padding(.bottom, 30) // Raise it slightly from the absolute bottom
    }
    
    private func tabButton(icon: String, tabIndex: Int, palette: ThemePalette) -> some View {
        let isSelected = selectedTab == tabIndex
        return Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedTab = tabIndex
            }
        }) {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(palette.primaryAccent)
                        .frame(width: 48, height: 48)
                        .shadow(color: palette.primaryAccent.opacity(0.4), radius: 8, x: 0, y: 0)
                }
                
                Image(systemName: isSelected ? "\(icon).fill" : icon)
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? .black : palette.textSecondary)
            }
            .frame(width: 48, height: 48)
        }
    }
}

private struct TopStatusBarScrim: View {
    let palette: ThemePalette
    let progress: CGFloat

    var body: some View {
        let clamped = min(max(progress, 0), 1)

        // Single graduated-blur layer (replaces previous 3-layer stack for GPU savings)
        let mask = LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black.opacity(0.7), location: 0.4),
                .init(color: .black.opacity(0), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )

        Rectangle()
            .fill(palette.screenBackground.opacity(0.6 + clamped * 0.3))
            .overlay(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.7 + clamped * 0.3)
            )
            .mask(mask)
            .frame(height: 100)
            .animation(.easeOut(duration: 0.22), value: clamped)
            .allowsHitTesting(false)
    }
}