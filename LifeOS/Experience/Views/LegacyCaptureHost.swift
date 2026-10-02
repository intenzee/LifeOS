import SwiftUI

/// Routes from the Capture sheet into the app's existing photo, barcode and
/// search flows (Phase 3 §3.5–3.7 redesign those screens later; until then the
/// proven flows are reused, and only the logging goes through `ExperienceStore`).
enum LegacyCaptureRoute: Equatable {
    case none
    case search
    case photo
    case barcode
    case portion(FoodItem)
    case unrecognized(barcode: String)
    case manual(barcode: String?)

    fileprivate var kind: Int {
        switch self {
        case .none: return 0
        case .search: return 1
        case .photo: return 2
        case .barcode: return 3
        case .portion: return 4
        case .unrecognized: return 5
        case .manual: return 6
        }
    }
}

struct LegacyCaptureHost: View {
    @Binding var route: LegacyCaptureRoute
    let slot: ExperienceMealSlot
    let apiClient: any APIClient
    let onLog: (FoodItem, ExperienceTimelineEntry.Source) -> Void
    let onSaveCustom: (FoodItem) -> Void

    var body: some View {
        ZStack {
            switch route {
            case .none:
                EmptyView()
            case .search:
                FoodSearchView(isPresented: presented(.search), selectedMeal: slot.mealType) { food in
                    onLog(food, .manual)
                }
            case .photo:
                AIMealScanView(isPresented: presented(.photo), selectedMeal: slot.mealType, apiClient: apiClient) { food in
                    onLog(food, .photo)
                }
            case .barcode:
                BarcodeScannerView(isPresented: presented(.barcode), selectedMeal: slot.mealType) { code in
                    lookUp(code)
                }
            case .portion(let food):
                PortionSizeSelectorView(isPresented: presented(route), baseFood: food) { scaled in
                    onLog(scaled, .barcode)
                }
            case .unrecognized(let code):
                BarcodeUnrecognizedPromptView(isPresented: presented(route), barcode: code,
                                              onRetryScan: { route = .barcode },
                                              onLogManually: { route = .manual(barcode: code) })
            case .manual(let code):
                CustomFoodView(isPresented: presented(route), mealType: slot.mealType, barcode: code,
                               initialFoodName: code == nil ? "" : "Unrecognized Item",
                               initialServingSize: "1 serving") { food in
                    onSaveCustom(food)
                    onLog(food, code == nil ? .manual : .barcode)
                }
            }
        }
    }

    /// The legacy views dismiss themselves by setting `isPresented = false`; only
    /// clear the route if it still belongs to that view (a barcode lookup may have
    /// already moved on to the portion step).
    private func presented(_ owner: LegacyCaptureRoute) -> Binding<Bool> {
        Binding(get: { route.kind == owner.kind },
                set: { if !$0 && route.kind == owner.kind { route = .none } })
    }

    private func lookUp(_ code: String) {
        Task { @MainActor in
            let food = try? await BarcodeFoodLookup.lookup(barcode: code, apiClient: apiClient)
            if var found = food {
                found.mealType = slot.mealType
                route = .portion(found)
            } else {
                route = .unrecognized(barcode: code)
            }
        }
    }
}
