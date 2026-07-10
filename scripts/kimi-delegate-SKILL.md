---
name: kimi-delegate
description: Use when the user wants coding/implementation work delegated to Kimi Code CLI agents instead of implemented directly — when they say "delegate", "delegate this", "delegate to kimi", "hand this off", "let kimi do it", "пусни на kimi", "делегирай", "give this to the agents", or ask to fan a larger build out across several parallel local agents to save Claude tokens/cost.
---

# Kimi Delegate

Turn Claude (Opus) into a **manager** of Kimi Code CLI agents. Claude does the expensive
thinking — understanding the goal, decomposing it into clean independent units, writing
precise briefs, and reviewing results. Kimi does the cheap, high-volume implementation
work in the terminal. This saves tokens/cost on Claude's side and lets several agents run
at once.

The core mental model: **you are a tech lead handing well-scoped tickets to contractors.**
A contractor who gets a vague ticket produces vague work. The quality of the delegation
is almost entirely determined by the quality of the brief you write.

## When this triggers

The keyword is **`delegate`** (and the natural-language variants in the description). When
the user says it, don't start coding yourself — switch into manager mode and follow the
workflow below.

## Prerequisites (check once, quickly)

Kimi Code CLI must be installed and logged in on the user's machine. A fast way to confirm:

```bash
kimi --version    # should print a version; if "command not found", Kimi isn't installed
```

If it's missing or not authenticated:
- Install: the official one-line installer from https://github.com/MoonshotAI/kimi-code
  (`curl ... | bash` on macOS/Linux), or via npm if Node ≥ 22.19 is present.
- Authenticate (device-code flow, no TUI): `kimi login`

Don't re-run these every invocation — only when `kimi --version` or a run actually fails.

## How Kimi is invoked (the contract you depend on)

Kimi runs **non-interactively** with `--print -p`. This is the whole basis of delegation:

```bash
kimi --print -p "FULL TASK BRIEF HERE"
```

**`--print` is required** (verified on kimi 1.41.0): `-p` alone only supplies the prompt
text and still launches the interactive shell UI, whose keyboard listener crashes with
`termios.error: (25, 'Inappropriate ioctl for device')` and hangs the agent when run
without a TTY (background jobs, CI, agent harnesses).

Key facts about `--print` mode (these shape how you delegate):
- It streams the assistant's output to **stdout**; thinking/tool-progress goes to **stderr**.
- It runs under **`auto` permission** — Kimi will edit files and run shell commands
  without asking (print mode auto-dismisses and auto-approves). Static deny rules still
  apply. So **only point it at trusted repos**, and prefer git isolation (below) so
  nothing is unrecoverable.
- The **current working directory is the project** Kimi operates on. `cd` into the repo
  (or use a worktree) before launching.
- Pick the model for a run with `-m`, e.g. `-m kimi-code/kimi-for-coding`.
- For machine-readable output (one JSON object per line) add `--output-format stream-json`
  (only valid together with `--print`). For human-readable logs, leave the default (`text`).
- `--quiet` is an alias for `--print --output-format text` printing only the final message.

Quick reference:

```bash
kimi --print -p "Implement X..."                                  # one task, text output
kimi --print -m kimi-code/kimi-for-coding -p "Implement X..."     # choose model
kimi --print -p "Implement X..." --output-format stream-json      # parseable output
kimi --print --continue -p "Now also do Y..."                     # follow-up in same session
```

## The delegation workflow

### 1. Understand and scope (Claude's job — do this well)

Before writing any brief, make sure you actually understand the request. Read the relevant
parts of the codebase yourself if needed (you're the one with the good judgment about
architecture). Clarify with the user only what genuinely blocks good decomposition —
otherwise proceed with sensible defaults and state them.

### 2. Decompose into independent units

Split the work into subtasks that can run **in parallel without stepping on each other**.
The golden rule: **each agent should own a disjoint set of files / modules.** Overlapping
edits are the main cause of merge pain. Good seams to split on:
- by layer (API handler vs. DB migration vs. frontend component)
- by feature/module (auth vs. billing vs. notifications)
- by file (one agent per file or per directory)

