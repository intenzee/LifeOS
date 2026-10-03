import QuickLook
import SceneKit
import SwiftUI
import UIKit

// Phase 5 §6: glass discs with a metal rim in the accent colour, engraved with a
// symbol and the date earned. Built in code (no Blender asset needed): about
// 1,200 triangles per medal, one shared material set, a 1024 px engraving.

// MARK: - 2D badge (grid, earning moment, places 3D can't go)

struct MedalBadge: View {
    let medal: Medal
    var earned = true
    var size: CGFloat = 96
    @Environment(\.lxTheme) private var theme

    var body: some View {
        let accent = theme.color(.accentPrimary)
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color.white.opacity(earned ? 0.55 : 0.18), accent.opacity(earned ? 0.18 : 0.04)],
                                     center: .init(x: 0.35, y: 0.3), startRadius: 2, endRadius: size * 0.6))
            Circle()
                .strokeBorder(AngularGradient(colors: earned ? [accent, .white.opacity(0.9), accent.opacity(0.7), accent]
                                                             : [.gray.opacity(0.5), .gray.opacity(0.3), .gray.opacity(0.5)],
                                              center: .center), lineWidth: size * 0.07)
            Image(systemName: medal.symbol)
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(earned ? AnyShapeStyle(accent) : AnyShapeStyle(.lx(.textTertiary)))
        }
        .frame(width: size, height: size)
        .shadow(color: earned ? accent.opacity(0.35) : .clear, radius: size * 0.12, y: size * 0.04)
        .accessibilityHidden(true)
    }
}

// MARK: - 3D medal

enum MedalScene {
    /// The medal faces +Z. `accent` tints the rim; the engraving carries symbol, title and date.
    static func make(_ medal: Medal, earnedOn: Date?, accent: UIColor) -> SCNScene {
        let scene = SCNScene()
        let root = SCNNode()
        root.name = "medal"

        let disc = SCNCylinder(radius: 1.0, height: 0.16)
        disc.radialSegmentCount = 96
        let glass = SCNMaterial()
        glass.lightingModel = .physicallyBased
        glass.diffuse.contents = UIColor(white: 1, alpha: 0.35)
        glass.metalness.contents = 0.0
        glass.roughness.contents = 0.06
        glass.transparencyMode = .dualLayer
        glass.fresnelExponent = 1.6
        glass.isDoubleSided = true
        disc.materials = [glass]
        let discNode = SCNNode(geometry: disc)
        discNode.eulerAngles.x = .pi / 2
        root.addChildNode(discNode)

        let rim = SCNTube(innerRadius: 0.97, outerRadius: 1.1, height: 0.22)
        rim.radialSegmentCount = 96
        let metal = SCNMaterial()
        metal.lightingModel = .physicallyBased
        metal.diffuse.contents = accent
        metal.metalness.contents = 1.0
        metal.roughness.contents = 0.22
        rim.materials = [metal]
        let rimNode = SCNNode(geometry: rim)
        rimNode.eulerAngles.x = .pi / 2
        root.addChildNode(rimNode)

        let engraving = SCNMaterial()
        engraving.lightingModel = .physicallyBased
        engraving.diffuse.contents = engravingURL(medal, earnedOn: earnedOn, accent: accent) ?? UIColor.clear
        engraving.metalness.contents = 0.6
        engraving.roughness.contents = 0.3
        engraving.isDoubleSided = false
        for (z, turn) in [(Float(0.085), Float(0)), (Float(-0.085), Float.pi)] {
            let face = SCNPlane(width: 1.7, height: 1.7)
            face.materials = [engraving]
            let node = SCNNode(geometry: face)
            node.position.z = z
            node.eulerAngles.y = turn
            root.addChildNode(node)
        }
        scene.rootNode.addChildNode(root)

        scene.lightingEnvironment.contents = studioEnvironment()
        scene.lightingEnvironment.intensity = 1.4
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 900
        key.eulerAngles = SCNVector3(-0.6, 0.5, 0)
        scene.rootNode.addChildNode(key)

        let camera = SCNNode()
        camera.name = "camera"
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 35
        camera.position = SCNVector3(0, 0, 4.2)
        scene.rootNode.addChildNode(camera)
        return scene
    }

