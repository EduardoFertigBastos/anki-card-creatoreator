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
    @Published var offlineFeedback: String?
    @Published private(set) var offlineSaveCooldownRemaining = 0
    @Published var apiEndpoint = UserDefaults.standard.string(forKey: "translation.endpoint") ?? Environment.value(for: "OPENAI_API_ENDPOINT") ?? "https://api.openai.com/v1/chat/completions"
    @Published var modelName = UserDefaults.standard.string(forKey: "translation.model") ?? Environment.value(for: "OPENAI_MODEL") ?? "gpt-4o-mini"
    @Published var apiKey: String
    @Published var selectedCollection = Collections.defaultCollection
    @Published private(set) var pendingCards: [QueuedCard]
    @Published private(set) var errorCards: [QueuedCard]

    private let fallbackTranslationService: TranslationService
    private let speechService = LocalSpeechService()
    private let ankiService = AnkiService()
    private let keychainStore = KeychainStore()
    private let queueStore = CardQueueStore()
    private let imageOCRService = ImageOCRService()
    let voiceInputService = VoiceTranscriptionService()

    init(translationService: TranslationService = DraftTranslationService()) {
        var resolvedAPIKey = KeychainStore().readAPIKey()
        if resolvedAPIKey.isEmpty {
            resolvedAPIKey = Environment.value(for: "OPENAI_API_KEY") ?? ""
        }
        self.fallbackTranslationService = translationService
        self.apiKey = resolvedAPIKey
        self.pendingCards = CardQueueStore().loadPending()
        self.errorCards = CardQueueStore().loadErrors()
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

    func extractTextFromImage(_ url: URL) {
        isGenerating = true
        statusMessage = nil
        errorMessage = nil

        Task {
            do {
                let extractedText = try imageOCRService.extractEnglishText(from: url)
                sentence = extractedText
                selectedTokenIDs.removeAll()
                translation = ""
                keywordMeaning = ""
                audioFileURL = nil
                statusMessage = "Text extracted from the image. Choose the keyword to continue."
            } catch {
                errorMessage = error.localizedDescription
            }
            isGenerating = false
        }
    }

    func extractTextFromImage(_ image: NSImage) {
        isGenerating = true
        statusMessage = nil
        errorMessage = nil

        Task {
            do {
                let extractedText = try imageOCRService.extractEnglishText(from: image)
                sentence = extractedText
                selectedTokenIDs.removeAll()
                translation = ""
                keywordMeaning = ""
                audioFileURL = nil
                statusMessage = "Text extracted from the pasted image. Choose the keyword to continue."
            } catch {
                errorMessage = error.localizedDescription
            }
            isGenerating = false
        }
    }

    func saveOffline() {
        guard offlineSaveCooldownRemaining == 0 else { return }
        guard draft.hasContent, !translation.isEmpty, audioFileURL != nil else {
            errorMessage = "Generate a complete card before saving it offline."
            return
        }
        do {
            let fingerprint = "\(selectedCollection.lowercased())|\(sentence.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(selectedKeyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
            if pendingCards.contains(where: { $0.fingerprint == fingerprint }) || errorCards.contains(where: { $0.fingerprint == fingerprint }) {
                errorMessage = "Oh man, this card is already in the offline queue."
                offlineFeedback = "This card is already queued."
                return
            }
            let card = try QueuedCard(draft: draft, deckName: selectedCollection)
            pendingCards.append(card)
            try queueStore.savePending(pendingCards)
            offlineFeedback = "Card saved offline. It is waiting to be synced to Anki."
            statusMessage = "Card added to the offline queue."
            startOfflineSaveCooldown()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startOfflineSaveCooldown() {
        offlineSaveCooldownRemaining = 3
        Task {
            for remaining in stride(from: 3, through: 1, by: -1) {
                offlineSaveCooldownRemaining = remaining
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            offlineSaveCooldownRemaining = 0
        }
    }

    func syncPendingCards() {
        guard !pendingCards.isEmpty else {
            statusMessage = "The offline queue is empty."
            return
        }
        isGenerating = true
        statusMessage = nil
        errorMessage = nil

        Task {
            do {
                try await ankiService.checkConnection()
                let remaining: [QueuedCard] = []
                var failed: [QueuedCard] = []
                for var card in pendingCards {
                    do {
                        try await ankiService.createNote(from: card.draft, deckName: card.deckName)
                    } catch {
                        card.lastError = error.localizedDescription
                        failed.append(card)
                    }
                }
                pendingCards = remaining
                errorCards.append(contentsOf: failed)
                try queueStore.savePending(pendingCards)
                try queueStore.saveErrors(errorCards)
                statusMessage = failed.isEmpty ? "Offline queue synced to Anki." : "Queue synced with \(failed.count) card error(s)."
            } catch {
                errorMessage = "Anki is not available. Open Anki with AnkiConnect enabled, then try syncing again."
            }
            isGenerating = false
        }
    }

    func retryErrorCards() {
        guard !errorCards.isEmpty else {
            statusMessage = "The error queue is empty."
            return
        }
        isGenerating = true
        statusMessage = nil
        errorMessage = nil

        Task {
            do {
                try await ankiService.checkConnection()
                var remaining: [QueuedCard] = []
                for var card in errorCards {
                    do {
                        try await ankiService.createNote(from: card.draft, deckName: card.deckName)
                    } catch {
                        card.lastError = error.localizedDescription
                        remaining.append(card)
                    }
                }
                errorCards = remaining
                try queueStore.saveErrors(errorCards)
                statusMessage = remaining.isEmpty ? "Error queue cleared." : "Some cards still need attention."
            } catch {
                errorMessage = "Anki is not available. Open Anki with AnkiConnect enabled, then try again."
            }
            isGenerating = false
        }
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
