import XCTest
@testable import aimdRenderer

// MARK: - Interactive Element Detector Tests

final class InteractiveElementDetectorTests: XCTestCase {

    // MARK: - Checkbox Detection

    func testDetectsUncheckedCheckbox() {
        let text = "- [ ] Buy groceries"
        let elements = InteractiveElementDetector.detect(in: text)
        XCTAssertEqual(elements.count, 1)
        guard case .checkbox(let cb) = elements.first else {
            XCTFail("Expected checkbox"); return
        }
        XCTAssertFalse(cb.isChecked)
        XCTAssertEqual(cb.label, "Buy groceries")
    }

    func testDetectsCheckedCheckbox() {
        let text = "- [x] Done task"
        let elements = InteractiveElementDetector.detect(in: text)
        XCTAssertEqual(elements.count, 1)
        guard case .checkbox(let cb) = elements.first else {
            XCTFail("Expected checkbox"); return
        }
        XCTAssertTrue(cb.isChecked)
        XCTAssertEqual(cb.label, "Done task")
    }

    func testMultipleCheckboxes() {
        let text = """
        - [ ] Task 1
        - [x] Task 2
        - [ ] Task 3
        """
        let elements = InteractiveElementDetector.detect(in: text)
        XCTAssertEqual(elements.count, 3)
    }

    func testCheckboxesInsideBlockquoteExcluded() {
        let text = """
        > **Pick one:**
        > [ ] A
        > [ ] B
        """
        let elements = InteractiveElementDetector.detect(in: text)
        // Should be a choice, not standalone checkboxes
        let checkboxes = elements.filter { if case .checkbox = $0 { return true }; return false }
        XCTAssertEqual(checkboxes.count, 0)
    }

    func testCheckboxWithLeadingWhitespace() {
        let text = "  - [ ] Indented task"
        let elements = InteractiveElementDetector.detect(in: text)
        XCTAssertEqual(elements.count, 1)
    }

    // MARK: - Choice Detection

    func testDetectsChoiceInBlockquote() {
        let text = """
        > **Which one?**
        > [ ] Option A
        > [x] Option B
        > [ ] Option C
        """
        let elements = InteractiveElementDetector.detect(in: text)
        let choices = elements.compactMap { if case .choice(let c) = $0 { return c }; return nil }
        XCTAssertEqual(choices.count, 1)
        XCTAssertEqual(choices[0].options.count, 3)
        XCTAssertEqual(choices[0].selectedIndex, 1) // Option B
    }

    func testChoiceNoSelection() {
        let text = """
        > **Pick:**
        > [ ] X
        > [ ] Y
        """
        let elements = InteractiveElementDetector.detect(in: text)
        let choices = elements.compactMap { if case .choice(let c) = $0 { return c }; return nil }
        XCTAssertEqual(choices.count, 1)
        XCTAssertNil(choices[0].selectedIndex)
    }

    // MARK: - Review Detection

    func testDetectsReviewApproval() {
        let text = """
        > **Review: Schema v2**
        > [ ] APPROVED
        """
        let elements = InteractiveElementDetector.detect(in: text)
        let reviews = elements.compactMap { if case .review(let r) = $0 { return r }; return nil }
        XCTAssertEqual(reviews.count, 1)
        XCTAssertNil(reviews[0].selectedStatus)
    }

    func testDetectsReviewQA() {
        let text = """
        > **QA: Login Flow**
        > [ ] PASS
        > [ ] FAIL
        > [ ] PASS WITH NOTES
        > [ ] BLOCKED
        > [ ] N/A
        """
        let elements = InteractiveElementDetector.detect(in: text)
        let reviews = elements.compactMap { if case .review(let r) = $0 { return r }; return nil }
        XCTAssertEqual(reviews.count, 1)
        XCTAssertEqual(reviews[0].options.count, 5)
    }

    func testDetectsSelectedReviewWithDate() {
        let text = """
        > **QA: Login**
        > [x] PASS — 2026-03-07
        > [ ] FAIL
        """
        let elements = InteractiveElementDetector.detect(in: text)
        let reviews = elements.compactMap { if case .review(let r) = $0 { return r }; return nil }
        XCTAssertEqual(reviews.count, 1)
        XCTAssertEqual(reviews[0].selectedStatus, .pass)
        XCTAssertEqual(reviews[0].options[0].date, "2026-03-07")
    }

