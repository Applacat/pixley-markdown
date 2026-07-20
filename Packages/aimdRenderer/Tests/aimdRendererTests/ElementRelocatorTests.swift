import XCTest
@testable import aimdRenderer

/// Stale-content regression tests for `ElementRelocator` (issue #77).
///
/// Every scenario simulates the real failure: an element is detected in
/// *displayed* content, the file changes on disk (AI edit, external editor),
/// and the write-back must land on the corresponding element in the *fresh*
/// content — or fail — never on an arbitrary offset.
final class ElementRelocatorTests: XCTestCase {

    /// A paragraph inserted "by the AI" above the interactive elements,
    /// shifting every offset in the document.
    private let insertedParagraph = "The AI added this new paragraph at the top.\n\n"

    private func offsetOf(_ substring: String, in content: String, backwards: Bool = false) -> Int {
        guard let range = content.range(of: substring, options: backwards ? .backwards : []) else {
            XCTFail("Substring not found: \(substring)")
            return 0
        }
        return content.distance(from: content.startIndex, to: range.lowerBound)
    }

    private func checkboxes(in content: String) -> [CheckboxElement] {
        InteractiveElementDetector.detect(in: content)
            .compactMap { if case .checkbox(let e) = $0 { return e } else { return nil } }
    }

    // MARK: - Checkbox

    func testCheckbox_relocatesAfterContentShift() {
        let displayed = "# Tasks\n\n- [ ] First task\n- [ ] Second task\n"
        let fresh = insertedParagraph + displayed

        let stale = checkboxes(in: displayed).first { $0.label == "Second task" }
        XCTAssertNotNil(stale)
        guard let stale else { return }

        let relocated = ElementRelocator.checkbox(stale, displayed: displayed, fresh: fresh)
        XCTAssertNotNil(relocated)
        XCTAssertEqual(relocated?.label, "Second task")
        if let relocated {
            XCTAssertEqual(
                ElementRelocator.offset(of: relocated.range.lowerBound, in: fresh),
                offsetOf("- [ ] Second task", in: fresh)
            )
        }
    }

    func testCheckbox_duplicateLabels_picksSameOrdinal() {
        // Two identical "Deploy" checkboxes; the user clicked the SECOND.
        // A large upstream insertion shifts offsets by more than the gap
        // between the duplicates — offset proximity alone would pick the
        // FIRST. Ordinal matching must keep the second targeted.
        let displayed = "- [ ] Deploy\n\nSection B\n\n- [ ] Deploy\n"
        let fresh = insertedParagraph + displayed

        let stale = checkboxes(in: displayed).last
        XCTAssertNotNil(stale)
        guard let stale else { return }

        let relocated = ElementRelocator.checkbox(stale, displayed: displayed, fresh: fresh)
        XCTAssertNotNil(relocated)
        if let relocated {
            XCTAssertEqual(
                ElementRelocator.offset(of: relocated.range.lowerBound, in: fresh),
                offsetOf("- [ ] Deploy", in: fresh, backwards: true),
                "Must target the second Deploy checkbox, not the first"
            )
        }
    }

    func testCheckbox_elementRemoved_returnsNil() {
        let displayed = "- [ ] Task A\n"
        let fresh = "The task list was replaced with prose.\n"

        let stale = checkboxes(in: displayed).first
        XCTAssertNotNil(stale)
        guard let stale else { return }

        XCTAssertNil(
            ElementRelocator.checkbox(stale, displayed: displayed, fresh: fresh),
            "A removed element must fail relocation, not corrupt other content"
        )
    }

    func testCheckbox_stateChangedExternally_returnsNil() {
        // The AI already checked the box; user's stale view still shows unchecked.
        let displayed = "- [ ] Only task\n"
        let fresh = "- [x] Only task\n"

        let stale = checkboxes(in: displayed).first
        XCTAssertNotNil(stale)
        guard let stale else { return }

        XCTAssertNil(
            ElementRelocator.checkbox(stale, displayed: displayed, fresh: fresh),
            "State mismatch must be refused — blind toggle would undo the external change"
        )
    }

    // MARK: - Fill-in

    func testFillIn_relocatesByHintAfterShift() {
        let displayed = "Name: [[enter your name]]\nCity: [[enter your city]]\n"
        let fresh = insertedParagraph + displayed

        let stale = InteractiveElementDetector.detect(in: displayed)
            .compactMap { if case .fillIn(let e) = $0 { return e } else { return nil } }
            .first { $0.hint == "enter your city" }
        XCTAssertNotNil(stale)
        guard let stale else { return }

        let relocated = ElementRelocator.fillIn(stale, displayed: displayed, fresh: fresh)
        XCTAssertNotNil(relocated)
        XCTAssertEqual(relocated?.hint, "enter your city")
    }

    // MARK: - Feedback

    func testFeedback_relocatesByTextAfterShift() {
        let displayed = "Point one.\n<!-- feedback: needs work -->\nPoint two.\n<!-- feedback: other -->\n"
        let fresh = insertedParagraph + displayed

        let stale = InteractiveElementDetector.detect(in: displayed)
            .compactMap { if case .feedback(let e) = $0 { return e } else { return nil } }
            .first { $0.existingText == "needs work" }
        XCTAssertNotNil(stale)
        guard let stale else { return }

        let relocated = ElementRelocator.feedback(stale, displayed: displayed, fresh: fresh)
        XCTAssertNotNil(relocated)
        XCTAssertEqual(relocated?.existingText, "needs work")
    }

