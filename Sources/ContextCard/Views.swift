import SwiftUI

struct ContentView: View {
    @ObservedObject var model: CardComposerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderView()
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SentenceSection(model: model)
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
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ContextCard")
                    .font(.system(size: 24, weight: .semibold))
                Text("Turn one sentence into a useful English flashcard.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(number: "01", title: "English sentence")
            TextEditor(text: $model.sentence)
                .font(.system(size: 17))
                .frame(minHeight: 96)
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
                .onChange(of: model.sentence) { _ in
                    if !model.tokens.contains(where: { $0.text.caseInsensitiveCompare(model.selectedKeyword) == .orderedSame }) {
                        model.selectedKeyword = ""
                    }
                }
            Text("Paste or type the subtitle sentence here.")
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
                            model.select(keyword: token.text)
                        } label: {
                            Text(token.text)
                                .font(.system(size: 15, weight: token.text.caseInsensitiveCompare(model.selectedKeyword) == .orderedSame ? .semibold : .regular))
                                .foregroundStyle(token.text.caseInsensitiveCompare(model.selectedKeyword) == .orderedSame ? .white : .primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(token.text.caseInsensitiveCompare(model.selectedKeyword) == .orderedSame ? Color.blue : Color.secondary.opacity(0.12))
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

                Spacer()

                Button("Clear") { model.reset() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

            if let statusMessage = model.statusMessage {
                Label(statusMessage, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
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

private struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: spacing)], alignment: .leading, spacing: spacing) {
            content
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
