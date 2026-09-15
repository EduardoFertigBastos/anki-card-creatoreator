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

    func testInitialCollectionIsTheRequestedAnkiDeck() {
        XCTAssertEqual(Collections.defaultCollection, "Anki Create English")
        XCTAssertTrue(Collections.available.contains("Anki Create English"))
    }
}
