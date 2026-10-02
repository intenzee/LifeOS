import AVFoundation
import Combine
import Foundation
import Speech

/// "Say" mode for the Capture sheet (Phase 3 §3.2): live transcript word by
/// word, an audio level for the glyph ripple, and an automatic stop after
/// 1.5 s of silence. Prefers on-device recognition when the phone supports it.
@MainActor
final class SpeechCapture: ObservableObject {
    enum Phase: Equatable {
        case idle
        case listening
        case denied       // microphone or speech permission refused: Type mode with a Settings link
        case unavailable  // recogniser not available for this language / offline without on-device support
        case finished(String)
        case nothingHeard
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var transcript = ""
    /// 0…1, smoothed, for the ripple.
    @Published private(set) var level: Double = 0
    @Published private(set) var isOnDevice = false

    private let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-IN"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Task<Void, Never>?
    private let silenceSeconds = 1.5

    func start() async {
        guard phase != .listening else { return }
        transcript = ""
        guard await Self.authorize() else { phase = .denied; return }
        guard let recognizer, recognizer.isAvailable else { phase = .unavailable; return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
                isOnDevice = true
            }
            request.addsPunctuation = false
            self.request = request

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.tapBlock(request: request, owner: self))
            engine.prepare()
            try engine.start()
            phase = .listening
            armSilenceTimer()

            task = recognizer.recognitionTask(with: request, resultHandler: Self.resultHandler(owner: self))
        } catch {
            stopAudio()
            phase = .unavailable
        }
    }

    /// Stops listening and publishes what was heard.
    func finish() {
        guard phase == .listening else { return }
        stopAudio()
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        phase = text.isEmpty ? .nothingHeard : .finished(text)
    }

    func cancel() {
        stopAudio()
        phase = .idle
        transcript = ""
    }

    private func stopAudio() {
        silenceTimer?.cancel()
        silenceTimer = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // Audio and Speech call these on their own queues, so they must not inherit
    // the class's main-actor isolation; they hop back explicitly.
    nonisolated private static func tapBlock(request: SFSpeechAudioBufferRecognitionRequest, owner: SpeechCapture) -> AVAudioNodeTapBlock {
        { [weak owner] buffer, _ in
            request.append(buffer)
            let rms = rms(buffer)
            Task { @MainActor [weak owner] in owner?.updateLevel(rms) }
        }
    }

    nonisolated private static func resultHandler(owner: SpeechCapture) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { [weak owner] result, error in
            let text = result?.bestTranscription.formattedString
            let done = (result?.isFinal ?? false) || error != nil
            Task { @MainActor [weak owner] in owner?.receive(text: text, done: done) }
        }
    }

    private func receive(text: String?, done: Bool) {
        if let text, !text.isEmpty, text != transcript {
            transcript = text
            armSilenceTimer()
        }
        if done { finish() }
    }

    private func armSilenceTimer() {
        silenceTimer?.cancel()
        // Allow longer before the first word than between words.
        let wait = transcript.isEmpty ? 5.0 : silenceSeconds
        silenceTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    private func updateLevel(_ rms: Float) {
        // -50 dB … -10 dB → 0…1, smoothed.
        let db = 20 * log10(max(Double(rms), 1e-6))
        let target = min(max((db + 50) / 40, 0), 1)
        level = level * 0.7 + target * 0.3
    }

    nonisolated private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<n { sum += data[i] * data[i] }
        return (sum / Float(n)).squareRoot()
    }

    private static func authorize() async -> Bool {
        let speech: Bool = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}
