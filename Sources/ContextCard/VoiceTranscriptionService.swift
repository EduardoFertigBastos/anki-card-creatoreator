import AVFoundation
import Foundation
import Speech

@MainActor
final class VoiceTranscriptionService: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var transcript = ""
    @Published var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func start() async throws {
        guard !isRecording else { return }
        guard let recognizer, recognizer.isAvailable else {
            throw CardComposerError.speechRecognitionPermissionDenied
        }

        let speechStatus = await requestSpeechAuthorization()
        guard speechStatus == .authorized else {
            throw CardComposerError.speechRecognitionPermissionDenied
        }

        guard await requestMicrophonePermission() else {
            throw CardComposerError.microphonePermissionDenied
        }

        recognitionTask?.cancel()
        recognitionTask = nil
        transcript = ""
        errorMessage = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self, weak request] buffer, _ in
            request?.append(buffer)
            guard self != nil else { return }
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if let error {
                    self.errorMessage = "Speech transcription stopped: \(error.localizedDescription)"
                    self.stop()
                } else if result?.isFinal == true {
                    self.stop()
                }
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
        } catch {
            inputNode.removeTap(onBus: 0)
            throw CardComposerError.audioGenerationFailed("Could not start microphone recording: \(error.localizedDescription)")
        }
    }

    func stop() {
        guard isRecording || audioEngine.isRunning else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        isRecording = false
    }

    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        if #available(macOS 14.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        }
        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
