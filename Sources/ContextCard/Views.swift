import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum FocusTarget: Hashable {
    case sentence
    case keyword(Int)
    case generateDraft
    case saveOffline
    case translation
    case keywordMeaning
    case copyForAnki
    case sendToAnki
    case clear
}

private enum ButtonVisibilityKey {
    static let importImage = "buttonVisibility.importImage"
    static let recordSentence = "buttonVisibility.recordSentence"
    static let generateDraft = "buttonVisibility.generateDraft"
    static let saveOffline = "buttonVisibility.saveOffline"
    static let copyForAnki = "buttonVisibility.copyForAnki"
    static let sendToAnki = "buttonVisibility.sendToAnki"
    static let clear = "buttonVisibility.clear"
    static let manageQueue = "buttonVisibility.manageQueue"
    static let syncQueue = "buttonVisibility.syncQueue"
    static let retryErrors = "buttonVisibility.retryErrors"
}

struct ContentView: View {
    @ObservedObject var model: CardComposerModel
    @State private var keyboardTarget: FocusTarget?
    @FocusState private var textFieldFocus: FocusTarget?
    @AppStorage(ButtonVisibilityKey.generateDraft) private var showGenerateDraft = true
    @AppStorage(ButtonVisibilityKey.saveOffline) private var showSaveOffline = true
    @AppStorage(ButtonVisibilityKey.copyForAnki) private var showCopyForAnki = true
    @AppStorage(ButtonVisibilityKey.sendToAnki) private var showSendToAnki = true
    @AppStorage(ButtonVisibilityKey.clear) private var showClear = true

    var body: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.width < 640

