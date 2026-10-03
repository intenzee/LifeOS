import Foundation
import LifeOSCore

/// One-time move of the meal scanner's corrections from the app's
/// `meal_corrections.json` (Application Support) into the store (FOOD-14).
///
/// Lossless: records decode with the same field names and keep their ids. The
/// old file is renamed, not deleted, so a bad migration can be redone by hand.
/// An unreadable file is left where it is and nothing is written.
public enum CorrectionMigrator {
    public enum Outcome: Equatable, Sendable {
        /// The store already had the document (a previous run).
        case alreadyMigrated
        case noLegacyFile
        case migrated(count: Int)
        case unreadable
    }

    public static let legacyFilename = "meal_corrections.json"
    public static let migratedFilename = "meal_corrections.migrated.json"

    public static func legacyURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(legacyFilename)
    }

    @discardableResult
    public static func run(legacyFile url: URL?, into repository: any MealCorrectionRepository) async throws
        -> Outcome {
        let fileManager = FileManager.default
        if try await repository.exists() {
            // Saved but not yet renamed (interrupted run): the store already holds it.
            if let url, fileManager.fileExists(atPath: url.path) { retire(url) }
            return .alreadyMigrated
        }
        guard let url, let data = fileManager.contents(atPath: url.path) else { return .noLegacyFile }
        guard let corrections = try? JSONDecoder().decode([MealCorrection].self, from: data) else {
            return .unreadable
        }
        try await repository.save(CorrectionLibrary(corrections: corrections))
        retire(url)
        return .migrated(count: corrections.count)
    }

    private static func retire(_ url: URL) {
        let target = url.deletingLastPathComponent().appendingPathComponent(migratedFilename)
        try? FileManager.default.removeItem(at: target)
        try? FileManager.default.moveItem(at: url, to: target)
    }
}
