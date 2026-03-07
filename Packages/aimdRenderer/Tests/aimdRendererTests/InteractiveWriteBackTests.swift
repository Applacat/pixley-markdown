import XCTest
@testable import aimdRenderer

/// Tests the detect → edit → re-detect round-trip for interactive elements.
/// These verify that string manipulation using ranges from the detector
/// produces correct results when re-parsed.
final class InteractiveWriteBackTests: XCTestCase {

    // MARK: - Checkbox Toggle

    func testToggleUncheckedCheckbox() {
        var content = "- [ ] Buy milk\n- [ ] Buy eggs\n"
        let elements = InteractiveElementDetector.detect(in: content)
        guard case .checkbox(let cb) = elements.first else {
            XCTFail("Expected checkbox"); return
        }
        XCTAssertFalse(cb.isChecked)

        // Toggle: replace check char with "x"
        content.replaceSubrange(cb.checkRange, with: "x")

        XCTAssertTrue(content.contains("- [x] Buy milk"))
        XCTAssertTrue(content.contains("- [ ] Buy eggs"))

        // Re-detect
        let after = InteractiveElementDetector.detect(in: content)
        guard case .checkbox(let r1) = after[0], case .checkbox(let r2) = after[1] else {
            XCTFail("Expected 2 checkboxes"); return
        }
        XCTAssertTrue(r1.isChecked)
        XCTAssertFalse(r2.isChecked)
    }

    func testToggleCheckedCheckbox() {
        var content = "- [x] Done task\n"
        let elements = InteractiveElementDetector.detect(in: content)
        guard case .checkbox(let cb) = elements.first else {
            XCTFail("Expected checkbox"); return
        }
        XCTAssertTrue(cb.isChecked)

        content.replaceSubrange(cb.checkRange, with: " ")
        XCTAssertTrue(content.contains("- [ ] Done task"))
    }

    func testToggleMultipleCheckboxesIndependently() {
        var content = "- [ ] A\n- [x] B\n- [ ] C\n"

        // Toggle first on
        let e1 = InteractiveElementDetector.detect(in: content)
        guard case .checkbox(let cb1) = e1[0] else { XCTFail(""); return }
        content.replaceSubrange(cb1.checkRange, with: "x")

        // Re-detect, toggle third on
        let e2 = InteractiveElementDetector.detect(in: content)
        guard case .checkbox(let cb3) = e2[2] else { XCTFail(""); return }
        content.replaceSubrange(cb3.checkRange, with: "x")

        // Verify final state
        let e3 = InteractiveElementDetector.detect(in: content)
        guard case .checkbox(let f1) = e3[0],
              case .checkbox(let f2) = e3[1],
              case .checkbox(let f3) = e3[2] else {
            XCTFail("Expected 3 checkboxes"); return
        }
        XCTAssertTrue(f1.isChecked)
        XCTAssertTrue(f2.isChecked)
        XCTAssertTrue(f3.isChecked)
    }

    // MARK: - Choice Selection (Radio)

    func testSelectChoiceOption() {
        var content = "> - [x] Option A\n> - [ ] Option B\n> - [ ] Option C\n"
        let elements = InteractiveElementDetector.detect(in: content)
        guard case .choice(let ch) = elements.first else {
            XCTFail("Expected choice"); return
        }

        // Radio select: option index 2 (C)
        let replacements = radioReplacements(choice: ch, selectIndex: 2)
        applyReplacements(&content, replacements)

        XCTAssertTrue(content.contains("> - [ ] Option A"))
        XCTAssertTrue(content.contains("> - [ ] Option B"))
        XCTAssertTrue(content.contains("> - [x] Option C"))

        // Re-detect: only C selected
        let after = InteractiveElementDetector.detect(in: content)
        guard case .choice(let ch2) = after.first else {
            XCTFail("Expected choice after edit"); return
        }
        XCTAssertFalse(ch2.options[0].isSelected)
        XCTAssertFalse(ch2.options[1].isSelected)
        XCTAssertTrue(ch2.options[2].isSelected)
    }

