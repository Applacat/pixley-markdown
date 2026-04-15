import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
import aimdRenderer

// MARK: - Native Control View

/// Maps a Pixley `InteractiveElement` to a native macOS SwiftUI control.
struct NativeControlView: View {

    let element: InteractiveElement
    let documentContent: String
    let palette: SyntaxPalette
    let onChanged: (InteractiveElement, Int?, String, String) -> Void
    let onClicked: (InteractiveElement, Int?) -> Void
    let onStatusSelected: (StatusElement, String) -> Void

    var body: some View {
        controlContent
            .focusable()
            #if os(iOS)
            // iOS: controls render as cards — system font, rounded background,
            // visual break from the monospace document text to signal interactivity.
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            #else
            .padding(.vertical, 2)
            #endif
    }

    @ViewBuilder
    private var controlContent: some View {
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
        case .slider(let s):
            sliderView(s)
        case .stepper(let s):
            stepperView(s)
        case .toggle(let t):
            toggleView(t)
        case .colorPicker(let cp):
            colorPickerView(cp)
        case .auditableCheckbox(let ac):
            auditableCheckboxView(ac)
        }
    }

    // MARK: - Checkbox → Toggle(.checkbox)

    private func checkboxView(_ cb: CheckboxElement) -> some View {
        #if os(iOS)
        // iOS: full-row tap target, system font, 44pt minimum height
        Button {
            onClicked(element, nil)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: cb.isChecked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(cb.isChecked ? .blue : .secondary)
                    .font(.title3)
                Text(cb.label)
                    .foregroundStyle(cb.isChecked ? .secondary : .primary)
                Spacer()
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        #else
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
        #endif
    }

    // MARK: - Choice → Picker

    private func choiceView(_ ch: ChoiceElement) -> some View {
        let labels = ch.options.map(\.label)
        let selected = ch.selectedIndex ?? -1

        #if os(iOS)
        // iOS: full-row tappable radio buttons, 44pt per row
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(labels.indices, id: \.self) { i in
                Button {
                    onClicked(element, i)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: i == selected ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(i == selected ? .blue : .secondary)
                            .font(.title3)
                        Text(labels[i])
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        #else
        return VStack(alignment: .leading, spacing: 4) {
            if labels.count <= 4 {
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
        #endif
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
                FilePathBadge(
                    path: fi.value,
                    iconName: "doc",
                    emptyLabel: "Choose file",
                    onClick: { onClicked(element, nil) }
                )

            case .folder:
                FilePathBadge(
                    path: fi.value,
                    iconName: "folder",
                    emptyLabel: "Choose folder",
                    onClick: { onClicked(element, nil) }
                )
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
            #if os(macOS)
            .frame(maxWidth: 200)
            #endif
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
                #if os(macOS)
                .controlSize(.small)
                #endif
            } else if conf.level == .low || conf.level == .medium {
                Button("Challenge") {
                    onChanged(element, nil, "challenge", "")
                }
                .buttonStyle(.bordered)
                #if os(macOS)
                .controlSize(.small)
                #endif
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
                #if os(macOS)
                .controlSize(.small)
                #endif

                Button("Reject") {
                    onChanged(element, nil, "suggestion", "reject")
                }
                .buttonStyle(.bordered)
                #if os(macOS)
                .controlSize(.small)
                #endif
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.1))
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
        let innerBlocks = parseCollapsibleContent(col)

        return DisclosureGroup(col.title) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(innerBlocks) { block in
                    ContentBlockView(
                        block: block,
                        palette: palette,
                        searchText: "",
                        onInteractiveElementChanged: onChanged,
                        onInteractiveElementClicked: onClicked,
                        onStatusSelected: onStatusSelected
                    )
                }
            }
        }
        .font(.system(.body, design: .monospaced))
    }

    private func parseCollapsibleContent(_ col: CollapsibleElement) -> [MarkdownBlock] {
        guard col.contentRange.lowerBound < col.contentRange.upperBound,
              col.contentRange.lowerBound >= documentContent.startIndex,
              col.contentRange.upperBound <= documentContent.endIndex else {
            return []
        }
        let innerElements = InteractiveElementDetector.detect(in: String(documentContent[col.contentRange]))
        return MarkdownBlockParser.parse(
            content: documentContent,
            sectionRange: col.contentRange,
            elements: innerElements,
            includeHeadings: true
        )
    }

    // MARK: - Slider (Spec 4)

    private func sliderView(_ s: SliderElement) -> some View {
        SliderControl(element: s, parent: element, onChanged: onChanged)
    }

    // MARK: - Stepper (Spec 4)

    private func stepperView(_ s: StepperElement) -> some View {
        StepperControl(element: s, parent: element, onChanged: onChanged)
    }

    // MARK: - Toggle (Spec 4)

    private func toggleView(_ t: ToggleElement) -> some View {
        ToggleControl(element: t, parent: element, onChanged: onChanged)
    }

    // MARK: - Color Picker (Spec 4)

    private func colorPickerView(_ cp: ColorPickerElement) -> some View {
        ColorPickerControl(element: cp, parent: element, onChanged: onChanged)
    }

    // MARK: - Auditable Checkbox (Spec 4)

    private func auditableCheckboxView(_ ac: AuditableCheckboxElement) -> some View {
        AuditableCheckboxControl(element: ac, parent: element, onChanged: onChanged, onClicked: onClicked)
    }
}

