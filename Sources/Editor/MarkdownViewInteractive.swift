import AppKit
import SwiftUI
import aimdRenderer
import MarkdownEngine

/// G4-P3 click routing for the interactive core four. The engine hands back
/// the opaque identifier the overlay stamped (`choice:<loc>:<idx>`,
/// `status:<loc>`, `fillin:<loc>`); we re-detect in the current text, match by
/// anchor offset, and route through `InteractionHandler` — the same serialized,
/// detector-anchored write path as every other edit, so the bytes match.
extension MarkdownView {

    /// Returns true if the identifier was recognized and handled.
    func handleElementClick(_ identifier: String, windowRect: NSRect) -> Bool {
        guard let url = coordinator.navigation.selectedFile else { return false }
        let text = coordinator.document.content
        let parts = identifier.split(separator: ":").map(String.init)
        guard let kind = parts.first else { return false }

        switch kind {
        case "choice":
            guard parts.count == 3, let anchor = Int(parts[1]), let optIdx = Int(parts[2]),
                  let choice = choice(at: anchor, in: text) else { return false }
            let handler = interactionHandler, watcher = fileWatcher
            runWrite(url: url) { onUpdate in
                try await handler.selectChoice(
                    optionIndex: optIdx, in: choice, displayedContent: text,
                    url: url, fileWatcher: watcher, onContentUpdated: onUpdate)
            }
            return true

        case "choice-add":
            guard parts.count == 2, let anchor = Int(parts[1]),
                  let choice = choice(at: anchor, in: text) else { return false }
            let handler = interactionHandler, watcher = fileWatcher
            runWrite(url: url) { onUpdate in
                try await handler.addChoiceOption(
                    choice, displayedContent: text, url: url,
                    fileWatcher: watcher, onContentUpdated: onUpdate)
            }
            return true

        case "status":
            guard parts.count == 2, let anchor = Int(parts[1]),
                  let status = status(at: anchor, in: text) else { return false }
            presentStatusMenu(status, url: url, text: text, windowRect: windowRect)
            return true

        case "fillin":
            guard parts.count == 2, let anchor = Int(parts[1]),
                  let fillIn = fillIn(at: anchor, in: text) else { return false }
            presentFillInPopover(fillIn, url: url, text: text, windowRect: windowRect)
            return true

        default:
            return false
        }
    }

    // MARK: - Element lookup (match the overlay's anchor offset)

    private func choice(at anchor: Int, in text: String) -> ChoiceElement? {
        for case .choice(let c) in InteractiveElementDetector.detect(in: text)
        where NSRange(c.blockquoteRange, in: text).location == anchor { return c }
        return nil
    }

    private func status(at anchor: Int, in text: String) -> StatusElement? {
        for case .status(let s) in InteractiveElementDetector.detect(in: text)
        where NSRange(s.labelRange, in: text).location == anchor { return s }
        return nil
    }

    private func fillIn(at anchor: Int, in text: String) -> FillInElement? {
        for case .fillIn(let f) in InteractiveElementDetector.detect(in: text)
        where NSRange(f.range, in: text).location == anchor { return f }
        return nil
    }

    // MARK: - Status menu

    private func presentStatusMenu(_ status: StatusElement, url: URL, text: String, windowRect: NSRect) {
        let menu = NSMenu()
        for state in status.nextStates {
            let item = NSMenuItem(title: state, action: nil, keyEquivalent: "")
            item.representedObject = state
            item.target = StatusMenuTarget.shared
            item.action = #selector(StatusMenuTarget.pick(_:))
            let handler = interactionHandler, watcher = fileWatcher
            StatusMenuTarget.shared.onPick = { [self] chosen in
                runWrite(url: url) { onUpdate in
                    try await handler.advanceStatus(
                        status, to: chosen, displayedContent: text,
                        in: url, fileWatcher: watcher, onContentUpdated: onUpdate)
                }
            }
            menu.addItem(item)
        }
        guard let contentView = NSApp.keyWindow?.contentView else { return }
        let viewRect = contentView.convert(windowRect, from: nil)
        menu.popUp(positioning: nil,
                   at: NSPoint(x: viewRect.minX, y: viewRect.minY),
                   in: contentView)
    }

    // MARK: - Fill-in popover

