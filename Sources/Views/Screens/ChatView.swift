import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif
#if canImport(AppKit)
import AppKit
#endif
import aimdRenderer

// MARK: - Chat View

/// The right panel containing Pixley Chat functionality.
/// Uses Apple Foundation Models for on-device AI inference.
/// Shows "Thinking..." while awaiting, then full response at once
/// (plain text respond(to:) doesn't support token streaming).
@available(macOS 26, iOS 26, *)
struct ChatView: View {

    @Environment(\.coordinator) private var coordinator

    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isLoading = false
    @State private var isWaitingForDocument = false
    @State private var askTask: Task<Void, Never>?
    @State private var initialQuestionTask: Task<Void, Never>?

    // Service for business logic — @State ensures single instance per view identity
    @State private var chatService = ChatService()
    @State private var cachedPrompts: [SuggestedPrompt] = []

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            chatHeader
            Divider()
            #endif

            // Content based on FM availability
            if SystemLanguageModel.default.availability != .available {
                fmUnavailableView
            } else if coordinator.navigation.selectedFile == nil {
                noFileView
            } else {
                chatContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: coordinator.ui.initialChatQuestion) { _, newValue in
            if newValue != nil {
                initialQuestionTask?.cancel()
                initialQuestionTask = Task { await handleInitialQuestion() }
            }
        }
        .onChange(of: coordinator.navigation.selectedFile) { oldValue, newValue in
            // Document switched — reset conversation for new document
            if oldValue != newValue, let newFile = newValue {
                messages.removeAll()
                chatService.switchDocument(
                    documentContent: coordinator.document.content,
                    documentPath: newFile.path
                )
                configureEditTool()
                cachedPrompts = suggestedPrompts(for: coordinator.document.content)
            }
        }
        .onChange(of: coordinator.document.content) { _, newContent in
            cachedPrompts = suggestedPrompts(for: newContent)
        }
        .onDisappear {
            cancelAllTasks()
        }
        .task {
            // Configure summary repository once SwiftData is ready
            if let repo = coordinator.chatSummaryRepository {
                chatService.configure(summaryRepository: repo)
            }
            // Configure edit tool for voice commands
            configureEditTool()
        }
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Forget", systemImage: "eraser.line.dashed") {
                    clearChat()
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(messages.isEmpty)
            }
        }
        #endif
    }

    // MARK: - Header

    private var chatHeader: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Pixley Chat", systemImage: "bubble.left.and.bubble.right")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                // Turn counter
                if chatService.turnCount > 0 {
                    Text("Turn \(chatService.turnCount)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }

                if !messages.isEmpty {
                    Button("Forget", systemImage: "eraser.line.dashed") {
                        clearChat()
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Forget conversation (ESC)")
                    .accessibilityLabel("Clear conversation history")
                    .keyboardShortcut(.escape, modifiers: [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func clearChat() {
        cancelAllTasks()
        messages.removeAll()
        chatService.resetSession()
    }

    private func cancelAllTasks() {
        askTask?.cancel()
        askTask = nil
        initialQuestionTask?.cancel()
        initialQuestionTask = nil
    }

    // MARK: - FM Unavailable View

    private var fmUnavailableView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "apple.intelligence")
                .font(.largeTitle.weight(.light))
                .imageScale(.large)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Apple Intelligence Required")
                .font(.headline)
                .foregroundStyle(.secondary)
            #if os(macOS)
            Text("Enable Apple Intelligence in System Settings > Apple Intelligence & Siri to use Pixley Chat.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            #else
            Text("Enable Apple Intelligence in Settings > Apple Intelligence to use Pixley Chat.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            #endif
            Spacer()
        }
        .padding()
    }

    // MARK: - No File View

    private var noFileView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.largeTitle.weight(.light))
                .imageScale(.large)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text("Pixley Chat")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Select a file to ask Pixley about it")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }

    // MARK: - Chat Content

    private var chatContent: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if messages.isEmpty {
                            emptyChat
                        } else {
                            ForEach(messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                        }

                        if isLoading {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Thinking...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .id("loading")
                        }

                        // "Organizing thoughts..." indicator during condensation
                        if chatService.isCondensing {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("Organizing thoughts...")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .transition(.opacity)
                            .id("condensing")
                        }
                    }
                    .padding(.vertical, 12)
                }
                .onChange(of: messages.last?.id) { _, _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: isLoading) { _, newValue in
                    if !newValue { scrollToBottom(proxy) }
                }
            }

            Divider()
            inputArea
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        let target: String
        if isLoading {
            target = "loading"
        } else if let last = messages.last {
            target = last.id.uuidString
        } else {
            return
        }

        #if canImport(AppKit)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #else
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        #endif
        if reduceMotion {
            proxy.scrollTo(target, anchor: .bottom)
        } else {
            withAnimation {
                proxy.scrollTo(target, anchor: .bottom)
            }
        }
    }

    // MARK: - Empty Chat (Suggested Prompts)

    private var emptyChat: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.title.weight(.light))
                .imageScale(.large)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            Text("Ask Pixley about this document")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Context-aware suggested prompt chips (cached, not computed in body)
            if !cachedPrompts.isEmpty {
                let prompts = cachedPrompts
                VStack(spacing: 8) {
                    ForEach(prompts) { prompt in
                        Button {
                            sendPrompt(prompt.text)
                        } label: {
                            Label(prompt.text, systemImage: prompt.icon)
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(prompt.text)
                    }
                }
                .padding(.horizontal, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Suggested Prompts

    private struct SuggestedPrompt: Identifiable {
        let id = UUID()
        let text: String
        let icon: String
    }

    private func suggestedPrompts(for content: String) -> [SuggestedPrompt] {
        guard !content.isEmpty else { return [] }

        let elements = InteractiveElementDetector.detect(in: content)
        var prompts: [SuggestedPrompt] = []

        let hasCheckboxes = elements.contains { if case .checkbox = $0 { return true } else { return false } }
        let hasFillIns = elements.contains { if case .fillIn = $0 { return true } else { return false } }
        let hasChoices = elements.contains { if case .choice = $0 { return true } else { return false } }

        if hasCheckboxes {
            prompts.append(.init(text: "What's left to do?", icon: "list.bullet"))
            prompts.append(.init(text: "Mark all tasks complete", icon: "checkmark.circle"))
        }
        if hasFillIns { prompts.append(.init(text: "Fill in the blanks", icon: "pencil.line")) }
        if hasChoices { prompts.append(.init(text: "Help me decide", icon: "arrow.triangle.branch")) }

        let universal: [SuggestedPrompt] = [
            .init(text: "Summarize this document", icon: "doc.text.magnifyingglass"),
        ]
        for u in universal where prompts.count < 4 {
            prompts.append(u)
        }

        return Array(prompts.prefix(4))
    }

    /// Sends a suggested prompt directly (auto-send, no text field population).
    private func sendPrompt(_ text: String) {
        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        askTask?.cancel()
        askTask = Task {
            await askAI(text)
        }
    }

    // MARK: - Input Area

    private var inputArea: some View {
        HStack(spacing: 12) {
            TextField("Ask a question...", text: $inputText)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    sendMessage()
                }

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(inputText.isEmpty ? Color.secondary : Color.accentColor)
            .disabled(inputText.isEmpty || isLoading)
            .accessibilityLabel("Send message")
        }
        .padding(16)
    }

    // MARK: - Actions

    private func handleInitialQuestion() async {
        guard let question = coordinator.consumeInitialChatQuestion() else { return }

        isWaitingForDocument = true
        defer { isWaitingForDocument = false }

        if coordinator.document.content.isEmpty {
            let didLoad = await waitForDocumentContent(timeout: .seconds(3))
            guard didLoad else {
                let errorMessage = ChatMessage(
                    role: .assistant,
                    content: "Unable to load the document. Please try selecting it again from the sidebar."
                )
                messages.append(errorMessage)
                return
            }
        }

        let userMessage = ChatMessage(role: .user, content: question)
        messages.append(userMessage)
        await askAI(question)
    }

    private func waitForDocumentContent(timeout: Duration) async -> Bool {
        if !coordinator.document.content.isEmpty { return true }

        let document = coordinator.document
        let deadline = ContinuousClock.now + timeout

        while document.content.isEmpty {
            guard !Task.isCancelled else { return false }
            guard ContinuousClock.now < deadline else { return false }
            await withCheckedContinuation { continuation in
                withObservationTracking {
                    _ = document.content
                } onChange: {
                    continuation.resume()
                }
            }
        }
        return true
    }

    @MainActor
    private func sendMessage() {
        // Validate input
        switch ChatInputValidator.validate(inputText) {
        case .failure(.empty):
            return
        case .failure(.tooLong(let max)):
            let errorMessage = ChatMessage(
                role: .assistant,
                content: "Your question is too long. Please keep questions under \(max) characters."
            )
            messages.append(errorMessage)
            return
        case .success(let question):
            let userMessage = ChatMessage(role: .user, content: question)
            messages.append(userMessage)
            inputText = ""

            askTask?.cancel()
            askTask = Task {
                await askAI(question)
            }
        }
    }

    /// Configures the edit tool with the current file URL and an edit handler
    /// that writes back through the InteractionHandler path.
    private func configureEditTool() {
        chatService.configureEditTool(
            fileURL: coordinator.navigation.selectedFile
        ) { [weak coordinator] edit, url in
            guard let coordinator else { return "Error: coordinator unavailable" }
            // Read fresh from disk, apply edit, write back
            let data = try Data(contentsOf: url)
            guard var content = String(data: data, encoding: .utf8) else {
                return "Error: invalid encoding"
            }
            switch edit {
            case .replace(let range, let newText):
                content.replaceSubrange(range, with: newText)
            case .replaceMultiple(let replacements):
                let sorted = replacements.sorted { $0.range.lowerBound > $1.range.lowerBound }
                for (range, newText) in sorted {
                    content.replaceSubrange(range, with: newText)
                }
            }
            try content.write(to: url, atomically: true, encoding: .utf8)
            coordinator.updateDocumentContent(content)
            return content
        }
    }

    /// State-as-Bridge pattern:
    /// 1. Synchronous state mutation (isLoading = true) before await
    /// 2. Async boundary delegated to chatService.ask()
    /// 3. Synchronous state update (isLoading = false, messages.append) after await
    @MainActor
    private func askAI(_ question: String) async {
        isLoading = true
        defer {
            isLoading = false
        }

        let documentPath = coordinator.navigation.selectedFile?.path ?? ""

        let result = await chatService.ask(
            question: question,
            documentContent: coordinator.document.content,
            documentPath: documentPath,
            messages: messages
        )

        guard !Task.isCancelled else { return }

        switch result {
        case .success(let content):
            messages.append(ChatMessage(role: .assistant, content: content))

        case .error(let errorContent):
            messages.append(ChatMessage(role: .assistant, content: errorContent))

        case .cancelled:
            break
        }
    }
}

// MARK: - Message Bubble

@available(macOS 26, iOS 26, *)
struct MessageBubble: View {

    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }

            Text(message.content)
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    if message.role == .user {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.accentColor)
                    } else {
                        // Assistant bubbles use material — gets Liquid Glass on iOS 26
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.regularMaterial)
                    }
                }
                .foregroundStyle(message.role == .user ? .white : .primary)
                .textSelection(.enabled)

            if message.role == .assistant {
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(message.role == .user ? "You" : "Pixley"): \(message.content)")
    }
}
