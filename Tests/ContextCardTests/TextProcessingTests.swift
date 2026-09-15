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
}
