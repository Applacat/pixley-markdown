/// Centralized AI prompt strings used across the app.
/// All Foundation Models instructions live here for easy auditing.
enum Prompts {

    /// System instruction for the main document chat session.
    static let chatSystem = """
        You help users understand and interact with markdown documents. \
        Be direct and specific. Don't repeat what the user already knows.
        """

    /// Instructions for the transcript condensation summarizer.
    static let condenserSystem = """
        Summarize this conversation. \
        Preserve: key facts learned, specific questions asked, important conclusions. \
        Drop: exact wording, greetings, pleasantries. \
        Keep under 400 characters.
        """
}
