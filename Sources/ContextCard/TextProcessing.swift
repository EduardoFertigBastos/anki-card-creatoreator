import Foundation

enum TextProcessing {
    static func tokens(in sentence: String) -> [WordToken] {
        var result: [WordToken] = []
        var currentStart: String.Index?
        var nextID = 0

        for index in sentence.indices {
            let character = sentence[index]
            let isWordCharacter = character.isLetter || character.isNumber || character == "'"

            if isWordCharacter {
                currentStart = currentStart ?? index
            } else if let start = currentStart {
                result.append(WordToken(id: nextID, text: String(sentence[start..<index]), range: start..<index))
                nextID += 1
                currentStart = nil
            }
        }

        if let start = currentStart {
            result.append(WordToken(id: nextID, text: String(sentence[start..<sentence.endIndex]), range: start..<sentence.endIndex))
        }

        return result
    }

    static func highlightedHTML(sentence: String, keyword: String) -> String {
        let escapedSentence = escapeHTML(sentence)
        let escapedKeyword = escapeHTML(keyword)
        guard !escapedKeyword.isEmpty else { return escapedSentence }

        return escapedSentence.replacingOccurrences(
            of: escapedKeyword,
            with: "<b>\(escapedKeyword)</b>",
            options: [.caseInsensitive, .literal]
        )
    }

    static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
