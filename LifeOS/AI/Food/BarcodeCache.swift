import Foundation

/// Offline cache of barcode lookups (F04 §4.4, ticket AI-146): a product found
/// once on OpenFoodFacts resolves instantly — and offline — every time after.
actor BarcodeCache {
    nonisolated struct Product: Codable, Sendable, Hashable {
        var name: String
        var per100g: Macros
        var servingDescription: String
        var cachedAt: Date
    }

    static let shared = BarcodeCache(url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first?.appendingPathComponent("AI/barcode-cache.json"))

    private let url: URL?
    private let capacity: Int
    private var products: [String: Product] = [:]
    private var loaded = false

    init(url: URL?, capacity: Int = 2_000) {
        self.url = url
        self.capacity = capacity
    }

    func product(for barcode: String) -> Product? {
        loadIfNeeded()
        return products[Self.key(barcode)]
    }

    func store(_ product: Product, for barcode: String) {
        loadIfNeeded()
        products[Self.key(barcode)] = product
        if products.count > capacity, let oldest = products.min(by: { $0.value.cachedAt < $1.value.cachedAt })?.key {
            products[oldest] = nil
        }
        guard let url, let data = try? JSONEncoder().encode(products) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    var count: Int {
        loadIfNeeded()
        return products.count
    }

    /// EAN-13 and UPC-A are the same product with or without the leading zero.
    static func key(_ barcode: String) -> String {
        let digits = barcode.filter(\.isNumber)
        return digits.count == 13 && digits.hasPrefix("0") ? String(digits.dropFirst()) : digits
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let url, let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: Product].self, from: data) else { return }
        products = decoded
    }
}
