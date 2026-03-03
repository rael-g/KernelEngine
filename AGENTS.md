# AGENTS.md

## Project overview

This project uses AI agents as active support in development. Agents must behave as responsible team members, respecting existing decisions, technical context, and scope boundaries.

The main focus is to produce correct, readable, predictable code aligned with the project’s defined architecture.

---

## Mandatory initial orientation

Before performing **any** action in the project, the agent **must**:

* Read the `README.md` entirely
* Read the `docs/Development/ProjectGuidelines.md` file to understand the specific engineering standards of this project.
* Read the documentation available in the `/docs` directory
* Explore the repository structure to understand code organization
* Identify existing conventions (naming, patterns, folder structure)
* Inspect existing code before proposing new abstractions or solutions

No implementation, refactor, or architectural suggestion should be made without first obtaining this high-level understanding of the project.

---

## Objectives and priorities

When making technical decisions, the priority order is:

1. Clarity
2. Simplicity
3. Correctness
4. Extensibility

Micro-optimizations, speculative generalization, and future-proofing without real use cases are **not** priorities.

---

## Agent scope of action

The agent may:

* Propose technical solutions
* Implement requested code
* Refactor code **only within the explicit task scope**
* Create automated tests
* Suggest design improvements
* Document technical decisions

The agent must not:

* Change public APIs without explicit request
* Refactor code outside the defined scope
* Introduce new dependencies, frameworks, or libraries
* Make global architectural decisions without validation
* Rewrite large portions of the system on its own initiative

---

## Fundamental rules

* Do not assume implicit behavior
* Do not invent requirements
* Do not "prepare the code for the future"
* Do not sacrifice readability for elegance
* Do not apply design patterns without real need

### Hardcoding

* Hardcoding solutions as a way to bypass implementation failure is **forbidden**
* Hardcoding is allowed **only temporarily** for debugging, experimentation, or problem isolation
* Hardcoded code must **never** be considered a final solution
* Any temporary hardcoding must be clearly identified and removed before delivery
* If a correct solution cannot be found, the agent must **admit failure** and ask for guidance instead of hardcoding

"Making it work" via hardcoding is **not** considered success.

### When the agent is blocked or fails

If the agent cannot complete the task correctly, it **must**:

* Stop repeated attempts without progress
* Explicitly state that it could not solve the problem
* Explain **why** the correct solution was not found
* List hypotheses that were evaluated and why they failed
* Identify which parts of the code or architecture caused the blockage
* Ask for clarification or guidance before proceeding

Entering retry loops or replacing a real solution with hardcoding is considered failure.

---

## Design principles and best practices

The following principles must be applied **pragmatically, never dogmatically**.

### SOLID

* **SRP**: classes must have a single, clear reason to change
* **OCP**: prefer extension over modification only when a real use case exists
* **LSP**: do not violate explicit or implicit contracts
* **ISP**: avoid bloated interfaces; prefer small, focused ones
* **DIP**: depend on abstractions only when multiple concrete implementations exist

Abstractions must not exist solely to "follow SOLID".

---

### YAGNI

* Do not implement functionality without proven current usage
* Do not create hooks, extension points, or configurability speculatively
* If there is no real call site, the feature does not exist

---

### KISS

* Prefer simple, direct solutions
* Avoid complex patterns when a straightforward function suffices
* Code should be understandable without extensive explanations

---

### DRY

* Avoid **conceptual** duplication, not just syntactic duplication
* Do not abstract code based solely on visual similarity
* Temporary duplication is acceptable until a clear pattern emerges

---

### Clean Code

* Explicit names are preferred over short ones
* Execution flow should be easy to follow
* Avoid hidden logic in constructors, setters, or operators
* Comments should explain *why*, not *what*

---

### Object Calisthenics

* Use as guidance to improve design
* Rules may be broken when they harm clarity
* Never apply rules mechanically

---

## Anti-patterns to avoid (STUPID)

* **Singleton abuse**: avoid global singletons and implicit shared state
* **Tight coupling**: do not create strong inter-module dependencies unnecessarily
* **Untestability**: code must be testable without excessive mocks or hacks
* **Premature optimization**: do not optimize before measuring
* **Indescriptive naming**: avoid generic names like Manager, Helper, Utils
* **Unjustified duplication**: duplication without intent or explanation

---

## Git usage rules

