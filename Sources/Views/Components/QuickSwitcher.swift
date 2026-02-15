import SwiftUI

// MARK: - Quick Switcher

/// Spotlight-like file switcher overlay (Cmd+P).
/// Shows a search field with fuzzy-filtered file results.
struct QuickSwitcher: View {

    @Environment(\.coordinator) private var coordinator
    let allFiles: [FolderItem]

    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var isSearchFocused: Bool

    private var results: [FolderItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return Array(allFiles.prefix(20))
        }

        let lowered = trimmed.lowercased()

        // Score and sort: prefix matches ranked higher than contains
        let scored = allFiles.compactMap { item -> (FolderItem, Int)? in
            let name = item.name.lowercased()
            if name.hasPrefix(lowered) {
                return (item, 2) // Prefix match = highest priority
            } else if name.localizedCaseInsensitiveContains(trimmed) {
                return (item, 1) // Contains match
            }
            return nil
        }

        return scored
            .sorted { $0.1 > $1.1 }
            .prefix(20)
            .map(\.0)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Go to file...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isSearchFocused)
                    .onSubmit { openSelected() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // Results list
            if results.isEmpty {
                Text("No matching files")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                                QuickSwitcherRow(
                                    item: item,
                                    isSelected: index == selectedIndex,
                                    rootURL: coordinator.navigation.rootFolderURL
                                )
                                .id(index)
                                .onTapGesture {
                                    selectedIndex = index
                                    openSelected()
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 300)
                    .onChange(of: selectedIndex) { _, newIndex in
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 500)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .onAppear {
            isSearchFocused = true
            selectedIndex = 0
        }
        .onChange(of: query) { _, _ in
            selectedIndex = 0
        }
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 {
                selectedIndex -= 1
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selectedIndex < results.count - 1 {
                selectedIndex += 1
            }
            return .handled
        }
        .onKeyPress(.escape) {
            coordinator.dismissQuickSwitcher()
            return .handled
        }
    }

    private func openSelected() {
        guard selectedIndex < results.count else { return }
        let file = results[selectedIndex]
        coordinator.selectFile(file.url)
        RecentFoldersManager.shared.addRecentFile(file.url, parentFolder: coordinator.navigation.rootFolderURL)
        coordinator.dismissQuickSwitcher()
    }
}

// MARK: - Quick Switcher Row

/// Single row in the quick switcher results list.
struct QuickSwitcherRow: View {

    let item: FolderItem
    let isSelected: Bool
    let rootURL: URL?

    /// Relative parent path from root folder
    private var parentPath: String {
        guard let root = rootURL else { return "" }
        let parentURL = item.url.deletingLastPathComponent()
        let rootPath = root.path
        let parentPathStr = parentURL.path

        if parentPathStr == rootPath {
            return ""
        }
        // Strip root prefix to get relative path
        if parentPathStr.hasPrefix(rootPath) {
            let relative = String(parentPathStr.dropFirst(rootPath.count))
            return relative.hasPrefix("/") ? String(relative.dropFirst()) : relative
        }
        return parentURL.lastPathComponent
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text.fill")
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.callout)
                    .lineLimit(1)

                if !parentPath.isEmpty {
                    Text(parentPath)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .contentShape(Rectangle())
    }
}

// MARK: - Quick Switcher Overlay Modifier

/// ViewModifier that adds the quick switcher as a dimmed overlay.
struct QuickSwitcherOverlay: ViewModifier {

    @Environment(\.coordinator) private var coordinator
    let allFiles: [FolderItem]

    func body(content: Content) -> some View {
        content.overlay {
            if coordinator.ui.isQuickSwitcherVisible {
                ZStack {
                    // Dimmed background — click to dismiss
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            coordinator.dismissQuickSwitcher()
                        }

                    // Switcher positioned near top
                    VStack {
                        QuickSwitcher(allFiles: allFiles)
                            .padding(.top, 80)
                        Spacer()
                    }
                }
                .transition(.opacity)
            }
        }
    }
}

extension View {
    /// Adds a Quick Switcher overlay (Cmd+P) showing all markdown files.
    func quickSwitcherOverlay(allFiles: [FolderItem]) -> some View {
        modifier(QuickSwitcherOverlay(allFiles: allFiles))
    }
}
