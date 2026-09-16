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
        guard let range = firstTokenPhraseRange(in: sentence, matching: keyword) else {
            return escapeHTML(sentence)
        }

        return highlightedHTML(sentence: sentence, ranges: [range])
    }

    static func firstTokenPhraseRange(in sentence: String, matching keyword: String) -> Range<String.Index>? {
        let keywordTokens = tokens(in: keyword).map { $0.text.lowercased() }
        guard !keywordTokens.isEmpty else { return nil }

        let sentenceTokens = tokens(in: sentence)
        guard sentenceTokens.count >= keywordTokens.count else { return nil }

        let lastStartIndex = sentenceTokens.count - keywordTokens.count
        for startIndex in 0...lastStartIndex {
            let endIndex = startIndex + keywordTokens.count
            let candidate = sentenceTokens[startIndex..<endIndex].map { $0.text.lowercased() }

            if Array(candidate) == keywordTokens {
                return sentenceTokens[startIndex].range.lowerBound..<sentenceTokens[endIndex - 1].range.upperBound
            }
        }

        return nil
    }

    static func highlightedHTML(sentence: String, ranges: [Range<String.Index>]) -> String {
        let validRanges = ranges
            .filter { $0.lowerBound >= sentence.startIndex && $0.upperBound <= sentence.endIndex && !$0.isEmpty }
            .sorted { $0.lowerBound < $1.lowerBound }

        guard !validRanges.isEmpty else { return escapeHTML(sentence) }

        var result = ""
        var currentIndex = sentence.startIndex

        for range in validRanges where range.lowerBound >= currentIndex {
            result += escapeHTML(String(sentence[currentIndex..<range.lowerBound]))
            result += "<b>\(escapeHTML(String(sentence[range])))</b>"
            currentIndex = range.upperBound
        }

        result += escapeHTML(String(sentence[currentIndex..<sentence.endIndex]))
        return result
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
