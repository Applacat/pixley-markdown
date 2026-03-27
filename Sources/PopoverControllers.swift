import AppKit
import aimdRenderer

// MARK: - Input Popover Configuration

/// Configuration for inline input popovers shown at interactive element positions.
struct InputPopoverConfig {
    let title: String
    let subtitle: String?
    let fieldName: String
    let placeholder: String
    let initialValue: String
    let multiline: Bool
    let allowEmpty: Bool

    init(title: String, subtitle: String? = nil, fieldName: String, placeholder: String = "",
         initialValue: String = "", multiline: Bool = false, allowEmpty: Bool = false) {
        self.title = title
        self.subtitle = subtitle
        self.fieldName = fieldName
        self.placeholder = placeholder
        self.initialValue = initialValue
        self.multiline = multiline
        self.allowEmpty = allowEmpty
    }
}

// MARK: - Input Popover Controller

/// NSViewController hosting a text input popover for fill-in, feedback, review notes, etc.
final class InputPopoverController: NSViewController {
    private let config: InputPopoverConfig
    private let onSubmit: (String) -> Void
    private let onCancel: () -> Void
    private var textField: NSTextField?
    private var scrolledTextView: NSScrollView?

    init(config: InputPopoverConfig, onSubmit: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.config = config
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let width: CGFloat = config.multiline ? 320 : 280
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 10))

        let title = NSTextField(labelWithString: config.title)
        title.font = .systemFont(ofSize: 13, weight: .semibold)

        var views: [NSView] = [title]

        if let sub = config.subtitle {
            let subtitle = NSTextField(wrappingLabelWithString: sub)
            subtitle.font = .systemFont(ofSize: 11)
            subtitle.textColor = .secondaryLabelColor
            views.append(subtitle)
        }

        if config.multiline {
            let sv = NSScrollView(frame: NSRect(x: 0, y: 0, width: width - 32, height: 80))
            let tv = NSTextView(frame: sv.contentView.bounds)
            tv.isRichText = false
            tv.font = .systemFont(ofSize: 13)
            tv.string = config.initialValue
            tv.isVerticallyResizable = true
            tv.autoresizingMask = [.width]
            tv.textContainer?.widthTracksTextView = true
            sv.documentView = tv
            sv.hasVerticalScroller = true
            sv.borderType = .bezelBorder
            sv.translatesAutoresizingMaskIntoConstraints = false
            sv.heightAnchor.constraint(equalToConstant: 80).isActive = true
            scrolledTextView = sv
            views.append(sv)
        } else {
            let tf = NSTextField(string: config.initialValue)
            tf.placeholderString = config.placeholder
            tf.font = .systemFont(ofSize: 13)
            // No target/action on the text field — the Submit button's keyEquivalent "\r"
            // handles Enter. Setting action here causes auto-submit when the field becomes
            // first responder with a pre-filled value (re-edit scenario).
            textField = tf
            views.append(tf)
        }

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancelButton.keyEquivalent = "\u{1b}"

        let submitButton = NSButton(title: "Submit", target: self, action: #selector(submitTapped))
        submitButton.keyEquivalent = "\r"
        submitButton.bezelStyle = .rounded

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let buttonStack = NSStackView(views: [cancelButton, spacer, submitButton])
        buttonStack.orientation = .horizontal
        views.append(buttonStack)

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.widthAnchor.constraint(equalToConstant: width),
        ])

        self.view = container
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if let tf = textField {
            tf.becomeFirstResponder()
            tf.selectText(nil)
        } else if let sv = scrolledTextView, let tv = sv.documentView as? NSTextView {
            view.window?.makeFirstResponder(tv)
        }
    }

    private var inputValue: String {
        if let tf = textField {
            return tf.stringValue
        } else if let sv = scrolledTextView, let tv = sv.documentView as? NSTextView {
            return tv.string
        }
        return ""
    }

    @objc private func submitTapped() {
        let value = inputValue
        guard config.allowEmpty || !value.isEmpty else { return }
        onSubmit(value)
    }

    @objc private func cancelTapped() {
        onCancel()
    }
}