If the work is inherently sequential (B depends on A's output), don't fake parallelism —
run them in sequence, or have one agent do the dependent chain.

How many agents: default to **2–4**. More than that and review/integration overhead usually
outweighs the savings. The user asked for "up to a few" — honor that.

### 3. Write a detailed brief per agent

This is where the value is. Each brief is **self-contained** — Kimi does not see this
conversation. A strong brief includes:

- **Goal**: one sentence on what success looks like.
- **Context**: what the project is, the relevant files/paths, how things currently work.
- **Exact scope**: which files this agent may create/modify — and explicitly which it must
  **not** touch (so parallel agents stay disjoint).
- **Requirements**: concrete, testable specifics (function signatures, endpoints, schema,
  edge cases, error handling).
- **Conventions**: language/version, style, libraries to use or avoid, patterns in the repo.
- **Verification**: how Kimi should check its own work (run `npm test`, `pytest`, a build,
  a specific command) before finishing.
- **Done criteria**: what to leave the repo in (committed? tests passing? a summary?).

Write each brief to its own file in a temp dir, e.g. `/tmp/kimi-briefs/<name>.md`. Files are
cleaner than shell-escaping long prompts.

**Optional per-brief frontmatter** (YAML block at the top; each key overrides the launcher
flags for that brief only):

```markdown
---
model: kimi-code/kimi-for-coding-highspeed   # tier: -highspeed for mechanical work,
                                             # kimi-for-coding for reasoning-heavy
timeout: 20m                                 # Ns/Nm/Nh wall-clock kill for this agent
schema: result.schema.json                   # validate the agent's final JSON message
skills: skill-a, skill-b                     # injected as MUST-use skill mandates
---
## Goal
...
```

- `schema:` (relative paths resolve from the brief's directory) makes the launcher append a
  "final message must be exactly one JSON object matching this schema" instruction, then
  validate the log with salvage semantics: valid → `OK`; some fields missing/wrong-typed →
  `PARTIAL(schema)` with the salvageable payload plus `_missing`/`_invalid` arrays written
  to `<results-dir>/<name>.partial.json`; nothing usable → `FAILED(schema)`. Pick the
  policy with `--schema-mode strict|salvage|warn` (default `salvage`).
- Pass `--lint` to require the `## Goal` / `## Scope` / `## Requirements` /
  `## Verification` sections in every brief (recommended once briefs follow the structure
  above; off by default for backward compatibility with free-form briefs).

### 4. Launch the agents

Use the bundled helper, which handles git-worktree isolation, parallel launch, logging, and
a summary. From the skill's `scripts/` directory:

```bash
bash scripts/kimi_parallel.sh --repo /path/to/repo /tmp/kimi-briefs/*.md
```

What it does: for each brief it creates a dedicated git worktree on a new branch
(`kimi/<brief-name>`), runs `kimi --print -p "<brief body>"` inside it in the background
(wrapped in `timeout` — kimi has no native per-call timeout flag, and hangs are a known
failure mode), tees output to `<results-dir>/<name>.log`, waits for all to finish, and
prints per-agent status: `OK`, `PARTIAL(schema)`, or `FAILED(timeout|quota|exit|schema|...)`.
Quota/auth failures print a fallback hint (agy-delegate / native subagents, per the
delegation policy). Run `bash scripts/kimi_parallel.sh --help` for all flags
(`--model`, `--timeout`, `--schema-mode`, `--lint`, `--no-worktree`, `--json`,
`--results-dir`, `--max-parallel`).

**Why worktrees:** they give each agent its own checkout on its own branch, so parallel
agents can't corrupt each other's working tree, and you review/merge each branch
independently. If the repo isn't a git repo, or the user wants everything in place, pass
`--no-worktree` (only safe when scopes are truly disjoint).

If you'd rather not use the script (e.g. a single agent, or a non-repo folder), launch
directly:

```bash
cd /path/to/repo && kimi --print -p "$(cat /tmp/kimi-briefs/task-a.md)" 2>&1 | tee /tmp/kimi-a.log
```

### 5. Review and integrate (Claude's job again)

When agents finish, **you** are the quality gate — don't blindly trust the output:
- Read each agent's log and the resulting diff (`git -C <worktree> diff main` or
  `git log -p`).
- Check the requirements were actually met and conventions followed.
- Run the test/build yourself to confirm.
- Merge the branches (`git merge kimi/<name>`), resolving any conflicts. If two agents did
  touch the same file, this is where you reconcile.
- Summarize for the user: what each agent did, what passed, what needs attention.

If an agent went off-track, you can re-delegate with a tightened brief, or fix small things
directly — whichever is cheaper.

## Tips that make delegation work

- **Briefs over chat.** Kimi only knows what's in the brief. Over-specify rather than under.
- **Disjoint scopes** are the difference between clean parallelism and merge hell.
- **Ask Kimi to verify itself** in every brief (run tests/build) — it dramatically raises
  the hit rate and saves you a round trip.
- **Start small.** For a first run, delegate one well-scoped task, confirm the loop works
  end-to-end, then fan out.
- **Keep Claude for judgment.** Architecture, decomposition, review, conflict resolution —
  that's where Claude's tokens are worth spending. Implementation volume goes to Kimi.

## Example

User: "delegate building the REST endpoints and the matching DB migration for the comments feature"

Manager (Claude) decomposes into two disjoint agents:
- `agent-a` → `migrations/` only: add a `comments` table migration.
- `agent-b` → `api/comments/` only: CRUD endpoints, assuming the table from the migration.

Writes `/tmp/kimi-briefs/migration.md` and `/tmp/kimi-briefs/endpoints.md`, each fully
self-contained, each stating exactly which directory it owns and not to touch the other.
Launches: `bash scripts/kimi_parallel.sh --repo ~/proj /tmp/kimi-briefs/*.md`. On completion,
reviews both branches, runs the test suite, merges, and reports back.
