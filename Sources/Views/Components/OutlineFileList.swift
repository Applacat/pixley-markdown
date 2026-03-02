import SwiftUI
import AppKit

// MARK: - Outline Node (NSObject wrapper for NSOutlineView)

/// NSOutlineView requires NSObject-based items for stable identity tracking.
/// Swift structs get boxed in `_SwiftValue` wrappers whose `as?` casts fail
/// silently in delegate notifications, breaking expansion state tracking.
/// This wrapper gives NSOutlineView real Objective-C objects to work with.
final class OutlineNode: NSObject {
    let folderItem: FolderItem
    var childNodes: [OutlineNode]?

    init(_ item: FolderItem) {
        self.folderItem = item
        self.childNodes = item.children?.map { OutlineNode($0) }
        super.init()
    }
}

// MARK: - NSOutlineView Wrapper

/// Native macOS file browser using NSOutlineView.
/// Single-column outline with disclosure triangles, like iPhone Files app.
struct OutlineFileList: NSViewRepresentable {

    let items: [FolderItem]
    @Binding var selection: URL?
    /// NavigationState holds expansion state that survives Coordinator recreation
    let navigationState: NavigationState
    var isFavorite: ((URL) -> Bool)? = nil
    var isChanged: ((URL) -> Bool)? = nil
    var onToggleFavorite: ((URL) -> Void)? = nil

    func makeNSView(context: Context) -> NSScrollView {
        // Outline view with keyboard handling
        let outlineView = KeyHandlingOutlineView()
        outlineView.headerView = nil
        outlineView.indentationPerLevel = 10
        outlineView.rowSizeStyle = .default
        outlineView.rowHeight = 24  // Explicit row height for consistency
        outlineView.style = .sourceList  // macOS source list style
        outlineView.autoresizesOutlineColumn = true
        outlineView.usesAlternatingRowBackgroundColors = false
        outlineView.floatsGroupRows = false
        outlineView.allowsEmptySelection = true
        outlineView.doubleAction = #selector(Coordinator.handleDoubleClick(_:))  // Native double-click expand

        // Single column for file names
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("FileColumn"))
        column.isEditable = false
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        // Accessibility
        outlineView.setAccessibilityLabel("File browser")
        outlineView.setAccessibilityHelp("Use arrow keys to navigate, left/right to expand/collapse folders, Return to select file")

        // Data source and delegate
        outlineView.dataSource = context.coordinator
        outlineView.delegate = context.coordinator

        // Scroll view container
        let scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder  // Clean borders

        // Store reference for updates
        context.coordinator.outlineView = outlineView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let outlineView = context.coordinator.outlineView else { return }

        // Keep callback references current
        context.coordinator.isFavorite = isFavorite
        context.coordinator.isChanged = isChanged
        context.coordinator.onToggleFavorite = onToggleFavorite
        context.coordinator.selection = _selection

        // Always keep coordinator's items in sync with SwiftUI
        let oldCount = context.coordinator.items.count
        let itemsChanged = oldCount != items.count
        context.coordinator.items = items
        context.coordinator.rebuildNodes()

        // Only rebuild pre-fetched sets when items actually change (avoids O(n) tree walk on every SwiftUI update)
        if itemsChanged {
            context.coordinator.refreshFavoriteSet(items: items)
        }
        context.coordinator.refreshChangedSet(items: items)

        // Reload if item count changed, changed paths differ, or outline view is empty but should have content
        let outlineStale = outlineView.numberOfRows == 0 && !items.isEmpty
        let changedPathsDiffer = context.coordinator.changedPathsSet != context.coordinator.previousChangedPathsSet

