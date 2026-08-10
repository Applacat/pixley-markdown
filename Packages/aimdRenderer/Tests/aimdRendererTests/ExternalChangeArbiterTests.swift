import XCTest
@testable import aimdRenderer

/// G3 (US-3.2) arbiter semantics + the 100-iteration AI-write-during-typing
/// fuzz: whatever the outcome, neither side's text is ever silently lost.
@MainActor
final class ExternalChangeArbiterTests: XCTestCase {

    private func makeDocument(_ source: String) -> MarkdownDocument {
        MarkdownDocument(url: URL(fileURLWithPath: "/tmp/arbiter-test.md"), source: source)
    }

    // MARK: - Outcome semantics

    func testDiskMatchesModel_noChange() {
        let doc = makeDocument("hello\n")
        doc.update(source: "hello world\n")
        let outcome = ExternalChangeArbiter.arbitrate(document: doc, diskContent: "hello world\n")
        XCTAssertEqual(outcome, .noChange)
        XCTAssertFalse(doc.isDirty, "rebaseline should make the doc clean")
    }

    func testCleanDocument_silentReload() {
        let doc = makeDocument("hello\n")
        let outcome = ExternalChangeArbiter.arbitrate(document: doc, diskContent: "external\n")
        XCTAssertEqual(outcome, .reloaded)
        XCTAssertEqual(doc.source, "external\n")
        XCTAssertFalse(doc.isDirty)
    }

    func testDirtyDocument_disjointEdits_autoMerged() {
        let doc = makeDocument("alpha\nbeta\ngamma\n")
        doc.update(source: "alpha MINE\nbeta\ngamma\n")
        let outcome = ExternalChangeArbiter.arbitrate(
            document: doc, diskContent: "alpha\nbeta\ngamma THEIRS\n")
        XCTAssertEqual(outcome, .merged)
        XCTAssertEqual(doc.source, "alpha MINE\nbeta\ngamma THEIRS\n")
        XCTAssertTrue(doc.isDirty, "merged model must want a save (disk still has theirs)")
        XCTAssertEqual(doc.baselineContent, "alpha\nbeta\ngamma THEIRS\n",
                       "baseline must be what is actually on disk")
    }

    func testDirtyDocument_sameRegion_clashLeavesModelUntouched() {
        let doc = makeDocument("alpha\nbeta\n")
        doc.update(source: "alpha MINE\nbeta\n")
        let revisionBefore = doc.revision
        let outcome = ExternalChangeArbiter.arbitrate(
            document: doc, diskContent: "alpha THEIRS\nbeta\n")
        XCTAssertEqual(outcome, .clash(theirs: "alpha THEIRS\nbeta\n"))
        XCTAssertEqual(doc.source, "alpha MINE\nbeta\n")
        XCTAssertEqual(doc.revision, revisionBefore)
        XCTAssertEqual(doc.baselineContent, "alpha\nbeta\n", "clash must not move the baseline")
    }

    func testKeepMine_rebaselinesSoSaveOverwrites() {
        let doc = makeDocument("alpha\n")
        doc.update(source: "alpha MINE\n")
        ExternalChangeArbiter.keepMine(document: doc, theirs: "alpha THEIRS\n")
        XCTAssertEqual(doc.source, "alpha MINE\n")
        XCTAssertTrue(doc.isDirty, "keep-mine leaves the model dirty against disk")
        XCTAssertEqual(doc.baselineContent, "alpha THEIRS\n")
    }

    func testTakeTheirs_adoptsExternalContent() {
        let doc = makeDocument("alpha\n")
        doc.update(source: "alpha MINE\n")
        ExternalChangeArbiter.takeTheirs(document: doc, theirs: "alpha THEIRS\n")
        XCTAssertEqual(doc.source, "alpha THEIRS\n")
        XCTAssertFalse(doc.isDirty)
    }

    // MARK: - Clash hold (review fix: saves must pause until resolution)

    func testClash_flagsPendingClashOnDocument() {
        let doc = makeDocument("alpha\n")
        doc.update(source: "alpha MINE\n")
        _ = ExternalChangeArbiter.arbitrate(document: doc, diskContent: "alpha THEIRS\n")
        XCTAssertEqual(doc.pendingClash, "alpha THEIRS\n",
                       "clash must hold saves until the user decides")
    }

