import AVFoundation
import LifeOSCore
import SwiftUI
import UIKit
import Vision
import VisionKit

// Camera plumbing shared by the 3.5 photo and 3.6 barcode screens. The screens
// themselves are pure SwiftUI on LX tokens; everything AVFoundation lives here.

/// Camera permission as the capture screens need it (3.12 permission states).
enum CameraAccess: Equatable {
    case granted, denied, unavailable

    static func request() async -> CameraAccess {
        guard AVCaptureDevice.default(for: .video) != nil else { return .unavailable }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .granted
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video) ? .granted : .denied
        default: return .denied
        }
    }

    static func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}

/// The back camera's torch, for scanning in a dim kitchen.
enum CameraTorch {
    static var isAvailable: Bool { AVCaptureDevice.default(for: .video)?.hasTorch ?? false }

    static func set(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        } catch {
            Log.ui.error("Torch toggle failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Still camera (3.5)

/// One back camera and a photo output. Session work runs on its own queue, never
/// the main thread, so opening the camera doesn't hitch the sheet animation.
nonisolated final class MealCamera: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "com.tanmay.LifeOS.meal-camera")
    private var configured = false
    private var pending: CheckedContinuation<UIImage?, Never>?

    var hasFlash: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)?.hasFlash ?? false
    }

    func start() {
        queue.async { [self] in
            if !configured { configure() }
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    /// Takes a photo; nil if the session isn't running or capture failed.
    func capture(flash: Bool) async -> UIImage? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard session.isRunning, pending == nil else { continuation.resume(returning: nil); return }
                pending = continuation
                let settings = AVCapturePhotoSettings()
                if output.supportedFlashModes.contains(.on) { settings.flashMode = flash ? .on : .off }
                settings.photoQualityPrioritization = .balanced
                output.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = error == nil ? photo.fileDataRepresentation().flatMap(UIImage.init(data:)) : nil
        queue.async { [self] in
            pending?.resume(returning: image)
            pending = nil
        }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
            session.addInput(input)
        }
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.maxPhotoQualityPrioritization = .balanced
        }
        session.commitConfiguration()
        configured = true
    }
}

/// Full-bleed live preview for `MealCamera`.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        // Safe: `layerClass` guarantees the layer type.
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

// MARK: - Barcode scanner (3.6)

/// Live barcode recognition. On iPhone XS and later VisionKit's data scanner
/// outlines the code it's tracking; older phones fall back to AVFoundation
/// metadata detection. `onCode` fires once per lock; the caller decides what
/// happens next and sets `isScanning` to false to freeze on the result.
struct BarcodeScannerSurface: View {
    var isScanning: Bool
    let onCode: (String) -> Void

    var body: some View {
        if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
            DataScannerSurface(isScanning: isScanning, onCode: onCode)
        } else {
            BarcodeScannerRepresentable(onBarcodeScanned: { code in if isScanning { onCode(code) } })
        }
    }
}

private struct DataScannerSurface: UIViewControllerRepresentable {
    var isScanning: Bool
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128, .code39, .itf14])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: false,
            isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onCode = onCode
        if isScanning, !scanner.isScanning {
            do { try scanner.startScanning() } catch {
                Log.ui.error("Barcode scanner failed to start: \(error.localizedDescription, privacy: .public)")
            }
        } else if !isScanning, scanner.isScanning {
            scanner.stopScanning()
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCode: (String) -> Void
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let barcode) = item, let code = barcode.payloadStringValue, !code.isEmpty {
                    onCode(code)
                    return
                }
            }
        }
    }
}

// MARK: - Camera chrome

/// A round glass control drawn over a camera feed (close, torch, flash, gallery).
struct CameraControl: View {
    let systemImage: String
    let label: String
    var isOn = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isOn ? .lx(.onAccent) : .lx(.textPrimary))
                .frame(width: LX.Space.minTouchTarget, height: LX.Space.minTouchTarget)
                .background { if isOn { Circle().fill(.lx(.accentPrimary)) } }
                .lxGlass(in: Circle(), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// The permission and no-camera states for both capture screens (3.12).
struct CameraBlockedState: View {
    let access: CameraAccess
    let purpose: String
    var alternativeTitle: String? = nil
    var onAlternative: () -> Void = {}

    var body: some View {
        VStack(spacing: LX.Space.s500) {
            LXEmptyState(systemImage: access == .unavailable ? "camera.metering.unknown" : "camera.fill",
                         message: access == .unavailable
                            ? "There's no camera available right now."
                            : "LifeOS needs the camera to \(purpose). You can allow it in Settings.",
                         actionTitle: access == .denied ? "Open Settings" : nil,
                         action: { CameraAccess.openSettings() })
            if let alternativeTitle {
                Button(alternativeTitle, action: onAlternative).buttonStyle(.lx(.secondary))
            }
        }
        .padding(LX.Space.s500)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
