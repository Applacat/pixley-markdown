import Foundation

/// Safe file access through NSFileCoordinator.
/// Use for any file that may be synced via iCloud Drive or accessed concurrently.
enum CoordinatedFileAccess {

    /// Reads file data using NSFileCoordinator for safe concurrent access.
    static func read(url: URL) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            let coordinator = NSFileCoordinator()
            var coordinatorError: NSError?
            var result: Result<Data, Error> = .failure(CoordinatedFileError.readFailed)

            coordinator.coordinate(
                readingItemAt: url,
                options: [],
                error: &coordinatorError
            ) { coordinatedURL in
                do {
                    result = .success(try Data(contentsOf: coordinatedURL))
                } catch {
                    result = .failure(error)
                }
            }

            if let coordinatorError {
                throw coordinatorError
            }

            return try result.get()
        }.value
    }

    /// Reads file as UTF-8 string using NSFileCoordinator.
    static func readString(url: URL) async throws -> String {
        let data = try await read(url: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CoordinatedFileError.invalidEncoding
        }
        return text
    }

    /// Writes data using NSFileCoordinator for safe concurrent access.
    static func write(data: Data, to url: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            let coordinator = NSFileCoordinator()
            var coordinatorError: NSError?
            var writeError: Error?

            coordinator.coordinate(
                writingItemAt: url,
                options: .forReplacing,
                error: &coordinatorError
            ) { coordinatedURL in
                do {
                    try data.write(to: coordinatedURL)
                } catch {
                    writeError = error
                }
            }

            if let coordinatorError {
                throw coordinatorError
            }
            if let writeError {
                throw writeError
            }
        }.value
    }
}

enum CoordinatedFileError: LocalizedError {
    case readFailed
    case invalidEncoding

    var errorDescription: String? {
        switch self {
        case .readFailed: return "Failed to read file"
        case .invalidEncoding: return "Unable to decode file as UTF-8 text"
        }
    }
}
