import Foundation
import WidgetKit

/// Phase 5 §3: writes today's numbers for the widgets after every store write
/// (`ExperienceStore.afterWrite`) and asks WidgetKit to redraw. Debounced, so a
/// burst of writes costs one reload.
@MainActor
enum WidgetBridge {
    private static var pending: Task<Void, Never>?
    private static var lastLogged: (id: String, at: Date)?

    static func publish(_ store: ExperienceStore) {
        guard store.isToday else { return }
        pending?.cancel()
        pending = Task { @MainActor [weak store] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let store else { return }
            let snapshot = make(store)
            guard snapshot != WidgetStore.read() else { return }
            WidgetStore.write(snapshot)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// The confirmation tick on the medium widget's preset button.
    static func markLogged(_ presetID: String) {
        lastLogged = (presetID, Date())
    }

    static func make(_ store: ExperienceStore, now: Date = Date()) -> WidgetSnapshot {
        let b = store.budget
        let items = store.timeline.prefix(8).map { e in
            WidgetSnapshot.Item(id: e.id, kind: WidgetSnapshot.Item.Kind(rawValue: e.kind.rawValue) ?? .meal,
                                title: e.title, detail: e.detail, kcal: e.kcal, time: e.time)
        }
        let presets = store.presets(for: store.currentSlot, limit: 2).map {
            WidgetSnapshot.Preset(id: $0.id, name: $0.nutrient.name, kcal: $0.nutrient.kcal, proteinG: $0.nutrient.protein)
        }
        return WidgetSnapshot(updatedAt: now, day: Calendar.current.startOfDay(for: now),
                              budget: b.budget, eaten: b.eaten, earned: b.earned,
                              proteinG: store.log.totalProtein(), proteinTargetG: store.macroTargets.protein,
                              water: store.waterCount, waterTarget: store.waterTarget, streak: store.perfectDayStreak,
                              presets: presets, items: Array(items),
                              lastLoggedPresetID: lastLogged?.id, lastLoggedAt: lastLogged?.at)
    }
}
