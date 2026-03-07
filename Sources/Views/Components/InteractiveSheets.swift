import SwiftUI

// MARK: - Fill-In Sheet

/// A sheet for entering text to fill in a `[[placeholder]]`.
struct FillInSheet: View {
    let hint: String
    @Binding var text: String
    let onSubmit: () -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("Fill In")
                .font(.headline)

            Text(hint)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField(hint, text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit {
                    if !text.isEmpty {
                        onSubmit()
                    }
                }

            HStack {
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Submit") {
                    onSubmit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear {
            isFocused = true
        }
    }
}

// MARK: - Feedback Sheet

/// A sheet for leaving feedback in a `<!-- feedback -->` comment.
struct FeedbackSheet: View {
    @Binding var text: String
    let onSubmit: () -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("Leave Feedback")
                .font(.headline)

            Text("Your comment will be saved in the document.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 80)
                .focused($isFocused)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

            HStack {
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Submit") {
                    onSubmit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380, height: 240)
        .onAppear {
            isFocused = true
        }
    }
}
