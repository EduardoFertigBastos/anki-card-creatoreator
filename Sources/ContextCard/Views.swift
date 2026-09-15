import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: CardComposerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderView(model: model)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SentenceSection(model: model, voiceService: model.voiceInputService)
                    KeywordSection(model: model)
                    CardPreviewSection(model: model)
                }
                .padding(32)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

private struct HeaderView: View {
    @ObservedObject var model: CardComposerModel

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ContextCard")
                    .font(.system(size: 24, weight: .semibold))
                Text("Turn one sentence into a useful English flashcard.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Collection", selection: $model.selectedCollection) {
                ForEach(Collections.available, id: \.self) { collection in
                    Text(collection).tag(collection)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 210)
            Image(systemName: "character.book.closed")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.blue)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 22)
    }
}

private struct SentenceSection: View {
    @ObservedObject var model: CardComposerModel
    @ObservedObject var voiceService: VoiceTranscriptionService
    @State private var isImportingImage = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(number: "01", title: "English sentence")
            HStack(spacing: 10) {
                Button {
                    isImportingImage = true
                } label: {
                    Label("Import image", systemImage: "photo")
                }
                .buttonStyle(.bordered)

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
            ClipboardTextEditor(text: $model.sentence) { image in
                model.extractTextFromImage(image)
            }
                .font(.system(size: 17))
                .frame(minHeight: 96)
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

private struct KeywordSection: View {
    @ObservedObject var model: CardComposerModel

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
    @State private var isManagingQueue = false

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

            HStack(alignment: .top, spacing: 16) {
                CardField(title: "FRONT · ENGLISH") {
                    Text(frontText)
                        .font(.system(size: 16))
                        .textSelection(.enabled)
                }
                CardField(title: "BACK · PORTUGUESE") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Sentence translation", text: $model.translation, axis: .vertical)
                        Divider()
                        TextField("Keyword meaning", text: $model.keywordMeaning, axis: .vertical)
                    }
                    .font(.system(size: 15))
                }
            }

            HStack(spacing: 10) {
                Button {
                    model.generateDraft()
                } label: {
                    Label("Generate draft", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canGenerate || model.isGenerating)

                Button {
                    model.copyForAnki()
                } label: {
                    Label("Copy for Anki", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .disabled(!model.draft.hasContent)

                Button {
                    model.sendToAnki()
                } label: {
                    Label("Send to Anki", systemImage: "arrow.up.circle")
                }
                .buttonStyle(.bordered)
                .disabled(model.translation.isEmpty || model.audioFileURL == nil || model.isGenerating)

                Button {
                    model.saveOffline()
                } label: {
                    Label(model.offlineSaveCooldownRemaining > 0 ? "Saved (\(model.offlineSaveCooldownRemaining))" : "Save offline", systemImage: "tray.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .disabled(model.translation.isEmpty || model.audioFileURL == nil || model.isGenerating || model.offlineSaveCooldownRemaining > 0)

                Spacer()

                Button("Clear") { model.reset() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
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
                    HStack(spacing: 14) {
                        Label("\(model.pendingCards.count) queued", systemImage: "tray.full")
                        Label("\(model.errorCards.count) errors", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(model.errorCards.isEmpty ? Color.secondary : Color.orange)
                        Spacer()
                        Button {
                            isManagingQueue = true
                        } label: {
                            Label("Manage queue", systemImage: "list.bullet.rectangle")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            model.syncPendingCards()
                        } label: {
                        Label("Sync queue", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.pendingCards.isEmpty || model.isGenerating)

                    Button {
                        model.retryErrorCards()
                    } label: {
                        Label("Retry errors", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.errorCards.isEmpty || model.isGenerating)
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
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content
                .frame(maxWidth: .infinity, minHeight: 105, alignment: .topLeading)
                .padding(16)
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

struct SettingsView: View {
    @ObservedObject var model: CardComposerModel

    var body: some View {
        Form {
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
        .frame(width: 520, height: 360)
        .padding()
    }
}
