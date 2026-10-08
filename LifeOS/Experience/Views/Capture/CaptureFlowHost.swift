import SwiftUI

/// Where the Capture sheet's Photo, Scan and Search buttons lead.
enum CaptureRoute: Equatable {
    case none
    case search
    case photo
    case barcode
}

/// Presents the capture flows from the root, after the Capture sheet has gone:
/// the 3.5 photo and 3.6/3.7 barcode screens full screen, and food search as a
/// sheet. Logging goes through `ExperienceStore`, so badges, the toast and Undo
/// still work.
struct CaptureFlowHost: View {
    @Binding var route: CaptureRoute
    let slot: ExperienceMealSlot
    let apiClient: any APIClient
    let foods: FoodDatabaseManager
    let mealTargets: (protein: Double, carbs: Double, fat: Double)
    let onLog: (FoodItem, ExperienceTimelineEntry.Source) -> Void
    let onSaveCustom: (FoodItem) -> Void
    /// Saves a food as a favourite preset.
    let onFavorite: (FoodItem) -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .sheet(isPresented: presented(.search)) {
                FoodSearchSheet(foods: foods, initialSlot: slot, mealTargets: mealTargets,
                                onLog: { onLog($0, .manual) }, onSaveCustom: onSaveCustom)
                    .lxSheetStyle(detents: [.large])
            }
            .fullScreenCover(isPresented: presented(.barcode)) {
                BarcodeCaptureView(slot: slot, apiClient: apiClient, mealTargets: mealTargets,
                                   onLog: { onLog($0, .barcode) }, onSaveCustom: onSaveCustom, onFavorite: onFavorite)
            }
            .fullScreenCover(isPresented: presented(.photo)) {
                MealPhotoView(slot: slot, mealTargets: mealTargets,
                              onLog: { onLog($0, .photo) }, onSavePreset: onFavorite)
            }
    }

    /// Clears the route only if it still belongs to the flow that closed.
    private func presented(_ owner: CaptureRoute) -> Binding<Bool> {
        Binding(get: { route == owner },
                set: { if !$0 && route == owner { route = .none } })
    }
}
