import XCTest
@testable import ContextCard

final class TextProcessingTests: XCTestCase {
    func testTokensPreserveContractionsAndIgnorePunctuation() {
        let tokens = TextProcessing.tokens(in: "I can't believe it!")
        XCTAssertEqual(tokens.map(\.text), ["I", "can't", "believe", "it"])
    }

    func testHighlightedHTMLEscapesMarkupAndEmphasizesKeyword() {
        let html = TextProcessing.highlightedHTML(sentence: "It's awkward <today>.", keyword: "awkward")
        XCTAssertEqual(html, "It&#39;s <b>awkward</b> &lt;today&gt;.")
    }

    func testMultiWordKeywordIsEmphasizedAsOnePhrase() {
        let html = TextProcessing.highlightedHTML(sentence: "I barely understood.", keyword: "barely understood")
        XCTAssertEqual(html, "I <b>barely understood</b>.")
    }

    func testHighlightedHTMLOnlyEmphasizesSelectedTokenRange() {
        let sentence = "But I did find this."
        let tokens = TextProcessing.tokens(in: sentence)
        let selectedToken = tokens.first { $0.text == "I" }

        let html = TextProcessing.highlightedHTML(sentence: sentence, ranges: selectedToken.map { [$0.range] } ?? [])

        XCTAssertEqual(html, "But <b>I</b> did find this.")
    }

    func testKeywordFallbackOnlyEmphasizesFirstMatchingTokenPhrase() {
        let html = TextProcessing.highlightedHTML(sentence: "But I did find this.", keyword: "I")

        XCTAssertEqual(html, "But <b>I</b> did find this.")
    }

    func testBackHTMLHighlightsKeywordTranslationAndRemovesDuplicateMeaningPrefix() {
        let draft = CardDraft(
            sentence: "But I did find this.",
            keyword: "I",
            keywordTranslation: "eu",
            translation: "mas eu encontrei isso",
            keywordMeaning: "eu: pronome pessoal que se refere à primeira pessoa do singular."
        )

        XCTAssertEqual(
            draft.backHTML,
            "<p>mas <b>eu</b> encontrei isso</p><p><b>I</b>: pronome pessoal que se refere à primeira pessoa do singular.</p>"
        )
    }

    func testInitialCollectionIsTheRequestedAnkiDeck() {
        XCTAssertEqual(Collections.defaultCollection, "Anki Create English")
        XCTAssertTrue(Collections.available.contains("Anki Create English"))
    }
}