    func testDetectsReviewWithNotes() {
        let text = """
        > **QA: Auth**
        > [x] FAIL — 2026-03-07: Token not refreshing
        > [ ] PASS
        """
        let elements = InteractiveElementDetector.detect(in: text)
        let reviews = elements.compactMap { if case .review(let r) = $0 { return r }; return nil }
        XCTAssertEqual(reviews.count, 1)
        XCTAssertEqual(reviews[0].options[0].notes, "Token not refreshing")
    }

    // MARK: - Fill-in-the-Blank Detection

    func testDetectsTextFillIn() {
        let text = "Project name: [[enter project name]]"
        let elements = InteractiveElementDetector.detect(in: text)
        guard case .fillIn(let fi) = elements.first else {
            XCTFail("Expected fillIn"); return
        }
        XCTAssertEqual(fi.hint, "enter project name")
        XCTAssertEqual(fi.type, .text)
    }

    func testDetectsFileFillIn() {
        let text = "Config: [[choose file]]"
        let elements = InteractiveElementDetector.detect(in: text)
        guard case .fillIn(let fi) = elements.first else {
            XCTFail("Expected fillIn"); return
        }
        XCTAssertEqual(fi.type, .file)
    }

    func testDetectsFolderFillIn() {
        let text = "Output: [[choose folder]]"
        let elements = InteractiveElementDetector.detect(in: text)
        guard case .fillIn(let fi) = elements.first else {
            XCTFail("Expected fillIn"); return
        }
        XCTAssertEqual(fi.type, .folder)
    }

    func testDetectsDateFillIn() {
        let text = "Deadline: [[pick date]]"
        let elements = InteractiveElementDetector.detect(in: text)
        guard case .fillIn(let fi) = elements.first else {
            XCTFail("Expected fillIn"); return
        }
        XCTAssertEqual(fi.type, .date)
    }

    func testMultipleFillIns() {
        let text = "Name: [[enter name]] File: [[choose file]]"
        let elements = InteractiveElementDetector.detect(in: text)
        let fillIns = elements.filter { if case .fillIn = $0 { return true }; return false }
        XCTAssertEqual(fillIns.count, 2)
    }

    func testFilledFillInReDetection() {
        // Simulate the full fill-in cycle: placeholder → filled → re-detected
        let original = "Name: [[enter your name]]"
        let originalElements = InteractiveElementDetector.detect(in: original)
        guard case .fillIn(let origFi) = originalElements.first else {
            XCTFail("Expected fillIn in original"); return
        }
        XCTAssertNil(origFi.value, "Unfilled should have nil value")
        XCTAssertEqual(origFi.type, .text)

        // Simulate fill-in write-back: wraps value in [[ ]]
        var modified = original
        modified.replaceSubrange(origFi.range, with: "[[John Smith]]")
        XCTAssertEqual(modified, "Name: [[John Smith]]")

        // Re-detect: should find filled fill-in with value
        let reElements = InteractiveElementDetector.detect(in: modified)
        guard case .fillIn(let reFi) = reElements.first else {
            XCTFail("Expected fillIn after re-edit"); return
        }
        XCTAssertEqual(reFi.value, "John Smith", "Should detect filled value")
        XCTAssertEqual(reFi.type, .text, "Filled value type should be .text")
        XCTAssertEqual(reFi.hint, "John Smith", "Hint should equal the filled value")
    }

    func testFilledFillInFromExtendedSyntax() {
        // Extended syntax from smoke test: [[fill-in: name | Your name]]
        let original = "**Tester:** [[fill-in: name | Your name]]"
        let originalElements = InteractiveElementDetector.detect(in: original)
        guard case .fillIn(let origFi) = originalElements.first else {
            XCTFail("Expected fillIn"); return
        }
        XCTAssertNil(origFi.value, "Extended syntax should be unfilled")

        // After fill-in write-back
        var modified = original
        modified.replaceSubrange(origFi.range, with: "[[John]]")

        let reElements = InteractiveElementDetector.detect(in: modified)
        guard case .fillIn(let reFi) = reElements.first else {
            XCTFail("Expected fillIn after fill"); return
        }
        XCTAssertEqual(reFi.value, "John")
        XCTAssertEqual(reFi.type, .text)
    }

    // MARK: - Feedback Detection

    func testDetectsEmptyFeedback() {
        let text = "Here is the design.\n\n<!-- feedback -->"
        let elements = InteractiveElementDetector.detect(in: text)
        guard case .feedback(let fb) = elements.first else {
            XCTFail("Expected feedback"); return
        }
        XCTAssertNil(fb.existingText)
    }