    func testSelectAlreadySelectedIsNoOp() {
        let content = "> - [x] Alpha\n> - [ ] Beta\n"
        let elements = InteractiveElementDetector.detect(in: content)
        guard case .choice(let ch) = elements.first else {
            XCTFail("Expected choice"); return
        }

        let replacements = radioReplacements(choice: ch, selectIndex: 0)
        // No changes needed — already selected
        XCTAssertTrue(replacements.isEmpty)
    }

    // MARK: - Fill-In

    func testFillInReplacement() {
        var content = "Name: [[your name]]\nAge: [[your age]]\n"
        let elements = InteractiveElementDetector.detect(in: content)
        guard case .fillIn(let fi) = elements.first else {
            XCTFail("Expected fillIn"); return
        }

        content.replaceSubrange(fi.range, with: "Alice")

        XCTAssertTrue(content.contains("Name: Alice"))
        XCTAssertTrue(content.contains("[[your age]]"))
    }

    func testFillInPreservesOtherPlaceholders() {
        var content = "[[first]] and [[second]]\n"
        let elements = InteractiveElementDetector.detect(in: content)
        guard case .fillIn(let fi1) = elements.first else {
            XCTFail("Expected fillIn"); return
        }

        content.replaceSubrange(fi1.range, with: "Hello")
        XCTAssertTrue(content.hasPrefix("Hello and [[second]]"))

        // Re-detect: second placeholder still detected
        let after = InteractiveElementDetector.detect(in: content)
        XCTAssertEqual(after.count, 1)
        guard case .fillIn(let fi2) = after.first else {
            XCTFail("Expected remaining fillIn"); return
        }
        XCTAssertEqual(fi2.hint, "second")
    }

    // MARK: - Feedback

    func testSetFeedback() {
        var content = "Review this.\n<!-- feedback -->\n"
        let elements = InteractiveElementDetector.detect(in: content)
        guard case .feedback(let fb) = elements.first else {
            XCTFail("Expected feedback"); return
        }

        let newComment = "<!-- feedback: Looks great! -->"
        content.replaceSubrange(fb.range, with: newComment)

        XCTAssertTrue(content.contains("<!-- feedback: Looks great! -->"))
        XCTAssertFalse(content.contains("<!-- feedback -->"))
    }

    func testOverwriteFeedback() {
        var content = "<!-- feedback: Old note -->\n"
        let elements = InteractiveElementDetector.detect(in: content)
        guard case .feedback(let fb) = elements.first else {
            XCTFail("Expected feedback"); return
        }

        content.replaceSubrange(fb.range, with: "<!-- feedback: New note -->")

        XCTAssertTrue(content.contains("<!-- feedback: New note -->"))
        XCTAssertFalse(content.contains("Old note"))

        // Re-detect: new text visible
        let after = InteractiveElementDetector.detect(in: content)
        guard case .feedback(let fb2) = after.first else {
            XCTFail("Expected feedback after edit"); return
        }
        XCTAssertEqual(fb2.existingText, "New note")
    }

    // MARK: - Mixed Document Round-Trip