        if itemsChanged || outlineStale || changedPathsDiffer {
            // Rebuild favorites too if not already done (changed paths without item change)
            if !itemsChanged {
                context.coordinator.refreshFavoriteSet(items: items)
            }
            context.coordinator.previousChangedPathsSet = context.coordinator.changedPathsSet

            // Guard: reloadData() fires outlineViewItemDidCollapse for every expanded item,
            // which would wipe expandedPaths before restoreExpansionState can use it.
            context.coordinator.isReloading = true
            outlineView.reloadData()
            context.coordinator.restoreExpansionState(outlineView: outlineView)
            context.coordinator.isReloading = false

            // Re-select the previously selected row if still visible (don't expand parents)
            if let selectedURL = context.coordinator.selection.wrappedValue {
                let rowCount = outlineView.numberOfRows
                for row in 0..<rowCount {
                    if let node = outlineView.item(atRow: row) as? OutlineNode,
                       node.folderItem.url == selectedURL {
                        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                        break
                    }
                }
            }
        }

        // Sync selection from coordinator → NSOutlineView
        context.coordinator.syncSelection(outlineView: outlineView)
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        if let outlineView = scrollView.documentView as? NSOutlineView {
            outlineView.dataSource = nil
            outlineView.delegate = nil
        }
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(items: items, selection: _selection, navigationState: navigationState, isFavorite: isFavorite, isChanged: isChanged, onToggleFavorite: onToggleFavorite)
    }

    // MARK: - Coordinator

    @MainActor
    class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {

        var items: [FolderItem]
        /// OutlineNode wrappers — NSObject-based items for NSOutlineView
        var nodes: [OutlineNode] = []
        var selection: Binding<URL?>
        weak var outlineView: NSOutlineView?
        /// NavigationState holds expansion state that survives Coordinator recreation
        let navigationState: NavigationState
        var isFavorite: ((URL) -> Bool)?
        var isChanged: ((URL) -> Bool)?
        var onToggleFavorite: ((URL) -> Void)?
        /// Pre-fetched favorite paths for O(1) lookup during cell configuration
        var favoritePathsSet = Set<String>()
        /// Pre-fetched changed file paths for O(1) lookup during cell configuration
        var changedPathsSet = Set<String>()
        /// Pre-fetched folder paths that have changed descendants (O(1) folder dot lookup)
        var changedFolderPathsSet = Set<String>()
        /// Previous changed paths — used to detect when dots need redrawing
        var previousChangedPathsSet = Set<String>()
        /// Guard flag: prevents reloadData() collapse delegate callbacks from wiping expandedPaths
        var isReloading = false
        /// Tracks last URL we synced to, so we don't fight the user's keyboard navigation
        fileprivate var lastSyncedURL: URL?

        /// Convenience accessor for expansion state stored on NavigationState
        private var expandedPaths: Set<String> {
            get { navigationState.sidebarExpandedPaths }
            set { navigationState.sidebarExpandedPaths = newValue }
        }

        init(items: [FolderItem], selection: Binding<URL?>, navigationState: NavigationState, isFavorite: ((URL) -> Bool)? = nil, isChanged: ((URL) -> Bool)? = nil, onToggleFavorite: ((URL) -> Void)? = nil) {
            self.items = items
            self.selection = selection
            self.navigationState = navigationState
            self.isFavorite = isFavorite
            self.isChanged = isChanged
            self.onToggleFavorite = onToggleFavorite
            super.init()
            rebuildNodes()
        }

        /// Rebuilds OutlineNode tree from current items.
        func rebuildNodes() {
            nodes = items.map { OutlineNode($0) }
        }

        /// Pre-fetches all favorites into a Set for O(1) lookup during cell configuration.
        func refreshFavoriteSet(items: [FolderItem]) {
            guard let isFavorite else {
                favoritePathsSet.removeAll()
                return
            }
            var set = Set<String>()
            func walk(_ items: [FolderItem]) {
                for item in items {
                    if item.isMarkdown, isFavorite(item.url) {
                        set.insert(item.url.path)
                    }
                    if let children = item.children {
                        walk(children)
                    }
                }
            }
            walk(items)
            favoritePathsSet = set
        }

        /// Pre-fetches all changed paths into Sets for O(1) lookup during cell configuration.
        /// Also computes ancestor folder paths so folder dot checks are O(1) instead of O(n).
        func refreshChangedSet(items: [FolderItem]) {
            guard let isChanged else {
                changedPathsSet.removeAll()
                changedFolderPathsSet.removeAll()
                return
            }
            var fileSet = Set<String>()
            func walk(_ items: [FolderItem]) {
                for item in items {
                    if isChanged(item.url) {
                        fileSet.insert(item.url.path)
                    }
                    if let children = item.children {
                        walk(children)
                    }
                }
            }
            walk(items)
            changedPathsSet = fileSet

            // Pre-compute ancestor folder paths for O(1) folder dot lookup
            var folderSet = Set<String>()
            for path in fileSet {
                var url = URL(fileURLWithPath: path).deletingLastPathComponent()
                while url.path != "/" {
                    if !folderSet.insert(url.path).inserted { break } // Already tracked ancestors
                    url.deleteLastPathComponent()
                }
            }
            changedFolderPathsSet = folderSet
        }

        // MARK: - Expansion State Management

        /// Restores expansion state from the expandedPaths set after reloadData.
        /// Folders start collapsed; only user-expanded folders are restored.
        func restoreExpansionState(outlineView: NSOutlineView) {
            restoreFromPaths(outlineView: outlineView, nodes: nodes)
        }

        private func restoreFromPaths(outlineView: NSOutlineView, nodes: [OutlineNode]) {
            for node in nodes where node.folderItem.isFolder {
                if expandedPaths.contains(node.folderItem.url.path) {
                    outlineView.expandItem(node, expandChildren: false)
                    if let children = node.childNodes {
                        restoreFromPaths(outlineView: outlineView, nodes: children)
                    }
                }
            }
        }


        // MARK: - Expansion Tracking (NSOutlineViewDelegate)
        // These now work reliably because OutlineNode is a real NSObject subclass.

        func outlineViewItemDidExpand(_ notification: Notification) {
            guard !isReloading else { return }
            guard let node = notification.userInfo?["NSObject"] as? OutlineNode else { return }
            expandedPaths.insert(node.folderItem.url.path)
        }

        func outlineViewItemDidCollapse(_ notification: Notification) {
            guard !isReloading else { return }
            guard let node = notification.userInfo?["NSObject"] as? OutlineNode else { return }
            let path = node.folderItem.url.path
            let prefix = path + "/"
            expandedPaths.remove(path)
            // Also remove all descendants — matches Finder/VS Code behavior
            expandedPaths = expandedPaths.filter { !$0.hasPrefix(prefix) }
        }

        // MARK: - Double Click Handler

        @objc func handleDoubleClick(_ sender: NSOutlineView) {
            let clickedRow = sender.clickedRow
            guard clickedRow >= 0,
                  let node = sender.item(atRow: clickedRow) as? OutlineNode,
                  node.folderItem.isFolder else {
                return
            }

            // Toggle expansion on double-click
            if sender.isItemExpanded(node) {
                sender.collapseItem(node)
            } else {
                sender.expandItem(node)
            }
        }

        // MARK: - Data Source

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            if let node = item as? OutlineNode {
                return node.childNodes?.count ?? 0
            }
            return nodes.count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            if let node = item as? OutlineNode {
                guard let children = node.childNodes, index < children.count else {
                    return OutlineNode(FolderItem(url: URL(fileURLWithPath: "/"), isFolder: false))
                }
                return children[index]
            }
            guard index < nodes.count else {
                return OutlineNode(FolderItem(url: URL(fileURLWithPath: "/"), isFolder: false))
            }
            return nodes[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let node = item as? OutlineNode else { return false }
            return node.folderItem.isFolder && (node.childNodes?.isEmpty == false)
        }

        // MARK: - Delegate

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let node = item as? OutlineNode else { return nil }
            let folderItem = node.folderItem

            let cellIdentifier = NSUserInterfaceItemIdentifier("FileCell")
            let cell: FileCellView

            if let existingCell = outlineView.makeView(withIdentifier: cellIdentifier, owner: self) as? FileCellView {
                cell = existingCell
            } else {
                cell = FileCellView()
                cell.identifier = cellIdentifier
            }

            // Calculate indentation level for this item
            var indentLevel = 0
            var currentItem: Any? = item
            while let parent = outlineView.parent(forItem: currentItem) {
                indentLevel += 1
                currentItem = parent
            }

            // Configure content with indentation awareness (uses pre-fetched favorites and changed sets)
            let favorited = folderItem.isMarkdown ? favoritePathsSet.contains(folderItem.url.path) : false
            let changed: Bool
            if folderItem.isFolder {
                // O(1) lookup using pre-computed ancestor folder paths
                changed = changedFolderPathsSet.contains(folderItem.url.path)
            } else {
                changed = changedPathsSet.contains(folderItem.url.path)
            }
            cell.configure(with: folderItem, indentLevel: indentLevel, outlineView: outlineView, isFavorite: favorited, isChanged: changed, onToggleFavorite: onToggleFavorite)

            return cell
        }

        // MARK: - Selection Sync

        /// Syncs the coordinator's selectedFile to the NSOutlineView's visual selection.
        /// Called from updateNSView when the binding changes externally (e.g., AppDelegate, session restore).
        /// Only acts when the binding value actually changes — prevents fighting the user's
        /// keyboard navigation (e.g., arrow-keying to a folder shouldn't snap back to the last file).
        func syncSelection(outlineView: NSOutlineView) {
            let targetURL = selection.wrappedValue

            // Don't fight the user's navigation if the binding hasn't changed
            guard targetURL != lastSyncedURL else { return }
            lastSyncedURL = targetURL

            // Get the currently selected item in the outline view
            let currentRow = outlineView.selectedRow
            if let targetURL {
                // Check if the outline view already has this item selected
                if currentRow >= 0,
                   let node = outlineView.item(atRow: currentRow) as? OutlineNode,
                   node.folderItem.url == targetURL {
                    return // Already in sync
                }

                // Find and select the target item
                if let row = findRow(for: targetURL, in: outlineView) {
                    outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                    outlineView.scrollRowToVisible(row)
                }
            } else if currentRow >= 0 {
                // No selection expected — deselect
                outlineView.deselectAll(nil)
            }
        }

        /// Recursively searches the node tree for a node matching the given URL.
        /// Expands parent folders as needed to reveal the item.
        private func findRow(for url: URL, in outlineView: NSOutlineView) -> Int? {
            func search(nodes: [OutlineNode], expandParents: Bool) -> OutlineNode? {
                for node in nodes {
                    if node.folderItem.url == url { return node }
                    if node.folderItem.isFolder, let children = node.childNodes {
                        if let found = search(nodes: children, expandParents: expandParents) {
                            if expandParents {
                                outlineView.expandItem(node)
                                expandedPaths.insert(node.folderItem.url.path)
                            }
                            return found
                        }
                    }
                }
                return nil
            }

            guard let _ = search(nodes: nodes, expandParents: true) else { return nil }

            // Now that parents are expanded, find the row
            let rowCount = outlineView.numberOfRows
            for row in 0..<rowCount {
                if let node = outlineView.item(atRow: row) as? OutlineNode,
                   node.folderItem.url == url {
                    return row
                }
            }
            return nil
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard let outlineView = notification.object as? NSOutlineView else { return }
            let selectedRow = outlineView.selectedRow
            guard selectedRow >= 0,
                  let node = outlineView.item(atRow: selectedRow) as? OutlineNode else {
                return
            }

            let item = node.folderItem
            if item.isMarkdown {
                selection.wrappedValue = item.url
            } else if item.isFolder {
                // Toggle expand/collapse on mouse click only (not keyboard navigation)
                if let event = NSApp.currentEvent,
                   event.type == .leftMouseUp || event.type == .leftMouseDown {
                    if outlineView.isItemExpanded(node) {
                        outlineView.collapseItem(node)
                    } else {
                        outlineView.expandItem(node)
                    }
                }
            }
        }

        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
            // Allow selecting everything - folders expand/collapse, files open
            return true
        }

    }
}

