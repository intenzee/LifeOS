import Foundation
import LifeOSConnectivity

/// The watch's App Group copy of `ComplicationSnapshot` (WCH-15). The watch app
/// writes it; the widget extension reads it. Compiled into both watch targets.
enum ComplicationStore {
    /// `nil` when the build isn't signed with the App Group.
    static var defaults: UserDefaults? {
        guard FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: ComplicationSnapshot.appGroup) != nil else { return nil }
        return UserDefaults(suiteName: ComplicationSnapshot.appGroup)
    }

    static func read() -> ComplicationSnapshot? {
        defaults?.data(forKey: ComplicationSnapshot.storageKey).flatMap(ComplicationCoding.decode)
    }

    /// `false` if there's no App Group to write to.
    @discardableResult
    static func write(_ snapshot: ComplicationSnapshot) -> Bool {
        guard let defaults, let data = try? ComplicationCoding.encode(snapshot) else { return false }
        defaults.set(data, forKey: ComplicationSnapshot.storageKey)
        return true
    }
}
