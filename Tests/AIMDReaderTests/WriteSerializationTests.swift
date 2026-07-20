import XCTest
import Foundation

// MARK: - Test-Only Type Definitions
// Mirrors InteractionHandler's per-URL write chain (issue #80): each write
// awaits the previous chain entry before its read-modify-write, so rapid
// interactions never interleave and lose edits.

@MainActor
private final class TestableWriteChain {

    private var chains: [String: Task<Void, Never>] = [:]

    /// Mirrors InteractionHandler.serializedWrite's chaining structure.
    func serialized<T: Sendable>(key: String, op: @escaping @MainActor () async throws -> T) async throws -> T {
        let previous = chains[key]
        let work = Task { () throws -> T in
            await previous?.value
            return try await op()
        }
        let chain = Task { _ = try? await work.value }
        chains[key] = chain
        defer {
            if chains[key] == chain {
                chains[key] = nil
            }
        }
        return try await work.value
    }
}

/// A simulated document on "disk" whose reads/writes can be slowed to force
/// the interleaving window that loses edits without serialization.
@MainActor
private final class SimulatedFile {
    var content: String
    private(set) var log: [String] = []

    init(_ content: String) { self.content = content }

    func read(as name: String, delayMs: UInt64 = 0) async -> String {
        log.append("\(name).read")
        if delayMs > 0 { try? await Task.sleep(for: .milliseconds(delayMs)) }
        return content
    }

    func write(_ new: String, as name: String) {
        log.append("\(name).write")
        content = new
    }
}

// MARK: - Tests

final class WriteSerializationTests: XCTestCase {

    /// The #80 regression: user rapidly checks checkbox A then checkbox B.
    /// Without serialization, B's read happens before A's write lands, so
    /// B's write is based on stale content and A's edit is lost.
    @MainActor
    func testRapidInterleavedWrites_bothEditsStick() async throws {
        let file = SimulatedFile("- [ ] A\n- [ ] B\n")
        let chain = TestableWriteChain()

        // Write A: slow read-modify-write (simulates large file / cold disk)
        let writeA = Task {
            try await chain.serialized(key: "doc") {
                let current = await file.read(as: "A", delayMs: 50)
                file.write(current.replacingOccurrences(of: "[ ] A", with: "[x] A"), as: "A")
            }
        }
        // Write B: fires immediately after, fast
        let writeB = Task {
            try await chain.serialized(key: "doc") {
                let current = await file.read(as: "B")
                file.write(current.replacingOccurrences(of: "[ ] B", with: "[x] B"), as: "B")
            }
        }

        try await writeA.value
        try await writeB.value

        XCTAssertEqual(file.content, "- [x] A\n- [x] B\n", "Both edits must survive rapid interaction")
        XCTAssertEqual(file.log, ["A.read", "A.write", "B.read", "B.write"],
                       "B's read must wait for A's write — no interleaving")
    }

    /// A failing write must not block subsequent writes (the chain advances
    /// past failures rather than deadlocking).
    @MainActor
    func testFailedWrite_doesNotBlockNextWrite() async throws {
        struct TestError: Error {}
        let file = SimulatedFile("- [ ] A\n")
        let chain = TestableWriteChain()

        let failing = Task {
            try await chain.serialized(key: "doc") {
                _ = await file.read(as: "bad", delayMs: 20)
                throw TestError()
            }
        }
        let succeeding = Task {
            try await chain.serialized(key: "doc") {
                let current = await file.read(as: "good")
                file.write(current.replacingOccurrences(of: "[ ] A", with: "[x] A"), as: "good")
            }
        }

        do {
            try await failing.value
            XCTFail("Expected failure")
        } catch {}
        try await succeeding.value

        XCTAssertEqual(file.content, "- [x] A\n")
    }

    /// Writes to different documents must not serialize against each other.
    @MainActor
    func testDifferentDocuments_runIndependently() async throws {
        let fileA = SimulatedFile("a")
        let fileB = SimulatedFile("b")
        let chain = TestableWriteChain()

        let slowA = Task {
            try await chain.serialized(key: "docA") {
                _ = await fileA.read(as: "A", delayMs: 100)
                fileA.write("a2", as: "A")
            }
        }
        let fastB = Task {
            try await chain.serialized(key: "docB") {
                _ = await fileB.read(as: "B")
                fileB.write("b2", as: "B")
            }
        }

        try await fastB.value
        XCTAssertEqual(fileB.content, "b2", "docB must complete without waiting for docA")
        XCTAssertEqual(fileA.content, "a", "docA still in flight")
        try await slowA.value
        XCTAssertEqual(fileA.content, "a2")
    }
}
