import SwiftUI

// MARK: - App Theme Selection
enum AppTheme: String, CaseIterable, Codable {
    case system
    case light
    case dark

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Design System
enum DesignSystem {
    // MARK: Spacing
    /// A standardized spacing scale for consistent padding and margins across the app.
    enum Spacing {
        /// 4pt
        static let xxSmall: CGFloat = 4
        /// 8pt
        static let xSmall: CGFloat = 8
        /// 12pt
        static let small: CGFloat = 12
        /// 16pt (Standard default margin)
        static let medium: CGFloat = 16
        /// 24pt
        static let large: CGFloat = 24
        /// 32pt
        static let xLarge: CGFloat = 32
        /// 48pt
        static let xxLarge: CGFloat = 48
    }
    
    // MARK: Typography
    /// Structural typographic scale. Relies on SwiftUI's Dynamic Type for accessibility.
    enum Typography {
        /// Large titles for main screens (Dynamic: .largeTitle rounded)
        static let heroTitle: Font = .system(.largeTitle, design: .rounded).weight(.bold)
        /// Standard H1 (Dynamic: .title)
        static let h1: Font = .title.weight(.bold)
        /// Standard H2 (Dynamic: .title2)
        static let h2: Font = .title2.weight(.semibold)
        /// Standard H3 (Dynamic: .title3)
        static let h3: Font = .title3.weight(.medium)
        /// Standard body copy (Dynamic: .body)
        static let body: Font = .body
        /// Secondary body text (Dynamic: .callout)
        static let callout: Font = .callout
        /// Helper/metadata text (Dynamic: .footnote)
        static let caption: Font = .footnote
    }
}

// MARK: - Colors
struct ThemePalette {
    let colorScheme: ColorScheme

    var screenBackground: Color {
        colorScheme == .dark ? Color(red: 0.08, green: 0.09, blue: 0.13) : Color(uiColor: .systemGroupedBackground) // #141721
    }

    var surface: Color {
        colorScheme == .dark ? Color(red: 0.13, green: 0.14, blue: 0.18) : Color(uiColor: .secondarySystemBackground) // #21242E
    }

    var elevatedSurface: Color {
        colorScheme == .dark ? Color(red: 0.16, green: 0.18, blue: 0.22) : Color(uiColor: .tertiarySystemBackground) // #292E38
    }

    var textPrimary: Color {
        colorScheme == .dark ? .white : .primary
    }

    var textSecondary: Color {
        colorScheme == .dark ? Color(red: 0.65, green: 0.68, blue: 0.73) : .secondary
    }

    var inputSurface: Color {
        colorScheme == .dark ? Color(red: 0.12, green: 0.13, blue: 0.16) : Color(uiColor: .secondarySystemBackground)
    }

    var overlay: Color {
        colorScheme == .dark ? Color.black.opacity(0.7) : Color.black.opacity(0.25)
    }

    var primaryAccent: Color {
        Color(red: 0.44, green: 0.93, blue: 0.78) // #70EDC6 Mint Cyan
    }
}