    // MARK: - Suggestion (CriticMarkup)

    func testSuggestion_relocatesHighlightAfterShift() {
        let displayed = "Some prose with {==flagged text==}{>>fix this<<} in it.\n"
        let fresh = insertedParagraph + displayed

        let stale = InteractiveElementDetector.detect(in: displayed)
            .compactMap { element -> SuggestionElement? in
                if case .suggestion(let e) = element { return e } else { return nil }
            }
            .first(where: { (s: SuggestionElement) in s.type == .highlight })
        XCTAssertNotNil(stale)
        guard let stale else { return }

        XCTAssertNotNil(ElementRelocator.suggestion(stale, displayed: displayed, fresh: fresh))
    }

    // MARK: - Status

    func testStatus_duplicateMachines_picksSameOrdinal() {
        let displayed = """
        ## Task A
        <!-- status: TODO/DOING/DONE -->
        **Status:** TODO

        ## Task B
        <!-- status: TODO/DOING/DONE -->
        **Status:** TODO
        """
        let statuses = InteractiveElementDetector.detect(in: displayed)
            .compactMap { if case .status(let s) = $0 { return s } else { return nil } }
        XCTAssertEqual(statuses.count, 2, "Test document should contain two status machines")
        guard statuses.count == 2 else { return }

        // User clicked Task B's status
        let fresh = insertedParagraph + displayed
        let relocated = ElementRelocator.status(statuses[1], displayed: displayed, fresh: fresh)
        XCTAssertNotNil(relocated)
        if let relocated {
            let freshStatuses = InteractiveElementDetector.detect(in: fresh)
                .compactMap { if case .status(let s) = $0 { return s } else { return nil } }
            XCTAssertEqual(freshStatuses.count, 2)
            XCTAssertEqual(
                ElementRelocator.offset(of: relocated.labelRange.lowerBound, in: fresh),
                ElementRelocator.offset(of: freshStatuses[1].labelRange.lowerBound, in: fresh),
                "Must target Task B's machine, not Task A's (first-match bug)"
            )
        }
    }

    // MARK: - Selection (Add Comment)

    func testSelection_picksSameOrdinalAfterShift() {
        let displayed = "First mention of target here. Another target there.\n"
        // User selected the SECOND "target"
        let staleRange = displayed.range(of: "target", options: .backwards)!
        let fresh = insertedParagraph + displayed

        let relocated = ElementRelocator.selection(
            text: "target", staleRange: staleRange, displayed: displayed, fresh: fresh
        )
        XCTAssertNotNil(relocated)
        if let relocated {
            XCTAssertEqual(
                ElementRelocator.offset(of: relocated.lowerBound, in: fresh),
                offsetOf("target", in: fresh, backwards: true),
                "Must anchor to the second occurrence"
            )
        }
    }

    func testSelection_textRemoved_returnsNil() {
        let displayed = "Some vanished words here.\n"
        let staleRange = displayed.range(of: "vanished words")!
        XCTAssertNil(ElementRelocator.selection(
            text: "vanished words", staleRange: staleRange,
            displayed: displayed, fresh: "Completely different content now.\n"
        ))
    }

    // MARK: - Anchor Line (Gutter Comments)

    func testAnchorLine_relocatesAfterLinesInsertedAbove() {
        let displayedLines = ["# Title", "", "Target line text", "Other line"]
        let freshLines = ["# Title", "New AI line one", "New AI line two", "", "Target line text", "Other line"]

        XCTAssertEqual(ElementRelocator.anchorLine(
            text: "Target line text", staleIndex: 2,
            displayedLines: displayedLines, freshLines: freshLines
        ), 4)
    }

    func testAnchorLine_duplicateLines_keepsOrdinal() {
        let displayedLines = ["a", "dup", "b", "dup"]
        let freshLines = ["inserted", "a", "dup", "b", "dup"]
        // User clicked the SECOND "dup" (index 3 in displayed)
        XCTAssertEqual(ElementRelocator.anchorLine(
            text: "dup", staleIndex: 3,
            displayedLines: displayedLines, freshLines: freshLines
        ), 4)
    }

    func testAnchorLine_lineRemoved_returnsNil() {
        XCTAssertNil(ElementRelocator.anchorLine(
            text: "gone", staleIndex: 1,
            displayedLines: ["x", "gone"], freshLines: ["a", "b"]
        ))
    }

    // MARK: - Choice

    func testChoice_relocatesAfterShift() {
        let displayed = "> [ ] Yes\n> [ ] No\n"
        let fresh = insertedParagraph + displayed

        let stale = InteractiveElementDetector.detect(in: displayed)
            .compactMap { if case .choice(let e) = $0 { return e } else { return nil } }
            .first
        XCTAssertNotNil(stale)
        guard let stale else { return }

        let relocated = ElementRelocator.choice(stale, displayed: displayed, fresh: fresh)
        XCTAssertNotNil(relocated)
        XCTAssertEqual(relocated?.options.count, 2)
    }
}
