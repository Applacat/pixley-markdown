import Foundation

/// Watches a file for external modifications using DispatchSource.
/// Notifies via callback when the file content changes on disk.
///
/// Handles atomic writes correctly: atomic writes create a temp file then rename,
/// which invalidates the original file descriptor. On `.rename`/`.delete` events,
/// the watcher re-opens the file to track the new inode.
@MainActor
final class FileWatcher {

    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var lastModificationDate: Date?
    private var watchedPath: String?
    private let onChange: @MainActor () -> Void

    /// Time-based suppression window for self-initiated writes.
    /// Atomic writes fire multiple DispatchSource events (write + rename),
    /// so a simple boolean flag is insufficient.
    private var suppressUntil: Date?

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    deinit {
        source?.cancel()
    }

    /// Suppress file change notifications for the next short window.
    /// Call this before writing to the watched file to prevent reload pills.
    /// Default of 1.0 second handles atomic writes which can trigger multiple
    /// file system events (write + rename + delete) that may be delayed/coalesced by macOS.
    /// Pair with `selfWriteCompleted()` / `selfWriteFailed()` so the window
    /// doesn't outlive the write it was armed for.
    func suppressChanges(for duration: TimeInterval = 1.0) {
        suppressUntil = Date().addingTimeInterval(duration)
    }

    /// Call after a self-initiated write to the watched file succeeds.
    /// Records the write's modification date (so its trailing FS events are
    /// deduplicated) and lifts the suppression window, so any *later* external
    /// change is delivered immediately instead of being swallowed.
    func selfWriteCompleted() {
        suppressUntil = nil
        guard let watchedPath else { return }
        lastModificationDate = Self.modificationDate(for: watchedPath)
    }

    /// Call when a self-initiated write fails after `suppressChanges` was armed.
    /// Nothing was written by us, so any modification-date change since the last
    /// delivered event is external — lift suppression and deliver it.
    func selfWriteFailed() {
        suppressUntil = nil
        guard let watchedPath else { return }
        checkForChange(path: watchedPath)
    }

    /// Start watching a file at the given URL.
    /// Stops any previous watch automatically.
    func watch(_ url: URL) {
        stop()

        let path = url.path
        watchedPath = path
        startSource(path: path)
    }

    /// Stop watching the current file.
    func stop() {
        source?.cancel()
        source = nil
        fileDescriptor = -1
        watchedPath = nil
    }

    // MARK: - Private

    private func startSource(path: String, isRewatch: Bool = false) {
        // Tear down the previous watch if any. Once a source exists, its cancel
        // handler owns the fd — closing it here too would double-close: the
        // manual close frees the fd number before open() below, open() reuses
        // it, and the queued cancel handler then closes the *new* watch's fd,
        // silently killing the watcher.
        if let source {
            source.cancel()
            self.source = nil
        } else if fileDescriptor >= 0 {
            close(fileDescriptor)
        }
        fileDescriptor = -1

        fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        if !isRewatch {
            // Fresh watch: current disk state is the baseline.
            lastModificationDate = Self.modificationDate(for: path)
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.handleFileEvent(path: path)
            }
        }

        let fd = fileDescriptor
        source.setCancelHandler {
            if fd >= 0 {
                close(fd)
            }
        }

        self.source = source
        source.resume()
    }

    private func handleFileEvent(path: String) {
        // Atomic writes invalidate the fd (rename replaces the inode).
        // Re-watch the path to track the new file.
        let events = source?.data ?? []
        if events.contains(.rename) || events.contains(.delete) {
            // Small delay to let the atomic rename complete
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, self.watchedPath == path else { return }
                self.startSource(path: path, isRewatch: true)
                // The new source won't report changes that landed before it was
                // armed — deliver anything that slipped into the gap.
                self.checkForChange(path: path)
            }
        }

        checkForChange(path: path)
    }

    /// Compares the file's modification date against the last *delivered* one
    /// and fires `onChange` when it differs. Suppressed changes are deliberately
    /// NOT recorded as seen: if a suppressed event was an external write rather
    /// than our own, a later event (or `selfWriteFailed`) must still surface it.
    /// Self-writes record their date via `selfWriteCompleted` instead.
    private func checkForChange(path: String) {
        let currentDate = Self.modificationDate(for: path)
        guard currentDate != lastModificationDate else { return }

        if let suppressUntil, Date() < suppressUntil {
            return
        }
        suppressUntil = nil

        lastModificationDate = currentDate
        onChange()
    }

    private static func modificationDate(for path: String) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
    }
}
