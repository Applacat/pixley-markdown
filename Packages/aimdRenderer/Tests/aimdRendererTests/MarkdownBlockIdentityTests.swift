import XCTest
@testable import aimdRenderer

/// Identity-stability tests for `MarkdownBlockParser` (issue #81).
///
/// Block ids drive SwiftUI ForEach identity in the Enhanced renderer. They
/// must be invariant under insertions/removals elsewhere in the document —
/// otherwise every reparse transplants control state and scroll anchors onto
/// neighboring blocks.
final class MarkdownBlockIdentityTests: XCTestCase {

    private func parseBlocks(_ content: String) -> [MarkdownBlock] {
        let elements = InteractiveElementDetector.detect(in: content)
        return MarkdownBlockParser.parseFlat(content: content, elements: elements)
    }

    private let document = """
    # Title

    Intro paragraph with some prose.

    - [ ] First task
    - [ ] Second task

    ```swift
    let x = 1
    ```

    Name: [[enter your name]]

    Closing paragraph.
    """

    // MARK: - Determinism

    func testSameDocumentParsedTwice_identicalIDs() {
        let first = parseBlocks(document).map(\.id)
        let second = parseBlocks(document).map(\.id)
        XCTAssertEqual(first, second)
        XCTAssertFalse(first.isEmpty)
    }

    func testIDsAreUnique() {
        let ids = parseBlocks(document).map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Block ids must be unique within a document")
    }

    // MARK: - Insertion invariance (the #81 regression)

    func testInsertionAtTop_downstreamIDsUnchanged() {
        let before = parseBlocks(document)
        let after = parseBlocks("An AI-inserted paragraph at the very top.\n\n" + document)

        // Every original block keeps its exact id after the insertion.
        let beforeIDs = Set(before.map(\.id))
        let afterIDs = Set(after.map(\.id))
        XCTAssertTrue(
            beforeIDs.isSubset(of: afterIDs),
            "Original block ids must survive an insertion above: missing \(beforeIDs.subtracting(afterIDs))"
        )
        XCTAssertEqual(after.count, before.count + 1)
    }

    func testInsertionInMiddle_surroundingIDsUnchanged() {
        let inserted = document.replacingOccurrences(
            of: "```swift",
            with: "A new paragraph the AI added mid-document.\n\n```swift"
        )
        let before = Set(parseBlocks(document).map(\.id))
        let after = Set(parseBlocks(inserted).map(\.id))
        XCTAssertTrue(before.isSubset(of: after))
    }

    func testRemoval_remainingIDsUnchanged() {
        let removed = document.replacingOccurrences(of: "Intro paragraph with some prose.\n\n", with: "")
        let after = Set(parseBlocks(removed).map(\.id))
        let expectedSurvivors = Set(parseBlocks(document).map(\.id))
            .subtracting(parseBlocks("Intro paragraph with some prose.").map(\.id))
        XCTAssertTrue(expectedSurvivors.isSubset(of: after))
    }

    // MARK: - Interactive element identity

    func testCheckboxToggle_keepsBlockIdentity() {
        // Checking a box changes content but must NOT change the block's id —
        // the row keeps its UI state and scroll anchor.
        let toggled = document.replacingOccurrences(of: "- [ ] First task", with: "- [x] First task")
        let beforeElement = parseBlocks(document).first { if case .interactiveElement = $0.kind { return true }; return false }
        let afterElement = parseBlocks(toggled).first { if case .interactiveElement = $0.kind { return true }; return false }
        XCTAssertNotNil(beforeElement)
        XCTAssertEqual(beforeElement?.id, afterElement?.id)
    }

    // MARK: - Duplicates

    func testDuplicateBlocks_getDistinctOrdinalIDs() {
        let dupDoc = "Same line.\n\nSame line.\n\nSame line.\n"
        let ids = parseBlocks(dupDoc).map(\.id)
        XCTAssertEqual(ids.count, 3)
        XCTAssertEqual(Set(ids).count, 3)
    }

    func testDuplicateListItems_distinctStableIDs() {
        let doc = "- dup\n- dup\n- unique\n"
        let blocks = parseBlocks(doc)
        guard case .unorderedList(let items)? = blocks.first?.kind else {
            return XCTFail("Expected unordered list")
        }
        let ids = items.map(\.id)
        XCTAssertEqual(Set(ids).count, 3, "Duplicate items must get distinct ordinal ids")
        // And they are stable across parses (no per-parse UUIDs)
        guard case .unorderedList(let items2)? = parseBlocks(doc).first?.kind else {
            return XCTFail("Expected unordered list")
        }
        XCTAssertEqual(ids, items2.map(\.id))
    }
}