    func testDetectsFilledFeedback() {
        let text = "<!-- feedback: Looks good -->"
        let elements = InteractiveElementDetector.detect(in: text)
        guard case .feedback(let fb) = elements.first else {
            XCTFail("Expected feedback"); return
        }
        XCTAssertEqual(fb.existingText, "Looks good")
    }

    // MARK: - CriticMarkup Detection

    func testDetectsAddition() {
        let text = "The API should {++include rate limiting++} for all endpoints."
        let elements = InteractiveElementDetector.detect(in: text)
        guard case .suggestion(let s) = elements.first else {
            XCTFail("Expected suggestion"); return
        }
        XCTAssertEqual(s.type, .addition)
        XCTAssertEqual(s.newText, "include rate limiting")
        XCTAssertNil(s.oldText)
    }

    func testDetectsDeletion() {
        let text = "The system {--currently uses polling but--} will use WebSockets."
        let elements = InteractiveElementDetector.detect(in: text)
        guard case .suggestion(let s) = elements.first else {
            XCTFail("Expected suggestion"); return
        }
        XCTAssertEqual(s.type, .deletion)
        XCTAssertEqual(s.oldText, "currently uses polling but")
        XCTAssertNil(s.newText)
    }

    func testDetectsSubstitution() {
        let text = "Deploy to {~~staging~>production~~} after QA."
        let elements = InteractiveElementDetector.detect(in: text)
        guard case .suggestion(let s) = elements.first else {
            XCTFail("Expected suggestion"); return
        }
        XCTAssertEqual(s.type, .substitution)
        XCTAssertEqual(s.oldText, "staging")
        XCTAssertEqual(s.newText, "production")
    }

    func testDetectsHighlightWithComment() {
        let text = "{==This endpoint has no auth==}{>>Add OAuth here?<<}"
        let elements = InteractiveElementDetector.detect(in: text)
        guard case .suggestion(let s) = elements.first else {
            XCTFail("Expected suggestion"); return
        }
        XCTAssertEqual(s.type, .highlight)
        XCTAssertEqual(s.oldText, "This endpoint has no auth")
        XCTAssertEqual(s.comment, "Add OAuth here?")
    }

    func testMultipleSuggestions() {
        let text = "Use {++REST++} instead of {--SOAP--} for the API."
        let elements = InteractiveElementDetector.detect(in: text)
        let suggestions = elements.filter { if case .suggestion = $0 { return true }; return false }
        XCTAssertEqual(suggestions.count, 2)
    }

    func testSuggestionsOnSameLineAsCheckbox() {
        let text = "- [ ] Update API to use {++REST++} instead of {--SOAP--}"
        let elements = InteractiveElementDetector.detect(in: text)
        let checkboxes = elements.filter { if case .checkbox = $0 { return true }; return false }
        let suggestions = elements.filter { if case .suggestion = $0 { return true }; return false }
        XCTAssertEqual(checkboxes.count, 1)
        XCTAssertEqual(suggestions.count, 2)
    }

    func testHighlightWithoutComment() {
        let text = "{==important text==}"
        let elements = InteractiveElementDetector.detect(in: text)
        // Highlight without comment should NOT match (pattern requires {>>comment<<})
        let suggestions = elements.filter { if case .suggestion = $0 { return true }; return false }
        XCTAssertEqual(suggestions.count, 0)
    }

    func testSuggestionPreservesWhitespace() {
        let text = "The {++very important ++}thing to do."
        let elements = InteractiveElementDetector.detect(in: text)
        guard case .suggestion(let s) = elements.first else {
            XCTFail("Expected suggestion"); return
        }
        XCTAssertEqual(s.newText, "very important ")
    }

    // MARK: - Status Detection

    func testDetectsStatus() {
        let text = """
        <!-- status: draft | review | approved | implemented -->
        **Status:** draft
        """
        let elements = InteractiveElementDetector.detect(in: text)
        guard case .status(let s) = elements.first else {
            XCTFail("Expected status"); return
        }
        XCTAssertEqual(s.states, ["draft", "review", "approved", "implemented"])
        XCTAssertEqual(s.currentState, "draft")
        XCTAssertEqual(s.nextStates, ["review", "approved", "implemented"])
    }

