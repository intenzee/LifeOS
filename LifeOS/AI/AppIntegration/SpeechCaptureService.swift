import AVFoundation
import Foundation
import Observation
import Speech

/// Voice capture for food logging (F02 §4.1).
///
/// Uses `SFSpeechRecognizer`, which runs on every supported iPhone — no Apple
/// Intelligence needed — and stays **on-device** whenever the locale supports
/// it. Food names are fed in as contextual strings so "paneer tikka" and
/// "sattu" are recognised. Stops by itself after 1.5 s of silence.
@Observable
final class SpeechCaptureService {
    enum Phase: Equatable {
        case idle, listening, finished
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var transcript = ""
    /// 0…1 microphone level, for the listening animation.
    private(set) var level: Double = 0
    private(set) var isOnDevice = false
    var contextualStrings: [String] = []

    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTask: Task<Void, Never>?
    private var onFinish: ((String) -> Void)?
    /// Audio/recognition threads publish into these; a main-actor task consumes them.
    private var levelContinuation: AsyncStream<Double>.Continuation?
    private var resultContinuation: AsyncStream<RecognitionUpdate>.Continuation?
    private var consumers: [Task<Void, Never>] = []

    private struct RecognitionUpdate: Sendable {
        var text: String?
        var isFinal: Bool
        var failed: Bool
    }

    var isListening: Bool { phase == .listening }

    func start(onFinish: @escaping (String) -> Void) async {
        guard phase != .listening else { return }
        self.onFinish = onFinish
        transcript = ""

        guard await Self.requestSpeechAuthorization() else {
            phase = .failed("Allow speech recognition in Settings to log by voice.")
            return
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            phase = .failed("Allow microphone access in Settings to log by voice.")
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-IN")) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            phase = .failed("Speech recognition isn't available right now. Type instead.")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.contextualStrings = Array(contextualStrings.prefix(100))
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
            isOnDevice = true
        }
        self.request = request

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let (levels, levelSink) = AsyncStream<Double>.makeStream(bufferingPolicy: .bufferingNewest(1))
            levelContinuation = levelSink
            consumers.append(Task { [weak self] in
                for await level in levels { self?.level = level }
            })

            let engine = AVAudioEngine()
            let input = engine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0),
                             block: Self.makeTap(request: request, level: { levelSink.yield($0) }))
            engine.prepare()
            try engine.start()
            audioEngine = engine
        } catch {
            phase = .failed("Couldn't start the microphone.")
            cleanUp()
            return
        }

        phase = .listening
        let (updates, updateSink) = AsyncStream<RecognitionUpdate>.makeStream()
        resultContinuation = updateSink
        consumers.append(Task { [weak self] in
            for await update in updates { self?.handle(text: update.text, isFinal: update.isFinal, failed: update.failed) }
        })
        task = recognizer.recognitionTask(with: request, resultHandler: Self.makeResultHandler { text, isFinal, failed in
            updateSink.yield(RecognitionUpdate(text: text, isFinal: isFinal, failed: failed))
        })
        restartSilenceTimer(initial: true)
    }

    func stop() {
        guard phase == .listening else { return }
        request?.endAudio()
        finish()
    }

    func cancel() {
        onFinish = nil
        task?.cancel()
        cleanUp()
        phase = .idle
    }

    // MARK: - Private

    private func handle(text: String?, isFinal: Bool, failed: Bool) {
        guard phase == .listening else { return }
        if let text, !text.isEmpty {
            transcript = text
            restartSilenceTimer(initial: false)
        }
        if isFinal || failed { finish() }
    }

    private func restartSilenceTimer(initial: Bool) {
        silenceTask?.cancel()
        // Longer grace before the first word; 1.5 s of silence after speech ends it.
        let wait: Duration = initial ? .seconds(6) : .milliseconds(1_500)
        silenceTask = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    private func finish() {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        cleanUp()
        phase = .finished
        let callback = onFinish
        onFinish = nil
        callback?(text)
    }

    private func cleanUp() {
        silenceTask?.cancel()
        silenceTask = nil
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        task?.finish()
        task = nil
        request = nil
        levelContinuation?.finish()
        resultContinuation?.finish()
        levelContinuation = nil
        resultContinuation = nil
        consumers.forEach { $0.cancel() }
        consumers = []
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // These closures run on audio / recognition threads, so they are built in
    // nonisolated contexts and hop to the main actor explicitly.

    private nonisolated static func makeTap(request: SFSpeechAudioBufferRecognitionRequest,
                                            level: @escaping @Sendable (Double) -> Void) -> AVAudioNodeTapBlock {
        { buffer, _ in
            request.append(buffer)
            guard let samples = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            guard count > 0 else { return }
            var sum: Float = 0
            for i in 0..<count { sum += samples[i] * samples[i] }
            let rms = sqrt(sum / Float(count))
            level(Double(min(1, max(0, (20 * log10(max(rms, 1e-6)) + 50) / 50))))
        }
    }

    private nonisolated static func makeResultHandler(
        _ handler: @escaping @Sendable (String?, Bool, Bool) -> Void
    ) -> (SFSpeechRecognitionResult?, (any Error)?) -> Void {
        { result, error in
            handler(result?.bestTranscription.formattedString, result?.isFinal ?? false, error != nil)
        }
    }

    private nonisolated static func requestSpeechAuthorization() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .denied, .restricted: return false
        default:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in continuation.resume(returning: status == .authorized) }
            }
        }
    }
}
