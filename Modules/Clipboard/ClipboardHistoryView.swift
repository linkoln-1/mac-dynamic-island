import SwiftUI

struct ClipboardHistoryView: View {
    @ObservedObject private var store = ClipboardModuleController.shared.store
    @ObservedObject private var lang = AppLanguageManager.shared
    @State private var kindFilter: ClipboardEntryKind?

    var body: some View {
        let rows = store.filtered(kind: kindFilter)
        VStack(spacing: 0) {
            header
            if rows.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 5) {
                        ForEach(rows) { entry in
                            ClipboardRowView(entry: entry)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
                }
            }
        }
        .onAppear { ClipboardModuleController.shared.activate() }
    }

    private var header: some View {
        HStack {
            Text(lang.string("module.clipboard.title"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            HStack(spacing: 3) {
                filterTab(nil, title: lang.string("attention.filter.all"))
                ForEach(ClipboardEntryKind.allCases, id: \.self) { kind in
                    if store.count(kind: kind) > 0 {
                        filterTab(kind, title: lang.string(kind.localizationKey))
                    }
                }
            }
            .padding(.leading, 6)
            Spacer()
            if store.entries.contains(where: { !$0.isPinned }) {
                Button(lang.string("agent.clear")) { store.clearUnpinned() }
                    .buttonStyle(.plain)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.1), in: Capsule())
                    .contentShape(Capsule())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private func filterTab(_ kind: ClipboardEntryKind?, title: String) -> some View {
        let isSelected = kindFilter == kind
        return Button {
            kindFilter = kind
        } label: {
            Text(title)
                .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(.white.opacity(isSelected ? 0.95 : 0.5))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(isSelected ? 0.16 : 0.0), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.35))
            Text(lang.string("clipboard.empty"))
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ClipboardRowView: View {
    let entry: ClipboardEntry
    @State private var isHovering = false
    @State private var showCopied = false
    @ObservedObject private var lang = AppLanguageManager.shared

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.isPinned ? "pin.fill" : entry.kind.systemImage)
                .font(.system(size: 12))
                .foregroundStyle(entry.isPinned ? Color.yellow.opacity(0.8) : .white.opacity(0.5))
                .frame(width: 18)
            Text(entry.preview)
                .font(entry.kind == .code
                    ? .system(size: 9, design: .monospaced)
                    : .system(size: 10))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 4)
            if showCopied {
                Text(lang.string("clipboard.copied"))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.green.opacity(0.85))
            } else if isHovering {
                rowButtons
            } else {
                Text(AttentionPresentation.relativeTime(from: entry.createdAt, now: Date(), lang: lang))
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(isHovering ? 0.10 : 0.06))
        )
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onTapGesture { copy() }
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(lang.string(entry.kind.localizationKey)): \(entry.preview)")
    }

    private var rowButtons: some View {
        HStack(spacing: 4) {
            rowButton("doc.on.doc", help: lang.string("screenshots.copy")) { copy() }
            rowButton(
                entry.isPinned ? "pin.slash" : "pin",
                help: lang.string(entry.isPinned ? "clipboard.action.unpin" : "clipboard.action.pin")
            ) {
                ClipboardModuleController.shared.store.togglePin(entry.id)
            }
            rowButton("xmark", help: lang.string("clipboard.action.delete")) {
                ClipboardModuleController.shared.store.remove(entry.id)
            }
        }
    }

    private func rowButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 18, height: 18)
                .background(Color.white.opacity(0.08), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private func copy() {
        ClipboardModuleController.shared.store.copyToPasteboard(entry.id)
        showCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { showCopied = false }
    }
}