// MARK: - Key Handling Outline View

/// NSOutlineView subclass that adds Return and Escape key handling.
/// Up/Down arrows and Left/Right expand/collapse are handled natively by NSOutlineView.
final class KeyHandlingOutlineView: NSOutlineView {
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36: // Return
            let row = selectedRow
            guard row >= 0, let node = item(atRow: row) as? OutlineNode else {
                super.keyDown(with: event)
                return
            }
            if node.folderItem.isFolder {
                // Toggle folder expansion
                if isItemExpanded(node) {
                    collapseItem(node)
                } else {
                    expandItem(node)
                }
            }
            // For files, the selection change already triggers opening via the delegate
            // so Return on a file is effectively a no-op (already selected = already open)

        case 53: // Escape
            deselectAll(nil)

        default:
            super.keyDown(with: event)
        }
    }
}

// MARK: - File Cell View

/// Custom cell view with icon, name, favorite star, change dot, and markdown count badge for folders.
final class FileCellView: NSTableCellView {

    private let changeDot = NSView()
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let starButton = NSButton()
    private let countLabel = NSTextField(labelWithString: "")
    private var countMinWidthConstraint: NSLayoutConstraint!
    private var countTrailingConstraint: NSLayoutConstraint!
    private var starWidthConstraint: NSLayoutConstraint!
    private var changeDotWidthConstraint: NSLayoutConstraint!
    private var iconLeadingConstraint: NSLayoutConstraint!
    private var itemURL: URL?
    private var isFavorited = false
    private var onToggleFavorite: ((URL) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        // Blue dot indicator for new/changed files
        changeDot.translatesAutoresizingMaskIntoConstraints = false
        changeDot.wantsLayer = true
        changeDot.layer?.backgroundColor = NSColor.systemBlue.cgColor
        changeDot.layer?.cornerRadius = 3.5 // Half of 7pt for circle
        changeDot.isHidden = true
        addSubview(changeDot)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)
        imageView = iconView

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.cell?.truncatesLastVisibleLine = true
        nameLabel.isEditable = false
        nameLabel.isSelectable = false
        nameLabel.isBordered = false
        nameLabel.backgroundColor = .clear
        addSubview(nameLabel)
        textField = nameLabel

