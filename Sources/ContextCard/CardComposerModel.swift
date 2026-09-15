import AppKit
import Foundation

@MainActor
final class CardComposerModel: ObservableObject {
    @Published var sentence = ""
    @Published var selectedKeyword = ""
    @Published var translation = ""
    @Published var keywordMeaning = ""
    @Published var audioFileURL: URL?
    @Published var isGenerating = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?
    @Published var apiEndpoint = UserDefaults.standard.string(forKey: "translation.endpoint") ?? "https://api.openai.com/v1/chat/completions"
    @Published var modelName = UserDefaults.standard.string(forKey: "translation.model") ?? "gpt-4o-mini"
    @Published var apiKey: String

    private let fallbackTranslationService: TranslationService
    private let speechService = LocalSpeechService()
    private let ankiService = AnkiService()
    private let keychainStore = KeychainStore()

    init(translationService: TranslationService = DraftTranslationService()) {
        self.fallbackTranslationService = translationService
        self.apiKey = KeychainStore().readAPIKey()
    }

    var tokens: [WordToken] { TextProcessing.tokens(in: sentence) }

    var canGenerate: Bool {
        !sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !selectedKeyword.isEmpty
    }

    var draft: CardDraft {
        CardDraft(sentence: sentence, keyword: selectedKeyword, translation: translation, keywordMeaning: keywordMeaning, audioFileURL: audioFileURL)
    }

    func select(keyword: String) {
        selectedKeyword = keyword
        errorMessage = nil
    }

    func generateDraft() {
        guard !sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = CardComposerError.missingSentence.localizedDescription
            return
        }
        guard !selectedKeyword.isEmpty else {
            errorMessage = CardComposerError.missingKeyword.localizedDescription
            return
        }

        isGenerating = true
        statusMessage = nil
        errorMessage = nil

        Task {
            do {
                let result = try await makeTranslationService().translate(sentence: sentence, keyword: selectedKeyword)
                translation = result.sentenceTranslation
                keywordMeaning = result.keywordMeaning
                audioFileURL = try await speechService.generateAudio(for: sentence)
                statusMessage = apiKey.isEmpty ? "Draft ready in local demo mode. Add an API key in Settings for real translation." : "Draft ready. Review the fields before exporting."
            } catch {
                errorMessage = error.localizedDescription
            }
            isGenerating = false
        }
    }

    func sendToAnki() {
        guard draft.hasContent else {
            errorMessage = CardComposerError.missingSentence.localizedDescription
            return
        }

        isGenerating = true
        statusMessage = nil
        errorMessage = nil

        Task {
            do {
                try await ankiService.createNote(from: draft)
                statusMessage = "Card sent to Anki."
            } catch {
                errorMessage = error.localizedDescription
            }
            isGenerating = false
        }
    }

    func copyForAnki() {
        let front = TextProcessing.highlightedHTML(sentence: sentence, keyword: selectedKeyword)
        let back = "<p>\(TextProcessing.escapeHTML(translation))</p><p><b>\(TextProcessing.escapeHTML(selectedKeyword))</b>: \(TextProcessing.escapeHTML(keywordMeaning))</p>"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("Front:\n\(front)\n\nBack:\n\(back)", forType: .string)
        statusMessage = "Card HTML copied to the clipboard."
    }

    func reset() {
        sentence = ""
        selectedKeyword = ""
        translation = ""
        keywordMeaning = ""
        audioFileURL = nil
        statusMessage = nil
        errorMessage = nil
    }

    func saveSettings() {
        UserDefaults.standard.set(apiEndpoint, forKey: "translation.endpoint")
        UserDefaults.standard.set(modelName, forKey: "translation.model")
        do {
            try keychainStore.saveAPIKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
            statusMessage = "Settings saved securely."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func makeTranslationService() -> TranslationService {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let endpoint = URL(string: apiEndpoint), endpoint.scheme != nil else {
            return fallbackTranslationService
        }
        return OpenAICompatibleTranslationService(endpoint: endpoint, model: modelName, apiKey: apiKey)
    }
}