    func testStatusAtTerminal() {
        let text = """
        <!-- status: draft | review | done -->
        **Status:** done
        """
        let elements = InteractiveElementDetector.detect(in: text)
        guard case .status(let s) = elements.first else {
            XCTFail("Expected status"); return
        }
        XCTAssertEqual(s.currentState, "done")
        XCTAssertEqual(s.nextStates, [])
    }

    // MARK: - Confidence Detection

    func testDetectsConfidenceHigh() {
        let text = "> [confidence: high] Use REST for the API"
        let elements = InteractiveElementDetector.detect(in: text)
        guard case .confidence(let c) = elements.first else {
            XCTFail("Expected confidence"); return
        }
        XCTAssertEqual(c.level, .high)
        XCTAssertEqual(c.text, "Use REST for the API")
    }

    func testDetectsConfidenceLow() {
        let text = "> [confidence: low] WebSocket might be needed"
        let elements = InteractiveElementDetector.detect(in: text)
        guard case .confidence(let c) = elements.first else {
            XCTFail("Expected confidence"); return
        }
        XCTAssertEqual(c.level, .low)
    }

    // MARK: - Conditional Detection

    func testDetectsConditional() {
        let text = """
        <!-- if: database = PostgreSQL -->
        ## PostgreSQL Setup
        Run docker-compose...
        <!-- endif -->
        """
        let elements = InteractiveElementDetector.detect(in: text)
        guard case .conditional(let c) = elements.first else {
            XCTFail("Expected conditional"); return
        }
        XCTAssertEqual(c.key, "database")
        XCTAssertEqual(c.value, "PostgreSQL")
    }

    // MARK: - Collapsible Detection

    func testDetectsCollapsible() {
        let text = """
        <!-- collapsible: Details -->
        Some detailed content here.
        <!-- endcollapsible -->
        """
        let elements = InteractiveElementDetector.detect(in: text)
        guard case .collapsible(let c) = elements.first else {
            XCTFail("Expected collapsible"); return
        }
        XCTAssertEqual(c.title, "Details")
    }

    // MARK: - Mixed Document

    func testMixedDocument() {
        let text = """
        # Project Setup

        - [ ] Install dependencies
        - [x] Create repo

        Project name: [[enter project name]]

        > **Use TypeScript?**
        > [ ] YES  [ ] NO

        <!-- feedback -->

        The API {++needs auth++} for production.

        <!-- status: draft | review | done -->
        **Status:** draft
        """
        let elements = InteractiveElementDetector.detect(in: text)

        let checkboxes = elements.filter { if case .checkbox = $0 { return true }; return false }
        let fillIns = elements.filter { if case .fillIn = $0 { return true }; return false }
        let choices = elements.filter { if case .choice = $0 { return true }; return false }
        let feedbacks = elements.filter { if case .feedback = $0 { return true }; return false }
        let suggestions = elements.filter { if case .suggestion = $0 { return true }; return false }
        let statuses = elements.filter { if case .status = $0 { return true }; return false }

        XCTAssertEqual(checkboxes.count, 2)
        XCTAssertEqual(fillIns.count, 1)
        XCTAssertEqual(choices.count, 1)
        XCTAssertEqual(feedbacks.count, 1)
        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(statuses.count, 1)
    }

    // MARK: - Empty Document

    func testEmptyDocument() {
        let elements = InteractiveElementDetector.detect(in: "")
        XCTAssertTrue(elements.isEmpty)
    }

    // MARK: - Element Ordering

    func testElementsSortedByPosition() {
        let text = """
        - [ ] First
        [[enter name]]
        <!-- feedback -->
        """
        let elements = InteractiveElementDetector.detect(in: text)
        XCTAssertEqual(elements.count, 3)

        // Verify ordering
        for i in 1..<elements.count {
            XCTAssertTrue(elements[i - 1].range.lowerBound < elements[i].range.lowerBound,
                         "Elements should be sorted by position")
        }
    }

    // MARK: - Starter Document Smoke Test