        // Configure star button
        starButton.translatesAutoresizingMaskIntoConstraints = false
        starButton.bezelStyle = .inline
        starButton.isBordered = false
        starButton.imagePosition = .imageOnly
        starButton.imageScaling = .scaleProportionallyDown
        starButton.target = self
        starButton.action = #selector(starClicked)
        addSubview(starButton)

        starWidthConstraint = starButton.widthAnchor.constraint(equalToConstant: 16)

        // Configure countLabel
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor
        countLabel.alignment = .right
        countLabel.isEditable = false
        countLabel.isSelectable = false
        countLabel.isBordered = false
        countLabel.backgroundColor = .clear
        addSubview(countLabel)

        // Create the width constraint but don't activate it yet
        countMinWidthConstraint = countLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 30)
        countTrailingConstraint = countLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4)
        changeDotWidthConstraint = changeDot.widthAnchor.constraint(equalToConstant: 0)
        iconLeadingConstraint = iconView.leadingAnchor.constraint(equalTo: changeDot.trailingAnchor, constant: 2)

        NSLayoutConstraint.activate([
            changeDot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            changeDot.centerYAnchor.constraint(equalTo: centerYAnchor),
            changeDotWidthConstraint,
            changeDot.heightAnchor.constraint(equalTo: changeDot.widthAnchor),

            iconLeadingConstraint,
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Star sits between name and count
            starButton.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: 4),
            starButton.trailingAnchor.constraint(equalTo: countLabel.leadingAnchor, constant: -4),
            starButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            starButton.heightAnchor.constraint(equalToConstant: 16),
            starWidthConstraint,

            countTrailingConstraint,
            countLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        // Make name compress first
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        starButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        countLabel.setContentHuggingPriority(.required, for: .horizontal)
    }

    func configure(with item: FolderItem, indentLevel: Int, outlineView: NSOutlineView, isFavorite: Bool = false, isChanged: Bool = false, onToggleFavorite: ((URL) -> Void)? = nil) {
        self.itemURL = item.url
        self.onToggleFavorite = onToggleFavorite

        nameLabel.stringValue = item.name
        nameLabel.textColor = (item.isMarkdown || item.isFolder) ? .labelColor : .secondaryLabelColor

        // Blue dot for new/changed files
        if isChanged {
            changeDot.isHidden = false
            changeDotWidthConstraint.constant = 7
            changeDot.layer?.backgroundColor = NSColor.systemBlue.cgColor
        } else {
            changeDot.isHidden = true
            changeDotWidthConstraint.constant = 0
        }

        // Accessibility: announce file type, favorite status, and change status to VoiceOver
        let typePrefix = item.isFolder ? "Folder" : "File"
        let favoriteStatus = isFavorite ? ", favorited" : ""
        let changedStatus = isChanged ? ", modified" : ""
        setAccessibilityLabel("\(typePrefix): \(item.name)\(favoriteStatus)\(changedStatus)")

        iconView.image = icon(for: item)
        iconView.contentTintColor = item.isFolder ? .systemBlue : (item.isMarkdown ? .labelColor : .secondaryLabelColor)

        // Adjust trailing padding to compensate for indentation
        let indentationOffset = CGFloat(indentLevel) * outlineView.indentationPerLevel
        countTrailingConstraint.constant = -(4 + indentationOffset)

        // Star for markdown files only
        if item.isMarkdown {
            self.isFavorited = isFavorite
            let starName = isFavorite ? "star.fill" : "star"
            starButton.image = NSImage(systemSymbolName: starName, accessibilityDescription: isFavorite ? "Unfavorite" : "Favorite")
            starButton.contentTintColor = isFavorite ? .systemYellow : .tertiaryLabelColor
            starButton.isHidden = false
            starWidthConstraint.constant = 16
        } else {
            starButton.isHidden = true
            starWidthConstraint.constant = 0
        }

        // Show markdown count for folders only
        if item.isFolder && item.markdownCount > 0 {
            countLabel.stringValue = "\(item.markdownCount)"
            countLabel.isHidden = false
            countMinWidthConstraint.isActive = true
        } else {
            countLabel.stringValue = ""
            countLabel.isHidden = true
            countMinWidthConstraint.isActive = false
        }
    }

    @objc private func starClicked() {
        guard let url = itemURL else { return }
        onToggleFavorite?(url)

        // Toggle star appearance immediately for instant feedback
        isFavorited.toggle()
        let starName = isFavorited ? "star.fill" : "star"
        starButton.image = NSImage(systemSymbolName: starName, accessibilityDescription: isFavorited ? "Unfavorite" : "Favorite")
        starButton.contentTintColor = isFavorited ? .systemYellow : .tertiaryLabelColor
    }

    private func icon(for item: FolderItem) -> NSImage? {
        let name: String
        if item.isFolder {
            name = "folder.fill"
        } else if item.isMarkdown {
            name = "doc.text.fill"
        } else {
            name = "doc.fill"
        }
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }
}
