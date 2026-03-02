import Foundation
import os.log

private let logger = Logger(subsystem: "com.aimd.reader", category: "FolderWatcher")

/// Watches an entire folder tree for changes using FSEvents.
/// Reports changed directory paths so the sidebar can refresh and show indicators.
///
/// Uses directory-level FSEvents (not per-file) for efficiency.
/// Suspends event delivery when the app resigns active to save energy.
@MainActor
final class FolderWatcher {

    private var stream: FSEventStreamRef?
    private var debounceTask: Task<Void, Never>?
    private let onChange: @MainActor (Set<String>) -> Void

    /// Paths accumulated during debounce window
    private var pendingPaths: Set<String> = []

    init(onChange: @escaping @MainActor (Set<String>) -> Void) {
        self.onChange = onChange
    }

    /// Start watching the folder at `url` recursively via FSEvents.
    /// Stops any previous watch automatically.
    func watch(_ url: URL) {
        stop()

        let path = url.path as CFString
        let pathsToWatch = [path] as CFArray

        // Context carrying a pointer back to self (prevent retain cycle via raw pointer)
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        // Directory-level events only (not kFSEventStreamCreateFlagFileEvents).
        // FolderWatcher only needs to know which directories changed — the callback
        // already strips paths to parent directories. This halves event volume.
        guard let stream = FSEventStreamCreate(
            nil,
            fsEventsCallback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0, // 1-second coalesce latency
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes)
        ) else {
            logger.error("Failed to create FSEventStream for \(url.path)")
            return
        }

        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream

        logger.debug("Started watching \(url.lastPathComponent)")
    }

    /// Stop watching and clean up.
    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        pendingPaths.removeAll()
        stopStream()
    }

    /// Pause event delivery (e.g., when app resigns active). Keeps stream allocated.
    func suspend() {
        guard let stream else { return }
        FSEventStreamStop(stream)
    }

    /// Resume event delivery (e.g., when app becomes active).
    func resume() {
        guard let stream else { return }
        FSEventStreamStart(stream)
    }

    private func stopStream() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        logger.debug("Stopped folder watcher")
    }

    /// Called from the C callback on the main queue. Accumulates paths and debounces.
    fileprivate func handleEvents(_ paths: Set<String>) {
        pendingPaths.formUnion(paths)

        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            guard let self else { return }

            let paths = self.pendingPaths
            self.pendingPaths.removeAll()
            guard !paths.isEmpty else { return }

            logger.debug("Folder changes detected in \(paths.count) paths")
            self.onChange(paths)
        }
    }
}

// MARK: - FSEvents C Callback

/// Global C-function callback for FSEvents. Dispatches to FolderWatcher instance.
/// THREADING: FSEventStreamSetDispatchQueue(.main) guarantees delivery on the main queue.
/// MainActor.assumeIsolated is valid because DispatchQueue.main == MainActor executor.
private func fsEventsCallback(
    _ streamRef: ConstFSEventStreamRef,
    _ clientCallBackInfo: UnsafeMutableRawPointer?,
    _ numEvents: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let clientCallBackInfo else { return }
    let watcher = Unmanaged<FolderWatcher>.fromOpaque(clientCallBackInfo).takeUnretainedValue()

    // Extract changed directory paths from CFArray
    guard let cfPaths = unsafeBitCast(eventPaths, to: CFArray?.self) else { return }
    var changedDirs = Set<String>()

    for i in 0..<numEvents {
        guard let cfPath = CFArrayGetValueAtIndex(cfPaths, i) else { continue }
        let path = unsafeBitCast(cfPath, to: CFString.self) as String
        // Normalize via URL to strip trailing slashes (FSEvents delivers "/folder/")
        let normalized = URL(fileURLWithPath: path).path
        changedDirs.insert(normalized)
    }

    MainActor.assumeIsolated {
        watcher.handleEvents(changedDirs)
    }
}
