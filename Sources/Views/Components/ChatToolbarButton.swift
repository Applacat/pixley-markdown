import SwiftUI

#if os(iOS)

// MARK: - Chat Toolbar Button

/// Persistent toolbar button for accessing Pixley Chat on iOS.
/// Shows a chat bubble icon with a small blue dot overlay when
/// chat history exists for the current document (Mail/Messages pattern).
@available(iOS 26, *)
struct ChatToolbarButton: View {

    @Environment(\.coordinator) private var coordinator
    @Binding var isChatPresented: Bool

    /// Whether chat history exists for the currently selected document.
    /// Checks the per-document summary repository (same data ChatService uses
    /// for transcript condensation).
    private var hasHistory: Bool {
        guard let url = coordinator.navigation.selectedFile,
              let repo = coordinator.chatSummaryRepository else { return false }
        return repo.getSummary(for: url.path) != nil
    }

    var body: some View {
        Button {
            isChatPresented = true
        } label: {
            Image(systemName: "bubble.left.and.bubble.right")
                .overlay(alignment: .topTrailing) {
                    if hasHistory {
                        Circle()
                            .fill(.blue)
                            .frame(width: 8, height: 8)
                            .offset(x: 3, y: -3)
                    }
                }
        }
        .buttonStyle(.borderedProminent)
        .tint(.accentColor)
        .accessibilityLabel(hasHistory ? "Pixley Chat (has history)" : "Pixley Chat")
        .accessibilityHint("Opens AI chat about the current document")
    }
}

#endif