// MARK: - Date Picker Popover Controller

/// NSViewController hosting a graphical date picker popover.
final class DatePickerPopoverController: NSViewController {
    private let onSubmit: (String) -> Void
    private let onCancel: () -> Void
    private let initialDate: String?
    private var datePicker: NSDatePicker!

    private static let outputFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init(initialDate: String? = nil, onSubmit: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.initialDate = initialDate
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 10))

        let title = NSTextField(labelWithString: "Pick a Date")
        title.font = .systemFont(ofSize: 13, weight: .semibold)

        datePicker = NSDatePicker()
        datePicker.datePickerStyle = .clockAndCalendar
        datePicker.datePickerElements = .yearMonthDay
        // Pre-populate with existing date if re-editing
        if let initialDate, let parsed = Self.outputFormatter.date(from: initialDate) {
            datePicker.dateValue = parsed
        } else {
            datePicker.dateValue = Date()
        }

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancelButton.keyEquivalent = "\u{1b}"

        let submitButton = NSButton(title: "Submit", target: self, action: #selector(submitTapped))
        submitButton.keyEquivalent = "\r"
        submitButton.bezelStyle = .rounded

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let buttonStack = NSStackView(views: [cancelButton, spacer, submitButton])
        buttonStack.orientation = .horizontal

        let stack = NSStackView(views: [title, datePicker, buttonStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        self.view = container
    }

    @objc private func submitTapped() {
        onSubmit(Self.outputFormatter.string(from: datePicker.dateValue))
    }

    @objc private func cancelTapped() {
        onCancel()
    }
}

// MARK: - Gutter Comment Popover Controller

/// NSViewController hosting a unified bookmark + comment popover for the gutter.
/// Shows a bookmark toggle checkbox and a multi-line text field for writing `<!-- feedback -->` comments.
final class GutterCommentPopoverController: NSViewController {
    private let isBookmarked: Bool
    private let existingComment: String
    private let onSubmit: (Bool, String) -> Void
    private let onCancel: () -> Void
    private var bookmarkCheckbox: NSButton!
    private var scrolledTextView: NSScrollView!

    init(isBookmarked: Bool, existingComment: String,
         onSubmit: @escaping (Bool, String) -> Void, onCancel: @escaping () -> Void) {
        self.isBookmarked = isBookmarked
        self.existingComment = existingComment
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let width: CGFloat = 300
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 10))

        let title = NSTextField(labelWithString: "Line Note")
        title.font = .systemFont(ofSize: 13, weight: .semibold)

        // Bookmark checkbox
        bookmarkCheckbox = NSButton(checkboxWithTitle: "Bookmark this line", target: nil, action: nil)
        bookmarkCheckbox.state = isBookmarked ? .on : .off

        // Comment text view
        let sv = NSScrollView(frame: NSRect(x: 0, y: 0, width: width - 32, height: 60))
        let tv = NSTextView(frame: sv.contentView.bounds)
        tv.isRichText = false
        tv.font = .systemFont(ofSize: 12)
        tv.string = existingComment
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        sv.documentView = tv
        sv.hasVerticalScroller = true
        sv.borderType = .bezelBorder
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.heightAnchor.constraint(equalToConstant: 60).isActive = true
        scrolledTextView = sv

        let commentLabel = NSTextField(labelWithString: "Comment")
        commentLabel.font = .systemFont(ofSize: 11)
        commentLabel.textColor = .secondaryLabelColor

        // Buttons
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancelButton.keyEquivalent = "\u{1b}"

        let submitButton = NSButton(title: "Save", target: self, action: #selector(submitTapped))
        submitButton.keyEquivalent = "\r"
        submitButton.bezelStyle = .rounded

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let buttonStack = NSStackView(views: [cancelButton, spacer, submitButton])
        buttonStack.orientation = .horizontal

        let stack = NSStackView(views: [title, bookmarkCheckbox, commentLabel, sv, buttonStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.widthAnchor.constraint(equalToConstant: width),
        ])

        self.view = container
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if let tv = scrolledTextView.documentView as? NSTextView {
            view.window?.makeFirstResponder(tv)
        }
    }

    @objc private func submitTapped() {
        let shouldBookmark = bookmarkCheckbox.state == .on
        let text = (scrolledTextView.documentView as? NSTextView)?.string ?? ""
        onSubmit(shouldBookmark, text)
    }

    @objc private func cancelTapped() {
        onCancel()
    }
}

