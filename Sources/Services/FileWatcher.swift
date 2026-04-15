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

    /// Snapshot the file's current modification date after a self-write.
    func acknowledgeWrite(at path: String) {
        lastModificationDate = Self.modificationDate(for: path)
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

/// iOS FileWatcher using NSFilePresenter for iCloud Drive change notifications.
/// Receives callbacks when the watched file is modified externally (e.g., edited on another device).
///
/// NSFilePresenter fires presentedItemDidChange() for ALL file changes — content,
/// metadata, extended attributes, iCloud sync markers. To avoid false positives
/// (e.g., reload pill after our own writes), we:
/// 1. Check the file's modification date before triggering (skip metadata-only changes)
/// 2. Support suppressChanges(for:) — called by InteractionHandler before self-writes
@MainActor
final class FileWatcher {

    private let onChange: @MainActor () -> Void
    private var presenter: FileChangePresenter?
    private var suppressUntil: Date?
    private var lastModificationDate: Date?

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    /// Time-based suppression (kept for compatibility with macOS callers).
    func suppressChanges(for duration: TimeInterval = 1.0) {
        suppressUntil = Date().addingTimeInterval(duration)
    }

    /// Snapshot the file's current modification date so the next
    /// presentedItemDidChange is ignored. Call this AFTER a self-write.
    /// Unlike time-based suppression, this is reliable regardless of
    /// how long iOS delays the NSFilePresenter notification.
    func acknowledgeWrite(at path: String) {
        lastModificationDate = Self.modificationDate(for: path)
    }

    func watch(_ url: URL) {
        stop()
        lastModificationDate = Self.modificationDate(for: url.path)
        let presenter = FileChangePresenter(url: url) { [weak self] in
            self?.handleChange(path: url.path)
        }
        NSFileCoordinator.addFilePresenter(presenter)
        self.presenter = presenter
    }

    func stop() {
        if let presenter {
            NSFileCoordinator.removeFilePresenter(presenter)
        }
        presenter = nil
    }

    private func handleChange(path: String) {
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

/// NSFilePresenter that monitors a single file for external changes.
private final class FileChangePresenter: NSObject, NSFilePresenter, Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue.main
    private let onChangeCallback: @MainActor () -> Void

    init(url: URL, onChange: @escaping @MainActor () -> Void) {
        self.presentedItemURL = url
        self.onChangeCallback = onChange
        super.init()
    }

    func presentedItemDidChange() {
        Task { @MainActor in
            onChangeCallback()
        }
    }
}

#endif