    private func presentFillInPopover(_ fillIn: FillInElement, url: URL, text: String, windowRect: NSRect) {
        guard let contentView = NSApp.keyWindow?.contentView else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        // Offer a native date picker when the field is date-typed OR its value
        // already looks like a date (the sample docs store `[[text: 2026-…]]`,
        // which is text-typed but clearly a date the user expects to pick).
        let looksLikeDate = (fillIn.value ?? "").range(
            of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
        let handler = interactionHandler, watcher = fileWatcher
        let controller = FillInEditController(
            initialValue: fillIn.value ?? "",
            hint: fillIn.hint,
            isDate: fillIn.type == .date || looksLikeDate
        ) { [self] newValue in
            popover.close()
            runWrite(url: url) { onUpdate in
                try await handler.fillIn(
                    fillIn, value: newValue, displayedContent: text,
                    in: url, fileWatcher: watcher, onContentUpdated: onUpdate)
            }
        }
        popover.contentViewController = controller
        let viewRect = contentView.convert(windowRect, from: nil)
        popover.show(relativeTo: viewRect, of: contentView, preferredEdge: .maxY)
    }

    // MARK: - Write plumbing

    /// Runs an InteractionHandler write and folds the result back into the
    /// model + debounced save, mirroring `handleTextEdited`. The write body
    /// and the update closure both stay on the MainActor (InteractionHandler
    /// is `@MainActor`), so nothing crosses an isolation boundary.
    private func runWrite(url: URL,
                          _ body: @escaping @MainActor (@escaping (String) -> Void) async throws -> Void) {
        let coordinator = self.coordinator
        let watcher = self.fileWatcher
        Task { @MainActor in
            do {
                try await body { newContent in
                    let document = MarkdownDocumentRegistry.obtain(url: url, initialSource: newContent)
                    document.update(source: newContent)
                    coordinator.updateDocumentContent(newContent)
                    SaveCoordinator.shared.scheduleSave(for: document, fileWatcher: watcher)
                }
            } catch {
                coordinator.showError(.error(message: error.localizedDescription))
            }
        }
    }
}

// MARK: - Status menu target (NSMenu needs an ObjC target)

@MainActor
private final class StatusMenuTarget: NSObject {
    static let shared = StatusMenuTarget()
    var onPick: ((String) -> Void)?

    @objc func pick(_ sender: NSMenuItem) {
        guard let state = sender.representedObject as? String else { return }
        onPick?(state)
    }
}

// MARK: - Fill-in edit controller

private final class FillInEditController: NSViewController {
    private let initialValue: String
    private let hint: String
    private let isDate: Bool
    private let onCommit: (String) -> Void
    private var field: NSTextField!
    private var datePicker: NSDatePicker!

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    init(initialValue: String, hint: String, isDate: Bool, onCommit: @escaping (String) -> Void) {
        self.initialValue = initialValue
        self.hint = hint
        self.isDate = isDate
        self.onCommit = onCommit
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let pad: CGFloat = 14
        let buttonH: CGFloat = 28
        let container = NSView()
        let input: NSView

        if isDate {
            // Graphical calendar picker (month grid), not a stepper field.
            let picker = NSDatePicker()
            picker.datePickerStyle = .clockAndCalendar
            picker.datePickerElements = .yearMonthDay   // calendar only, no clock
            picker.dateValue = Self.dateFormatter.date(from: initialValue) ?? Date(timeIntervalSince1970: 0)
            picker.sizeToFit()
            picker.target = self
            picker.action = #selector(datePicked)        // pick a day → commit
            datePicker = picker
            input = picker
        } else {
            let tf = NSTextField()
            tf.stringValue = initialValue
            tf.placeholderString = hint
            tf.target = self
            tf.action = #selector(commit)
            tf.frame = NSRect(x: 0, y: 0, width: 236, height: 24)
            field = tf
            input = tf
        }

        // Lay out: input on top, Save button below it, right-aligned, roomy.
        let inputSize = input.fittingSize.width > 1 ? input.fittingSize : input.frame.size
        let contentW = max(inputSize.width, 236)
        let width = contentW + pad * 2
        let height = inputSize.height + buttonH + pad * 3

        input.setFrameOrigin(NSPoint(x: pad, y: pad * 2 + buttonH))
        container.addSubview(input)

        let button = NSButton(frame: NSRect(x: width - pad - 84, y: pad, width: 84, height: buttonH))
        button.title = "Save"
        button.bezelStyle = .rounded
        button.target = self
        button.action = #selector(commit)
        button.keyEquivalent = "\r"
        container.addSubview(button)

        container.frame = NSRect(x: 0, y: 0, width: width, height: height)
        view = container
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(isDate ? datePicker : field)
    }

    /// Clicking a day in the graphical calendar commits immediately.
    @objc private func datePicked() {
        // Single-click on a day fires the action; commit so the user doesn't
        // also have to press Save (Save stays for keyboard users).
        commit()
    }

    @objc private func commit() {
        let value = isDate ? Self.dateFormatter.string(from: datePicker.dateValue) : field.stringValue
        onCommit(value)
    }
}
