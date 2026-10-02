import UIKit

/// Production Groq vision client for full-plate macro estimation.
///
/// This is a ground-up rebuild of the old in-view networking. The old code
/// hardcoded a single model (`meta-llama/llama-4-scout-17b-16e-instruct`) which
/// Groq decommissioned on 2026-06-17 — after that date every scan failed with a
/// 404 and there was no recovery path. The design goals here directly answer
/// that failure mode:
///
///  • **Model resilience.** We try a prioritised list of current vision models
///    and automatically advance past any that Groq has retired, so a future
///    model rotation degrades to "use the next model", never to a dead feature.
///  • **Strict JSON.** We request `response_format: json_object` and parse
///    defensively, so a chatty model can't break logging.
///  • **Bounded, retried I/O.** Transient 429/5xx get a short backoff-and-retry;
///    everything maps to a precise `MealScanError` the UI can act on.
///  • **Size-safe uploads** via `MealImageProcessor`.
struct GroqMealAnalyzer {

    /// Prioritised Groq vision models (as of 2026-09). The first that responds
    /// wins; a decommissioned/unknown model is skipped automatically. Ordered
    /// smaller-first for latency on the free tier. Editing this list is the only
    /// change needed when Groq's lineup shifts again.
    static let candidateModels: [String] = [
        "qwen/qwen3.6-27b",
        "qwen/qwen3.8-27b"
    ]

    private let endpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
    private let session: URLSession
    private let models: [String]

