import Foundation

#if os(macOS)

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
    func suppressChanges(for duration: TimeInterval = 1.0) {
        suppressUntil = Date().addingTimeInterval(duration)
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

    private func startSource(path: String) {
        if fileDescriptor >= 0 {
            let oldFD = fileDescriptor
            source?.cancel()
            source = nil
            close(oldFD)
            fileDescriptor = -1
        }

        fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        lastModificationDate = Self.modificationDate(for: path)

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
        let events = source?.data ?? []
        if events.contains(.rename) || events.contains(.delete) {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, self.watchedPath == path else { return }
                self.startSource(path: path)
            }
        }

        let currentDate = Self.modificationDate(for: path)
        guard currentDate != lastModificationDate else { return }
        lastModificationDate = currentDate

        if let suppressUntil, Date() < suppressUntil {
            return
        }
        suppressUntil = nil

        onChange()
    }

    private static func modificationDate(for path: String) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
    }
}

#else

/// Stub FileWatcher for iOS — file watching will be handled by NSFilePresenter in Phase 2 (iCloud).
@MainActor
final class FileWatcher {

    init(onChange: @escaping @MainActor () -> Void) {}

    func suppressChanges(for duration: TimeInterval = 1.0) {}
    func watch(_ url: URL) {}
    func stop() {}
}

#endif
