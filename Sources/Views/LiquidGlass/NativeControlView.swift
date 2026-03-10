import SwiftUI
import AppKit
import aimdRenderer

// MARK: - Native Control View

/// Maps a Pixley `InteractiveElement` to a native macOS SwiftUI control.
struct NativeControlView: View {

    let element: InteractiveElement
    let onChanged: (InteractiveElement, Int?, String, String) -> Void
    let onClicked: (InteractiveElement, Int?) -> Void
    let onStatusSelected: (StatusElement, String) -> Void

    var body: some View {
        Group {
            switch element {
            case .checkbox(let cb):
                checkboxView(cb)
            case .choice(let ch):
                choiceView(ch)
            case .fillIn(let fi):
                fillInView(fi)
            case .feedback(let fb):
                feedbackView(fb)
            case .status(let st):
                statusView(st)
            case .confidence(let conf):
                confidenceView(conf)
            case .suggestion(let sug):
                suggestionView(sug)
            case .review(let rv):
                reviewView(rv)
            case .collapsible(let col):
                collapsibleView(col)
            case .conditional:
                EmptyView()
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Checkbox → Toggle(.checkbox)

    private func checkboxView(_ cb: CheckboxElement) -> some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(
                get: { cb.isChecked },
                set: { _ in onClicked(element, nil) }
            )) {
                Text(cb.label)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(cb.isChecked ? .secondary : .primary)
            }
            .toggleStyle(.checkbox)
        }
    }

    // MARK: - Choice → Picker

