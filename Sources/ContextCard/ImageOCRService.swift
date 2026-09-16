import AppKit
import Foundation
import Vision

struct ImageOCRService {
    func extractEnglishText(from url: URL) async throws -> String {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        guard let imageData = try? Data(contentsOf: url), !imageData.isEmpty else {
            throw CardComposerError.imageOCRFailed("ContextCard could not read that image.")
        }

        return try await recognizeText(in: imageData)
    }

    func extractEnglishText(from image: NSImage) async throws -> String {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let imageData = bitmap.representation(using: .png, properties: [:]) else {
            throw CardComposerError.imageOCRFailed("ContextCard could not read the pasted image.")
        }
        return try await recognizeText(in: imageData)
    }

    private func recognizeText(in imageData: Data) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    if let text = try recognizeText(in: imageData, recognitionLevel: .fast) {
                        continuation.resume(returning: text)
                        return
                    }

                    if let text = try recognizeText(in: imageData, recognitionLevel: .accurate) {
                        continuation.resume(returning: text)
                        return
                    }

                    throw CardComposerError.imageOCRFailed("No readable English text was found in that image.")
                } catch let error as CardComposerError {
                    continuation.resume(throwing: error)
                } catch {
                    continuation.resume(
                        throwing: CardComposerError.imageOCRFailed(
                            "macOS could not analyze this image. Try copying it again or use Import image."
                        )
                    )
                }
            }
        }
    }

    private func recognizeText(
        in imageData: Data,
        recognitionLevel: VNRequestTextRecognitionLevel
    ) throws -> String? {
        let request = VNRecognizeTextRequest()
        request.revision = VNRecognizeTextRequestRevision3
        request.recognitionLevel = recognitionLevel
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"]

        let handler = VNImageRequestHandler(data: imageData, options: [:])
        try handler.perform([request])

        let lines = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
        let text = lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
