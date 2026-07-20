import XCTest
import Foundation

// MARK: - Test-Only Type Definitions
// FileWatcher uses DispatchSource which is hard to test directly.
// We mirror the delivery logic: deduplication by modification date,
// the suppression window for self-writes, and the selfWriteCompleted/
// selfWriteFailed settlement that prevents suppressed external changes
// from being swallowed permanently (issue #79).

// MARK: - FileWatcher Mirror

/// Mirrors FileWatcher's delivery logic without DispatchSource.
/// Key behaviors:
/// - checkForChange only fires onChange when the modification date differs
///   from the last *delivered* one.
/// - Suppressed changes are NOT recorded as seen, so a later event can
///   still surface an external change that landed during the window.
/// - selfWriteCompleted records the self-write's date (deduplicating its
///   trailing events) and lifts suppression.
/// - selfWriteFailed lifts suppression and delivers anything that changed.
/// `now` and the current disk date are injected for determinism.
@MainActor
private final class TestableFileWatcher {

    private(set) var lastModificationDate: Date?
    private(set) var isWatching = false
    private(set) var onChangeCallCount = 0
    private var suppressUntil: Date?

    /// Simulates watch() — records initial modification date
    func watch(initialModificationDate: Date?) {
        stop()
        lastModificationDate = initialModificationDate
        isWatching = true
    }

    /// Simulates stop()
    func stop() {
        isWatching = false
    }

    /// Mirrors suppressChanges(for:)
    func suppressChanges(for duration: TimeInterval = 1.0, now: Date = Date()) {
        suppressUntil = now.addingTimeInterval(duration)
    }

    /// Mirrors handleFileEvent → checkForChange
    func handleFileEvent(currentModificationDate: Date?, now: Date = Date()) {
        checkForChange(currentModificationDate: currentModificationDate, now: now)
    }

    /// Mirrors selfWriteCompleted — records the write's date, lifts suppression
    func selfWriteCompleted(currentModificationDate: Date?) {
        suppressUntil = nil
        lastModificationDate = currentModificationDate
    }

    /// Mirrors selfWriteFailed — lifts suppression, delivers pending change
    func selfWriteFailed(currentModificationDate: Date?, now: Date = Date()) {
        suppressUntil = nil
        checkForChange(currentModificationDate: currentModificationDate, now: now)
    }

    private func checkForChange(currentModificationDate: Date?, now: Date) {
        guard currentModificationDate != lastModificationDate else { return }
        if let suppressUntil, now < suppressUntil { return }
        suppressUntil = nil
        lastModificationDate = currentModificationDate
        onChangeCallCount += 1
    }
}

// MARK: - Tests

final class FileWatcherTests: XCTestCase {

    private var watcher: TestableFileWatcher!

    override func setUp() async throws {
        watcher = await TestableFileWatcher()
    }

    override func tearDown() async throws {
        watcher = nil
    }

    // MARK: - Deduplication Logic

    @MainActor
    func testSameModificationDate_doesNotTriggerOnChange() {
        let date = Date(timeIntervalSince1970: 1000)
        watcher.watch(initialModificationDate: date)

        // Same date — no change
        watcher.handleFileEvent(currentModificationDate: date)
        XCTAssertEqual(watcher.onChangeCallCount, 0)
    }

    @MainActor
    func testDifferentModificationDate_triggersOnChange() {
        let date1 = Date(timeIntervalSince1970: 1000)
        let date2 = Date(timeIntervalSince1970: 2000)
        watcher.watch(initialModificationDate: date1)

        // Different date — triggers change
        watcher.handleFileEvent(currentModificationDate: date2)
        XCTAssertEqual(watcher.onChangeCallCount, 1)
        XCTAssertEqual(watcher.lastModificationDate, date2)
    }

    // MARK: - Watch Lifecycle

    @MainActor
    func testWatch_replacesPreviousWatch() {
        let date1 = Date(timeIntervalSince1970: 1000)
        watcher.watch(initialModificationDate: date1)
        XCTAssertTrue(watcher.isWatching)

        // Watch again — replaces previous
        let date2 = Date(timeIntervalSince1970: 2000)
        watcher.watch(initialModificationDate: date2)
        XCTAssertTrue(watcher.isWatching)
        XCTAssertEqual(watcher.lastModificationDate, date2)
    }

    @MainActor
    func testStop_clearsWatchingState() {
        watcher.watch(initialModificationDate: Date())
        XCTAssertTrue(watcher.isWatching)

        watcher.stop()
        XCTAssertFalse(watcher.isWatching)
    }

    // MARK: - Suppression Window (self-writes)