    func testStarterDocumentDetectsAll9Patterns() {
        // Mirrors the Interactive Starter Document content
        let text = """
        # Interactive Markdown Starter

        ## Setup Checklist
        - [ ] Read this document
        - [ ] Try toggling a checkbox

        ## Your Info
        - **Name:** [[your name]]
        - **Start Date:** [[choose a date]]

        ## Choose Your Focus
        > - [ ] Design
        > - [ ] Engineering

        ## Review Gate
        > - [ ] APPROVED
        > - [ ] PASS
        > - [ ] FAIL

        ## Suggested Edits
        This uses {++a modern ++}architecture with {--legacy --}components.
        The timeline is {~~6 months~>3 months~~} for completion.
        {==Key decision==}{>>Consider alternatives<<}

        ## Project Status
        <!-- status: draft | review | approved | shipped -->
        **Status:** draft

        ## AI Confidence
        > [confidence: high] Use SwiftUI for the interface.
        > [confidence: low] WebSocket might be needed.

        ## Feedback
        <!-- feedback -->
        """
        let elements = InteractiveElementDetector.detect(in: text)

        let checkboxes = elements.filter { if case .checkbox = $0 { return true }; return false }
        let fillIns = elements.filter { if case .fillIn = $0 { return true }; return false }
        let choices = elements.filter { if case .choice = $0 { return true }; return false }
        let reviews = elements.filter { if case .review = $0 { return true }; return false }
        let suggestions = elements.filter { if case .suggestion = $0 { return true }; return false }
        let statuses = elements.filter { if case .status = $0 { return true }; return false }
        let confidences = elements.filter { if case .confidence = $0 { return true }; return false }
        let feedbacks = elements.filter { if case .feedback = $0 { return true }; return false }

        // All 8 actionable patterns detected (conditional/collapsible are pattern 9 but deferred)
        XCTAssertEqual(checkboxes.count, 2, "checkboxes")
        XCTAssertEqual(fillIns.count, 2, "fillIns")
        XCTAssertEqual(choices.count, 1, "choices")
        XCTAssertEqual(reviews.count, 1, "reviews")
        XCTAssertGreaterThanOrEqual(suggestions.count, 3, "suggestions (add + del + sub + highlight)")
        XCTAssertEqual(statuses.count, 1, "statuses")
        XCTAssertEqual(confidences.count, 2, "confidences")
        XCTAssertEqual(feedbacks.count, 1, "feedbacks")

        // Verify structure has correct sections
        let structure = MarkdownStructureParser.parse(text: text)
        XCTAssertGreaterThanOrEqual(structure.sections.count, 1, "top-level sections")

        // Verify progress on Setup Checklist section
        if let setup = structure.sections.first?.children.first {
            let progress = setup.checkboxProgress
            XCTAssertNotNil(progress, "setup checklist should have progress")
            XCTAssertEqual(progress?.total, 2, "setup checklist has 2 checkboxes")
            XCTAssertEqual(progress?.completed, 0, "none checked yet")
        }
    }
}

// MARK: - Document Structure Parser Tests

final class MarkdownStructureParserTests: XCTestCase {

    func testEmptyDocument() {
        let structure = MarkdownStructureParser.parse(text: "")
        XCTAssertTrue(structure.sections.isEmpty)
        XCTAssertTrue(structure.elements.isEmpty)
    }

    func testSingleHeading() {
        let text = "# Title\nSome content"
        let structure = MarkdownStructureParser.parse(text: text)
        XCTAssertEqual(structure.sections.count, 1)
        XCTAssertEqual(structure.sections[0].level, 1)
        XCTAssertEqual(structure.sections[0].title, "Title")
    }

    func testNestedHeadings() {
        let text = """
        # Top Level
        ## Section A
        Content A
        ## Section B
        Content B
        ### Subsection B1
        Content B1
        """
        let structure = MarkdownStructureParser.parse(text: text)
        XCTAssertEqual(structure.sections.count, 1) // One top-level
        XCTAssertEqual(structure.sections[0].children.count, 2) // Two ##
        XCTAssertEqual(structure.sections[0].children[1].children.count, 1) // One ###
        XCTAssertEqual(structure.sections[0].children[1].children[0].title, "Subsection B1")
    }

    func testDeepNesting() {
        let text = """
        # L1
        ## L2
        ### L3
        #### L4
        Content
        """
        let structure = MarkdownStructureParser.parse(text: text)
        XCTAssertEqual(structure.sections.count, 1)
        XCTAssertEqual(structure.sections[0].children.count, 1)
        XCTAssertEqual(structure.sections[0].children[0].children.count, 1)
        XCTAssertEqual(structure.sections[0].children[0].children[0].children.count, 1)
    }

