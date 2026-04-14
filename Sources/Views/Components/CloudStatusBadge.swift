import SwiftUI

/// Shows iCloud download status for a file: downloaded, downloading, or cloud-only.
struct CloudStatusBadge: View {
    let url: URL

    @State private var status: CloudStatus = .local

    var body: some View {
        Group {
            switch status {
            case .local:
                EmptyView()
            case .downloaded:
                EmptyView() // No badge needed — file is available
            case .notDownloaded:
                Image(systemName: "icloud.and.arrow.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Available in iCloud")
            case .downloading:
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityLabel("Downloading from iCloud")
            }
        }
        .onAppear { updateStatus() }
        .onChange(of: url) { _, _ in updateStatus() }
    }

    private func updateStatus() {
        status = Self.cloudStatus(for: url)
    }

    static func cloudStatus(for url: URL) -> CloudStatus {
        let keys: Set<URLResourceKey> = [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemIsDownloadingKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isUbiquitousItem == true else {
            return .local
        }

        if values.ubiquitousItemIsDownloading == true {
            return .downloading
        }

        switch values.ubiquitousItemDownloadingStatus {
        case .current, .downloaded:
            return .downloaded
        case .notDownloaded:
            return .notDownloaded
        default:
            return .local
        }
    }

    /// Starts downloading a cloud-only file.
    static func startDownload(url: URL) {
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
    }
}

enum CloudStatus {
    case local          // Not an iCloud file
    case downloaded     // Downloaded and current
    case notDownloaded  // Cloud-only, needs download
    case downloading    // Currently downloading
}