    func testMixedDocumentRoundTrip() {
        var content = """
        # Setup
        - [ ] Install tools
        - [ ] Configure

        ## Options
        > - [ ] Plan A
        > - [x] Plan B

        Name: [[your name]]

        <!-- feedback -->

        """

        // 1. Toggle first checkbox
        var elements = InteractiveElementDetector.detect(in: content)
        guard case .checkbox(let cb) = elements[0] else { XCTFail(""); return }
        content.replaceSubrange(cb.checkRange, with: "x")

        // 2. Change choice to Plan A
        elements = InteractiveElementDetector.detect(in: content)
        guard case .choice(let ch) = elements.first(where: {
            if case .choice = $0 { return true }; return false
        }) else { XCTFail("Expected choice"); return }
        let reps = radioReplacements(choice: ch, selectIndex: 0)
        applyReplacements(&content, reps)

        // 3. Fill in name
        elements = InteractiveElementDetector.detect(in: content)
        guard case .fillIn(let fi) = elements.first(where: {
            if case .fillIn = $0 { return true }; return false
        }) else { XCTFail("Expected fillIn"); return }
        content.replaceSubrange(fi.range, with: "Bob")

        // 4. Set feedback
        elements = InteractiveElementDetector.detect(in: content)
        guard case .feedback(let fb) = elements.first(where: {
            if case .feedback = $0 { return true }; return false
        }) else { XCTFail("Expected feedback"); return }
        content.replaceSubrange(fb.range, with: "<!-- feedback: Done -->")

        // Verify final state
        let final_elements = InteractiveElementDetector.detect(in: content)

        // Checkboxes: first checked, second unchanged
        let checkboxes = final_elements.compactMap { e -> CheckboxElement? in
            if case .checkbox(let cb) = e { return cb }; return nil
        }
        XCTAssertEqual(checkboxes.count, 2)
        XCTAssertTrue(checkboxes[0].isChecked)
        XCTAssertFalse(checkboxes[1].isChecked)

        // Choice: Plan A selected
        let choices = final_elements.compactMap { e -> ChoiceElement? in
            if case .choice(let c) = e { return c }; return nil
        }
        XCTAssertEqual(choices.count, 1)
        XCTAssertTrue(choices[0].options[0].isSelected)
        XCTAssertFalse(choices[0].options[1].isSelected)

        // Fill-in replaced (no more fill-in elements)
        let fillIns = final_elements.filter { if case .fillIn = $0 { return true }; return false }
        XCTAssertTrue(fillIns.isEmpty)
        XCTAssertTrue(content.contains("Name: Bob"))

        // Feedback set
        let feedbacks = final_elements.compactMap { e -> FeedbackElement? in
            if case .feedback(let f) = e { return f }; return nil
        }
        XCTAssertEqual(feedbacks.count, 1)
        XCTAssertEqual(feedbacks[0].existingText, "Done")
    }

    // MARK: - Helpers

    /// Computes radio-style replacements for a choice element.
    private func radioReplacements(
        choice: ChoiceElement,
        selectIndex: Int
    ) -> [(range: Range<String.Index>, newText: String)] {
        var replacements: [(range: Range<String.Index>, newText: String)] = []
        for (i, option) in choice.options.enumerated() {
            let newChar = (i == selectIndex) ? "x" : " "
            let currentChar = option.isSelected ? "x" : " "
            if String(newChar) != String(currentChar) {
                replacements.append((range: option.checkRange, newText: String(newChar)))
            }
        }
        return replacements
    }

    /// Applies multiple replacements in reverse order to preserve indices.
    private func applyReplacements(
        _ content: inout String,
        _ replacements: [(range: Range<String.Index>, newText: String)]
    ) {
        let sorted = replacements.sorted { $0.range.lowerBound > $1.range.lowerBound }
        for (range, newText) in sorted {
            content.replaceSubrange(range, with: newText)
        }
    }

    // MARK: - Phase 3: CriticMarkup Accept/Reject

    func testAcceptAddition() {
        var content = "This is {++very ++}important.\n"
        let elements = InteractiveElementDetector.detect(in: content)
        guard case .suggestion(let s) = elements.first else {
            XCTFail("Expected suggestion"); return
        }
        XCTAssertEqual(s.type, .addition)

        // Accept: {++text++} → text
        content.replaceSubrange(s.range, with: s.newText ?? "")
        XCTAssertEqual(content, "This is very important.\n")
    }

    func testRejectAddition() {
        var content = "This is {++very ++}important.\n"
        let elements = InteractiveElementDetector.detect(in: content)
        guard case .suggestion(let s) = elements.first else {
            XCTFail("Expected suggestion"); return
        }

        // Reject: {++text++} → removed
        content.replaceSubrange(s.range, with: "")
        XCTAssertEqual(content, "This is important.\n")
    }