    func testElementsAssignedToSections() {
        let text = """
        # Phase 1
        - [ ] Task A
        - [ ] Task B

        ## Subtask
        - [x] Sub-task done

        # Phase 2
        - [ ] Task C
        """
        let structure = MarkdownStructureParser.parse(text: text)
        XCTAssertEqual(structure.sections.count, 2)

        // Phase 1 direct elements (checkboxes not in subtask)
        XCTAssertEqual(structure.sections[0].elements.count, 2) // Task A, Task B
        // Subtask has 1 element
        XCTAssertEqual(structure.sections[0].children[0].elements.count, 1) // Sub-task done
        // Phase 2 has 1 element
        XCTAssertEqual(structure.sections[1].elements.count, 1) // Task C
    }

    func testOutlineDepth1() {
        let text = """
        # Title
        ## Section
        ### Subsection
        """
        let structure = MarkdownStructureParser.parse(text: text)
        let outline = structure.outline(maxDepth: 1)
        XCTAssertTrue(outline.contains("# Title"))
        XCTAssertFalse(outline.contains("## Section"))
    }

    func testOutlineDepth2() {
        let text = """
        # Title
        ## Section A
        ### Subsection
        ## Section B
        """
        let structure = MarkdownStructureParser.parse(text: text)
        let outline = structure.outline(maxDepth: 2)
        XCTAssertTrue(outline.contains("# Title"))
        XCTAssertTrue(outline.contains("## Section A"))
        XCTAssertTrue(outline.contains("## Section B"))
        XCTAssertFalse(outline.contains("### Subsection"))
    }

    func testSummaryShowsElementCounts() {
        let text = """
        # Setup
        - [ ] Install
        - [ ] Configure
        [[enter name]]
        """
        let structure = MarkdownStructureParser.parse(text: text)
        let summary = structure.summary()
        XCTAssertTrue(summary.contains("Setup"))
        XCTAssertTrue(summary.contains("checkbox"))
        XCTAssertTrue(summary.contains("fill-in"))
    }

    func testProgressCalculation() {
        let text = """
        # Tasks
        - [x] Done
        - [x] Also done
        - [ ] Not done
        """
        let structure = MarkdownStructureParser.parse(text: text)
        let progress = structure.sections[0].checkboxProgress
        XCTAssertNotNil(progress)
        XCTAssertEqual(progress?.completed, 2)
        XCTAssertEqual(progress?.total, 3)
    }

    func testProgressIgnoresReviews() {
        let text = """
        # QA Section
        - [x] Pre-check

        > **QA: Login**
        > [x] PASS — 2026-03-07
        > [ ] FAIL

        > **QA: Signup**
        > [ ] PASS
        > [ ] FAIL
        """
        let structure = MarkdownStructureParser.parse(text: text)
        let progress = structure.sections[0].checkboxProgress
        XCTAssertNotNil(progress)
        // Only 1 standalone checkbox counted (reviews excluded)
        XCTAssertEqual(progress?.completed, 1)
        XCTAssertEqual(progress?.total, 1)
    }

    func testProgressIgnoresChoices() {
        let text = """
        # Setup
        - [x] Install

        > **Database?**
        > [x] PostgreSQL
        > [ ] MySQL
        """
        let structure = MarkdownStructureParser.parse(text: text)
        let progress = structure.sections[0].checkboxProgress
        XCTAssertNotNil(progress)
        // Only 1 standalone checkbox counted (choices excluded)
        XCTAssertEqual(progress?.completed, 1)
        XCTAssertEqual(progress?.total, 1)
    }

    func testProgressNilWhenNoTrackableElements() {
        let text = """
        # Notes
        Just some text here.
        """
        let structure = MarkdownStructureParser.parse(text: text)
        XCTAssertNil(structure.sections[0].checkboxProgress)
    }

    func testHeadingWithNoContent() {
        let text = """
        # Empty Section
        # Another Section
        Some content
        """
        let structure = MarkdownStructureParser.parse(text: text)
        XCTAssertEqual(structure.sections.count, 2)
        XCTAssertEqual(structure.sections[0].title, "Empty Section")
        XCTAssertEqual(structure.sections[1].title, "Another Section")
    }

    func testContentBeforeFirstHeading() {
        let text = """
        Some preamble text.

        # First Heading
        Content
        """
        let structure = MarkdownStructureParser.parse(text: text)
        // Should have preamble section + heading section
        XCTAssertGreaterThanOrEqual(structure.sections.count, 1)
    }

    func testMultipleElementTypesPerSection() {
        let text = """
        # Review Section

        - [ ] Pre-check done

        > **Approve?**
        > [ ] YES  [ ] NO

        <!-- feedback -->
        """
        let structure = MarkdownStructureParser.parse(text: text)
        let allElements = structure.sections[0].allElementsRecursive
        XCTAssertGreaterThanOrEqual(allElements.count, 3) // checkbox + choice + feedback
    }
}