    private func choiceView(_ ch: ChoiceElement) -> some View {
        let labels = ch.options.map(\.label)
        let selected = ch.selectedIndex ?? -1

        return VStack(alignment: .leading, spacing: 4) {
            if labels.count <= 4 {
                // Segmented picker for small option counts
                Picker("", selection: Binding(
                    get: { selected },
                    set: { newIndex in
                        if newIndex >= 0 && newIndex < ch.options.count {
                            onClicked(element, newIndex)
                        }
                    }
                )) {
                    ForEach(labels.indices, id: \.self) { i in
                        Text(labels[i]).tag(i)
                    }
                }
                .pickerStyle(.segmented)
            } else {
                // Menu picker for many options
                Picker("Select", selection: Binding(
                    get: { selected },
                    set: { newIndex in
                        if newIndex >= 0 && newIndex < ch.options.count {
                            onClicked(element, newIndex)
                        }
                    }
                )) {
                    ForEach(labels.indices, id: \.self) { i in
                        Text(labels[i]).tag(i)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    // MARK: - Fill-In → TextField / DatePicker / Button

    private func fillInView(_ fi: FillInElement) -> some View {
        Group {
            switch fi.type {
            case .text:
                FillInTextField(element: fi, onSubmit: { value in
                    onChanged(element, nil, "value", value)
                })

            case .date:
                FillInDatePicker(element: fi, onSubmit: { value in
                    onChanged(element, nil, "value", value)
                })

            case .file:
                Button {
                    onClicked(element, nil)
                } label: {
                    Label(fi.value ?? fi.hint, systemImage: "doc")
                }
                .buttonStyle(.bordered)

            case .folder:
                Button {
                    onClicked(element, nil)
                } label: {
                    Label(fi.value ?? fi.hint, systemImage: "folder")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Feedback → TextEditor

    private func feedbackView(_ fb: FeedbackElement) -> some View {
        FeedbackTextEditor(element: fb, onSubmit: { value in
            onChanged(element, nil, "feedback", value)
        })
    }

    // MARK: - Status → Picker (menu)

    private func statusView(_ st: StatusElement) -> some View {
        HStack(spacing: 8) {
            Text("Status:")
                .font(.system(.body, design: .monospaced).weight(.semibold))

            Picker("", selection: Binding(
                get: { st.currentState },
                set: { newState in
                    onStatusSelected(st, newState)
                }
            )) {
                ForEach(st.states, id: \.self) { state in
                    Text(state).tag(state)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 200)
        }
    }

    // MARK: - Confidence → Gauge

    private func confidenceView(_ conf: ConfidenceElement) -> some View {
        HStack(spacing: 8) {
            let value: Double = switch conf.level {
            case .high: 1.0
            case .medium: 0.6
            case .low: 0.3
            case .confirmed: 1.0
            }

            let color: Color = switch conf.level {
            case .high: .green
            case .medium: .orange
            case .low: .red
            case .confirmed: .blue
            }

            Gauge(value: value) {
                Text(conf.level.rawValue.capitalized)
                    .font(.system(.caption, design: .monospaced))
            }
            .gaugeStyle(.accessoryLinear)
            .tint(color)
            .frame(maxWidth: 200)

            Text(conf.text)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)

            if conf.level == .high {
                Button("Confirm") {
                    onClicked(element, nil)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if conf.level == .low || conf.level == .medium {
                Button("Challenge") {
                    // Show challenge input
                    onChanged(element, nil, "challenge", "")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Suggestion → Diff view

    private func suggestionView(_ sug: SuggestionElement) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "pencil.and.outline")
                    .foregroundStyle(.orange)
                Text("Suggested Edit")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.orange)
            }

            if let old = sug.oldText, !old.isEmpty {
                HStack(spacing: 4) {
                    Text("-")
                        .foregroundStyle(.red)
                        .fontWeight(.bold)
                    Text(old)
                        .strikethrough()
                        .foregroundStyle(.red.opacity(0.7))
                }
                .font(.system(.body, design: .monospaced))
            }

            if let new = sug.newText, !new.isEmpty {
                HStack(spacing: 4) {
                    Text("+")
                        .foregroundStyle(.green)
                        .fontWeight(.bold)
                    Text(new)
                        .foregroundStyle(.green.opacity(0.8))
                }
                .font(.system(.body, design: .monospaced))
            }

            HStack(spacing: 8) {
                Button("Accept") {
                    onChanged(element, nil, "suggestion", "accept")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Reject") {
                    onChanged(element, nil, "suggestion", "reject")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Review → Segmented Picker + Notes

    private func reviewView(_ rv: ReviewElement) -> some View {
        ReviewControlView(element: rv, parentElement: element, onChanged: onChanged)
    }

    // MARK: - Collapsible

    private func collapsibleView(_ col: CollapsibleElement) -> some View {
        DisclosureGroup(col.title) {
            // Render inner content as raw text for now
            Text("(collapsible content)")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .font(.system(.body, design: .monospaced))
    }
}

// MARK: - Fill-In Text Field

private struct FillInTextField: View {
    let element: FillInElement
    let onSubmit: (String) -> Void
    @State private var value: String

    init(element: FillInElement, onSubmit: @escaping (String) -> Void) {
        self.element = element
        self.onSubmit = onSubmit
        self._value = State(initialValue: element.value ?? "")
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField(element.hint, text: $value)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: 300)
                .onSubmit {
                    onSubmit(value)
                }

            if !value.isEmpty && value != element.value {
                Button("Save") {
                    onSubmit(value)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}

// MARK: - Fill-In Date Picker

private struct FillInDatePicker: View {
    let element: FillInElement
    let onSubmit: (String) -> Void
    @State private var date: Date

    init(element: FillInElement, onSubmit: @escaping (String) -> Void) {
        self.element = element
        self.onSubmit = onSubmit

        // Parse existing value if present
        if let value = element.value {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            self._date = State(initialValue: fmt.date(from: value) ?? Date())
        } else {
            self._date = State(initialValue: Date())
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            DatePicker(element.hint, selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .frame(maxWidth: 300)
                .onChange(of: date) {
                    let fmt = DateFormatter()
                    fmt.dateFormat = "yyyy-MM-dd"
                    onSubmit(fmt.string(from: date))
                }
        }
    }
}

// MARK: - Feedback Text Editor

private struct FeedbackTextEditor: View {
    let element: FeedbackElement
    let onSubmit: (String) -> Void
    @State private var text: String

    init(element: FeedbackElement, onSubmit: @escaping (String) -> Void) {
        self.element = element
        self.onSubmit = onSubmit
        self._text = State(initialValue: element.existingText ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Feedback")
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(.secondary)

            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 60, maxHeight: 120)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                )

            HStack {
                Spacer()
                Button("Submit") {
                    onSubmit(text)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(text.isEmpty)
            }
        }
    }
}

// MARK: - Review Control View

private struct ReviewControlView: View {
    let element: ReviewElement
    let parentElement: InteractiveElement
    let onChanged: (InteractiveElement, Int?, String, String) -> Void

    @State private var selectedIndex: Int
    @State private var notes: String = ""

    init(element: ReviewElement, parentElement: InteractiveElement, onChanged: @escaping (InteractiveElement, Int?, String, String) -> Void) {
        self.element = element
        self.parentElement = parentElement
        self.onChanged = onChanged

        let initial = element.options.firstIndex(where: { $0.isSelected }) ?? -1
        self._selectedIndex = State(initialValue: initial)

        if let selected = element.options.first(where: { $0.isSelected }), let n = selected.notes {
            self._notes = State(initialValue: n)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Segmented picker for review options
            Picker("", selection: $selectedIndex) {
                ForEach(element.options.indices, id: \.self) { i in
                    Text(element.options[i].status.rawValue).tag(i)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedIndex) { _, newIndex in
                guard newIndex >= 0, newIndex < element.options.count else { return }
                let option = element.options[newIndex]
                if option.status.promptsForNotes {
                    // Wait for notes input
                } else {
                    onChanged(parentElement, newIndex, "review", "")
                }
            }

            // Notes field for statuses that prompt for notes
            if selectedIndex >= 0, selectedIndex < element.options.count,
               element.options[selectedIndex].status.promptsForNotes {
                HStack(spacing: 8) {
                    TextField("Notes...", text: $notes)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    Button("Submit") {
                        onChanged(parentElement, selectedIndex, "review", notes)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }
}