// MARK: - Spec 4 Control Views

private struct SliderControl: View {
    let element: SliderElement
    let parent: InteractiveElement
    let onChanged: (InteractiveElement, Int?, String, String) -> Void

    @State private var draftValue: Double

    init(element: SliderElement, parent: InteractiveElement, onChanged: @escaping (InteractiveElement, Int?, String, String) -> Void) {
        self.element = element
        self.parent = parent
        self.onChanged = onChanged
        self._draftValue = State(initialValue: Double(element.minValue))
    }

    var body: some View {
        HStack(spacing: 8) {
            Slider(
                value: $draftValue,
                in: Double(element.minValue)...Double(element.maxValue),
                step: 1,
                onEditingChanged: { editing in
                    // Write on release (editing transitions from true → false)
                    if !editing {
                        let intValue = Int(draftValue.rounded())
                        onChanged(parent, nil, "value", "\(intValue)")
                    }
                }
            )
            #if os(macOS)
            .frame(width: 160)
            #else
            .frame(maxWidth: .infinity)
            #endif

            Text("\(Int(draftValue.rounded()))")
                .font(.system(.body, design: .monospaced).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 24, alignment: .trailing)
        }
    }
}

private struct StepperControl: View {
    let element: StepperElement
    let parent: InteractiveElement
    let onChanged: (InteractiveElement, Int?, String, String) -> Void

    @State private var value: Int

    init(element: StepperElement, parent: InteractiveElement, onChanged: @escaping (InteractiveElement, Int?, String, String) -> Void) {
        self.element = element
        self.parent = parent
        self.onChanged = onChanged
        // Initialize at minValue (or 0 for unbounded) so it's always within range — avoids clamping onChange
        self._value = State(initialValue: element.minValue ?? 0)
    }

    var body: some View {
        HStack(spacing: 4) {
            Stepper(
                value: $value,
                in: (element.minValue ?? 0)...(element.maxValue ?? 99),
                step: 1
            ) {
                Text("\(value)")
                    .font(.system(.body, design: .monospaced).monospacedDigit())
                    .frame(minWidth: 24, alignment: .trailing)
            }
            .onChange(of: value) { _, newValue in
                onChanged(parent, nil, "value", "\(newValue)")
            }
        }
    }
}

private struct ToggleControl: View {
    let element: ToggleElement
    let parent: InteractiveElement
    let onChanged: (InteractiveElement, Int?, String, String) -> Void

    @State private var isOn: Bool = false

    var body: some View {
        Toggle("Toggle", isOn: $isOn)
            .toggleStyle(.switch)
            .onChange(of: isOn) { _, newValue in
                onChanged(parent, nil, "state", newValue ? "on" : "off")
            }
    }
}

private struct ColorPickerControl: View {
    let element: ColorPickerElement
    let parent: InteractiveElement
    let onChanged: (InteractiveElement, Int?, String, String) -> Void

    @State private var selectedColor: Color = .gray