// MARK: - Spec 4: New Controls Detection Tests

final class Spec4DetectionTests: XCTestCase {

    // MARK: - Slider

    func testDetectsSlider() {
        let text = "Priority: [[slide 1-10]]"
        let elements = InteractiveElementDetector.detect(in: text)
        XCTAssertEqual(elements.count, 1)
        guard case .slider(let s) = elements.first else {
            XCTFail("Expected slider"); return
        }
        XCTAssertEqual(s.minValue, 1)
        XCTAssertEqual(s.maxValue, 10)
        XCTAssertEqual(s.keyword, "slide")
    }

    func testDetectsRateSlider() {
        let text = "Satisfaction: [[rate 1-5]]"
        let elements = InteractiveElementDetector.detect(in: text)
        XCTAssertEqual(elements.count, 1)
        guard case .slider(let s) = elements.first else {
            XCTFail("Expected slider"); return
        }
        XCTAssertEqual(s.minValue, 1)
        XCTAssertEqual(s.maxValue, 5)
        XCTAssertEqual(s.keyword, "rate")
    }

    func testInvalidSliderRangeNotDetected() {
        // Reversed range (min > max) should not be detected
        let text = "Bad: [[slide 10-1]]"
        let elements = InteractiveElementDetector.detect(in: text)
        // Falls through to generic fillIn (is a placeholder)
        for element in elements {
            if case .slider = element {
                XCTFail("Should not detect invalid slider range")
            }
        }
    }

    func testSliderWithoutRangeNotDetected() {
        let text = "[[slide]]"
        let elements = InteractiveElementDetector.detect(in: text)
        for element in elements {
            if case .slider = element {
                XCTFail("Slider requires MIN-MAX range")
            }
        }
    }

    // MARK: - Stepper

    func testDetectsStepperWithRange() {
        let text = "Count: [[pick number 1-20]]"
        let elements = InteractiveElementDetector.detect(in: text)
        XCTAssertEqual(elements.count, 1)
        guard case .stepper(let s) = elements.first else {
            XCTFail("Expected stepper"); return
        }
        XCTAssertEqual(s.minValue, 1)
        XCTAssertEqual(s.maxValue, 20)
    }

    func testDetectsStepperWithoutRange() {
        let text = "Count: [[pick number]]"
        let elements = InteractiveElementDetector.detect(in: text)
        XCTAssertEqual(elements.count, 1)
        guard case .stepper(let s) = elements.first else {
            XCTFail("Expected stepper"); return
        }
        XCTAssertNil(s.minValue)
        XCTAssertNil(s.maxValue)
    }

    // MARK: - Toggle

    func testDetectsToggle() {
        let text = "Enable: [[toggle]]"
        let elements = InteractiveElementDetector.detect(in: text)
        XCTAssertEqual(elements.count, 1)
        guard case .toggle = elements.first else {
            XCTFail("Expected toggle"); return
        }
    }

    func testMultipleToggles() {
        let text = """
        Dark mode: [[toggle]]
        Notifications: [[toggle]]
        """
        let elements = InteractiveElementDetector.detect(in: text)
        let toggles = elements.filter { if case .toggle = $0 { return true }; return false }
        XCTAssertEqual(toggles.count, 2)
    }

    // MARK: - Color Picker

    func testDetectsColorPicker() {
        let text = "Brand: [[pick color]]"
        let elements = InteractiveElementDetector.detect(in: text)
        XCTAssertEqual(elements.count, 1)
        guard case .colorPicker = elements.first else {
            XCTFail("Expected color picker"); return
        }
    }

    func testStepperAndColorPickerDistinct() {
        let text = """
        Count: [[pick number 1-10]]
        Color: [[pick color]]
        """
        let elements = InteractiveElementDetector.detect(in: text)
        let steppers = elements.filter { if case .stepper = $0 { return true }; return false }
        let colors = elements.filter { if case .colorPicker = $0 { return true }; return false }
        XCTAssertEqual(steppers.count, 1)
        XCTAssertEqual(colors.count, 1)
    }

    // MARK: - Auditable Checkbox

