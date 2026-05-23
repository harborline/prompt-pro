import AppKit
import PromptProducerCore
import SwiftUI

struct PromptPreview: Equatable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var body: String
    var tags: [String]
    var updatedAt: Date

    init(prompt: Prompt) {
        id = prompt.id
        title = prompt.title
        body = prompt.body
        tags = prompt.tags
        updatedAt = prompt.updatedAt
    }

    init(id: UUID, title: String, body: String, tags: [String], updatedAt: Date) {
        self.id = id
        self.title = title
        self.body = body
        self.tags = tags
        self.updatedAt = updatedAt
    }
}

struct PromptPreviewView: View {
    let preview: PromptPreview
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider().overlay(NordTheme.separator)

            ScrollView {
                Text(previewText)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(preview.body.isEmpty ? NordTheme.secondaryText : NordTheme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .textSelection(.enabled)
            }
            .background(NordTheme.background)

            Divider().overlay(NordTheme.separator)

            footer
        }
        .frame(minWidth: 520, minHeight: 420)
        .background(NordTheme.background)
        .foregroundStyle(NordTheme.text)
        .tint(NordTheme.accent)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(preview.title.isEmpty ? "Untitled prompt" : preview.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                    .foregroundStyle(NordTheme.text)

                Spacer()

                Button {
                    copyPreview()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(NordTheme.secondaryText)
                .help("Close")
            }

            if !preview.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(preview.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .foregroundStyle(NordTheme.snow1)
                            .background(NordTheme.polarNight3.opacity(0.72), in: Capsule())
                    }
                }
            }
        }
        .padding(18)
        .background(NordTheme.panel)
    }

    private var footer: some View {
        HStack {
            Text("Updated \(preview.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                .lineLimit(1)

            Spacer()

            Text("\(preview.body.count) characters")
        }
        .font(.caption)
        .foregroundStyle(NordTheme.secondaryText)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(NordTheme.panel)
    }

    private var previewText: String {
        preview.body.isEmpty ? "Empty prompt" : preview.body
    }

    private func copyPreview() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(preview.body, forType: .string)
    }
}
