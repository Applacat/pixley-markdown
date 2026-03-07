import SwiftUI
import aimdRenderer

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

// MARK: - Date Picker Sheet

/// A sheet for picking a date to fill in a `[[pick date]]` placeholder.
struct DatePickerSheet: View {
    @State private var selectedDate: Date
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    private static let outputFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init(initialDate: Date = Date(), onSubmit: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self._selectedDate = State(initialValue: initialDate)
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Pick a Date")
                .font(.headline)

            DatePicker(
                "Date",
                selection: $selectedDate,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()

            HStack {
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Submit") {
                    onSubmit(Self.outputFormatter.string(from: selectedDate))
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
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

// MARK: - Review Notes Sheet

/// A sheet for entering notes when selecting a review status that prompts for notes (FAIL, PASS WITH NOTES, BLOCKED).
struct ReviewNotesSheet: View {
    let status: ReviewStatus
    @Binding var text: String
    let onSubmit: () -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("Review: \(status.rawValue)")
                .font(.headline)

            Text("Add notes for this review status.")
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

                Button("Submit Without Notes") {
                    text = ""
                    onSubmit()
                }

                Button("Submit") {
                    onSubmit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400, height: 260)
        .onAppear {
            isFocused = true
        }
    }
}

// MARK: - Suggestion Sheet

/// A sheet for accepting or rejecting a CriticMarkup suggestion.
struct SuggestionSheet: View {
    let suggestion: SuggestionElement
    let onAccept: () -> Void
    let onReject: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Suggested Edit")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                if let oldText = suggestion.oldText, !oldText.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                        Text(oldText)
                            .font(.callout)
                            .strikethrough()
                            .foregroundStyle(.secondary)
                    }
                }
                if let newText = suggestion.newText, !newText.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.green)
                        Text(newText)
                            .font(.callout)
                    }
                }
                if let comment = suggestion.comment {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "text.bubble")
                            .foregroundStyle(.yellow)
                        Text(comment)
                            .font(.callout)
                            .italic()
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            HStack {
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Reject", role: .destructive) {
                    onReject()
                }

                Button("Accept") {
                    onAccept()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

// MARK: - Status Picker Sheet

/// A sheet for selecting the next status state from available transitions.
struct StatusPickerSheet: View {
    let currentState: String
    let nextStates: [String]
    let onSelect: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Advance Status")
                .font(.headline)

            Text("Current: \(currentState)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(nextStates, id: \.self) { state in
                    Button {
                        onSelect(state)
                    } label: {
                        Text(state)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }

            Button("Cancel", role: .cancel) {
                onCancel()
            }
            .keyboardShortcut(.escape)
        }
        .padding(20)
        .frame(width: 300)
    }
}
