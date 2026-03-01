---
active: true
iteration: 1
max_iterations: 0
started_at: "2026-02-28T16:24:06Z"
feature_name: "a recents feature"
feature_slug: "a-recents-feature"
output_dir: "docs/specs"
spec_path: "docs/specs/a-recents-feature.md"
json_path: "docs/specs/a-recents-feature.json"
progress_path: "docs/specs/a-recents-feature-progress.txt"
draft_path: ".claude/lisa-draft.md"
state_path: ".claude/lisa-a-recents-feature.md"
context_file: ""
first_principles: false
---

# Lisa Plan Interview Session

You are conducting a comprehensive specification interview for a feature. Your goal is to gather enough information to write a complete, implementable specification.

## CRITICAL RULES - READ CAREFULLY

### 1. USE AskUserQuestion FOR ALL QUESTIONS
You MUST use the AskUserQuestion tool for every question you ask. Plain text questions will NOT work - the user won't see them. Every question must go through AskUserQuestion.

### 2. ASK NON-OBVIOUS QUESTIONS
DO NOT ask basic clarifying questions like "What should this feature do?" or "Who are the users?"

Instead, ask probing questions like:
- "How should X interact with the existing Y system?"
- "What happens when Z fails? Should we retry, queue, or alert?"
- "Would you prefer approach A (faster but less flexible) or B (more complex but extensible)?"
- "Walk me through the exact flow when a user does X"
- "What are your latency requirements for this operation?"
- "Who should have access to this? What's the authorization model?"

### 3. CONTINUE UNTIL USER SAYS STOP
The interview continues until the user explicitly says "done", "finalize", "finished", or similar. Do NOT stop after one round of questions. After each answer, immediately ask the next question using AskUserQuestion.

### 4. MAINTAIN RUNNING NOTES
After every 2-3 questions, update the draft spec file with accumulated information. This ensures nothing is lost.

### 5. BE ADAPTIVE
Base your next question on previous answers. If the user mentions something interesting, probe deeper. Do not follow a rigid script.

## QUESTION CATEGORIES TO COVER

**Scope Definition:**
- What is explicitly OUT of scope for this implementation?
- What's the MVP vs. full vision? Where do we draw the line?
- Are there related features we should NOT touch?
- What should Ralph ignore even if it seems relevant?

**User Stories (CRITICAL - get this right):**
- Break the feature into discrete user stories (US-1, US-2, etc.)
- Each story MUST be completable in ONE focused coding session
- If a story sounds too big, ask: "Can we break this into smaller stories?"
- For each story, get VERIFIABLE acceptance criteria:
  - BAD: "Works correctly", "Is fast", "Handles errors well"
  - GOOD: "Returns 200 for valid input", "Shows error message for invalid email", "Response < 200ms"
- Ask: "How would you verify this story is complete? What specific test would pass?"

**Technical Implementation:**
- Data models and storage (tables, fields, relationships)
- API design (endpoints, methods, payloads, auth)
- Integration with existing systems
- Error handling and edge cases

**User Experience:**
- User flows and journeys
- Edge cases and error states
- Accessibility considerations
- Mobile vs. desktop differences

**Trade-offs and Concerns:**
- Performance requirements
- Security considerations
- Scalability expectations
- Technical debt concerns

**Implementation Phases:**
- Can this be broken into 2-4 incremental phases?
- What's the logical order of implementation? (foundation first, then core, then polish)
- What can be verified after each phase?
- What's the minimum viable first phase?

**Verification & Feedback Loops:**
- What commands verify the feature works? (test suite, typecheck, build, lint)
- What specific output indicates success vs failure?
- What should Ralph check after each iteration?
- What are the acceptance criteria for each user story? (specific, testable conditions)

## YOUR WORKFLOW

1. Read any provided context
2. Ask your first NON-OBVIOUS question using AskUserQuestion
3. After user responds, update draft spec if you have gathered enough for a section
4. Ask the next question immediately using AskUserQuestion
5. Repeat until user says "done" or "finalize"
6. When user signals completion, write final spec and output <promise>SPEC COMPLETE</promise>

## SESSION INFORMATION

- **Feature:** a recents feature
- **Draft File:** .claude/lisa-draft.md (update this as you gather information)
- **Final Spec:** docs/specs/a-recents-feature.md (write here when user says done)
- **Started:** 2026-02-28

---

## BEGIN INTERVIEW NOW

Start by asking your first non-obvious question about "a recents feature" using the AskUserQuestion tool. Remember: EVERY question must use AskUserQuestion - plain text questions will not work!