// MARK: - Suggestion Popover Controller

/// NSViewController hosting an accept/reject popover for CriticMarkup suggestions.
final class SuggestionPopoverController: NSViewController {
    private let suggestion: SuggestionElement
    private let onAccept: () -> Void
    private let onReject: () -> Void
    private let onCancel: () -> Void

    init(suggestion: SuggestionElement, onAccept: @escaping () -> Void, onReject: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.suggestion = suggestion
        self.onAccept = onAccept
        self.onReject = onReject
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 10))

        let title = NSTextField(labelWithString: "Suggested Edit")
        title.font = .systemFont(ofSize: 13, weight: .semibold)

        // Build change rows as grid for proper column alignment and sizing
        var gridRows: [[NSView]] = []
        let labelMaxWidth: CGFloat = 240

        if let oldText = suggestion.oldText, !oldText.isEmpty {
            let icon = NSImageView(image: NSImage(systemSymbolName: "minus.circle.fill", accessibilityDescription: "Remove")!)
            icon.contentTintColor = .systemRed
            icon.setContentHuggingPriority(.required, for: .horizontal)

            let label = NSTextField(labelWithString: "")
            label.lineBreakMode = .byWordWrapping
            label.maximumNumberOfLines = 0
            label.preferredMaxLayoutWidth = labelMaxWidth
            label.attributedStringValue = NSAttributedString(string: oldText, attributes: [
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: 12),
            ])
            gridRows.append([icon, label])
        }

        if let newText = suggestion.newText, !newText.isEmpty {
            let icon = NSImageView(image: NSImage(systemSymbolName: "plus.circle.fill", accessibilityDescription: "Add")!)
            icon.contentTintColor = .systemGreen
            icon.setContentHuggingPriority(.required, for: .horizontal)

            let label = NSTextField(labelWithString: newText)
            label.font = .systemFont(ofSize: 12)
            label.lineBreakMode = .byWordWrapping
            label.maximumNumberOfLines = 0
            label.preferredMaxLayoutWidth = labelMaxWidth
            gridRows.append([icon, label])
        }

        if let comment = suggestion.comment {
            let icon = NSImageView(image: NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "Comment")!)
            icon.contentTintColor = .systemYellow
            icon.setContentHuggingPriority(.required, for: .horizontal)

            let label = NSTextField(labelWithString: comment)
            label.font = .systemFont(ofSize: 12)
            label.textColor = .secondaryLabelColor
            label.lineBreakMode = .byWordWrapping
            label.maximumNumberOfLines = 0
            label.preferredMaxLayoutWidth = labelMaxWidth
            gridRows.append([icon, label])
        }

        let grid = NSGridView(views: gridRows)
        grid.rowSpacing = 6
        grid.columnSpacing = 8
        grid.column(at: 0).width = 20  // icon column fixed width

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancelButton.keyEquivalent = "\u{1b}"

        let rejectButton = NSButton(title: "Reject", target: self, action: #selector(rejectTapped))
        rejectButton.contentTintColor = .systemRed

        let acceptButton = NSButton(title: "Accept", target: self, action: #selector(acceptTapped))
        acceptButton.keyEquivalent = "\r"
        acceptButton.bezelStyle = .rounded

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let buttonStack = NSStackView(views: [cancelButton, spacer, rejectButton, acceptButton])
        buttonStack.orientation = .horizontal

        let stack = NSStackView(views: [title, grid, buttonStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.widthAnchor.constraint(equalToConstant: 320),
        ])

        self.view = container
    }

    @objc private func acceptTapped() { onAccept() }
    @objc private func rejectTapped() { onReject() }
    @objc private func cancelTapped() { onCancel() }
}

