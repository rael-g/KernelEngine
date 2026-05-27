# 19 — CLI & Agent Surface

> **Status**: 📋 Architectural decision. Not implemented. This chapter specifies the `ke` CLI grammar and the agent integration surface. Both are thin frontends over [18 - Editor Lib API](18%20-%20Editor%20Lib%20API.md).

## 1. The CLI is the reference frontend

`ke` is the most complete frontend in the project. Two reasons:

1. **AI agents drive it.** Until (or unless) a richer IPC surface ships, agents invoke `ke` via shell and parse its output. That makes the CLI the de-facto agent API.
2. **Engine maintainers dogfood it.** Anyone working on the engine itself should reach for `ke` before opening the future GUI editor. Forces the lib to stay complete.

Conversely: **anything that cannot be done via `ke` cannot be done via the GUI either**. The GUI is a graphical wrapper around CLI-equivalent operations; if a feature is missing from the CLI, it is missing from the lib, and the GUI can't show it.

## 2. Grammar

```
ke <verb> <noun> [target] [--flags]
```

### 2.1 Canonical verbs

Closed set; new verbs require a chapter update.

| Verb       | Meaning |
|---|---|
| `new`      | Create a new entity (project, scene, resource, …). |
| `add`      | Add a child entity to an existing one (node to scene, reference to project). |
| `remove`   | Inverse of `add`. |
| `set`      | Assign a value (property, setting, configuration). |
| `get`      | Read a value. |
| `list`     | Enumerate entities matching a filter. |
| `move`     | Reparent / relocate. |
| `import`   | Trigger asset import. |
| `inspect`  | Structured read of a complex entity (whole node, scene, project). |
| `build`    | Compile / produce output (shaders, bindings, ship build). |
| `run`      | Launch the project. |
| `undo`     | Revert last command (Editor Lib command stack). |
| `redo`     | Re-apply last undone command. |
| `config`   | Read/write project configuration (chapter 16). |
| `help`     | Self-describe (introspection — see §6). |

### 2.2 Examples

```bash
ke new project MyGame
ke new scene scenes/Level1.scene
ke add node MeshRenderer Cube --to scenes/Level1.scene --parent Root
ke set property scenes/Level1.scene Cube.MaterialHandle res://materials/red.material
ke list nodes --scene scenes/Level1.scene --type MeshRenderer
ke inspect scene scenes/Level1.scene
ke import assets/meshes/character.glb
ke build win-x64 --configuration Release
ke run --headless --frames 60 --trace run.jsonl
ke undo
ke config get runtime.window.fullscreen
ke config set runtime.window.fullscreen true
```

Verb first, noun second, target third, flags last. Reads like English; reads like other tools (`git`, `dotnet`, `cargo`).

### 2.3 Aliases

Short aliases for common operations: `ke ls` → `ke list`, `ke rm` → `ke remove`, `ke mv` → `ke move`. Listed in `--help`. Long form remains canonical in docs.

## 3. Output formats

Same command, different lens.

| Flag | Behaviour |
|---|---|
| *(default)* | Human-readable. ANSI colors when stdout is a TTY, plain when piped. |
| `--json`    | JSON on stdout (one object or array per command; no streaming framing). |
| `--jsonl`   | JSON Lines, one record per line — for `list`/`inspect`/long ops with progress. |
| `--quiet`   | Only errors on stderr; success is silent; exit code carries the result. |

Errors always go to stderr with the same structure (`EditorError` from chapter 18 §3). Exit codes: 0 success, 1 user-input error, 2 internal error, 130 cancelled (SIGINT).

Agents always pass `--json` or `--jsonl`. They never parse human output.

## 4. Completion

Generated from the command tree manifest (a TOML/JSON file checked into the repo, sourced from the same definitions the CLI uses for parsing).

```bash
ke completion bash    > /etc/bash_completion.d/ke
ke completion zsh     > ~/.zsh/completions/_ke
ke completion pwsh   >> $PROFILE
```

Includes verb completion, noun completion based on verb, and dynamic completion of paths (scene files exist on disk) and node names (parsed from the targeted scene). Dynamic completion calls `ke list --json` internally — no separate code path.

## 5. Pipes and composition

No invented composition language. Use the shell:

```bash
ke list nodes --json --scene Level1.scene | \
  jq -r '.[] | select(.type == "MeshRenderer") | .name' | \
  xargs -I {} ke set property Level1.scene {}.MaterialHandle res://materials/grey.toml
```

If an operation needs "do N edits atomically", that is a transaction in the Editor Lib (§6 of chapter 18) — exposed in the CLI as:

```bash
ke begin transaction "rename enemies" && \
  ke ... && ke ... && \
  ke commit transaction
```

Or simpler when no atomicity is needed: chain with `&&`.

