import Foundation
import Security
import SwiftUI
import UIKit

// UI/UX Phase 5 §3/§4: code compiled into BOTH the app and the "LifeOS Widgets"
// extension (synchronized folder in both targets). Foundation/SwiftUI only;
// app-only calls sit behind `#if !WIDGET_EXTENSION`.

nonisolated enum LifeOSShared {
    static let appGroup = "group.com.tanmay.LifeOS"
    static let snapshotKey = "lx.widget.snapshot.v1"
    /// Fallback when the account can't sign an App Group: a keychain item in the
    /// team's shared access group (granted as `<TeamID>.*` on this account).
    static let keychainService = "com.tanmay.LifeOS.widget"
    static let urlScheme = "lifeos"

    enum Kind {
        static let today = "lx.widget.today"
        static let todayLog = "lx.widget.todayLog"
        static let timeline = "lx.widget.timeline"
        static let controlCapture = "lx.control.capture"
        static let controlWater = "lx.control.water"
    }

    static func url(_ path: String) -> URL { URL(string: "\(urlScheme)://\(path)")! }
}

/// What the widgets show. The app writes it after every change; widgets only read.
nonisolated struct WidgetSnapshot: Codable, Equatable, Sendable {
    nonisolated struct Preset: Codable, Equatable, Sendable, Identifiable {
        var id: String
        var name: String
        var kcal: Double
        var proteinG: Double
    }

    nonisolated struct Item: Codable, Equatable, Sendable, Identifiable {
        enum Kind: String, Codable, Sendable { case meal, workout, water, weight }
        var id: String
        var kind: Kind
        var title: String
        var detail: String
        var kcal: Int?
        var time: Date?
    }

    var updatedAt: Date
    var day: Date
    var budget: Double
    var eaten: Double
    var earned: Double
    var proteinG: Double
    var proteinTargetG: Double
    var water: Int
    var waterTarget: Int
    var streak: Int
    var presets: [Preset]
    var items: [Item]
    /// The preset just logged from a widget, for the confirmation tick.
    var lastLoggedPresetID: String?
    var lastLoggedAt: Date?

    var remaining: Double { budget - eaten }
    var isOver: Bool { budget > 0 && remaining < 0 }
    var fill: Double { budget > 0 ? max(eaten, 0) / budget : 0 }

    /// Yesterday's numbers must not show as today's: after midnight, eaten/water reset until the app writes again.
    func forDisplay(now: Date = Date(), calendar: Calendar = .current) -> WidgetSnapshot {
        guard !calendar.isDate(day, inSameDayAs: now) else { return self }
        var s = self
        s.day = calendar.startOfDay(for: now)
        s.eaten = 0
        s.earned = 0
        s.budget = max(budget - earned, 0)
        s.proteinG = 0
        s.water = 0
        s.items = []
        s.lastLoggedPresetID = nil
        return s
    }

    func justLogged(_ presetID: String, now: Date = Date()) -> Bool {
        lastLoggedPresetID == presetID && (lastLoggedAt.map { now.timeIntervalSince($0) < 600 } ?? false)
    }

    static let placeholder = WidgetSnapshot(
        updatedAt: Date(), day: Date(), budget: 1_920, eaten: 1_280, earned: 222, proteinG: 96, proteinTargetG: 120,
        water: 5, waterTarget: 8, streak: 6,
        presets: [.init(id: "a", name: "Poha", kcal: 250, proteinG: 6), .init(id: "b", name: "Dal and rice", kcal: 480, proteinG: 18)],
        items: [.init(id: "1", kind: .meal, title: "Poha", detail: "Breakfast", kcal: 250, time: Date().addingTimeInterval(-18_000)),
                .init(id: "2", kind: .workout, title: "Strength", detail: "12 sets", kcal: -190, time: Date().addingTimeInterval(-9_000)),
                .init(id: "3", kind: .meal, title: "Dal and rice", detail: "Lunch", kcal: 480, time: Date().addingTimeInterval(-5_400))],
        lastLoggedPresetID: nil, lastLoggedAt: nil)
}

/// Reads and writes the snapshot: App Group defaults when the account has one,
/// otherwise the shared keychain item.
nonisolated enum WidgetStore {
    static var hasAppGroup: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: LifeOSShared.appGroup) != nil
    }

    static func read() -> WidgetSnapshot? {
        let data: Data?
        if hasAppGroup {
            data = UserDefaults(suiteName: LifeOSShared.appGroup)?.data(forKey: LifeOSShared.snapshotKey)
        } else {
            data = Keychain.read()
        }
        guard let data else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    static func write(_ snapshot: WidgetSnapshot) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(snapshot) else { return }
        if hasAppGroup {
            UserDefaults(suiteName: LifeOSShared.appGroup)?.set(data, forKey: LifeOSShared.snapshotKey)
        } else {
            Keychain.write(data)
        }
    }

    private enum Keychain {
        static var query: [String: Any] {
            [kSecClass as String: kSecClassGenericPassword,
             kSecAttrService as String: LifeOSShared.keychainService,
             kSecAttrAccount as String: LifeOSShared.snapshotKey]
        }

        static func read() -> Data? {
            var q = query
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var out: CFTypeRef?
            return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
        }

        static func write(_ data: Data) {
            let attrs: [String: Any] = [kSecValueData as String: data,
                                        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
            if SecItemUpdate(query as CFDictionary, attrs as CFDictionary) == errSecItemNotFound {
                SecItemAdd(query.merging(attrs) { $1 } as CFDictionary, nil)
            }
        }
    }
}

/// The phone's data colours (dark/light pairs from LXTokens), for the widget
/// target which doesn't compile the design system. Keep in step with the tokens.
nonisolated enum WidgetPalette {
    static let energy = pair(0xF2A65A, 0xA0560B)
    static let activity = pair(0x5FD6C2, 0x0F7468)
    static let protein = pair(0xF08A8A, 0xB03B48)
    static let water = pair(0x8BD6EE, 0x1750A1)
    static let over = pair(0xD98C5F, 0xA0491F)
    static let onTrack = pair(0x8CC9A8, 0x2B7350)
    static let accent = pair(0x70EDC6, 0x0B7A5E)

    private static func pair(_ dark: UInt32, _ light: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(widgetHex: dark) : UIColor(widgetHex: light) })
    }
}

extension UIColor {
    nonisolated convenience init(widgetHex hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