// MARK: - Comment Popover Controller

/// NSViewController hosting a read/edit/remove popover for CriticMarkup highlight comments.
/// Shows the comment text with Edit and Remove actions.
final class CommentPopoverController: NSViewController {
    private let commentText: String
    private let onEdit: (String) -> Void
    private let onRemove: () -> Void
    private let onCancel: () -> Void
    private var isEditing = false
    private var commentLabel: NSTextField!
    private var editTextView: NSScrollView?
    private var editButton: NSButton!
    private var saveButton: NSButton!

    init(commentText: String,
         onEdit: @escaping (String) -> Void,
         onRemove: @escaping () -> Void,
         onCancel: @escaping () -> Void) {
        self.commentText = commentText
        self.onEdit = onEdit
        self.onRemove = onRemove
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let width: CGFloat = 300
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 10))

        let title = NSTextField(labelWithString: "Comment")
        title.font = .systemFont(ofSize: 13, weight: .semibold)

        // Comment text (read-only label)
        commentLabel = NSTextField(wrappingLabelWithString: commentText)
        commentLabel.font = .systemFont(ofSize: 12)
        commentLabel.textColor = .secondaryLabelColor
        commentLabel.maximumNumberOfLines = 10
        commentLabel.preferredMaxLayoutWidth = width - 32 // account for edge insets

        // Buttons
        let removeButton = NSButton(title: "Remove", target: self, action: #selector(removeTapped))
        removeButton.contentTintColor = .systemRed

        editButton = NSButton(title: "Edit", target: self, action: #selector(editTapped))

        saveButton = NSButton(title: "Save", target: self, action: #selector(saveTapped))
        saveButton.keyEquivalent = "\r"
        saveButton.bezelStyle = .rounded
        saveButton.isHidden = true

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let buttonStack = NSStackView(views: [removeButton, spacer, editButton, saveButton])
        buttonStack.orientation = .horizontal

        let stack = NSStackView(views: [title, commentLabel, buttonStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.widthAnchor.constraint(equalToConstant: width),
        ])

        self.view = container
    }

    @objc private func editTapped() {
        guard !isEditing else { return }
        isEditing = true

        // Replace label with editable text view
        let sv = NSScrollView(frame: NSRect(x: 0, y: 0, width: 268, height: 60))
        let tv = NSTextView(frame: sv.contentView.bounds)
        tv.isRichText = false
        tv.font = .systemFont(ofSize: 12)
        tv.string = commentText
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        sv.documentView = tv
        sv.hasVerticalScroller = true
        sv.borderType = .bezelBorder
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.heightAnchor.constraint(equalToConstant: 60).isActive = true

        if let stack = commentLabel.superview as? NSStackView,
           let index = stack.arrangedSubviews.firstIndex(of: commentLabel) {
            stack.removeArrangedSubview(commentLabel)
            commentLabel.removeFromSuperview()
            stack.insertArrangedSubview(sv, at: index)
            editTextView = sv
        }

        editButton.isHidden = true
        saveButton.isHidden = false
        view.window?.makeFirstResponder(tv)
    }

    @objc private func saveTapped() {
        guard let tv = editTextView?.documentView as? NSTextView else { return }
        let newComment = tv.string
        guard !newComment.isEmpty else { return }
        onEdit(newComment)
    }

    @objc private func removeTapped() {
        onRemove()
    }
}
