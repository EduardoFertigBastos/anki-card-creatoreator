import AppKit
import Foundation
import Vision

struct ImageOCRService {
    func extractEnglishText(from url: URL) throws -> String {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        guard let image = NSImage(contentsOf: url),
              var proposedRect = Optional<NSRect>.some(.zero),
              let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            throw CardComposerError.imageOCRFailed("ContextCard could not read that image.")
        }

        return try recognizeText(in: cgImage)
    }

    func extractEnglishText(from image: NSImage) throws -> String {
        var proposedRect = NSRect.zero
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            throw CardComposerError.imageOCRFailed("ContextCard could not read the pasted image.")
        }
        return try recognizeText(in: cgImage)
    }

    private func recognizeText(in cgImage: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        let lines = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
        let text = lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw CardComposerError.imageOCRFailed("No readable English text was found in that image.")
        }
        return text
    }
}