    var body: some View {
        HStack(spacing: 6) {
            ColorPicker("", selection: $selectedColor, supportsOpacity: false)
                .labelsHidden()
                .onChange(of: selectedColor) { _, newColor in
                    onChanged(parent, nil, "hex", hexString(from: newColor))
                }

            Text("pick color")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func hexString(from color: Color) -> String {
        #if canImport(AppKit)
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? .gray
        let r = Int((max(0, min(1, nsColor.redComponent)) * 255).rounded())
        let g = Int((max(0, min(1, nsColor.greenComponent)) * 255).rounded())
        let b = Int((max(0, min(1, nsColor.blueComponent)) * 255).rounded())
        #else
        let uiColor = UIColor(color)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: nil)
        let r = Int((max(0, min(1, red)) * 255).rounded())
        let g = Int((max(0, min(1, green)) * 255).rounded())
        let b = Int((max(0, min(1, blue)) * 255).rounded())
        #endif
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

private struct AuditableCheckboxControl: View {
    let element: AuditableCheckboxElement
    let parent: InteractiveElement
    let onChanged: (InteractiveElement, Int?, String, String) -> Void
    let onClicked: (InteractiveElement, Int?) -> Void

    @State private var showNotePopover: Bool = false
    @State private var noteText: String = ""

    var body: some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(
                get: { element.isChecked },
                set: { newValue in
                    if newValue {
                        // Show note prompt on check
                        showNotePopover = true
                    } else {
                        // Uncheck immediately — clear audit trail
                        onChanged(parent, nil, "uncheck", "")
                    }
                }
            )) {
                HStack(spacing: 6) {
                    Text(element.label)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(element.isChecked ? .secondary : .primary)

                    if let date = element.date {
                        Text("— \(date)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    if let note = element.note, !note.isEmpty {
                        Text(": \(note)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            #if os(macOS)
            .toggleStyle(.checkbox)
            #endif
        }
        .popover(isPresented: $showNotePopover) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Add note (optional)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)

                TextField("Note…", text: $noteText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    #if os(macOS)
                    .frame(width: 240)
                    #else
                    .frame(maxWidth: .infinity)
                    #endif

                HStack {
                    Button("Cancel") {
                        showNotePopover = false
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)

                    Button("No note") {
                        onChanged(parent, nil, "check", "")
                        showNotePopover = false
                    }
                    .buttonStyle(.bordered)

                    Button("Save") {
                        onChanged(parent, nil, "check", noteText)
                        showNotePopover = false
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(noteText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(12)
        }
        .onChange(of: showNotePopover) { _, shown in
            if !shown { noteText = "" }
        }
    }
}

// MARK: - File Path Badge (Spec 4: Re-pickable file/folder)

/// Clickable badge showing a file or folder path. Empty state shows a "Choose file/folder" button.
/// Filled state shows filename + faded parent path.
private struct FilePathBadge: View {
    let path: String?
    let iconName: String
    let emptyLabel: String
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.caption)

                if let path, !path.isEmpty {
                    // Show faded parent + filename
                    let url = URL(fileURLWithPath: path)
                    let filename = url.lastPathComponent
                    let parent = url.deletingLastPathComponent().path

                    if !parent.isEmpty && parent != "/" {
                        Text("\(abbreviatedParent(parent)) ‹ ")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(filename)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                } else {
                    Text(emptyLabel)
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
        .buttonStyle(.bordered)
        .help(path ?? emptyLabel)
    }

    /// Abbreviates home directory to `~` on macOS. On iOS, shows parent folder name.
    private func abbreviatedParent(_ path: String) -> String {
        #if os(macOS)
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + String(path.dropFirst(home.count))
        }
        return path
        #else
        return URL(fileURLWithPath: path).lastPathComponent
        #endif
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
                #if os(macOS)
                .frame(maxWidth: 300)
                #endif
                .onSubmit {
                    onSubmit(value)
                }

            if !value.isEmpty && value != element.value {
                Button("Save") {
                    onSubmit(value)
                }
                .buttonStyle(.bordered)
                #if os(macOS)
                .controlSize(.small)
                #endif
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
                #if os(iOS)
                .datePickerStyle(.compact)
                #else
                .datePickerStyle(.graphical)
                .frame(maxWidth: 300)
                #endif
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
                #if os(macOS)
                .controlSize(.small)
                #endif
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
                    #if os(macOS)
                    .controlSize(.small)
                    #endif
                }
            }
        }
    }
}