    init(session: URLSession? = nil, models: [String] = GroqMealAnalyzer.candidateModels) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 45
            config.waitsForConnectivity = false
            self.session = URLSession(configuration: config)
        }
        self.models = models
    }

    /// Analyzes a meal photo. Throws a `MealScanError` on any failure so the
    /// orchestrator can decide whether to surface it or fall back.
    /// - Parameters:
    ///   - prepared: an already size-normalised image; pass one to avoid
    ///     re-encoding when the caller has computed it. When `nil`, we prepare it.
    ///   - learnedHints: few-shot guidance distilled from the user's past
    ///     corrections, injected so the model learns from prior mistakes.
    func analyze(_ image: UIImage,
                 apiKey: String,
                 prepared preparedImage: MealImageProcessor.Prepared? = nil,
                 learnedHints: String? = nil) async throws -> MealAnalysis {
        try await run(image: image,
                      apiKey: apiKey,
                      prepared: preparedImage,
                      learnedHints: learnedHints,
                      refinement: nil)
    }

    /// Re-estimates the SAME photo after a natural-language correction from the
    /// user (e.g. "it's egg fried rice, I added 4 eggs"). The model sees the
    /// image, its previous estimate, and the user's note, and returns corrected
    /// totals — so the user can teach it in plain words instead of typing macros.
    func refine(_ image: UIImage,
                apiKey: String,
                previous: MealAnalysis,
                feedback: String,
                prepared preparedImage: MealImageProcessor.Prepared? = nil,
                learnedHints: String? = nil) async throws -> MealAnalysis {
        let note = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else { return previous }
        return try await run(image: image,
                             apiKey: apiKey,
                             prepared: preparedImage,
                             learnedHints: learnedHints,
                             refinement: Refinement(previousSummary: Self.summary(of: previous),
                                                    feedback: note))
    }

    /// Shared model loop with automatic fallback across candidate models.
    private func run(image: UIImage,
                     apiKey: String,
                     prepared preparedImage: MealImageProcessor.Prepared?,
                     learnedHints: String?,
                     refinement: Refinement?) async throws -> MealAnalysis {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw MealScanError.missingKey }

        guard let prepared = preparedImage ?? MealImageProcessor.prepare(image) else {
            throw MealScanError.imageEncodingFailed
        }

        var lastRecoverable: MealScanError = .noModelAvailable

        for model in models {
            do {
                let content = try await requestCompletion(model: model,
                                                          dataURL: prepared.dataURL,
                                                          apiKey: key,
                                                          learnedHints: learnedHints,
                                                          refinement: refinement)
                return try decodeAnalysis(from: content)
            } catch let error as MealScanError {
                switch error {
                case .authFailed, .rateLimited:
                    // Not the model's fault — stop and surface immediately.
                    throw error
                case .noModelAvailable, .badResponse, .server:
                    // This model is gone or misbehaving — try the next candidate.
                    lastRecoverable = error
                    continue
                default:
                    throw error
                }
            }
        }

        throw lastRecoverable
    }

    /// A user correction to fold into a re-estimate.
    struct Refinement {
        let previousSummary: String
        let feedback: String
    }

    // MARK: - Networking

    private func requestCompletion(model: String,
                                   dataURL: String,
                                   apiKey: String,
                                   learnedHints: String?,
                                   refinement: Refinement?) async throws -> String {
        let body = try makeRequestBody(model: model,
                                       dataURL: dataURL,
                                       learnedHints: learnedHints,
                                       refinement: refinement)

        // One retry for transient conditions (429 / 5xx / network blips).
        var attempt = 0
        let maxAttempts = 2

        while true {
            attempt += 1
            do {
                let (data, response) = try await performRequest(body: body, apiKey: apiKey)
                guard let http = response as? HTTPURLResponse else {
                    throw MealScanError.badResponse
                }

                switch http.statusCode {
                case 200..<300:
                    return try extractContent(from: data)
                case 401, 403:
                    throw MealScanError.authFailed
                case 429:
                    if attempt < maxAttempts { try await backoff(attempt); continue }
                    throw MealScanError.rateLimited
                case 400, 404, 422:
                    // Almost always a decommissioned/unknown model for this key.
                    throw MealScanError.noModelAvailable
                case 500..<600:
                    if attempt < maxAttempts { try await backoff(attempt); continue }
                    throw MealScanError.server(http.statusCode)
                default:
                    throw MealScanError.server(http.statusCode)
                }
            } catch let error as MealScanError {
                throw error
            } catch is CancellationError {
                throw MealScanError.cancelled
            } catch let urlError as URLError where urlError.code == .cancelled {
                throw MealScanError.cancelled
            } catch {
                // Transport-level failure (offline, timeout, DNS).
                if attempt < maxAttempts { try await backoff(attempt); continue }
                throw MealScanError.network(error.localizedDescription)
            }
        }
    }

    private func performRequest(body: Data, apiKey: String) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return try await session.data(for: request)
    }

    private func backoff(_ attempt: Int) async throws {
        // 0.6s, then 1.4s.
        let seconds = attempt == 1 ? 0.6 : 1.4
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    // MARK: - Request body

    private func makeRequestBody(model: String,
                                 dataURL: String,
                                 learnedHints: String?,
                                 refinement: Refinement?) throws -> Data {
        var systemContent = Self.systemPrompt
        if let learnedHints, !learnedHints.isEmpty {
            systemContent += "\n\n" + learnedHints
        }

        let userText: String
        if let refinement {
            userText = Self.refinementPrompt(previousSummary: refinement.previousSummary,
                                             feedback: refinement.feedback)
        } else {
            userText = Self.userPrompt
        }

        let payload: [String: Any] = [
            "model": model,
            "temperature": 0.2,
            "max_tokens": 900,
            "response_format": ["type": "json_object"],
            "messages": [
                [
                    "role": "system",
                    "content": systemContent
                ],
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": userText],
                        ["type": "image_url", "image_url": ["url": dataURL]]
                    ]
                ]
            ]
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    static let systemPrompt = """
    You are a meticulous nutrition estimation engine. You analyse a single photo \
    of a meal and estimate its nutrition. You always reply with a single JSON \
    object and nothing else — no prose, no markdown fences.
    """

    /// The JSON contract, shared by the initial estimate and the refinement.
    static let schemaBlock = """
    Respond with ONLY this JSON shape:
    {
      "name": "short descriptive name of the whole meal",
      "servingSize": "the portion shown, e.g. 1 plate",
      "calories": <total kcal, number>,
      "protein": <total grams, number>,
      "carbs": <total grams, number>,
      "fat": <total grams, number>,
      "items": [
        { "name": "component", "calories": <number>, "protein": <number>, "carbs": <number>, "fat": <number> }
      ]
    }

    Rules:
    - All macro values are grams, numbers only (no units, no ranges).
    - If unsure, give your best single realistic estimate rather than 0.
    - "items" may be empty if the meal is a single food.
    """

    static let userPrompt = """
    Estimate the nutrition for the ENTIRE plate in this photo. Identify each \
    distinct component (e.g. rice, grilled chicken, salad) and estimate its \
    calories and macros for the visible portion, then provide plate totals.

    \(schemaBlock)
    """

    /// Prompt for a user-driven correction pass.
    static func refinementPrompt(previousSummary: String, feedback: String) -> String {
        """
        You previously estimated this meal as:
        \(previousSummary)

        The user is correcting you. Their exact words:
        "\(feedback)"

        Re-examine the SAME photo and produce a CORRECTED estimate. Apply the \
        user's correction faithfully: honour the dish name they give, and if they \
        mention ingredients or quantities (e.g. "I added 4 eggs", "2 cups of rice", \
        "300g chicken"), add or adjust the corresponding items and recompute the \
        totals accordingly. Keep everything they didn't mention consistent with \
        the photo.

        \(schemaBlock)
        """
    }

    /// Compact one-line summary of a prior estimate, fed back into a refinement.
    static func summary(of analysis: MealAnalysis) -> String {
        let items = analysis.components.isEmpty
            ? ""
            : " Items: " + analysis.components.map { "\($0.name) (\(Int($0.calories))kcal)" }.joined(separator: ", ") + "."
        return "\(analysis.name) — \(analysis.servingSize), \(Int(analysis.calories)) kcal, " +
               "P\(Int(analysis.protein))/C\(Int(analysis.carbs))/F\(Int(analysis.fat)).\(items)"
    }

    // MARK: - Parsing

    private struct ChatResponse: Decodable {
        struct Choice: Decodable { let message: Message }
        struct Message: Decodable { let content: String }
        let choices: [Choice]
    }

    private struct Payload: Decodable {
        let name: String?
        let servingSize: String?
        let calories: Double?
        let protein: Double?
        let carbs: Double?
        let fat: Double?
        let items: [Item]?

        struct Item: Decodable {
            let name: String?
            let calories: Double?
            let protein: Double?
            let carbs: Double?
            let fat: Double?
        }
    }

    private func extractContent(from data: Data) throws -> String {
        guard let decoded = try? JSONDecoder().decode(ChatResponse.self, from: data),
              let content = decoded.choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MealScanError.badResponse
        }
        return content
    }

    private func decodeAnalysis(from content: String) throws -> MealAnalysis {
        let json = Self.isolateJSONObject(content)
        guard let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw MealScanError.badResponse
        }

        let components: [MealAnalysis.Component] = (payload.items ?? []).compactMap { item in
            guard let name = item.name, !name.isEmpty else { return nil }
            return MealAnalysis.Component(
                name: name,
                calories: max(0, item.calories ?? 0),
                protein: max(0, item.protein ?? 0),
                carbs: max(0, item.carbs ?? 0),
                fat: max(0, item.fat ?? 0)
            )
        }

        // Prefer explicit totals; if the model only itemised, sum the items.
        let calories = payload.calories ?? components.reduce(0) { $0 + $1.calories }
        let protein = payload.protein ?? components.reduce(0) { $0 + $1.protein }
        let carbs = payload.carbs ?? components.reduce(0) { $0 + $1.carbs }
        let fat = payload.fat ?? components.reduce(0) { $0 + $1.fat }

        let analysis = MealAnalysis(
            name: payload.name?.isEmpty == false ? payload.name! : "Meal",
            calories: max(0, calories),
            protein: max(0, protein),
            carbs: max(0, carbs),
            fat: max(0, fat),
            servingSize: payload.servingSize?.isEmpty == false ? payload.servingSize! : "1 plate",
            confidence: 0.9,
            source: .groq,
            components: components
        )

        guard !analysis.isEmpty else { throw MealScanError.badResponse }
        return analysis
    }

    /// Pulls the first balanced `{...}` JSON object out of arbitrary model text,
    /// tolerating stray prose or code fences even though we ask for pure JSON.
    static func isolateJSONObject(_ text: String) -> String {
        var stripped = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped.hasPrefix("```") {
            stripped = stripped
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let start = stripped.firstIndex(of: "{") else { return stripped }
        var depth = 0
        var index = start
        while index < stripped.endIndex {
            let ch = stripped[index]
            if ch == "{" { depth += 1 }
            else if ch == "}" {
                depth -= 1
                if depth == 0 {
                    return String(stripped[start...index])
                }
            }
            index = stripped.index(after: index)
        }
        return String(stripped[start...])
    }
}