    func testAcceptDeletion() {
        var content = "Remove {--this word --}here.\n"
        let elements = InteractiveElementDetector.detect(in: content)
        guard case .suggestion(let s) = elements.first else {
            XCTFail("Expected suggestion"); return
        }
        XCTAssertEqual(s.type, .deletion)

        // Accept deletion: {--text--} → removed
        content.replaceSubrange(s.range, with: "")
        XCTAssertEqual(content, "Remove here.\n")
    }

    func testRejectDeletion() {
        var content = "Remove {--this word --}here.\n"
        let elements = InteractiveElementDetector.detect(in: content)
        guard case .suggestion(let s) = elements.first else {
            XCTFail("Expected suggestion"); return
        }

        // Reject deletion: {--text--} → keep text
        content.replaceSubrange(s.range, with: s.oldText ?? "")
        XCTAssertEqual(content, "Remove this word here.\n")
    }

    func testAcceptSubstitution() {
        var content = "Use {~~old~>new~~} value.\n"
        let elements = InteractiveElementDetector.detect(in: content)
        guard case .suggestion(let s) = elements.first else {
            XCTFail("Expected substitution"); return
        }
        XCTAssertEqual(s.type, .substitution)

        // Accept: {~~old~>new~~} → new
        content.replaceSubrange(s.range, with: s.newText ?? "")
        XCTAssertEqual(content, "Use new value.\n")
    }

    func testRejectSubstitution() {
        var content = "Use {~~old~>new~~} value.\n"
        let elements = InteractiveElementDetector.detect(in: content)
        guard case .suggestion(let s) = elements.first else {
            XCTFail("Expected substitution"); return
        }

        // Reject: {~~old~>new~~} → old
        content.replaceSubrange(s.range, with: s.oldText ?? "")
        XCTAssertEqual(content, "Use old value.\n")
    }

    // MARK: - Phase 3: Status Advance

    func testStatusAdvanceSingle() {
        var content = "<!-- status: draft | review | approved -->\n**Status:** draft\n"
        let elements = InteractiveElementDetector.detect(in: content)
        guard case .status(let st) = elements.first else {
            XCTFail("Expected status"); return
        }
        XCTAssertEqual(st.currentState, "draft")
        XCTAssertEqual(st.nextStates, ["review", "approved"])

        // Advance to review
        content.replaceSubrange(st.labelRange, with: "**Status:** review")

        // Re-detect
        let after = InteractiveElementDetector.detect(in: content)
        guard case .status(let st2) = after.first else {
            XCTFail("Expected status after advance"); return
        }
        XCTAssertEqual(st2.currentState, "review")
        XCTAssertEqual(st2.nextStates, ["approved"])
    }

    func testStatusTerminalAppendDate() {
        var content = "<!-- status: draft | approved -->\n**Status:** draft\n"
        let elements = InteractiveElementDetector.detect(in: content)
        guard case .status(let st) = elements.first else {
            XCTFail("Expected status"); return
        }

        // Advance to terminal state with date
        let isTerminal = (st.states.last == "approved")
        XCTAssertTrue(isTerminal)
        content.replaceSubrange(st.labelRange, with: "**Status:** approved — 2026-03-07")

        XCTAssertTrue(content.contains("**Status:** approved — 2026-03-07"))
    }

    // MARK: - Phase 3: Confidence

    func testConfirmHighConfidence() {
        var content = "> [confidence: high] This is reliable.\n"
        let elements = InteractiveElementDetector.detect(in: content)
        guard case .confidence(let conf) = elements.first else {
            XCTFail("Expected confidence"); return
        }
        XCTAssertEqual(conf.level, .high)

        // Confirm: replace with confirmed (preserve the text portion)
        content.replaceSubrange(conf.range, with: "> [confidence: confirmed] This is reliable.")

        let after = InteractiveElementDetector.detect(in: content)
        guard case .confidence(let conf2) = after.first else {
            XCTFail("Expected confidence after confirm"); return
        }
        XCTAssertEqual(conf2.level, .confirmed)
    }
}