            VStack(alignment: .leading, spacing: 0) {
                HeaderView(model: model, isCompact: isCompact)
                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: isCompact ? 20 : 24) {
                        SentenceSection(model: model, voiceService: model.voiceInputService, keyboardTarget: $keyboardTarget, isCompact: isCompact)
                        KeywordSection(model: model, keyboardTarget: $keyboardTarget)
                        GenerateDraftButton(model: model, keyboardTarget: $keyboardTarget)
                        CardPreviewSection(model: model, isCompact: isCompact, keyboardTarget: $keyboardTarget, textFieldFocus: $textFieldFocus)
                    }
                    .padding(.horizontal, isCompact ? 18 : 32)
                    .padding(.vertical, isCompact ? 20 : 32)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .background(
            KeyboardNavigationMonitor(
                onTab: moveKeyboardFocus,
                onEnter: activateFocusedControl
            )
        )
        .onChange(of: textFieldFocus) { value in
            if let value {
                keyboardTarget = value
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var keyboardOrder: [FocusTarget] {
        var order: [FocusTarget] = [.sentence] + model.tokens.map { .keyword($0.id) }
        if showGenerateDraft { order.append(.generateDraft) }
        if showSaveOffline { order.append(.saveOffline) }
        order.append(contentsOf: [.translation, .keywordMeaning])
        if showCopyForAnki { order.append(.copyForAnki) }
        if showSendToAnki { order.append(.sendToAnki) }
        if showClear { order.append(.clear) }
        return order
    }

    private func moveKeyboardFocus(forward: Bool) -> Bool {
        guard let keyboardTarget else { return false }
        guard let currentIndex = keyboardOrder.firstIndex(of: keyboardTarget) else {
            self.keyboardTarget = forward ? keyboardOrder.first : keyboardOrder.last
            return self.keyboardTarget != nil
        }

        let nextIndex = forward ? currentIndex + 1 : currentIndex - 1
        guard keyboardOrder.indices.contains(nextIndex) else { return false }
        let target = keyboardOrder[nextIndex]
        self.keyboardTarget = target
        if target == .translation || target == .keywordMeaning {
            DispatchQueue.main.async {
                self.textFieldFocus = target
            }
        } else {
            textFieldFocus = nil
        }
        return true
    }

    private func activateFocusedControl() -> Bool {
        switch keyboardTarget {
        case let .keyword(tokenID):
            model.toggleKeyword(tokenID: tokenID)
            return true
        case .generateDraft where showGenerateDraft && model.canGenerate && !model.isGenerating:
            model.generateDraft()
            return true
        case .saveOffline where showSaveOffline && !model.translation.isEmpty && model.audioFileURL != nil && !model.isGenerating && model.offlineSaveCooldownRemaining == 0:
            model.saveOffline()
            return true
        case .copyForAnki where showCopyForAnki && model.draft.hasContent:
            model.copyForAnki()
            return true
        case .sendToAnki where showSendToAnki && !model.translation.isEmpty && model.audioFileURL != nil && !model.isGenerating:
            model.sendToAnki()
            return true
        case .clear where showClear:
            model.reset()
            return true
        default:
            return false
        }
    }
}

private struct HeaderView: View {
    @ObservedObject var model: CardComposerModel
    let isCompact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 12 : 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ContextCard")
                    .font(.system(size: isCompact ? 22 : 24, weight: .semibold))
                Text("Turn one sentence into a useful English flashcard.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Picker("Collection", selection: $model.selectedCollection) {
                    ForEach(Collections.available, id: \.self) { collection in
                        Text(collection).tag(collection)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: isCompact ? .infinity : 210, alignment: .leading)

                if !isCompact {
                    Spacer()
                }

                Image(systemName: "character.book.closed")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.blue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, isCompact ? 18 : 32)
        .padding(.vertical, isCompact ? 16 : 22)
    }
}

private struct SentenceSection: View {
    @ObservedObject var model: CardComposerModel
    @ObservedObject var voiceService: VoiceTranscriptionService
    @Binding var keyboardTarget: FocusTarget?
    let isCompact: Bool
    @State private var isImportingImage = false
    @AppStorage(ButtonVisibilityKey.importImage) private var showImportImage = true
    @AppStorage(ButtonVisibilityKey.recordSentence) private var showRecordSentence = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(number: "01", title: "English sentence")
            if showImportImage || showRecordSentence {
                HStack(spacing: 10) {
                    if showImportImage {
                        Button {
                            isImportingImage = true
                        } label: {
                            Label("Import image", systemImage: "photo")
                        }
                        .buttonStyle(.bordered)
                    }

                    if showRecordSentence {
                        Button {
                            if voiceService.isRecording {
                                model.stopVoiceInput()
                            } else {
                                model.beginVoiceInput()
                            }
                        } label: {
                            Label(voiceService.isRecording ? "Stop recording" : "Record sentence", systemImage: voiceService.isRecording ? "stop.circle.fill" : "mic.fill")
                        }
                        .buttonStyle(.bordered)

                        if voiceService.isRecording {
                            Label("Listening…", systemImage: "waveform")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            if !voiceService.transcript.isEmpty {
                Text(voiceService.transcript)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)
            }
            if let voiceError = voiceService.errorMessage {
                Label(voiceError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            ClipboardTextEditor(
                text: $model.sentence,
                onImagePaste: { image in
                    model.extractTextFromImage(image)
                },
                onFocus: {
                    keyboardTarget = .sentence
                },
                onTabForward: {
                    if let firstToken = model.tokens.first {
                        keyboardTarget = .keyword(firstToken.id)
                    } else {
                        keyboardTarget = .generateDraft
                    }
                },
                onTabBackward: {
                    keyboardTarget = .sentence
                }
            )
                .font(.system(size: 17))
                .frame(height: isCompact ? 58 : 68)
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
                .onChange(of: model.sentence) { _ in
                    let validIDs = Set(model.tokens.map(\.id))
                    model.selectedTokenIDs = model.selectedTokenIDs.intersection(validIDs)
                }
                .onChange(of: voiceService.isRecording) { isRecording in
                    if !isRecording, !voiceService.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        model.useVoiceTranscript()
                    }
                }
                .fileImporter(isPresented: $isImportingImage, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
                    switch result {
                    case let .success(urls):
                        if let url = urls.first {
                            model.extractTextFromImage(url)
                        }
                    case let .failure(error):
                        model.errorMessage = "Could not import the image: \(error.localizedDescription)"
                    }
                }
            Text("Paste or type text, or press Command-V with an image copied to the clipboard.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct GenerateDraftButton: View {
    @ObservedObject var model: CardComposerModel
    @Binding var keyboardTarget: FocusTarget?
    @AppStorage(ButtonVisibilityKey.generateDraft) private var showGenerateDraft = true
    @AppStorage(ButtonVisibilityKey.saveOffline) private var showSaveOffline = true

    var body: some View {
        Group {
            if showGenerateDraft || showSaveOffline {
                HStack {
                    if showGenerateDraft {
                        Button {
                            model.generateDraft()
                        } label: {
                            Label("Generate draft", systemImage: "sparkles")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.canGenerate || model.isGenerating)
                        .keyboardShortcut(.defaultAction)
                        .focusable()
                        .keyboardFocusStyle(keyboardTarget == .generateDraft)
                    }

                    if showSaveOffline {
                        Button {
                            model.saveOffline()
                        } label: {
                            Label(model.offlineSaveCooldownRemaining > 0 ? "Saved (\(model.offlineSaveCooldownRemaining))" : "Save offline", systemImage: "tray.and.arrow.down")
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.translation.isEmpty || model.audioFileURL == nil || model.isGenerating || model.offlineSaveCooldownRemaining > 0)
                        .focusable()
                        .keyboardFocusStyle(keyboardTarget == .saveOffline)
                    }

                    Spacer()
                }
            }
        }
    }
}

private struct KeywordSection: View {
    @ObservedObject var model: CardComposerModel
    @Binding var keyboardTarget: FocusTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(number: "02", title: "Choose the keyword")
            if model.tokens.isEmpty {
                Text("Your words will appear here after you enter a sentence.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(model.tokens) { token in
                        Button {
                            model.toggleKeyword(tokenID: token.id)
                        } label: {
                            Text(token.text)
                                .font(.system(size: 15, weight: model.selectedTokenIDs.contains(token.id) ? .semibold : .regular))
                                .foregroundStyle(model.selectedTokenIDs.contains(token.id) ? .white : .primary)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(model.selectedTokenIDs.contains(token.id) ? Color.blue : Color.secondary.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .focusable()
                        .keyboardFocusStyle(keyboardTarget == .keyword(token.id))
                    }
                }
            }
            if !model.selectedKeyword.isEmpty {
                Label("Selected: \(model.selectedKeyword)", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.blue)
            }
        }
    }
}

private struct CardPreviewSection: View {
    @ObservedObject var model: CardComposerModel
    let isCompact: Bool
    @Binding var keyboardTarget: FocusTarget?
    @FocusState.Binding var textFieldFocus: FocusTarget?
    @State private var isManagingQueue = false
    @AppStorage(ButtonVisibilityKey.copyForAnki) private var showCopyForAnki = true
    @AppStorage(ButtonVisibilityKey.sendToAnki) private var showSendToAnki = true
    @AppStorage(ButtonVisibilityKey.clear) private var showClear = true
    @AppStorage(ButtonVisibilityKey.manageQueue) private var showManageQueue = true
    @AppStorage(ButtonVisibilityKey.syncQueue) private var showSyncQueue = true
    @AppStorage(ButtonVisibilityKey.retryErrors) private var showRetryErrors = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionLabel(number: "03", title: "Card preview")
                Spacer()
                if model.isGenerating {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if isCompact {
                VStack(alignment: .leading, spacing: 14) {
                    frontCardField
                    backCardField
                }
            } else {
                HStack(alignment: .top, spacing: 16) {
                    frontCardField
                    backCardField
                }
            }

            if showCopyForAnki || showSendToAnki || (showClear && !hasQueuedCards) {
                HStack(spacing: 10) {
                    if showCopyForAnki {
                        Button {
                            model.copyForAnki()
                        } label: {
                            Label("Copy for Anki", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!model.draft.hasContent)
                        .focusable()
                        .keyboardFocusStyle(keyboardTarget == .copyForAnki)
                    }

                    if showSendToAnki {
                        Button {
                            model.sendToAnki()
                        } label: {
                            Label("Send to Anki", systemImage: "arrow.up.circle")
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.translation.isEmpty || model.audioFileURL == nil || model.isGenerating)
                        .focusable()
                        .keyboardFocusStyle(keyboardTarget == .sendToAnki)
                    }

                    Spacer()

                    if showClear && !hasQueuedCards {
                        clearButton
                    }
                }
            }

            if let offlineFeedback = model.offlineFeedback {
                Label(
                    model.offlineSaveCooldownRemaining > 0 ? "\(offlineFeedback) Save available in \(model.offlineSaveCooldownRemaining)s." : offlineFeedback,
                    systemImage: "checkmark.circle.fill"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(.green)
            }

            if let statusMessage = model.statusMessage {
                Label(statusMessage, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

                if !model.pendingCards.isEmpty || !model.errorCards.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 14) {
                        Label("\(model.pendingCards.count) queued", systemImage: "tray.full")
                        Label("\(model.errorCards.count) errors", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(model.errorCards.isEmpty ? Color.secondary : Color.orange)
                        }

                        if showManageQueue || showSyncQueue || showRetryErrors || showClear {
                            HStack(spacing: 10) {
                                if showManageQueue {
                                    Button {
                                        isManagingQueue = true
                                    } label: {
                                        Label("Manage queue", systemImage: "list.bullet.rectangle")
                                    }
                                    .buttonStyle(.bordered)
                                }

                                if showSyncQueue {
                                    Button {
                                        model.syncPendingCards()
                                    } label: {
                                        Label("Sync queue", systemImage: "arrow.triangle.2.circlepath")
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(model.pendingCards.isEmpty || model.isGenerating)
                                }

                                if showRetryErrors {
                                    Button {
                                        model.retryErrorCards()
                                    } label: {
                                        Label("Retry errors", systemImage: "arrow.clockwise")
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(model.errorCards.isEmpty || model.isGenerating)
                                }

                                Spacer()

                                if showClear {
                                    clearButton
                                }
                            }
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !model.errorCards.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Error queue")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                        ForEach(model.errorCards.prefix(3)) { card in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(card.sentence)
                                    .lineLimit(1)
                                Text(card.lastError ?? "Unknown sync error")
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .font(.caption)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .sheet(isPresented: $isManagingQueue) {
            QueueManagementView(model: model)
        }
    }

    private var frontCardField: some View {
        CardField(title: "FRONT · ENGLISH", height: isCompact ? 78 : 88) {
            Text(frontText)
                .font(.system(size: 16))
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }

    private var hasQueuedCards: Bool {
        !model.pendingCards.isEmpty || !model.errorCards.isEmpty
    }

    private var clearButton: some View {
        Button("Clear") { model.reset() }
            .buttonStyle(.plain)
            .font(.body)
            .foregroundStyle(.secondary)
            .focusable()
            .keyboardFocusStyle(keyboardTarget == .clear)
    }

    private var backCardField: some View {
        CardField(title: "BACK · PORTUGUESE", height: isCompact ? 88 : 96) {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Sentence translation", text: $model.translation, axis: .vertical)
                    .lineLimit(1...2)
                    .focused($textFieldFocus, equals: .translation)
                Divider()
                TextField("Keyword meaning", text: $model.keywordMeaning, axis: .vertical)
                    .lineLimit(1...2)
                    .focused($textFieldFocus, equals: .keywordMeaning)
            }
            .font(.system(size: 15))
        }
    }

    private var frontText: AttributedString {
        var result = AttributedString(model.sentence)
        guard !model.selectedKeyword.isEmpty,
              let range = result.range(of: model.selectedKeyword, options: .caseInsensitive) else { return result }
        result[range].font = .system(size: 16, weight: .bold)
        result[range].foregroundColor = .blue
        return result
    }
}

private struct QueueManagementView: View {
    @ObservedObject var model: CardComposerModel
    @SwiftUI.Environment(\.dismiss) private var dismiss
    @State private var editingCard: QueuedCard?
    @State private var cardPendingDeletion: QueuedCard?

    private var allCards: [QueueDisplayCard] {
        model.pendingCards.map { QueueDisplayCard(card: $0, state: .pending) }
            + model.errorCards.map { QueueDisplayCard(card: $0, state: .error) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Queue")
                        .font(.title2.weight(.semibold))
                    Text("\(model.pendingCards.count) waiting to sync · \(model.errorCards.count) need attention")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.bordered)
                .help("Close")
            }
            .padding(20)

            Divider()

            if allCards.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text("Queue is empty")
                        .font(.headline)
                    Text("Saved offline cards will appear here before they sync to Anki.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(allCards) { item in
                    QueueCardRow(item: item) {
                        editingCard = item.card
                    } onDelete: {
                        cardPendingDeletion = item.card
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                }
                .listStyle(.plain)
            }
        }
        .frame(minWidth: 660, minHeight: 480)
        .sheet(item: $editingCard) { card in
            QueueEditView(card: card) { updatedCard in
                model.updateQueuedCard(updatedCard)
                editingCard = nil
            } onCancel: {
                editingCard = nil
            }
        }
        .confirmationDialog(
            "Delete this queued card?",
            isPresented: Binding(
                get: { cardPendingDeletion != nil },
                set: { if !$0 { cardPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete card", role: .destructive) {
                if let cardPendingDeletion {
                    model.deleteQueuedCard(cardPendingDeletion)
                }
                cardPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                cardPendingDeletion = nil
            }
        } message: {
            Text("This removes the queued card and its stored audio file.")
        }
    }
}

private struct QueueDisplayCard: Identifiable {
    enum State {
        case pending
        case error

        var title: String {
            switch self {
            case .pending: return "Queued"
            case .error: return "Error"
            }
        }

        var systemImage: String {
            switch self {
            case .pending: return "tray.full"
            case .error: return "exclamationmark.triangle"
            }
        }

        var color: Color {
            switch self {
            case .pending: return .secondary
            case .error: return .orange
            }
        }
    }

    let card: QueuedCard
    let state: State

    var id: UUID { card.id }
}

private struct QueueCardRow: View {
    let item: QueueDisplayCard
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Label(item.state.title, systemImage: item.state.systemImage)
                .font(.caption.weight(.medium))
                .foregroundStyle(item.state.color)
                .frame(width: 82, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                Text(item.card.sentence)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(2)
                    .textSelection(.enabled)
                HStack(spacing: 8) {
                    Text(item.card.deckName)
                    Text(item.card.keyword)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let lastError = item.card.lastError, !lastError.isEmpty {
                    Text(lastError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.bordered)
                .help("Edit card")

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .help("Delete card")
            }
        }
    }
}

private struct QueueEditView: View {
    @State private var card: QueuedCard
    let onSave: (QueuedCard) -> Void
    let onCancel: () -> Void

    init(card: QueuedCard, onSave: @escaping (QueuedCard) -> Void, onCancel: @escaping () -> Void) {
        _card = State(initialValue: card)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Edit Queued Card")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 10) {
                TextField("English text", text: $card.sentence, axis: .vertical)
                    .lineLimit(3...6)
                TextField("Keyword", text: $card.keyword)
                TextField("Portuguese translation", text: $card.translation, axis: .vertical)
                    .lineLimit(2...5)
                TextField("Keyword meaning", text: $card.keywordMeaning, axis: .vertical)
                    .lineLimit(2...5)
                Picker("Collection", selection: $card.deckName) {
                    ForEach(Collections.available, id: \.self) { collection in
                        Text(collection).tag(collection)
                    }
                }
            }
            .textFieldStyle(.roundedBorder)

            Spacer()

            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                Button {
                    onSave(card)
                } label: {
                    Label("Save changes", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(card.sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || card.keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 520, height: 460)
    }
}

private struct CardField<Content: View>: View {
    let title: String
    let height: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content
                .frame(height: height, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(12)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SectionLabel: View {
    let number: String
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Text(number)
                .font(.caption.monospaced().weight(.bold))
                .foregroundStyle(.blue)
            Text(title)
                .font(.headline)
        }
    }
}

private struct KeyboardFocusStyle: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isFocused ? Color.accentColor : Color.clear, lineWidth: 2)
                    .padding(-3)
            )
            .shadow(
                color: isFocused ? Color.accentColor.opacity(0.35) : Color.clear,
                radius: 4
            )
    }
}

private extension View {
    func keyboardFocusStyle(_ isFocused: Bool) -> some View {
        modifier(KeyboardFocusStyle(isFocused: isFocused))
    }
}

private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var widestRow: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                widestRow = max(widestRow, rowWidth)
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += (rowWidth == 0 ? 0 : spacing) + size.width
            rowHeight = max(rowHeight, size.height)
        }

        widestRow = max(widestRow, rowWidth)
        totalHeight += rowHeight
        return CGSize(width: proposal.width ?? widestRow, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct KeyboardNavigationMonitor: NSViewRepresentable {
    let onTab: (Bool) -> Bool
    let onEnter: () -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.hostView = view
        context.coordinator.installMonitor()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.hostView = nsView
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        var parent: KeyboardNavigationMonitor
        weak var hostView: NSView?
        private var monitor: Any?

        init(parent: KeyboardNavigationMonitor) {
            self.parent = parent
        }

        deinit {
            removeMonitor()
        }

        func installMonitor() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, NSApp.isActive else { return event }

                let blockedModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
                guard event.modifierFlags.intersection(blockedModifiers).isEmpty else { return event }

                if event.keyCode == 48 {
                    let handled = self.parent.onTab(!event.modifierFlags.contains(.shift))
                    if handled {
                        event.window?.makeFirstResponder(nil)
                        return nil
                    }
                }

                if event.keyCode == 36 || event.keyCode == 76 {
                    return self.parent.onEnter() ? nil : event
                }

                return event
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: CardComposerModel
    @AppStorage(ButtonVisibilityKey.importImage) private var showImportImage = true
    @AppStorage(ButtonVisibilityKey.recordSentence) private var showRecordSentence = true
    @AppStorage(ButtonVisibilityKey.generateDraft) private var showGenerateDraft = true
    @AppStorage(ButtonVisibilityKey.saveOffline) private var showSaveOffline = true
    @AppStorage(ButtonVisibilityKey.copyForAnki) private var showCopyForAnki = true
    @AppStorage(ButtonVisibilityKey.sendToAnki) private var showSendToAnki = true
    @AppStorage(ButtonVisibilityKey.clear) private var showClear = true
    @AppStorage(ButtonVisibilityKey.manageQueue) private var showManageQueue = true
    @AppStorage(ButtonVisibilityKey.syncQueue) private var showSyncQueue = true
    @AppStorage(ButtonVisibilityKey.retryErrors) private var showRetryErrors = true

    var body: some View {
        Form {
            Section("Main window buttons") {
                Toggle("Import image", isOn: $showImportImage)
                Toggle("Record sentence", isOn: $showRecordSentence)
                Toggle("Generate draft", isOn: $showGenerateDraft)
                Toggle("Save offline", isOn: $showSaveOffline)
                Toggle("Copy for Anki", isOn: $showCopyForAnki)
                Toggle("Send to Anki", isOn: $showSendToAnki)
                Toggle("Clear", isOn: $showClear)
                Toggle("Manage queue", isOn: $showManageQueue)
                Toggle("Sync queue", isOn: $showSyncQueue)
                Toggle("Retry errors", isOn: $showRetryErrors)
            }
            .toggleStyle(.switch)

            Section("Translation") {
                TextField("API endpoint", text: $model.apiEndpoint)
                TextField("Model", text: $model.modelName)
                SecureField("API key", text: $model.apiKey)
                Text("The key is stored in macOS Keychain. Leave it empty to use local demo mode.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    model.saveSettings()
                } label: {
                    Label("Save settings", systemImage: "lock.open")
                }
            }
            Section("Anki") {
                Text("Install AnkiConnect in Anki to enable direct export. The app uses the local AnkiConnect address on port 8765.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Next input source") {
                Text("Photo import and OCR are intentionally reserved for the next phase. This version never captures your screen.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 680)
        .padding()
    }
}
