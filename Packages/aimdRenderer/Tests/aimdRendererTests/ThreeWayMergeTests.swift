import XCTest
@testable import aimdRenderer

/// G3 (US-3.1) merge test matrix: disjoint edits both survive, adjacent-line
/// edits both survive, same-region clashes are detected and never silently
/// resolved.
final class ThreeWayMergeTests: XCTestCase {

    private let base = """
    # Title

    Line one.
    Line two.
    Line three.

    - [ ] a task

    End.
    """

    private func merged(_ result: ThreeWayMerge.Result) -> String? {
        if case .merged(let content) = result { return content }
        return nil
    }

    // MARK: - Trivial cases

    func testOnlyTheirsChanged_takesTheirs() {
        let theirs = base.replacingOccurrences(of: "Line two.", with: "Line 2!")
        XCTAssertEqual(ThreeWayMerge.merge(base: base, mine: base, theirs: theirs), .merged(theirs))
    }

    func testOnlyMineChanged_takesMine() {
        let mine = base.replacingOccurrences(of: "Line two.", with: "Line 2!")
        XCTAssertEqual(ThreeWayMerge.merge(base: base, mine: mine, theirs: base), .merged(mine))
    }

    func testIdenticalChangeBothSides_mergesOnce() {
        let both = base.replacingOccurrences(of: "Line two.", with: "Line 2!")
        XCTAssertEqual(ThreeWayMerge.merge(base: base, mine: both, theirs: both), .merged(both))
    }

    // MARK: - Disjoint edits

    func testDisjointEdits_bothSurvive() {
        let mine = base.replacingOccurrences(of: "# Title", with: "# MINE Title")
        let theirs = base.replacingOccurrences(of: "End.", with: "THEIRS end.")
        guard let result = merged(ThreeWayMerge.merge(base: base, mine: mine, theirs: theirs)) else {
            return XCTFail("disjoint edits clashed")
        }
        XCTAssertTrue(result.contains("# MINE Title"))
        XCTAssertTrue(result.contains("THEIRS end."))
    }

    func testDisjointInsertions_bothSurvive() {
        let mine = base.replacingOccurrences(of: "# Title", with: "# Title\nMINE inserted line.")
        let theirs = base.replacingOccurrences(of: "End.", with: "THEIRS inserted line.\nEnd.")
        guard let result = merged(ThreeWayMerge.merge(base: base, mine: mine, theirs: theirs)) else {
            return XCTFail("disjoint insertions clashed")
        }
        XCTAssertTrue(result.contains("MINE inserted line."))
        XCTAssertTrue(result.contains("THEIRS inserted line."))
        XCTAssertTrue(result.contains("# Title"))
        XCTAssertTrue(result.contains("End."))
    }

    func testMineDeletion_theirsDistantEdit_bothSurvive() {
        let mine = base.replacingOccurrences(of: "Line two.\n", with: "")
        let theirs = base.replacingOccurrences(of: "End.", with: "THEIRS end.")
        guard let result = merged(ThreeWayMerge.merge(base: base, mine: mine, theirs: theirs)) else {
            return XCTFail("deletion + distant edit clashed")
        }
        XCTAssertFalse(result.contains("Line two."))
        XCTAssertTrue(result.contains("THEIRS end."))
    }

    // MARK: - Adjacent-line edits (the AC that kills naive chunk merging)

    func testAdjacentLineEdits_bothSurvive() {
        let mine = base.replacingOccurrences(of: "Line one.", with: "Line one MINE.")
        let theirs = base.replacingOccurrences(of: "Line two.", with: "Line two THEIRS.")
        guard let result = merged(ThreeWayMerge.merge(base: base, mine: mine, theirs: theirs)) else {
            return XCTFail("adjacent-line edits clashed")
        }
        XCTAssertTrue(result.contains("Line one MINE."))
        XCTAssertTrue(result.contains("Line two THEIRS."))
        XCTAssertTrue(result.contains("Line three."))
    }

    func testAdjacentEditAndCheckboxToggle_bothSurvive() {
        // The signature scenario: user types prose while the AI checks a task.
        let mine = base.replacingOccurrences(of: "Line three.", with: "Line three, typed more.")
        let theirs = base.replacingOccurrences(of: "- [ ] a task", with: "- [x] a task")
        guard let result = merged(ThreeWayMerge.merge(base: base, mine: mine, theirs: theirs)) else {
            return XCTFail("prose edit + checkbox toggle clashed")
        }
        XCTAssertTrue(result.contains("Line three, typed more."))
        XCTAssertTrue(result.contains("- [x] a task"))
    }

    // MARK: - Same-region clashes

    func testSameLineDifferentEdits_clash() {
        let mine = base.replacingOccurrences(of: "Line two.", with: "Line two MINE.")
        let theirs = base.replacingOccurrences(of: "Line two.", with: "Line two THEIRS.")
        XCTAssertEqual(ThreeWayMerge.merge(base: base, mine: mine, theirs: theirs), .clash)
    }

    func testCompetingInsertionsAtSamePoint_clash() {
        let mine = base.replacingOccurrences(of: "# Title", with: "# Title\nMINE line.")
        let theirs = base.replacingOccurrences(of: "# Title", with: "# Title\nTHEIRS line.")
        XCTAssertEqual(ThreeWayMerge.merge(base: base, mine: mine, theirs: theirs), .clash)
    }

    func testDeleteVersusEditSameLine_clash() {
        let mine = base.replacingOccurrences(of: "Line two.\n", with: "")
        let theirs = base.replacingOccurrences(of: "Line two.", with: "Line two THEIRS.")
        XCTAssertEqual(ThreeWayMerge.merge(base: base, mine: mine, theirs: theirs), .clash)
    }

    // MARK: - Fidelity

    func testCRLFDocument_mergePreservesLineEndings() {
        let crlfBase = "# CRLF\r\n\r\n- [ ] task one\r\n- [ ] task two\r\nEnd.\r\n"
        let mine = crlfBase.replacingOccurrences(of: "End.", with: "End MINE.")
        let theirs = crlfBase.replacingOccurrences(of: "- [ ] task one", with: "- [x] task one")
        guard let result = merged(ThreeWayMerge.merge(base: crlfBase, mine: mine, theirs: theirs)) else {
            return XCTFail("CRLF merge clashed")
        }
        XCTAssertTrue(result.contains("End MINE.\r\n"))
        XCTAssertTrue(result.contains("- [x] task one\r\n"))
        XCTAssertFalse(result.replacingOccurrences(of: "\r\n", with: "").contains("\r"),
                       "stray CR outside CRLF pairs")
    }

    func testTrailingNewline_preserved() {
        let baseNL = "alpha\nbeta\ngamma\n"
        let mine = "alpha MINE\nbeta\ngamma\n"
        let theirs = "alpha\nbeta\ngamma THEIRS\n"
        XCTAssertEqual(ThreeWayMerge.merge(base: baseNL, mine: mine, theirs: theirs),
                       .merged("alpha MINE\nbeta\ngamma THEIRS\n"))
    }

    func testUntouchedRegions_byteIdentical() {
        let mine = base.replacingOccurrences(of: "# Title", with: "# T")
        let theirs = base.replacingOccurrences(of: "End.", with: "E")
        guard let result = merged(ThreeWayMerge.merge(base: base, mine: mine, theirs: theirs)) else {
            return XCTFail("clashed")
        }
        XCTAssertEqual(result, base
            .replacingOccurrences(of: "# Title", with: "# T")
            .replacingOccurrences(of: "End.", with: "E"))
    }
}
