import Foundation
import Security

protocol TranslationService {
    func translate(sentence: String, keyword: String) async throws -> TranslationResult
}

struct OpenAICompatibleTranslationService: TranslationService {
    let endpoint: URL
    let model: String
    let apiKey: String

    func translate(sentence: String, keyword: String) async throws -> TranslationResult {
        let instructions = """
        Translate an English learning sentence into Brazilian Portuguese. Return only valid JSON with exactly these string fields: sentenceTranslation and keywordMeaning. sentenceTranslation must translate the complete sentence naturally. keywordMeaning must explain the selected English keyword in this context, with a concise Portuguese meaning and no extra commentary. This is for a language-learning card; keep the text natural and neutral, and never imitate or impersonate a character, celebrity, or speaker from the source video.

        English sentence: \(sentence)
        Selected keyword: \(keyword)
        """

        let body: [String: Any] = [
            "model": model,
            "temperature": 0.2,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": "You are a concise English-to-Brazilian-Portuguese language tutor."],
                ["role": "user", "content": instructions]
            ]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
                throw CardComposerError.translationFailed("The translation service returned an error. Check the endpoint, model, and API key in Settings.")
            }

            let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let choices = envelope?["choices"] as? [[String: Any]]
            let message = choices?.first?["message"] as? [String: Any]
            let content = message?["content"] as? String
            guard let content, let contentData = content.data(using: .utf8) else {
                throw CardComposerError.translationFailed("The translation service returned an unexpected response.")
            }

            let result = try JSONDecoder().decode(TranslationResultDTO.self, from: contentData)
            return TranslationResult(sentenceTranslation: result.sentenceTranslation, keywordMeaning: result.keywordMeaning)
        } catch let error as CardComposerError {
            throw error
        } catch {
            throw CardComposerError.translationFailed("Could not complete the translation request. Check your network connection and Settings.")
        }
    }

    private struct TranslationResultDTO: Decodable {
        let sentenceTranslation: String
        let keywordMeaning: String
    }
}

/// A transparent local fallback keeps the workflow testable before an API is configured.
struct DraftTranslationService: TranslationService {
    func translate(sentence: String, keyword: String) async throws -> TranslationResult {
        let commonMeanings: [String: String] = [
            "awkward": "constrangedor / desconfortável",
            "barely": "mal / por pouco",
            "despite": "apesar de",
            "eventually": "eventualmente / no fim",
            "guess": "adivinhar / achar",
            "likely": "provável",
            "meanwhile": "enquanto isso",
            "notice": "perceber / notar",
            "reckon": "achar / considerar",
            "stubborn": "teimoso",
            "though": "embora / mas",
            "unless": "a menos que",
            "willing": "disposto",
            "within": "dentro de / no prazo de"
        ]
        let meaning = commonMeanings[keyword.lowercased()] ?? "Adicione aqui o significado em português."
        return TranslationResult(
            sentenceTranslation: "Adicione aqui a tradução em português.",
            keywordMeaning: meaning
        )
    }
}

struct LocalSpeechService {
    func generateAudio(for text: String) async throws -> URL {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { throw CardComposerError.missingSentence }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ContextCard", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("sentence-\(UUID().uuidString).aiff")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = ["-o", fileURL.path, cleanText]
        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw CardComposerError.audioGenerationFailed("Could not start macOS speech synthesis: \(error.localizedDescription)")
        }

        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: fileURL.path) else {
            let details = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw CardComposerError.audioGenerationFailed("Audio generation failed. \(details)")
        }
        return fileURL
    }
}

struct AnkiService {
    let endpoint = URL(string: "http://127.0.0.1:8765")!

    func createNote(from draft: CardDraft, deckName: String = "ContextCard") async throws {
        guard let audioURL = draft.audioFileURL else {
            throw CardComposerError.ankiUnavailable("Generate audio before sending the card to Anki.")
        }

        let audioData = try Data(contentsOf: audioURL)
        let requestBody: [String: Any] = [
            "action": "addNote",
            "version": 6,
            "params": [
                "note": [
                    "deckName": deckName,
                    "modelName": "Basic",
                    "fields": [
                        "Front": TextProcessing.highlightedHTML(sentence: draft.sentence, keyword: draft.keyword),
                        "Back": "<p>\(TextProcessing.escapeHTML(draft.translation))</p><p><b>\(TextProcessing.escapeHTML(draft.keyword))</b>: \(TextProcessing.escapeHTML(draft.keywordMeaning))</p>"
                    ],
                    "options": ["allowDuplicate": true],
                    "tags": ["contextcard", "english"],
                    "audio": [[
                        "filename": audioURL.lastPathComponent,
                        "data": audioData.base64EncodedString(),
                        "fields": ["Front"]
                    ]]
                ]
            ]
        ]

        _ = try await post(action: "createDeck", params: ["deck": deckName])
        _ = try await post(action: "addNote", params: requestBody["params"] as? [String: Any] ?? [:])
    }

    private func post(action: String, params: [String: Any]) async throws -> Any? {
        let requestBody: [String: Any] = [
            "action": action,
            "version": 6,
            "params": params
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
                throw CardComposerError.ankiUnavailable("AnkiConnect did not respond successfully. Is Anki open with AnkiConnect installed?")
            }

            guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CardComposerError.ankiUnavailable("AnkiConnect returned an invalid response.")
            }
            if let error = result["error"], !(error is NSNull) {
                throw CardComposerError.ankiUnavailable("AnkiConnect: \(String(describing: error))")
            }
            return result["result"]
        } catch let error as CardComposerError {
            throw error
        } catch {
            throw CardComposerError.ankiUnavailable("Could not reach AnkiConnect. Open Anki and check that AnkiConnect is installed.")
        }
    }

}

struct KeychainStore {
    private let service = "com.contextcard.app"
    private let account = "translation-api-key"

    func readAPIKey() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    func saveAPIKey(_ value: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
                throw CardComposerError.translationFailed("Could not store the API key in Keychain.")
            }
        } else if status != errSecSuccess {
            throw CardComposerError.translationFailed("Could not store the API key in Keychain.")
        }
    }
}
