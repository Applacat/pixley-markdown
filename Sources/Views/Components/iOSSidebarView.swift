import SwiftUI

#if os(iOS)

// MARK: - iOS Sidebar View

/// SwiftUI folder browser for iOS, replacing the macOS NSOutlineView-backed OutlineFileList.
/// Uses List + DisclosureGroup for hierarchical folder browsing with the same FolderItem model.
struct iOSSidebarView: View {

    @Environment(\.coordinator) private var coordinator
    @State private var isLoading = false
    @State private var showFavoritesOnly = false
    @State private var filteredItems: [FolderItem] = []
    @State private var filterTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            // Navigate-up breadcrumb
            if let rootURL = coordinator.navigation.rootFolderURL,
               rootURL.pathComponents.count > 2 {
                iOSNavigateUpButton(rootURL: rootURL)
            }

            // Filter bar
            filterBar

            Divider()

            // Content
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredItems.isEmpty && (showFavoritesOnly || !coordinator.navigation.sidebarFilterQuery.isEmpty) {
                emptyFilterView
            } else {
                fileList
            }
        }
        .task(id: coordinator.navigation.rootFolderURL) {
            await loadRootFolder()
        }
        .onChange(of: coordinator.navigation.sidebarFilterQuery) { _, _ in
            recomputeFilteredItems(debounce: true)
        }
        .onChange(of: coordinator.navigation.displayItems) { _, _ in
            recomputeFilteredItems(debounce: false)
        }
        .onChange(of: showFavoritesOnly) { _, _ in
            recomputeFilteredItems(debounce: false)
        }
        .onDisappear {
            filterTask?.cancel()
            filterTask = nil
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.caption)
            TextField("Filter files...", text: Binding(
                get: { coordinator.navigation.sidebarFilterQuery },
                set: { coordinator.sidebarFilterQuery = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.callout)

            if !coordinator.navigation.sidebarFilterQuery.isEmpty {
                Button {
                    coordinator.setSidebarFilter("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear sidebar filter")
            }

            Button {
                showFavoritesOnly.toggle()
            } label: {
                Image(systemName: showFavoritesOnly ? "star.fill" : "star")
                    .foregroundStyle(showFavoritesOnly ? .yellow : .secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showFavoritesOnly ? "Show all files" : "Show favorites only")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - File List

    private var fileList: some View {
        List(selection: Binding(
            get: { coordinator.navigation.selectedFile },
            set: { newValue in
                if let url = newValue {
                    coordinator.selectFile(url)
                    RecentFoldersManager.shared.addRecentFile(url, parentFolder: coordinator.navigation.rootFolderURL)
                } else {
                    // nil = back button tapped on iPhone. Clear selection so
                    // NavigationSplitView can pop back to the sidebar.
                    coordinator.deselectFile()
                }
            }
        )) {
            ForEach(filteredItems) { item in
                if item.isFolder {
                    FolderDisclosureGroup(item: item)
                } else {
                    FileRow(item: item)
                        .tag(item.url)
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Empty Filter View

    private var emptyFilterView: some View {
        VStack(spacing: 8) {
            Image(systemName: showFavoritesOnly ? "star" : "doc.text.magnifyingglass")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text(showFavoritesOnly ? "No favorites yet" : "No matching files")
                .font(.callout)
                .foregroundStyle(.secondary)
            if showFavoritesOnly {
                Text("Star files to see them here")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data Loading

    private func loadRootFolder() async {
        guard let rootURL = coordinator.navigation.rootFolderURL else { return }
        isLoading = true
        FolderService.shared.invalidateCache(for: rootURL)
        let rootItems = await FolderService.shared.loadTree(at: rootURL)
        coordinator.setDisplayItems(FolderTreeFilter.filterMarkdownOnly(rootItems))
        filteredItems = coordinator.navigation.displayItems

        // First launch welcome: select first markdown
        if coordinator.navigation.isFirstLaunchWelcome {
            if let firstMarkdown = FolderTreeFilter.findFirstMarkdown(in: coordinator.navigation.displayItems) {
                coordinator.selectFile(firstMarkdown.url)
            }
            coordinator.setFirstLaunchWelcome(false)
        }

        isLoading = false
    }

    private func recomputeFilteredItems(debounce: Bool) {
        filterTask?.cancel()
        filterTask = Task {
            if debounce {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
            }

            var items = coordinator.navigation.displayItems
            let query = coordinator.navigation.sidebarFilterQuery
            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                items = FolderTreeFilter.filterByName(items, query: query, rootPath: coordinator.navigation.rootFolderURL?.path ?? "")
            }

            if showFavoritesOnly {
                let allFiles = FolderTreeFilter.flattenMarkdownFiles(items)
                filteredItems = allFiles.filter { coordinator.isFavorite($0.url) }
            } else {
                filteredItems = items
            }
        }
    }
}

// MARK: - Folder Disclosure Group

/// Expandable folder row using DisclosureGroup.
/// Reads coordinator from Environment — consistent with OOD pattern.
private struct FolderDisclosureGroup: View {

    let item: FolderItem
    @Environment(\.coordinator) private var coordinator
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if let children = item.children {
                ForEach(children) { child in
                    if child.isFolder {
                        FolderDisclosureGroup(item: child)
                    } else {
                        FileRow(item: child)
                            .tag(child.url)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
                    .font(.body)

                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                if item.markdownCount > 0 {
                    Text("\(item.markdownCount)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            .contentShape(Rectangle())
        }
    }
}

// MARK: - File Row

/// Single file row in the sidebar list.
/// Reads coordinator from Environment — consistent with OOD pattern.
private struct FileRow: View {

    let item: FolderItem
    @Environment(\.coordinator) private var coordinator

    private var isSelected: Bool {
        coordinator.navigation.selectedFile == item.url
    }

    private var isChanged: Bool {
        coordinator.navigation.isChanged(item.url)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .foregroundStyle(isSelected ? .primary : .secondary)
                .font(.body)

            Text(item.name)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if isChanged {
                Circle()
                    .fill(.blue)
                    .frame(width: 6, height: 6)
                    .accessibilityLabel("Modified")
            }

            if coordinator.isFavorite(item.url) {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption2)
                    .accessibilityLabel("Favorite")
            }
        }
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                coordinator.toggleFavorite(for: item.url)
            } label: {
                Label(
                    coordinator.isFavorite(item.url) ? "Unfavorite" : "Favorite",
                    systemImage: coordinator.isFavorite(item.url) ? "star.slash" : "star.fill"
                )
            }
            .tint(.yellow)
        }
    }
}

// MARK: - iOS Navigate Up Button

/// Navigate-up button for iOS sidebar.
/// Reads coordinator from Environment — consistent with OOD pattern.
struct iOSNavigateUpButton: View {
    let rootURL: URL
    @Environment(\.coordinator) private var coordinator

    var body: some View {
        Button {
            navigateUp()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.caption2.weight(.semibold))
                Text(rootURL.lastPathComponent)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Navigate up to parent folder")
    }

    private func navigateUp() {
        let parentURL = rootURL.deletingLastPathComponent()
        let canAccess = (try? FileManager.default.contentsOfDirectory(atPath: parentURL.path)) != nil

        if canAccess {
            RecentFoldersManager.shared.addFolder(parentURL)
            coordinator.openFolder(parentURL)
        }
        // On iOS we can't show NSOpenPanel — just attempt access directly
    }
}

#endif
