import AppIntents
import SwiftUI
import WidgetKit

/// The single LifeOS widget extension (free-account rule: one App ID for every
/// widget, control and Live Activity). UI/UX Phase 5 §3/§4.
@main
struct LifeOSWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        TodayLogWidget()
        TimelineWidget()
        LifeOSLiveActivity()
        if #available(iOS 18.0, *) {
            CaptureControl()
            AddWaterControl()
        }
    }
}

/// Control Center / Lock Screen: "Capture" opens the Capture sheet.
@available(iOS 18.0, *)
struct CaptureControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: LifeOSShared.Kind.controlCapture) {
            ControlWidgetButton(action: OpenCaptureIntent()) {
                Label("Capture", systemImage: "plus.circle.fill")
            }
        }
        .displayName("Capture a meal")
        .description("Opens LifeOS ready to log what you ate.")
    }
}

/// Control Center / Lock Screen: "+1 glass" without opening the app.
@available(iOS 18.0, *)
struct AddWaterControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: LifeOSShared.Kind.controlWater) {
            ControlWidgetButton(action: AddWaterWidgetIntent()) {
                Label("Add water", systemImage: "drop.fill")
            }
        }
        .displayName("Add a glass of water")
        .description("Adds one glass to today in LifeOS.")
    }
}
