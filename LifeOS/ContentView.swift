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
            appearance.stackedLayoutAppearance.selected.iconColor = UIColor.systemBlue
            appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.systemBlue]
        case .light:
            appearance.backgroundColor = UIColor.clear
            appearance.stackedLayoutAppearance.normal.iconColor = UIColor.gray
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.gray]
            appearance.stackedLayoutAppearance.selected.iconColor = UIColor.systemBlue
            appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.systemBlue]
        case .dark:
            appearance.backgroundColor = UIColor.clear
            appearance.stackedLayoutAppearance.normal.iconColor = UIColor.lightGray
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.lightGray]
            appearance.stackedLayoutAppearance.selected.iconColor = UIColor.systemBlue
            appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.systemBlue]
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
        
        // Graduated-blur mask: opaque at top → transparent at bottom
        let baseMask = LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black.opacity(0.8), location: 0.35),
                .init(color: .black.opacity(0.4), location: 0.65),
                .init(color: .black.opacity(0), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )

        ZStack {
            // Layer 1 — Always-visible graduated blur (base)
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(baseMask)
                .frame(height: 100)
                .opacity(0.85)

            // Layer 2 — Screen-background tint (anchors the notch color)
            Rectangle()
                .fill(palette.screenBackground.opacity(0.55))
                .mask(baseMask)
                .frame(height: 100)

            // Layer 3 — Extra intensity layer that fades in on scroll
            Rectangle()
                .fill(.thinMaterial)
                .mask(baseMask)
                .frame(height: 120)
                .opacity(clamped * 0.7)
        }
        .animation(.easeOut(duration: 0.22), value: clamped)
        .allowsHitTesting(false)
    }
}