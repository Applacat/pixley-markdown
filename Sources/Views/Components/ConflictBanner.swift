import SwiftUI

/// Banner shown when a file has unresolved iCloud conflict versions.
/// Lets the user choose between the current version and conflict versions.
struct ConflictBanner: View {

    let fileURL: URL
    let onResolved: () -> Void

    @State private var conflicts: [ConflictResolver.ConflictVersion] = []
    @State private var isResolving = false

    var body: some View {
        Group {
            if !conflicts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("This file was edited on another device")
                            .font(.callout.weight(.medium))
                        Spacer()
                    }

                    HStack(spacing: 12) {
                        Button("Keep This Version") {
                            resolveKeepCurrent()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        if let conflict = conflicts.first {
                            Button("Use Other (\(conflict.summary))") {
                                resolveKeepOther(conflict)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .disabled(isResolving)
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
            }
        }
        .onAppear {
            conflicts = ConflictResolver.conflictVersions(for: fileURL)
        }
        .onChange(of: fileURL) { _, newURL in
            conflicts = ConflictResolver.conflictVersions(for: newURL)
        }
    }

    private func resolveKeepCurrent() {
        isResolving = true
        let url = fileURL
        Task.detached {
            try? ConflictResolver.keepCurrent(url: url)
        }
        // Small delay for file system to settle, then refresh
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            conflicts = []
            isResolving = false
            onResolved()
        }
    }

    private func resolveKeepOther(_ version: ConflictResolver.ConflictVersion) {
        isResolving = true
        let url = fileURL
        nonisolated(unsafe) let fileVersion = version.fileVersion
        Task.detached {
            try? fileVersion.replaceItem(at: url, options: [])
            fileVersion.isResolved = true
            if let remaining = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) {
                for conflict in remaining {
                    conflict.isResolved = true
                }
            }
            try? NSFileVersion.removeOtherVersionsOfItem(at: url)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            conflicts = []
            isResolving = false
            onResolved()
        }
    }
}
