import AppKit
import Foundation

@MainActor
final class CardComposerModel: ObservableObject {
    @Published var sentence = ""
    @Published var selectedTokenIDs: Set<Int> = []
    @Published var translation = ""
    @Published var keywordMeaning = ""
    @Published var audioFileURL: URL?
    @Published var isGenerating = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?
    @Published var apiEndpoint = UserDefaults.standard.string(forKey: "translation.endpoint") ?? Environment.value(for: "OPENAI_API_ENDPOINT") ?? "https://api.openai.com/v1/chat/completions"
    @Published var modelName = UserDefaults.standard.string(forKey: "translation.model") ?? Environment.value(for: "OPENAI_MODEL") ?? "gpt-4o-mini"
    @Published var apiKey: String
    @Published var selectedCollection = Collections.defaultCollection

    private let fallbackTranslationService: TranslationService
    private let speechService = LocalSpeechService()
    private let ankiService = AnkiService()
    private let keychainStore = KeychainStore()
    let voiceInputService = VoiceTranscriptionService()

    init(translationService: TranslationService = DraftTranslationService()) {
        self.fallbackTranslationService = translationService
        self.apiKey = KeychainStore().readAPIKey()
        if self.apiKey.isEmpty {
            self.apiKey = Environment.value(for: "OPENAI_API_KEY") ?? ""
        }
    }

    var tokens: [WordToken] { TextProcessing.tokens(in: sentence) }

    var selectedKeyword: String {
        tokens
            .filter { selectedTokenIDs.contains($0.id) }
            .map(\.text)
            .joined(separator: " ")
    }

    var canGenerate: Bool {
        !sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !selectedKeyword.isEmpty
    }

    var draft: CardDraft {
        CardDraft(sentence: sentence, keyword: selectedKeyword, translation: translation, keywordMeaning: keywordMeaning, audioFileURL: audioFileURL)
    }

    func toggleKeyword(tokenID: Int) {
        if selectedTokenIDs.contains(tokenID) {
            selectedTokenIDs.remove(tokenID)
        } else {
            selectedTokenIDs.insert(tokenID)
        }
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
                try await ankiService.createNote(from: draft, deckName: selectedCollection)
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
        selectedTokenIDs.removeAll()
        translation = ""
        keywordMeaning = ""
        audioFileURL = nil
        statusMessage = nil
        errorMessage = nil
    }

    func beginVoiceInput() {
        Task {
            do {
                try await voiceInputService.start()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func stopVoiceInput() {
        voiceInputService.stop()
    }

    func useVoiceTranscript() {
        let value = voiceInputService.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        sentence = value
        selectedTokenIDs.removeAll()
        translation = ""
        keywordMeaning = ""
        audioFileURL = nil
        statusMessage = "Transcript added. Choose the keyword to continue."
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
