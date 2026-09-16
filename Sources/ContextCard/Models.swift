import Foundation

struct CardDraft: Equatable {
    var sentence: String = ""
    var keyword: String = ""
    var keywordTranslation: String = ""
    var translation: String = ""
    var keywordMeaning: String = ""
    var audioFileURL: URL?
    var frontHTML: String?

    var hasContent: Bool {
        !sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var backHTML: String {
        let highlightedTranslation = TextProcessing.highlightedHTML(sentence: translation, keyword: keywordTranslation)
        return "<p>\(highlightedTranslation)</p><p><b>\(TextProcessing.escapeHTML(keyword))</b>: \(TextProcessing.escapeHTML(cleanKeywordMeaning))</p>"
    }

    private var cleanKeywordMeaning: String {
        let trimmedMeaning = keywordMeaning.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKeywordTranslation = keywordTranslation.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedKeywordTranslation.isEmpty else { return trimmedMeaning }

        let separators = [":", "-", "–", "—"]
        for separator in separators {
            let prefix = "\(trimmedKeywordTranslation)\(separator)"
            if trimmedMeaning.range(of: prefix, options: [.caseInsensitive, .anchored]) != nil {
                return String(trimmedMeaning.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return trimmedMeaning
    }
}

struct TranslationResult: Equatable {
    let sentenceTranslation: String
    let keywordTranslation: String
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
    case microphonePermissionDenied
    case speechRecognitionPermissionDenied
    case imageOCRFailed(String)
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
        case .microphonePermissionDenied:
            return "Microphone access is disabled. Enable it for ContextCard in System Settings > Privacy & Security > Microphone."
        case .speechRecognitionPermissionDenied:
            return "Speech recognition access is disabled. Enable it for ContextCard in System Settings > Privacy & Security > Speech Recognition."
        case let .imageOCRFailed(message):
            return message
        case let .audioGenerationFailed(message), let .ankiUnavailable(message):
            return message
        }
    }
}