    /// The engraving as a PNG file, so it travels inside the USDZ for AR Quick Look.
    private static func engravingURL(_ medal: Medal, earnedOn: Date?, accent: UIColor) -> URL? {
        let size = CGSize(width: 1024, height: 1024)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            let config = UIImage.SymbolConfiguration(pointSize: 300, weight: .semibold)
            if let symbol = UIImage(systemName: medal.symbol, withConfiguration: config)?.withTintColor(accent, renderingMode: .alwaysOriginal) {
                let s = symbol.size
                symbol.draw(in: CGRect(x: (size.width - s.width) / 2, y: 250 - s.height / 2 + 120, width: s.width, height: s.height))
            }
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let title: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 92, weight: .bold), .foregroundColor: UIColor.white, .paragraphStyle: paragraph]
            (medal.title.uppercased() as NSString).draw(in: CGRect(x: 0, y: 610, width: size.width, height: 120), withAttributes: title)
            if let earnedOn {
                let date: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedDigitSystemFont(ofSize: 60, weight: .medium),
                                                           .foregroundColor: UIColor.white.withAlphaComponent(0.85), .paragraphStyle: paragraph]
                (earnedOn.formatted(date: .abbreviated, time: .omitted) as NSString).draw(in: CGRect(x: 0, y: 740, width: size.width, height: 90), withAttributes: date)
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("medal-\(medal.rawValue)-engraving.png")
        guard let png = image.pngData(), (try? png.write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }

    private static func studioEnvironment() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 512, height: 256)).image { ctx in
            let colors = [UIColor(white: 0.95, alpha: 1).cgColor, UIColor(white: 0.35, alpha: 1).cgColor, UIColor(white: 0.08, alpha: 1).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 0.45, 1])!
            ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 256), options: [])
        }
    }

    /// Writes the medal as USDZ for AR Quick Look ("View in your space").
    static func exportUSDZ(_ medal: Medal, earnedOn: Date?, accent: UIColor) -> URL? {
        let scene = make(medal, earnedOn: earnedOn, accent: accent)
        scene.rootNode.childNode(withName: "camera", recursively: false)?.removeFromParentNode()
        // AR Quick Look works in metres: a 9 cm medal.
        scene.rootNode.childNode(withName: "medal", recursively: false)?.scale = SCNVector3(0.04, 0.04, 0.04)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("LifeOS \(medal.title) medal.usdz")
        try? FileManager.default.removeItem(at: url)
        return scene.write(to: url, options: nil, delegate: nil, progressHandler: nil) ? url : nil
    }
}

struct MedalViewer: View {
    let medal: Medal
    let earnedOn: Date?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lxTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scene: SCNScene?
    @State private var arURL: URL?
    @State private var exportFailed = false

    var body: some View {
        NavigationStack {
            VStack(spacing: LX.Space.s500) {
                if let scene {
                    SceneView(scene: scene, pointOfView: scene.rootNode.childNode(withName: "camera", recursively: false),
                              options: [.allowsCameraControl], antialiasingMode: .multisampling4X)
                        .frame(height: 340)
                        .accessibilityLabel("\(medal.title) medal, 3D. Drag to turn it.")
                } else {
                    MedalBadge(medal: medal, size: 200).frame(height: 340)
                }
                VStack(spacing: LX.Space.s200) {
                    Text(medal.title).lxFont(.title2).foregroundStyle(.lx(.textPrimary))
                    Text(medal.criterion).lxFont(.body).foregroundStyle(.lx(.textSecondary))
                    if let earnedOn {
                        Text("Earned \(earnedOn.formatted(date: .long, time: .omitted))").lxFont(.footnote, numeric: true).foregroundStyle(.lx(.textTertiary))
                    }
                }
                .multilineTextAlignment(.center)
                Button {
                    arURL = MedalScene.exportUSDZ(medal, earnedOn: earnedOn, accent: UIColor(theme.color(.accentPrimary)))
                    exportFailed = arURL == nil
                } label: {
                    Label("View in your space", systemImage: "arkit").frame(maxWidth: .infinity)
                }
                .buttonStyle(.lx(.primary))
                if exportFailed {
                    Text("The 3D file couldn't be made on this iPhone.").lxFont(.footnote).foregroundStyle(.lx(.textSecondary))
                }
                Spacer()
            }
            .padding(LX.Space.s400)
            .background(LXScreenBackground(heroGlow: true).ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .quickLookPreview($arURL)
            .task {
                let made = MedalScene.make(medal, earnedOn: earnedOn, accent: UIColor(theme.color(.accentPrimary)))
                if !reduceMotion {
                    // A slow idle turn so light catches the rim; dragging takes over.
                    made.rootNode.childNode(withName: "medal", recursively: false)?
                        .runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 14)))
                }
                scene = made
            }
        }
    }
}