## 6. Introspection — `ke help` and `ke describe`

Every command supports `--help`. Beyond that, `ke describe` exposes the capability database (chapter 20) as structured JSON for agents:

```bash
ke describe operations          # → JSON: every Editor Lib operation, args, return type
ke describe types               # → class_database.toml contents
ke describe plugins             # → plugin_database.toml contents
ke describe operation Scene.AddNode   # → single operation detail
```

An agent's first call against a fresh project is `ke describe operations --json` — it learns the full surface, no human-in-the-loop required.

## 7. No interactive mode

`ke` is one-shot. No REPL, no curses interface, no progress bar that hides the underlying state. Each invocation is a single operation; long ops emit progress as `--jsonl` events on stdout.

Rationale: REPLs are local-only and don't compose with agents or scripts. Anything that begs for interactivity is better as a small script over `ke` than as a new mode inside `ke`.

## 8. Configuration & state

`ke` is mostly stateless between invocations. The one piece of state it carries is the "current project" — the directory it was invoked from (containing a `Project`). Standard discovery: walk up parents until found, like `git`.

`ke --project /path/to/project ...` overrides the discovery.

Authentication, credentials, cloud state — none. If a remote build server or asset hosting service appears, it gets its own `ke remote` subverb and explicit config.

## 9. Agent surface

Three layers were considered. **Two are in scope; one is rejected.**

### 9.1 Layer (a) — CLI piping  ✅ **Primary surface**

Agent shells out to `ke`, passes `--json`, parses results. Works today (once `ke` exists). Zero engine-side IPC plumbing. Composes with shell tools the agent already knows.

For Claude Code specifically, this matches how the agent already interacts with `git`, `cargo`, `dotnet`. No new mental model. **This is the answer.**

Costs:
- Process spawn per command (~tens of ms on Windows, less on Linux). Acceptable for most workflows.
- No streaming of mid-operation events back to the agent (the operation completes, then the agent reads the output).
- No persistent state between calls beyond what `ke` writes to disk.

For 95% of agent workflows, these costs do not matter. The agent is editing files and running build/test commands — operations naturally complete before the next decision.

### 9.2 Layer (b) — MCP server  🟡 **Parking lot — only if cheap**

An optional `ke mcp-server` mode that exposes the editor lib as MCP tools, with a persistent process and bidirectional event streaming. Wins:

- Sub-millisecond per call (no spawn).
- Real-time event push (agent learns about a build failure mid-build, not after).
- Slightly cleaner per-tool documentation surface (MCP's native schema).

Costs that make it conditional:

- An entire IPC protocol surface to maintain (versioning, error semantics, transport bugs).
- Agent-side configuration to start the server.
- Duplicates the CLI's job for marginal performance benefit on most workflows.

**Implement only if it falls out trivially from how the editor lib is shaped** — e.g. if the Editor Lib already exposes operations as a typed dispatch interface, wrapping that in an MCP server is a few hundred lines. If it requires significant refactoring or a new layer, it is over-engineering. Park it as an idea, revisit when the CLI surface is mature and we are bored.

### 9.3 Layer (c) — Embedded library  ❌ **Rejected**

Linking `KernelEngine.Editor` directly into an agent's process (as a .NET assembly or via P/Invoke from Python) was considered for maximum throughput. Not pursued:

- Forces the agent runtime to host the engine's GC, dependencies, and version constraints. Fragile.
- Almost no real workflow needs the throughput that this would unlock over (a) or (b).
- Closes more doors than it opens (the agent becomes coupled to a specific build of the engine).

The bar to revisit this is "we measured CLI/MCP and they're the bottleneck for a workflow that matters". Not before.

## 10. Common to whatever agent surface is used

Regardless of (a) vs (b):

- Structured output (JSON / JSONL) is mandatory.
- Introspection works (`describe operations`, `describe types`, `describe schema`) so the agent can self-bootstrap.
- Operations are idempotent where possible (re-running `ke import x.glb` does the right thing even if x is already imported).
- Errors are typed (`EditorErrorKind`), never freeform text the agent has to grep.

These are properties of the editor lib (chapter 18); the surface just doesn't get in their way.

## 11. Cross-references

- The lib both frontends consume: [18 - Editor Lib API](18%20-%20Editor%20Lib%20API.md).
- The vision context: [14 - Editor, CLI & Agent Layer](14%20-%20Editor%2C%20CLI%20%26%20Agent%20Layer.md).
- What `ke describe` returns: [20 - Capability Database](20%20-%20Capability%20Database.md).
- Five layers of agent visibility into a running game (orthogonal to this surface, which is about *authoring*): [14 - Editor, CLI & Agent Layer §4](14%20-%20Editor%2C%20CLI%20%26%20Agent%20Layer.md).
