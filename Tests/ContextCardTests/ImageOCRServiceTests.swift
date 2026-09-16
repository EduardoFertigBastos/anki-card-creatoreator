import AppKit
import XCTest
@testable import ContextCard

final class ImageOCRServiceTests: XCTestCase {
    @MainActor
    func testExtractsTextFromClipboardStyleImage() async throws {
        let image = NSImage(size: NSSize(width: 900, height: 180))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        NSString(string: "The quick brown fox jumps over the lazy dog.").draw(
            at: NSPoint(x: 30, y: 60),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 42, weight: .medium),
                .foregroundColor: NSColor.black
            ]
        )
        image.unlockFocus()

        let text = try await ImageOCRService().extractEnglishText(from: image)

        XCTAssertTrue(text.localizedCaseInsensitiveContains("quick brown fox"))
    }
}
