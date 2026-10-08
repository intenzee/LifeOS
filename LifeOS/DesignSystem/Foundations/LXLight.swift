import SwiftUI

/// Physical light, not theme colour: specular highlights on glass and metal, and
/// the scrim behind a full-screen moment. Real light is white and shade is black in
/// every direction and appearance, so these never follow `.lx(role)` and live here,
/// inside the design system, instead of as raw colours in feature code.
enum LXLight {
    /// Highlights and rim light on glass, metal and orbs.
    static let specular = Color.white
    /// The dimming layer behind a full-screen moment (medal, camera chrome).
    static let scrim = Color.black
    /// Text and symbols drawn directly on `scrim` or on a camera feed.
    static let onScrim = Color.white
}
