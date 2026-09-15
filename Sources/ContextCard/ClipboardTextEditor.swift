import AppKit
import SwiftUI

struct ClipboardTextEditor: NSViewRepresentable {
    @Binding var text: String
    let onImagePaste: (NSImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = ImagePasteTextView()
        textView.delegate = context.coordinator
        textView.imagePasteHandler = onImagePaste
        textView.string = text
        textView.font = .systemFont(ofSize: 17)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ImagePasteTextView else { return }
        textView.imagePasteHandler = onImagePaste
        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ClipboardTextEditor

        init(_ parent: ClipboardTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

private final class ImagePasteTextView: NSTextView {
    var imagePasteHandler: ((NSImage) -> Void)?

    override func paste(_ sender: Any?) {
        if let image = NSImage(pasteboard: NSPasteboard.general) {
            imagePasteHandler?(image)
            return
        }
        super.paste(sender)
    }
}