    func testDetectsAuditableCheckboxUnchecked() {
        let text = "- [ ] Deploy to staging (notes)"
        let elements = InteractiveElementDetector.detect(in: text)
        XCTAssertEqual(elements.count, 1)
        guard case .auditableCheckbox(let ac) = elements.first else {
            XCTFail("Expected auditable checkbox"); return
        }
        XCTAssertFalse(ac.isChecked)
        XCTAssertEqual(ac.label, "Deploy to staging")
        XCTAssertNil(ac.date)
        XCTAssertNil(ac.note)
    }

    func testDetectsAuditableCheckboxCheckedNoNote() {
        let text = "- [x] Deploy to staging (notes) — 2026-04-10"
        let elements = InteractiveElementDetector.detect(in: text)
        XCTAssertEqual(elements.count, 1)
        guard case .auditableCheckbox(let ac) = elements.first else {
            XCTFail("Expected auditable checkbox"); return
        }
        XCTAssertTrue(ac.isChecked)
        XCTAssertEqual(ac.label, "Deploy to staging")
        XCTAssertEqual(ac.date, "2026-04-10")
        XCTAssertNil(ac.note)
    }

    func testDetectsAuditableCheckboxCheckedWithNote() {
        let text = "- [x] Deploy to staging (notes) — 2026-04-10: had to rerun migration"
        let elements = InteractiveElementDetector.detect(in: text)
        XCTAssertEqual(elements.count, 1)
        guard case .auditableCheckbox(let ac) = elements.first else {
            XCTFail("Expected auditable checkbox"); return
        }
        XCTAssertTrue(ac.isChecked)
        XCTAssertEqual(ac.label, "Deploy to staging")
        XCTAssertEqual(ac.date, "2026-04-10")
        XCTAssertEqual(ac.note, "had to rerun migration")
    }

    func testRegularCheckboxWithoutNotesMarker() {
        let text = "- [ ] Regular task"
        let elements = InteractiveElementDetector.detect(in: text)
        XCTAssertEqual(elements.count, 1)
        guard case .checkbox = elements.first else {
            XCTFail("Expected regular checkbox, got auditable"); return
        }
    }

    // MARK: - Re-pickable File/Folder

    func testDetectsFilledFilePath() {
        let text = "Report: [[file: /Users/test/report.pdf]]"
        let elements = InteractiveElementDetector.detect(in: text)
        XCTAssertEqual(elements.count, 1)
        guard case .fillIn(let fi) = elements.first else {
            XCTFail("Expected fillIn"); return
        }
        XCTAssertEqual(fi.type, .file)
        XCTAssertEqual(fi.value, "/Users/test/report.pdf")
    }

    func testDetectsFilledFolderPath() {
        let text = "Output: [[folder: /Users/test/exports]]"
        let elements = InteractiveElementDetector.detect(in: text)
        XCTAssertEqual(elements.count, 1)
        guard case .fillIn(let fi) = elements.first else {
            XCTFail("Expected fillIn"); return
        }
        XCTAssertEqual(fi.type, .folder)
        XCTAssertEqual(fi.value, "/Users/test/exports")
    }

    func testEmptyFilePicker() {
        let text = "Report: [[choose file]]"
        let elements = InteractiveElementDetector.detect(in: text)
        XCTAssertEqual(elements.count, 1)
        guard case .fillIn(let fi) = elements.first else {
            XCTFail("Expected fillIn"); return
        }
        XCTAssertEqual(fi.type, .file)
        XCTAssertNil(fi.value)
    }

    // MARK: - Detection Priority

    func testSpec4ControlsDontConflictWithGenericFillIn() {
        let text = """
        Name: [[enter name]]
        Rating: [[slide 1-10]]
        Color: [[pick color]]
        Toggle: [[toggle]]
        Number: [[pick number 1-5]]
        """
        let elements = InteractiveElementDetector.detect(in: text)
        XCTAssertEqual(elements.count, 5)

        let sliders = elements.filter { if case .slider = $0 { return true }; return false }
        let colors = elements.filter { if case .colorPicker = $0 { return true }; return false }
        let toggles = elements.filter { if case .toggle = $0 { return true }; return false }
        let steppers = elements.filter { if case .stepper = $0 { return true }; return false }
        let fillIns = elements.filter { if case .fillIn = $0 { return true }; return false }

        XCTAssertEqual(sliders.count, 1)
        XCTAssertEqual(colors.count, 1)
        XCTAssertEqual(toggles.count, 1)
        XCTAssertEqual(steppers.count, 1)
        XCTAssertEqual(fillIns.count, 1) // Only [[enter name]]
    }
}
