import SwiftUI
import aimdRenderer

// MARK: - Go To Line Overlay

/// A small text field overlay triggered by Cmd+G for jumping to a specific line number.
struct GoToLineOverlay: View {

    let palette: SyntaxPalette
    let maxLine: Int
    let onGoToLine: (Int) -> Void
    let onDismiss: () -> Void

    @State private var lineText: String = ""
    @State private var showError: Bool = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack {
            HStack(spacing: 8) {
                Text("Go to line:")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(palette.foreground)

                TextField("1–\(maxLine)", text: $lineText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 100)
                    .focused($isFocused)
                    .onSubmit {
                        submit()
                    }
                    .onExitCommand {
                        onDismiss()
                    }

                if showError {
                    Text("Invalid")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(12)
            .background(palette.background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(palette.comment.opacity(0.3), lineWidth: 1)
            )
            .shadow(radius: 8)

            Spacer()
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity)
        .onAppear {
            isFocused = true
        }
    }

    private func submit() {
        guard let line = Int(lineText), line >= 1, line <= maxLine else {
            showError = true
            return
        }
        showError = false
        onGoToLine(line)
    }
}