The agent may freely use **non-destructive, read-only Git commands** to inspect the repository state, such as:

* `git status`
* `git log`
* `git diff`
* `git show`
* `git branch`

### Destructive or state-changing Git commands

The agent must **never** execute destructive or state-changing Git commands without **explicit user confirmation**.

This includes, but is not limited to:

* `git add`
* `git commit`
* `git reset`
* `git checkout` (when it changes files or HEAD)
* `git rebase`
* `git merge`
* `git stash`
* `git clean`
* `git push`

For these commands, the agent must:

* **Only suggest**, never execute automatically
* Clearly explain what will change
* Wait for explicit user approval before proceeding

### Commits

All commits **must follow the Conventional Commits specification**.

#### Commit granularity

* **1 commit = 1 task**
* A commit must represent exactly **one completed task**
* A task is a single, well-defined unit of work (one feature, one fix, one refactor, one docs change, one test addition, etc.)
* Different tasks must **never** be mixed in the same commit

If multiple tasks were worked on before committing, they **must** be split into separate commits.

If a commit message requires more than one line to explain what was done, it is a strong signal that the commit can (and should) be split.

#### Commit messages

* Use a single Conventional Commit type per commit (e.g. `feat`, `fix`, `refactor`, `docs`, `test`, `chore`)
* The commit message subject must describe **one operation only**
* Avoid long descriptions, explanations, or justifications in the commit body
* If a long explanation feels necessary, the changes are likely too broad for a single commit

#### Staging rules

* The agent must **never** use `git add .`
* Files must be staged **explicitly and selectively**, based on the logical change being committed
* Each staged file must directly relate to the commit’s purpose

#### Agent behavior

Before suggesting a commit, the agent must:

* Group changes by logical intent
* Propose one commit per group
* Show which files belong to each commit
* Propose a Conventional Commit message for each one
* Wait for explicit user confirmation before staging or committing

---

## Coding standards

* Prioritize readability and predictability
* Avoid deep inheritance hierarchies
* Prefer composition over inheritance
* No meaningful logic should be hidden in constructors
* Avoid implicit or magical behavior

---

## Agent operating modes

The agent operates explicitly in **modes** to prevent unproductive loops, false solutions, or hardcoding.

### IMPLEMENTATION mode (default)

This is the default operating mode.

In IMPLEMENTATION mode, the agent must:

* Implement the requested solution
* Strictly follow the rules, principles, and constraints defined in this document
* Produce functional, readable, project-aligned code
* Stop immediately if it detects repeated attempts without real progress

The agent must **not** force a solution when clarity is insufficient.

---

### DIAGNOSTIC mode

DIAGNOSTIC mode is used when the correct implementation path is unclear or when the agent enters an "AI panic" state.

The agent may enter DIAGNOSTIC mode when:

* Explicitly instructed by the user
* Detecting multiple attempts without progress
* Considering hardcoding as an alternative
* Encountering unexpected or contradictory behavior

In DIAGNOSTIC mode, the agent must:

* **Not implement definitive code**
* Analyze the problem in isolation
* Explain what is failing and why
* List plausible technical hypotheses
* Identify suspicious areas in code or architecture
* Propose next steps or clear questions

The goal of DIAGNOSTIC mode is **understanding**, not delivery.

---

## Human-quality output (anti-AI artifacts)

All outputs produced by the agent **must look indistinguishable from work done by a professional software engineer**. The goal is not to "sound correct", but to **sound human, intentional, and experienced**.

### Forbidden AI artifacts

The agent MUST NOT leave behind:

* Commentary about the change itself (e.g. "now this does X", "this was updated to…")
* Obvious or redundant comments that restate what the code already expresses
* Explanatory comments added only because code was modified
* Documentation that references the past, the conversation, or previous problems
* Phrases like:

  * "now"
  * "previously"
  * "to avoid X from happening"
  * "as discussed"
  * "this change fixes"

Documentation and comments must describe **what the system is**, not how it got there.

### Commenting rules

* Comments must explain **why**, never **what**
* If the code is self-explanatory, **do not comment**
* Remove comments that became obsolete after refactors
* Fewer comments is better than unnecessary comments

### Documentation rules

* Documentation must be written as if the system always worked this way
* No historical notes unless explicitly required
* No narrative, no changelog-style text
* No leaked reasoning, discussions, or motivations from the agent