    @MainActor
    func testSuppressedEvent_doesNotFireOnChange() {
        let t0 = Date(timeIntervalSince1970: 1000)
        watcher.watch(initialModificationDate: t0)

        // Self-write flow: suppress, write lands, its event arrives in-window
        watcher.suppressChanges(for: 1.0, now: t0)
        let selfWriteDate = t0.addingTimeInterval(0.1)
        watcher.handleFileEvent(currentModificationDate: selfWriteDate, now: t0.addingTimeInterval(0.2))

        XCTAssertEqual(watcher.onChangeCallCount, 0)
    }

    @MainActor
    func testExternalChangeDuringSuppression_isNotSwallowedForever() {
        // Regression test for issue #79: an external change that arrives inside
        // the suppression window must still surface after the window expires.
        let t0 = Date(timeIntervalSince1970: 1000)
        watcher.watch(initialModificationDate: t0)

        watcher.suppressChanges(for: 1.0, now: t0)

        // External write lands during the window — suppressed, but NOT recorded
        let externalDate = t0.addingTimeInterval(0.8)
        watcher.handleFileEvent(currentModificationDate: externalDate, now: t0.addingTimeInterval(0.9))
        XCTAssertEqual(watcher.onChangeCallCount, 0)

        // A later event after the window (same on-disk state) delivers it
        watcher.handleFileEvent(currentModificationDate: externalDate, now: t0.addingTimeInterval(1.5))
        XCTAssertEqual(watcher.onChangeCallCount, 1)
        XCTAssertEqual(watcher.lastModificationDate, externalDate)
    }

    @MainActor
    func testSelfWriteCompleted_deduplicatesTrailingEvents_thenDeliversExternal() {
        let t0 = Date(timeIntervalSince1970: 1000)
        watcher.watch(initialModificationDate: t0)

        // Self-write: suppress → write → settle
        watcher.suppressChanges(for: 1.0, now: t0)
        let selfWriteDate = t0.addingTimeInterval(0.1)
        watcher.selfWriteCompleted(currentModificationDate: selfWriteDate)

        // Trailing FS events from our own atomic write: same date — no pill,
        // even though selfWriteCompleted already lifted the suppression window
        watcher.handleFileEvent(currentModificationDate: selfWriteDate, now: t0.addingTimeInterval(0.3))
        XCTAssertEqual(watcher.onChangeCallCount, 0)

        // External change right after — delivered immediately (window is gone)
        let externalDate = t0.addingTimeInterval(0.5)
        watcher.handleFileEvent(currentModificationDate: externalDate, now: t0.addingTimeInterval(0.6))
        XCTAssertEqual(watcher.onChangeCallCount, 1)
    }

    @MainActor
    func testSelfWriteFailed_deliversChangeThatLandedDuringWindow() {
        let t0 = Date(timeIntervalSince1970: 1000)
        watcher.watch(initialModificationDate: t0)

        watcher.suppressChanges(for: 1.0, now: t0)

        // External write lands during the window — suppressed
        let externalDate = t0.addingTimeInterval(0.2)
        watcher.handleFileEvent(currentModificationDate: externalDate, now: t0.addingTimeInterval(0.3))
        XCTAssertEqual(watcher.onChangeCallCount, 0)

        // Our own write then fails — settlement must deliver the external change
        watcher.selfWriteFailed(currentModificationDate: externalDate, now: t0.addingTimeInterval(0.4))
        XCTAssertEqual(watcher.onChangeCallCount, 1)
        XCTAssertEqual(watcher.lastModificationDate, externalDate)
    }

    @MainActor
    func testSelfWriteFailed_noChange_noSpuriousDelivery() {
        let t0 = Date(timeIntervalSince1970: 1000)
        watcher.watch(initialModificationDate: t0)

        watcher.suppressChanges(for: 1.0, now: t0)
        // Write failed before anything hit the disk — nothing to deliver
        watcher.selfWriteFailed(currentModificationDate: t0, now: t0.addingTimeInterval(0.1))
        XCTAssertEqual(watcher.onChangeCallCount, 0)
    }

    // MARK: - Integration with Real Temp Files

    @MainActor
    func testRealFile_writeTriggersChange() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileWatcherTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("test.md")
        try "initial content".write(to: fileURL, atomically: true, encoding: .utf8)

        let initialDate = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date
        watcher.watch(initialModificationDate: initialDate)

        // Wait a moment, then write new content
        Thread.sleep(forTimeInterval: 0.05)
        try "updated content".write(to: fileURL, atomically: true, encoding: .utf8)

        let newDate = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date
        watcher.handleFileEvent(currentModificationDate: newDate)

        XCTAssertEqual(watcher.onChangeCallCount, 1)
    }

    @MainActor
    func testRealFile_noWriteNoChange() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileWatcherTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("test.md")
        try "content".write(to: fileURL, atomically: true, encoding: .utf8)

        let date = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date
        watcher.watch(initialModificationDate: date)

        // Same file, same date — no spurious callback
        watcher.handleFileEvent(currentModificationDate: date)
        XCTAssertEqual(watcher.onChangeCallCount, 0)
    }
}
