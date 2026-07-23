import XCTest
@testable import aimdRenderer

/// Regression tests for the Gate G1 detector fixes (#86, #87, #88, #89, #106).
final class DetectorFixRegressionTests: XCTestCase {

    // MARK: - #86: Same-line choice options

    func testSameLineChoice_yesNo_detectsTwoOptions() {
        let text = "> [ ] YES  [ ] NO"
        let elements = InteractiveElementDetector.detect(in: text)
        guard case .choice(let choice)? = elements.first else {
            return XCTFail("Expected a choice element for same-line options")
        }
        XCTAssertEqual(choice.options.count, 2)
        XCTAssertEqual(choice.options[0].label, "YES")
        XCTAssertEqual(choice.options[1].label, "NO")
    }

    func testSameLineChoice_threeOptions() {
        let text = "> [ ] Small [x] Medium [ ] Large"
        let elements = InteractiveElementDetector.detect(in: text)
        guard case .choice(let choice)? = elements.first else {
            return XCTFail("Expected a choice element")
        }
        XCTAssertEqual(choice.options.map(\.label), ["Small", "Medium", "Large"])
        XCTAssertEqual(choice.selectedIndex, 1)
    }

    func testSameLineReview_passFail() {
        let text = "> [ ] PASS  [ ] FAIL"
        let elements = InteractiveElementDetector.detect(in: text)
        guard case .review(let review)? = elements.first else {
            return XCTFail("Expected a review element for same-line PASS/FAIL")
        }
        XCTAssertEqual(review.options.map(\.status), [.pass, .fail])
    }

    func testMultiLineChoice_unaffected() {
        let text = "> [ ] Design\n> [x] Engineering"
        let elements = InteractiveElementDetector.detect(in: text)
        guard case .choice(let choice)? = elements.first else {
            return XCTFail("Expected a choice element")
        }
        XCTAssertEqual(choice.options.map(\.label), ["Design", "Engineering"])
        XCTAssertEqual(choice.selectedIndex, 1)
    }

    // MARK: - #87: Multi-word status states

    func testMultiWordStatus_currentStateComplete() {
        let text = "<!-- status: TODO / IN PROGRESS / DONE -->\n**Status:** IN PROGRESS\n"
        let elements = InteractiveElementDetector.detect(in: text)
        guard case .status(let status)? = elements.first else {
            return XCTFail("Expected status")
        }
        XCTAssertEqual(status.currentState, "IN PROGRESS")
        XCTAssertEqual(status.nextStates, ["TODO", "DONE"], "Real current state must be filtered out")
    }

    func testMultiWordStatus_labelRangeCoversWholeState() {
        let text = "<!-- status: TODO / IN PROGRESS / DONE -->\n**Status:** IN PROGRESS\n"
        let elements = InteractiveElementDetector.detect(in: text)
        guard case .status(let status)? = elements.first else {
            return XCTFail("Expected status")
        }
        // Replacing labelRange must not leave residue (the #75 "append" symptom):
        // the label line becomes exactly the new state, nothing trailing.
        var content = text
        content.replaceSubrange(status.labelRange, with: "**Status:** DONE")
        XCTAssertTrue(content.hasSuffix("**Status:** DONE\n"), "Label line has residue: \(content)")
    }

    func testMultiWordStatus_withDateSuffix() {
        let text = "<!-- status: OPEN / SIGNED OFF -->\n**Status:** SIGNED OFF — 2026-07-01\n"
        let elements = InteractiveElementDetector.detect(in: text)
        guard case .status(let status)? = elements.first else {
            return XCTFail("Expected status")
        }
        XCTAssertEqual(status.currentState, "SIGNED OFF")
    }

    // MARK: - #88/#106: Explicit typed filled values

    func testDatePrefix_preservesDateType() {
        let text = "Due: [[date: 2026-07-09]]"
        let elements = InteractiveElementDetector.detect(in: text)
        guard case .fillIn(let fillIn)? = elements.first else {
            return XCTFail("Expected fill-in")
        }
        XCTAssertEqual(fillIn.type, .date, "Picked dates must stay dates (#106)")
        XCTAssertEqual(fillIn.value, "2026-07-09")
    }

    func testTextPrefix_valueNotMistakenForPlaceholder() {
        // "Enterprise Portal" contains "enter" — the heuristic used to
        // misread it as an unfilled hint (#88). The explicit prefix wins.
        let text = "Project: [[text: Enterprise Portal]]"
        let elements = InteractiveElementDetector.detect(in: text)
        guard case .fillIn(let fillIn)? = elements.first else {
            return XCTFail("Expected fill-in")
        }
        XCTAssertEqual(fillIn.type, .text)
        XCTAssertEqual(fillIn.value, "Enterprise Portal")
    }

    func testTextPrefix_valueWithColonSurvives() {
        let text = "When: [[text: Meeting 10:30]]"
        let elements = InteractiveElementDetector.detect(in: text)
        guard case .fillIn(let fillIn)? = elements.first else {
            return XCTFail("Expected fill-in")
        }
        XCTAssertEqual(fillIn.value, "Meeting 10:30")
    }

    // MARK: - #89: Single `]` allowed inside fill-in values

    func testFillIn_singleBracketInValue() {
        let text = "Note: [[text: see array[0] for details]]"
        let elements = InteractiveElementDetector.detect(in: text)
        guard case .fillIn(let fillIn)? = elements.first else {
            return XCTFail("Expected fill-in")
        }
        XCTAssertEqual(fillIn.value, "see array[0] for details")
    }

    func testFillIn_unfilledHintStillDetects() {
        let text = "Name: [[enter your name]]"
        let elements = InteractiveElementDetector.detect(in: text)
        guard case .fillIn(let fillIn)? = elements.first else {
            return XCTFail("Expected fill-in")
        }
        XCTAssertNil(fillIn.value)
        XCTAssertEqual(fillIn.type, .text)
    }
}