### Final human check (mandatory)

Before delivering any output, the agent MUST perform the following internal checks:

#### AI Smell Detection Checklist

If **any** answer is "yes", the output must be revised.

* Would another engineer immediately suspect this was written by an AI?
* Does the text explain *that* something was changed instead of *what it does*?
* Does it include conversational tone, narrative, or meta-commentary?
* Are there comments that could be removed without losing understanding?
* Does the documentation mention past behavior, bugs, or decisions?
* Does the wording feel verbose, apologetic, or over-explanatory?

#### "What would a software engineer do?" test

The agent should explicitly ask:

* What would a senior software engineer write here?
* What would they **not** write?
* What does an engineer expect to read at this location?
* Would this pass a serious code review without raising suspicion?

If the output would not survive a professional code review, it is not acceptable.

## Testing guidelines (mandatory)

Testing is a **first-class engineering activity**, not an optional follow-up. All changes must be evaluated in terms of their impact on existing tests and the need for new ones.

### General principles

* Tests exist to protect behavior, not implementation details
* Prefer fewer, meaningful tests over many fragile ones
* Tests must be deterministic, isolated, and repeatable
* A test that only verifies what the code already trivially guarantees is a bad test

### Unit tests

Unit tests MUST:

* Test a single unit of behavior
* Avoid external systems (filesystem, network, database, clock, random)
* Use mocks/fakes only where boundaries truly exist
* Be fast enough to run frequently

Unit tests MUST NOT:

* Reproduce the implementation logic step by step
* Assert on internal/private details unless unavoidable
* Depend on execution order or shared state

If a unit test is tightly coupled to the implementation, it is a refactoring hazard.

### Integration tests

Integration tests SHOULD:

* Validate interactions between real components
* Cover critical paths where unit tests are insufficient
* Prefer real dependencies over mocks when behavior matters

Integration tests MUST:

* Clearly state what is being integrated
* Be fewer and more intentional than unit tests
* Have explicit setup and teardown

### End-to-end / system tests

End-to-end tests SHOULD:

* Validate user-visible behavior
* Cover only the most critical flows

They MUST NOT:

* Replace unit or integration tests
* Be relied upon for diagnosing low-level failures

### When to write tests

The agent MUST consider tests when:

* Adding new behavior
* Fixing a bug (prefer a failing test first when feasible)
* Refactoring logic with non-trivial behavior

The agent MAY skip tests only if:

* The change is purely mechanical (renaming, formatting)
* Tests already fully cover the affected behavior

Skipping tests MUST be explicitly justified in the response.

### Test quality check

Before finalizing, the agent should ask:

* Would this test fail for the right reason?
* Would this test still be valuable after refactoring?
* Is this testing behavior or just code structure?

If the answer is unclear, the test likely needs improvement.

---

## Public API documentation (mandatory)

All **publicly visible APIs** MUST be documented. Public APIs are considered part of the project’s contract and must be understandable without reading the implementation.

This requirement applies regardless of whether the API is currently used internally or externally.

### General rules

* Every public type, method, function, property, and parameter MUST be documented
* Documentation must describe **intent and behavior**, not implementation details
* Documentation must be written for other engineers, not for the author
* If something is public but not meant to be used, it should likely not be public

Undocumented public APIs are considered a defect.

### C# documentation rules

For C# code:

* Use XML documentation comments (`///`)
* Every `public` and `protected` member MUST have XML documentation
* Documentation SHOULD include:

  * Summary of behavior
  * Meaning of parameters
  * Return value semantics
  * Relevant exceptions (when non-obvious)

The documentation must be suitable for tooling such as IntelliSense and generated API docs.

### C++ documentation rules

For C++ code:

* Use Doxygen-style comments
* Every `public` class, struct, function, and method MUST have at least a `@brief`
* Parameters and return values SHOULD be documented when not obvious

Example:

```
/// @brief Represents a physics body in the simulation.
```

Documentation must be compatible with automated Doxygen generation.

### What NOT to document

* Private/internal helpers (unless non-trivial)
* Obvious getters/setters with no semantic meaning
* Implementation details that may change

### Documentation quality check

Before finalizing, the agent must ask:

* Could another engineer use this API without reading the source?
* Does the documentation describe *what it does*, not *how it works*?
* Would this documentation still be valid after a refactor?

If the answer is "no", the documentation must be improved.