// MARK: - Achievements screen

struct AchievementsScreen: View {
    @ObservedObject private var achievements = AchievementStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var viewing: Medal?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LX.Space.s500) {
                    Text("A few medals for the habits that matter. No points, no levels.")
                        .lxFont(.body).foregroundStyle(.lx(.textSecondary))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: LX.Space.s300)], spacing: LX.Space.s300) {
                        ForEach(achievements.progress, id: \.medal) { p in tile(p) }
                    }
                }
                .padding(LX.Space.s400)
            }
            .background(LXScreenBackground(heroGlow: false).ignoresSafeArea())
            .navigationTitle("Achievements").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $viewing) { m in MedalViewer(medal: m, earnedOn: achievements.earnedOn[m]) }
            .onAppear { achievements.refresh() }
        }
    }

    private func tile(_ p: MedalProgress) -> some View {
        Button { if p.earned { viewing = p.medal } } label: {
            VStack(spacing: LX.Space.s200) {
                MedalBadge(medal: p.medal, earned: p.earned, size: 84)
                Text(p.medal.title).lxFont(.headline).foregroundStyle(.lx(.textPrimary))
                Text(p.medal.criterion).lxFont(.caption).foregroundStyle(.lx(.textSecondary)).multilineTextAlignment(.center)
                if p.earned, let d = achievements.earnedOn[p.medal] {
                    Text(d.formatted(date: .abbreviated, time: .omitted)).lxFont(.caption, numeric: true).foregroundStyle(.lx(.textTertiary))
                } else if !p.earned {
                    LXProgressBar(value: Double(p.current) / Double(p.medal.target), role: .accentPrimary)
                    Text(p.text).lxFont(.caption, numeric: true).foregroundStyle(.lx(.textTertiary)).multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .lxCard(padding: LX.Space.s300)
        }
        .buttonStyle(.plain)
        .disabled(!p.earned)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(p.medal.title). \(p.medal.criterion). \(p.earned ? "Earned" + (achievements.earnedOn[p.medal].map { " " + $0.formatted(date: .long, time: .omitted) } ?? "") : p.text).")
        .accessibilityHint(p.earned ? "Opens the medal in 3D" : "")
        .accessibilityAddTraits(p.earned ? .isButton : [])
    }
}

// MARK: - Earning moment

/// Full screen, about 2.5 s: the medal drops in and settles, one success haptic.
/// Reduce Motion: a fade.
struct MedalEarningMoment: View {
    let medal: Medal
    var onDone: () -> Void
    var onView: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.lxDirection) private var direction
    @State private var landed = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture { onDone() }
            VStack(spacing: LX.Space.s500) {
                MedalBadge(medal: medal, size: 180)
                    .offset(y: landed || reduceMotion ? 0 : -420)
                    .rotation3DEffect(.degrees(landed || reduceMotion ? 0 : 50), axis: (x: 1, y: 0, z: 0))
                    .opacity(reduceMotion ? (landed ? 1 : 0) : 1)
                VStack(spacing: LX.Space.s200) {
                    Text("New medal").lxFont(.footnote, weight: .semibold).foregroundStyle(.white.opacity(0.8)).textCase(.uppercase)
                    Text(medal.title).lxFont(.displayL).foregroundStyle(.white)
                    Text(medal.criterion).lxFont(.body).foregroundStyle(.white.opacity(0.85))
                }
                .multilineTextAlignment(.center)
                .opacity(landed ? 1 : 0)
                HStack(spacing: LX.Space.s300) {
                    Button("View in 3D", action: onView).buttonStyle(.lx(.primary))
                    Button("Done", action: onDone).buttonStyle(.lx(.secondary))
                }
                .opacity(landed ? 1 : 0)
            }
            .padding(LX.Space.s600)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .sensoryFeedback(.success, trigger: landed) { _, new in new }
        .onAppear {
            withAnimation(LXMotion.celebrate.animation(direction: direction, reduceMotion: reduceMotion)) { landed = true }
            UIAccessibility.post(notification: .announcement, argument: "New medal: \(medal.title). \(medal.criterion).")
        }
    }
}
