import Foundation

/// Resolves the weekday-name keys used by pre-P0 storage ("Monday", or a
/// localized name such as "Montag") to concrete dates.
///
/// The legacy app keyed todos, gym logs and protein checklists by weekday name
/// and mapped "Monday" to *this week's* Monday (weeks start on Monday). That is
/// all the old data can represent, so migration maps each name into the week
/// containing `reference`.
public enum LegacyWeekdayName {
    /// Returns the date for `name` in the Monday-first week containing `reference`.
    /// `nil` when the name isn't a weekday in English or any of `locales`.
    public static func dayKey(for name: String,
                              inWeekOf reference: DayKey,
                              locales: [Locale] = [Locale(identifier: "en_US_POSIX"), .current]) -> DayKey? {
        guard let weekday = weekday(for: name, locales: locales) else { return nil }
        let monday = reference.startOfWeek(firstWeekday: .monday)
        let offset = (weekday.rawValue - Weekday.monday.rawValue + 7) % 7
        return monday.adding(days: offset)
    }

    /// Matches `name` case-insensitively against the weekday symbols of each locale.
    public static func weekday(for name: String, locales: [Locale]) -> Weekday? {
        let needle = name.trimmingCharacters(in: .whitespacesAndNewlines)
        for locale in locales {
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = locale
            for symbols in [calendar.weekdaySymbols, calendar.standaloneWeekdaySymbols] {
                if let index = symbols.firstIndex(where: {
                    $0.compare(needle, options: [.caseInsensitive, .diacriticInsensitive], locale: locale) == .orderedSame
                }) {
                    return Weekday(rawValue: index + 1)
                }
            }
        }
        return nil
    }
}
