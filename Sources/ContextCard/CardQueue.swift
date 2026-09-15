import Foundation

struct QueuedCard: Codable, Equatable, Identifiable {
    let id: UUID
    var sentence: String
    var keyword: String
    var translation: String
    var keywordMeaning: String
    let audioFilename: String
    var deckName: String
    let createdAt: Date
    var lastError: String?

    var audioFileURL: URL {
        CardQueueStore.audioDirectory.appendingPathComponent(audioFilename)
    }

    var draft: CardDraft {
        CardDraft(sentence: sentence, keyword: keyword, translation: translation, keywordMeaning: keywordMeaning, audioFileURL: audioFileURL)
    }

    var fingerprint: String {
        "\(deckName.lowercased())|\(sentence.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    init(draft: CardDraft, deckName: String) throws {
        guard let sourceAudioURL = draft.audioFileURL else {
            throw CardComposerError.audioGenerationFailed("Generate audio before saving the card offline.")
        }

        id = UUID()
        sentence = draft.sentence
        keyword = draft.keyword
        translation = draft.translation
        keywordMeaning = draft.keywordMeaning
        audioFilename = "\(id.uuidString).\(sourceAudioURL.pathExtension.isEmpty ? "aiff" : sourceAudioURL.pathExtension)"
        self.deckName = deckName
        createdAt = Date()
        lastError = nil

        try FileManager.default.createDirectory(at: CardQueueStore.audioDirectory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: sourceAudioURL, to: audioFileURL)
    }
}

struct CardQueueStore {
    private static let directoryName = "ContextCard"
    static let applicationDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(directoryName, isDirectory: true)
    static let audioDirectory = applicationDirectory.appendingPathComponent("audio", isDirectory: true)

    private let pendingURL = applicationDirectory.appendingPathComponent("pending.json")
    private let errorURL = applicationDirectory.appendingPathComponent("errors.json")

    func loadPending() -> [QueuedCard] {
        load(from: pendingURL)
    }

    func loadErrors() -> [QueuedCard] {
        load(from: errorURL)
    }

    func savePending(_ cards: [QueuedCard]) throws {
        try save(cards, to: pendingURL)
    }

    func saveErrors(_ cards: [QueuedCard]) throws {
        try save(cards, to: errorURL)
    }

    private func load(from url: URL) -> [QueuedCard] {
        guard let data = try? Data(contentsOf: url),
              let cards = try? JSONDecoder().decode([QueuedCard].self, from: data) else { return [] }
        return cards
    }

    private func save(_ cards: [QueuedCard], to url: URL) throws {
        try FileManager.default.createDirectory(at: Self.applicationDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(cards).write(to: url, options: .atomic)
    }
}
