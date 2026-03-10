import AppKit
import aimdRenderer

// MARK: - Upgrade Popover Controller

/// NSViewController that hosts the Pro upgrade prompt shown when a free user clicks a locked element.
final class UpgradePopoverController: NSViewController {
    private let elementName: String
    private let price: String
    private let onDismiss: () -> Void

    init(elementName: String, price: String, onDismiss: @escaping () -> Void) {
        self.elementName = elementName
        self.price = price
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 150))

        // Icon
        let iconView = NSImageView(frame: .zero)
        iconView.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Locked")
        iconView.symbolConfiguration = .init(pointSize: 20, weight: .medium)
        iconView.contentTintColor = .controlAccentColor
        iconView.translatesAutoresizingMaskIntoConstraints = false

        // Title
        let title = NSTextField(labelWithString: "Unlock \(elementName)")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false

        // Subtitle
        let subtitle = NSTextField(labelWithString: "Pixley Pro unlocks all interactive elements.")
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        // Purchase button
        let purchaseButton = NSButton(title: "Upgrade — \(price)", target: self, action: #selector(purchaseTapped))
        purchaseButton.bezelStyle = .rounded
        purchaseButton.controlSize = .large
        purchaseButton.keyEquivalent = "\r"
        purchaseButton.translatesAutoresizingMaskIntoConstraints = false

        // Restore link
        let restoreButton = NSButton(title: "Restore Purchase", target: self, action: #selector(restoreTapped))
        restoreButton.bezelStyle = .inline
        restoreButton.isBordered = false
        restoreButton.contentTintColor = .controlAccentColor
        restoreButton.font = .systemFont(ofSize: 11)
        restoreButton.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [iconView, title, subtitle, purchaseButton, restoreButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
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

    @objc private func purchaseTapped() {
        Task { @MainActor in
            await StoreService.shared.purchase()
            if StoreService.shared.isUnlocked {
                onDismiss()
            }
        }
    }

    @objc private func restoreTapped() {
        Task { @MainActor in
            await StoreService.shared.restore()
            if StoreService.shared.isUnlocked {
                onDismiss()
            }
        }
    }
}

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

        var contentViews: [NSView] = []

        if let oldText = suggestion.oldText, !oldText.isEmpty {
            let icon = NSImageView(image: NSImage(systemSymbolName: "minus.circle.fill", accessibilityDescription: "Remove")!)
            icon.contentTintColor = .systemRed
            let label = NSTextField(wrappingLabelWithString: oldText)
            label.font = .systemFont(ofSize: 12)
            let attrStr = NSMutableAttributedString(string: oldText, attributes: [
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: 12),
            ])
            label.attributedStringValue = attrStr
            let row = NSStackView(views: [icon, label])
            row.orientation = .horizontal
            row.spacing = 4
            contentViews.append(row)
        }

        if let newText = suggestion.newText, !newText.isEmpty {
            let icon = NSImageView(image: NSImage(systemSymbolName: "plus.circle.fill", accessibilityDescription: "Add")!)
            icon.contentTintColor = .systemGreen
            let label = NSTextField(wrappingLabelWithString: newText)
            label.font = .systemFont(ofSize: 12)
            let row = NSStackView(views: [icon, label])
            row.orientation = .horizontal
            row.spacing = 4
            contentViews.append(row)
        }

        if let comment = suggestion.comment {
            let icon = NSImageView(image: NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "Comment")!)
            icon.contentTintColor = .systemYellow
            let label = NSTextField(wrappingLabelWithString: comment)
            label.font = .systemFont(ofSize: 12)
            label.textColor = .secondaryLabelColor
            let row = NSStackView(views: [icon, label])
            row.orientation = .horizontal
            row.spacing = 4
            contentViews.append(row)
        }

        let contentStack = NSStackView(views: contentViews)
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 6

        let box = NSBox()
        box.boxType = .custom
        box.cornerRadius = 6
        box.fillColor = .quaternaryLabelColor
        box.borderColor = .clear
        box.contentView = contentStack
        box.contentViewMargins = NSSize(width: 8, height: 8)

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

        let stack = NSStackView(views: [title, box, buttonStack])
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

    @objc private func acceptTapped() { onAccept() }
    @objc private func rejectTapped() { onReject() }
    @objc private func cancelTapped() { onCancel() }
}
