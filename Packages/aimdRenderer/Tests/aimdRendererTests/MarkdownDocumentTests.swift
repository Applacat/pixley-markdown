import XCTest
@testable import aimdRenderer

/// G1 document-model tests (US-1.1): the in-memory source of truth that the
/// interaction path mutates instead of reading disk.
@MainActor
final class MarkdownDocumentTests: XCTestCase {

    private let url = URL(fileURLWithPath: "/tmp/model-test.md")

    override func setUp() async throws {
        MarkdownDocumentRegistry._resetForTesting()
    }

    func testUpdate_bumpsRevisionAndDirties() {
        let doc = MarkdownDocument(url: url, source: "a")
        XCTAssertFalse(doc.isDirty)
        doc.update(source: "b")
        XCTAssertEqual(doc.revision, 1)
        XCTAssertTrue(doc.isDirty, "Unsaved local mutation must read as dirty")
    }

    func testUpdate_identicalContent_noRevisionChurn() {
        let doc = MarkdownDocument(url: url, source: "a")
        doc.update(source: "a")
        XCTAssertEqual(doc.revision, 0)
    }

    func testSyncToDisk_clearsDirtyAndResetsBaseline() {
        let doc = MarkdownDocument(url: url, source: "a")
        doc.update(source: "b")
        doc.syncToDisk(content: "b")   // save confirmed
        XCTAssertFalse(doc.isDirty)
        doc.syncToDisk(content: "c")   // external reload
        XCTAssertEqual(doc.source, "c")
        XCTAssertFalse(doc.isDirty)
    }

    func testRegistry_obtainReturnsSameInstance() {
        let first = MarkdownDocumentRegistry.obtain(url: url, initialSource: "a")
        first.update(source: "edited")
        let second = MarkdownDocumentRegistry.obtain(url: url, initialSource: "IGNORED")
        XCTAssertTrue(first === second, "Every writer must mutate the same live document")
        XCTAssertEqual(second.source, "edited")
    }

    func testRegistry_syncFromDisk_updatesLiveDocument() {
        let doc = MarkdownDocumentRegistry.obtain(url: url, initialSource: "old")
        MarkdownDocumentRegistry.syncFromDisk(url: url, content: "fresh from disk")
        XCTAssertEqual(doc.source, "fresh from disk")
        XCTAssertFalse(doc.isDirty)
    }

    func testRegistry_release_dropsDocument() {
        let doc = MarkdownDocumentRegistry.obtain(url: url, initialSource: "a")
        doc.update(source: "b")
        MarkdownDocumentRegistry.release(url: url)
        let fresh = MarkdownDocumentRegistry.obtain(url: url, initialSource: "new")
        XCTAssertFalse(fresh === doc)
        XCTAssertEqual(fresh.source, "new")
    }
}
