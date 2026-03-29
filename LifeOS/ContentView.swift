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
    @StateObject private var healthManager = HealthManager()
    @State private var selectedTab = 0
    @AppStorage("appTheme") private var appThemeRaw = AppTheme.system.rawValue

    init() {
        Self.configureTabBarAppearance(theme: AppTheme(rawValue: UserDefaults.standard.string(forKey: "appTheme") ?? AppTheme.system.rawValue) ?? .system)
    }

    private var preferredColorScheme: ColorScheme? {
        (AppTheme(rawValue: appThemeRaw) ?? .system).preferredColorScheme
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
        ZStack {
            ThemePalette(colorScheme: colorScheme).screenBackground
                .ignoresSafeArea()

            TabView(selection: $selectedTab) {
                HomeView(healthManager: healthManager)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)
            
            StreaksView()
                .tabItem {
                    Label("Streaks", systemImage: "flame.fill")
                }
                .tag(1)
            
            TodoTabView()
                .tabItem {
                    Label("To Do", systemImage: "checklist")
                }
                .tag(2)
        }
        .accentColor(.blue)
        .preferredColorScheme(preferredColorScheme)
        .onAppear {
            Self.configureTabBarAppearance(theme: AppTheme(rawValue: appThemeRaw) ?? .system)
        }
        .onChange(of: appThemeRaw) { _, newValue in
            Self.configureTabBarAppearance(theme: AppTheme(rawValue: newValue) ?? .system)
        }
        } // ZStack
    }
}