import AppKit

/// The spike's central question made concrete: the text view's storage is a
/// PROJECTION of the model source (checkbox lines become atomic attachments),
/// and the projection must be losslessly reversible at all times.
///
/// `source == serialize(buildStorage(source))` is asserted every cycle of the
/// stress loop — if this mapping can't hold under real editing, the TextKit 2
/// approach fails the spike.
@MainActor
enum SpikeProjection {

    static let bodyFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    /// Model source → attributed storage. Checkbox lines (`- [ ] label`)
    /// become a single attachment character; everything else passes through
    /// verbatim with lightweight styling (headings, bold markers visible —
    /// Typora reveal is US-0.2's problem, not US-0.1's).
    static func buildStorage(
        source: String,
        onToggle: @escaping (CheckboxAttachment) -> Void
    ) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        let lines = source.components(separatedBy: "\n")

        for (index, line) in lines.enumerated() {
            if let checkbox = parseCheckboxLine(line) {
                let attachment = CheckboxAttachment(isChecked: checkbox.isChecked, label: checkbox.label)
                attachment.onToggle = onToggle
                result.append(NSAttributedString(attachment: attachment))
            } else {
                result.append(styledLine(line))
            }
            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: [.font: bodyFont]))
            }
        }
        return result
    }

    /// Attributed storage → model source. Attachments reconstruct their
    /// checkbox line from live attachment state; text passes through verbatim.
    static func serialize(storage: NSAttributedString) -> String {
        var result = ""
        storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length)) { attributes, range, _ in
            if let attachment = attributes[.attachment] as? CheckboxAttachment {
                result += "- [\(attachment.isChecked ? "x" : " ")] \(attachment.label)"
            } else {
                result += (storage.string as NSString).substring(with: range)
            }
        }
        // NSTextAttachment occupies U+FFFC in the plain string; ensure none leaked
        return result.replacingOccurrences(of: "\u{FFFC}", with: "")
    }

    // MARK: - Checkbox line grammar

    struct CheckboxLine {
        let isChecked: Bool
        let label: String
    }

    static func parseCheckboxLine(_ line: String) -> CheckboxLine? {
        // Spike grammar: exact `- [ ] label` / `- [x] label`, no leading indent
        guard line.hasPrefix("- [") , line.count >= 6 else { return nil }
        let markIndex = line.index(line.startIndex, offsetBy: 3)
        let closeIndex = line.index(line.startIndex, offsetBy: 4)
        let mark = line[markIndex]
        guard line[closeIndex] == "]", mark == " " || mark == "x" else { return nil }
        let afterClose = line.index(closeIndex, offsetBy: 1)
        guard afterClose < line.endIndex, line[afterClose] == " " else { return nil }
        let label = String(line[line.index(after: afterClose)...])
        return CheckboxLine(isChecked: mark == "x", label: label)
    }

    // MARK: - Styling (markers visible in US-0.1)

    private static func styledLine(_ line: String) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: line, attributes: [
            .font: bodyFont,
            .foregroundColor: NSColor.textColor,
        ])

        if line.hasPrefix("# ") {
            attributed.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 22, weight: .bold), range: NSRange(location: 0, length: attributed.length))
        } else if line.hasPrefix("## ") {
            attributed.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 18, weight: .bold), range: NSRange(location: 0, length: attributed.length))
        }

        // Bold runs: style content, markers stay visible (US-0.1)
        let pattern = try! NSRegularExpression(pattern: #"\*\*([^*]+)\*\*"#)
        let ns = line as NSString
        for match in pattern.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
            attributed.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .bold), range: match.range)
        }
        return attributed
    }
}
