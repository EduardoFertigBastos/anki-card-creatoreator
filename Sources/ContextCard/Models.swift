import Foundation

struct CardDraft: Equatable {
    var sentence: String = ""
    var keyword: String = ""
    var translation: String = ""
    var keywordMeaning: String = ""
    var audioFileURL: URL?

    var hasContent: Bool {
        !sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct TranslationResult: Equatable {
    let sentenceTranslation: String
    let keywordMeaning: String
}

struct WordToken: Identifiable, Equatable {
    let id: Int
    let text: String
    let range: Range<String.Index>
}

enum CardComposerError: LocalizedError {
    case missingSentence
    case missingKeyword
    case translationUnavailable
    case translationFailed(String)
    case audioGenerationFailed(String)
    case ankiUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .missingSentence:
            return "Enter an English sentence first."
        case .missingKeyword:
            return "Choose the word you want to learn."
        case .translationUnavailable:
            return "Translation is not configured yet. You can still edit the Portuguese fields manually."
        case let .translationFailed(message):
            return message
        case let .audioGenerationFailed(message), let .ankiUnavailable(message):
            return message
        }
    }
}
