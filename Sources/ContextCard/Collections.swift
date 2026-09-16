import Foundation
import Combine

enum Collections {
    // Kept as a source-compatible fallback for tests and older integrations.
    static let available = ["Anki Create English"]
    static let defaultCollection = available[0]
}

@MainActor
final class CollectionStore: ObservableObject {
    static let shared = CollectionStore()

    private static let userDefaultsKey = "anki.collections"
    private static let initialCollections = Collections.available

    @Published private(set) var collections: [String]

    private init(userDefaults: UserDefaults = .standard) {
        let savedCollections = userDefaults.stringArray(forKey: Self.userDefaultsKey) ?? []
        collections = Self.normalized(savedCollections.isEmpty ? Self.initialCollections : savedCollections)
    }

    @discardableResult
    func add(_ name: String) -> Bool {
        let normalizedName = Self.normalizedName(name)
        guard !normalizedName.isEmpty,
              !collections.contains(where: { $0.caseInsensitiveCompare(normalizedName) == .orderedSame }) else {
            return false
        }
        collections.append(normalizedName)
        persist()
        return true
    }

    @discardableResult
    func rename(_ oldName: String, to newName: String) -> Bool {
        let normalizedName = Self.normalizedName(newName)
        guard let index = collections.firstIndex(of: oldName),
              !normalizedName.isEmpty,
              !collections.enumerated().contains(where: { $0.offset != index && $0.element.caseInsensitiveCompare(normalizedName) == .orderedSame }) else {
            return false
        }
        collections[index] = normalizedName
        persist()
        return true
    }

    @discardableResult
    func remove(_ name: String) -> Bool {
        guard collections.count > 1, let index = collections.firstIndex(of: name) else { return false }
        collections.remove(at: index)
        persist()
        return true
    }

    private func persist() {
        UserDefaults.standard.set(collections, forKey: Self.userDefaultsKey)
    }

    private static func normalized(_ values: [String]) -> [String] {
        var result: [String] = []
        for value in values {
            let name = normalizedName(value)
            guard !name.isEmpty, !result.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { continue }
            result.append(name)
        }
        return result.isEmpty ? initialCollections : result
    }

    private static func normalizedName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
