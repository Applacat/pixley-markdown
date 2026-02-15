import Foundation

/// Watches a file for external modifications using DispatchSource.
/// Notifies via callback when the file content changes on disk.
@MainActor
final class FileWatcher {

    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var lastModificationDate: Date?
    private let onChange: @MainActor () -> Void

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    deinit {
        // Cancel triggers setCancelHandler which closes the file descriptor
        source?.cancel()
    }

    /// Start watching a file at the given URL.
    /// Stops any previous watch automatically.
    func watch(_ url: URL) {
        stop()

        let path = url.path
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

    /// Stop watching the current file.
    func stop() {
        source?.cancel()
        source = nil
        fileDescriptor = -1
    }

    private func handleFileEvent(path: String) {
        let currentDate = Self.modificationDate(for: path)
        guard currentDate != lastModificationDate else { return }
        lastModificationDate = currentDate
        onChange()
    }

    private static func modificationDate(for path: String) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
    }
}