    func testClashResolution_clearsPendingClash() {
        let keep = makeDocument("alpha\n")
        keep.update(source: "alpha MINE\n")
        _ = ExternalChangeArbiter.arbitrate(document: keep, diskContent: "alpha THEIRS\n")
        ExternalChangeArbiter.keepMine(document: keep, theirs: "alpha THEIRS\n")
        XCTAssertNil(keep.pendingClash)

        let take = makeDocument("alpha\n")
        take.update(source: "alpha MINE\n")
        _ = ExternalChangeArbiter.arbitrate(document: take, diskContent: "alpha THEIRS\n")
        ExternalChangeArbiter.takeTheirs(document: take, theirs: "alpha THEIRS\n")
        XCTAssertNil(take.pendingClash)
    }

    func testAutoMergeAndReload_neverFlagClash() {
        let doc = makeDocument("alpha\nbeta\n")
        doc.update(source: "alpha MINE\nbeta\n")
        _ = ExternalChangeArbiter.arbitrate(document: doc, diskContent: "alpha\nbeta THEIRS\n")
        XCTAssertNil(doc.pendingClash)

        let clean = makeDocument("alpha\n")
        _ = ExternalChangeArbiter.arbitrate(document: clean, diskContent: "external\n")
        XCTAssertNil(clean.pendingClash)
    }

    func testSequentialMerges_baselineAdvances() {
        // Two external writes in a row against a continuously dirty doc.
        let doc = makeDocument("a\nb\nc\nd\n")
        doc.update(source: "a MINE\nb\nc\nd\n")
        XCTAssertEqual(ExternalChangeArbiter.arbitrate(
            document: doc, diskContent: "a\nb\nc THEIRS1\nd\n"), .merged)
        // Doc still unsaved; a second external write arrives on top of the first.
        XCTAssertEqual(ExternalChangeArbiter.arbitrate(
            document: doc, diskContent: "a\nb\nc THEIRS1\nd THEIRS2\n"), .merged)
        XCTAssertEqual(doc.source, "a MINE\nb\nc THEIRS1\nd THEIRS2\n")
    }

    // MARK: - 100-iteration AI-write-during-typing fuzz (US-3.2 AC)

    /// Deterministic RNG so failures reproduce (SplitMix64).
    private struct SeededRNG: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    func testFuzz_aiWriteDuringTyping_noDataLossEitherSide() {
        var rng = SeededRNG(state: 0xB1E55ED)
        let lineCount = 30

        for iteration in 0..<100 {
            let baseLines = (0..<lineCount).map { "line-\($0) of the document body." }
            let base = baseLines.joined(separator: "\n") + "\n"

            // The user types on line a (dirty model)…
            let a = Int.random(in: 0..<lineCount, using: &rng)
            var mineLines = baseLines
            mineLines[a] += " MINE-\(iteration)"
            let mine = mineLines.joined(separator: "\n") + "\n"

            // …while the AI writes line b to disk.
            let b = Int.random(in: 0..<lineCount, using: &rng)
            var theirLines = baseLines
            theirLines[b] += " THEIRS-\(iteration)"
            let theirs = theirLines.joined(separator: "\n") + "\n"

            let doc = makeDocument(base)
            doc.update(source: mine)
            XCTAssertTrue(doc.isDirty)

            switch ExternalChangeArbiter.arbitrate(document: doc, diskContent: theirs) {
            case .merged:
                XCTAssertNotEqual(a, b, "iteration \(iteration): same-line edits must clash, not merge")
                XCTAssertTrue(doc.source.contains("MINE-\(iteration)"),
                              "iteration \(iteration): user's typing lost in merge")
                XCTAssertTrue(doc.source.contains("THEIRS-\(iteration)"),
                              "iteration \(iteration): AI's write lost in merge")
            case .clash(let disk):
                XCTAssertEqual(a, b, "iteration \(iteration): disjoint edits must merge, not clash")
                XCTAssertTrue(doc.source.contains("MINE-\(iteration)"),
                              "iteration \(iteration): clash mutated the user's model")
                XCTAssertTrue(disk.contains("THEIRS-\(iteration)"),
                              "iteration \(iteration): clash lost the AI's disk content")
            case .noChange, .reloaded:
                XCTFail("iteration \(iteration): dirty doc with differing disk must merge or clash")
            }
        }
    }
}
