# Auto-selector Phase 2/3 — expanded research & brainstorm (2026-07-10)

Expansion of the Phase 1 opportunities report (task-gate-opportunities.md). New evidence
gathered 2026-07-10 afternoon: local pipe-tests, kimi/agy delegation-script mining
(code-level, exact line refs), Kimi CLI v0.23.4 introspection, and a 2025-26 web/community
sweep (routing, hooks ecosystem, salvage validation). Phase definitions from
docs/superpowers/specs/2026-07-10-task-gate-design.md.

## A. New verified evidence (this session)

1. **Substring false positives generalize across the gate table** (pipe-tested):
   - "add a prefix to the log lines" → [fix] (`*"fix"*` matches "prefix"/"suffix")
   - "open the preview of the page" → [review] (`*review*` matches "preview")
   - "rebuild the failover logic" → [fix] (`*fail*` matches "failover")
   The firing-#1 lesson (Hooks_project→[config]) is a class, not an instance. Phase 2 must
   move the WHOLE table to word-boundary matching, not patch archetypes one by one.
2. **Compaction blind spot**: after /compact the injected directive is gone from context,
   but the per-session state file still suppresses re-injection (dedup keys on archetype
   change only). Fix: clear/ignore the state file on SessionStart matcher=compact (the
   state-reinject hook already runs there).
3. **Coverage is unmeasurable**: non-matching prompts log nothing, so gate precision can be
   estimated from telemetry but recall cannot. Add an `event:"pass"` line (still ~0 cost,
   rotated at 2000) to make the soak evaluation two-sided.
4. **kimi_parallel.sh reliability gaps** (vs agy_parallel.sh, code-level):
   - **No per-agent timeout at all** — kimi hangs are a documented failure mode (termios,
     quota stalls); agy wraps `timeout $((secs+60))`. This is the single highest-value
     Phase 3 fix, independent of frontmatter.
   - No quota classification: agy tags FAILED(quota) vs FAILED(timeout) vs FAILED(exit) and
     prints the fallback hint; kimi_parallel reports a bare FAILED.
   - No brief lint, no duplicate-name check, no meta.txt provenance, no --verify contract
     check.
   - Shebang `#!/usr/bin/env bash` is broken on this host (/usr/bin/env absent) — works
     only when invoked as `bash kimi_parallel.sh`.
5. **Kimi CLI v0.23.4 facts** (installed version — SKILL.md documents 1.41.x; version drift):
   - `-m/--model` exists; config.toml defines exactly 2 aliases: `kimi-code/kimi-for-coding`
     and `kimi-code/kimi-for-coding-highspeed` (default). A real but binary "tier" choice.
   - **No per-call timeout flag**; config-only (`agent_task_timeout_s=900`,
     `print_wait_ceiling_s=3600`, `max_steps_per_turn=100`, `max_retries_per_step=3`).
     Frontmatter `timeout:` therefore must be enforced by the wrapper (`timeout` cmd) — same
     as agy.
   - `--output-format stream-json` exists: JSONL lines `{"role":"assistant","content":...}`
     + meta events. Machine-readable result extraction is feasible and beats log-scraping.
   - **No structured-output/schema enforcement** — the validate_output.py port is the only
     route to schema verdicts.
   - Local telemetry (~/.kimi-code/telemetry/*.jsonl) is session/event-level
     (system_metrics, mcp_failed) — NOT per-tool {tool_name,outcome,duration_ms} as the
     earlier 1.41.x source analysis suggested. Correction recorded.
   - Agent-reported (UNVERIFIED, conflicts with live experience): `--print` allegedly absent
     in 0.23.4 and `-p` allegedly breaks on multi-word prompts non-TTY. Live sessions have
     used `kimi --print -p "multi word"` successfully — verify with one cheap call before
     Phase 3 relies on either claim.

## B. Phase 2 brainstorm — classification & routing (task-gate v3)

### B1. Word-boundary matcher (proven requirement, evidence A1)
Replace per-archetype case-globs with ONE awk pass using regex word boundaries over the
lowered prompt; keep the same precedence order and first-match semantics. Single process
spawn (~10-20ms), fixes the entire substring class ("prefix", "preview", "failover",
future aliases), keeps EN+BG (awk regex handles Cyrillic classes as literal alternations).
Table becomes data (archetype|regex|directive rows in the script or a sourced .tsv),
making tuning diff-able and testable. Regression suite: extend the existing 8-case pipe
test with the 4 verified false positives as MUST-STAY-SILENT cases.
Growth path (web-validated, D1): keyword-first layered signals is the production
architecture of vLLM's Semantic Router ("start with keywords, add embeddings later");
if the table grows past ~50 rows, one `grep -Ff tagged-keywords.txt` pass (Aho-Corasick
inside GNU grep) keeps latency flat at any table size — full-path grep on this host.

### B2. New archetypes (candidates — gate on soak data before adding all)
- **test**: "write tests", "add coverage", "напиши тестове" → TDD directive
  (superpowers:test-driven-development; don't hack the mock — user's review rule).
- **commit/git**: "commit", "push", "PR", "merge" → git-workflow directive (no bot
  trailers, git fetch first, safety-net awareness). High frequency in this user's history.
- **bundle/sync**: "bundle", "copy to Documents", "sync state" → deterministic bundle
  procedure directive (targets: Hooks_project / Auto-selector; verify file counts after
  copy). User runs these constantly; currently silent. Needs word boundaries (evidence A1).
- **explain/question**: DELIBERATELY stays silent (assessment-only prompts need no process
  skill; injecting would be noise). Recorded as anti-archetype.
- **memory**: "remember", "запомни" → memory-file discipline directive (check-for-existing,
  MEMORY.md pointer). Low frequency but cheap.
Precedence proposal: delegate > fix > review > test > commit > config > deploy > research >
bundle > build > memory.

### B3. Effort/model hints (agy 7-tier idea, adapted to what a hook can actually do)
A UserPromptSubmit hook cannot change Claude's model/effort — additionalContext only. What
IS actionable in-directive:
- **Subagent tier hints**: research directive gains "use haiku/kimi-search for bulk
  legwork; reserve the session model for synthesis" (Agent tool has a model override).
- **Kimi tier hint** (Phase 3 tie-in): delegate directive gains "highspeed alias for
  mechanical edits, kimi-for-coding for reasoning-heavy briefs" — actionable via
  frontmatter `model:` once B/Phase 3 lands.
- **Signals worth encoding** (from router research, D2): prompt length, imperative-verb vs
  question-mark, code-fence/file-path presence, constraint count — all bash-measurable in
  the 60ms budget. NVIDIA's router taxonomy (task type + 6 complexity dimensions) is a
  ready checklist for which features matter. Cheap first guard: question-mark + no
  imperative verb → suppress gate (assessment mode, reduces noise).
- **Explicit-intent phrases beat inference** (GPT-5 router lesson, D2): "think hard",
  "quick check", "be thorough" are the highest-precision effort signals and are trivially
  case-glob-able — support them before any derived heuristics. Corollaries from the same
  discourse: always leave a manual override, and when in doubt route UP (the backlash was
  over aggressive cheap-defaulting).
- **Sticky tier per session** (OpenRouter pattern, D2): don't flip-flop hints mid-session;
  the existing per-session state file already gives us this for free.
- NOT doing: per-prompt model switching, scoring, or any LLM/embedding call (evidence
  unchanged from Phase 1; the ecosystem's LLM-scoring alternative exists — D3 — and costs
  a Haiku call per prompt).

### B4. Plugin-route hints
Archetype directives name concrete plugin skills where they exist today: review →
code-review; build → superpowers pipeline; config → update-config + plugin-dev:hook-development
for hook work specifically; deploy → verify + finishing-a-development-branch. Keep ONE
skill per directive (menus are ignored — Phase 1 evidence); secondary skill named only as
conditional ("for plugin hooks specifically, plugin-dev:hook-development").

### B5. Gate hygiene fixes (small, do with v3)
- Clear state on compact (evidence A2).
- `event:"pass"` telemetry for coverage (evidence A3).
- Log first 60 chars of prompt in gate events (false-positive auditing without transcript
  archaeology; privacy acceptable — local file, rotated).
- Re-injection TTL: optionally re-fire same-archetype directive after N gate-silent prompts
  (directive decays as context grows) — measure need from soak first.

## C. Phase 3 brainstorm — delegation upgrade (kimi-delegate v2)

### C1. The port (mapped line-by-line, agy → kimi)
1. Source agy_lib.sh as-is (fm_get, brief_body, lint_brief, duration_to_secs,
   sanitize_name are target-agnostic pure functions) — share the file, don't fork it:
   kimi_parallel.sh sources ~/agy-delegate/scripts/agy_lib.sh if present, else vendored copy.
2. Frontmatter keys: `model:` (maps to `-m`, validate against config.toml aliases),
   `timeout:` (wrapper `timeout` cmd — kimi has no flag), `schema:` (path, resolved
   relative to brief; injected into prompt tail exactly like agy line 236-239).
3. validate_output.py: port verbatim (it's CLI-agnostic — log file + schema in, partial
   JSON + exit code out). Same --schema-mode strict|salvage|warn flag and
   OK/PARTIAL(schema)/FAILED(schema) status mapping.
4. Quota classifier: agy's log_tail_matches_quota with kimi's proven marker set from
   subagent-kimi-guard.sh (insufficient_quota|quota exhausted|quota_exceeded|rate limit|
   rate_limit|termios|RPM limit|429) + FAILED(quota) status + the agy-delegate fallback
   hint. Closes the loop with the delegation policy (fall back to agy/native).
5. Reliability items from A4: timeout wrapper (even WITHOUT frontmatter — default 15m),
   dup-name check, meta.txt, fixed shebang (`#!/data/data/com.termux/files/usr/bin/bash`
   in the live copy; deploy-zip installer already patches shebangs per platform).

### C2. Beyond the port (new ideas)
- **`skills:` frontmatter key** (user's original Phase 3 wish): injects "You MUST use your
  <skill> skill for this task" into the brief body tail — kimi honors skill mandates in
  prompt (same mechanism as its superpowers enforcement). Comma-list, each expanded to one
  mandate line.
- **stream-json result extraction**: with `--json`, parse the last assistant message from
  the JSONL log (jq) instead of regex-scraping mixed text logs — feeds validate_output.py a
  clean payload; quota detection reads meta/error events instead of tail-grep. Fall back to
  text scraping when --json off.
- **Run summary JSONL** (`<results-dir>/summary.jsonl`: one line per agent — name, status,
  duration, branch, partial-json path). The orchestrator (Claude) reads ONE small file
  instead of N logs; mirrors what .partial.json does for payloads.
- **Unified front door** (`delegate.sh`): picks kimi vs agy from live quota state (recent
  FAILED(quota) markers, kimi-guard .done files <1h) and forwards briefs unchanged —
  frontmatter grammar is now shared, so briefs are engine-portable. Task-gate delegate
  directive then names one entry point. (Candidate — only if the manual choice actually
  costs anything in practice; keep YAGNI.)
- **--verify contract check** for kimi (mirror agy's 3-check: version, non-TTY echo, file
  edit) — burns quota, flag-gated; would have caught the 0.23.4-vs-1.41.x drift (A5).
- **One-shot repair re-ask** (TypeChat pattern, D4): when salvage returns PARTIAL, re-run
  the SAME brief once with the `_missing`/`_invalid` list appended ("your previous output
  lacked fields X,Y — emit the complete JSON object only"). Bounded (1 retry), uses the
  delegated agent's quota not Claude's, converts most PARTIALs to OK. Flag-gated
  (--repair) since it doubles worst-case cost.
- **Pure-jq salvage fallback** (D4): for the deploy-zip (hosts without python3), the
  salvage semantics reduce to ~15 lines of jq (strip fences → close unbalanced brackets →
  `_missing`/`_invalid` marking). Keep validate_output.py as primary (richer type checks);
  ship the jq variant only in the portability package.

### C3. Sequencing recommendation
Phase 3 does NOT need to wait on gate telemetry (the soak gates Phase 2 TABLE changes;
kimi-delegate reliability is independent and two items are latent defects — own-the-codebase
rule applies). Proposed order: C1.5 reliability fixes → C1 port (frontmatter+salvage) →
C2 stream-json + skills: → C2 summary/front-door only if usage shows need.

## D. Web/community findings (2025-26 sweep; raw agent data in research/web-routing-hooks-sweep.md)

### D1. Non-LLM prompt classification — keyword-first is production-grade
- vLLM Semantic Router (Nov 2025): layered independent signals — keyword (radix tree,
  10k+ rules, flat latency, traceable), embeddings, classifier — combined by boolean
  decision trees; official guidance "start with keywords, add embeddings later". Our
  keyword gate is the validated first layer, not a stopgap.
- semantic-router (Aurelio), RouteLLM (lm-sys): both need encoders/torch — not portable,
  but two designs port: "route = utterance list compiled offline into tables" (build-time
  smart, runtime dumb) and "scalar score + threshold" for tier decisions.
- Aho-Corasick via `grep -Ff` is the flat-latency upgrade path at any table size.
- Only realistic ML step-up on this hardware if ever needed: quantized fastText (single
  C++ binary, ARM-buildable, needs a few hundred labeled prompts — telemetry will
  eventually provide exactly that labeled corpus). Parked, not planned.

### D2. Effort/model routing — what the routers key on
- OpenRouter Auto (NotDiamond): complexity + task type + capability match; a 0-10
  cost/quality dial; sticky per-conversation pinning.
- GPT-5 router: conversation type, complexity, tool needs, explicit intent phrases;
  backlash forced manual overrides — design lesson: transparency + override + route-up
  bias.
- Anthropic's own effort docs: low = classification/lookup/high-volume, high = complex
  reasoning/difficult coding — directives can cite these criteria verbatim.
- arXiv "When to Reason" (2025): coarse category→reasoning-mode toggling retains accuracy
  with large token savings — direct evidence the archetype→effort-hint mapping is sound.

### D3. Claude Code hooks ecosystem — where we stand
- Official contract confirmed: UserPromptSubmit stdout/additionalContext is injected
  prompt-adjacent as a system-reminder — the mechanical reason single directives work.
- diet103/claude-code-infrastructure-showcase (closest relative): skill-rules.json with
  keyword+regex promptTriggers injecting tiered "SKILL ACTIVATION CHECK" menus; claims
  "100% skill loading", ships NO quantitative data. It's the ranked-menu shape our
  transcript evidence says gets ignored.
- disler/claude-code-hooks-mastery: canonical inject/block mechanics reference.
- jefflester/claude-skills-supercharged: per-prompt Haiku scoring — the LLM-call
  alternative; exists because bare keywords were "too coarse", costs latency+tokens per
  prompt. Our answer to coarseness is word boundaries + telemetry, not an LLM call.
- SuperClaude "auto-activating personas": prose instructions, model-side, no hook.
- **Notable: no published quantitative evidence anywhere that injected directives change
  behavior. Our gates-vs-invokes telemetry (plus the 229-injection router post-mortem) is
  the only measurement we found — worth writing up once the soak completes.**

### D4. Salvage validation — convergent patterns
- BAML schema-aligned parsing (<10ms Rust), instructor/Pydantic partial mode, promplate
  partial-json-parser (bracket-stack closing), json_repair: all converge on
  extract-mark-continue instead of validate-or-die — agy's _missing/_invalid design is
  the same family; port with confidence.
- TypeChat's contribution: feed validator diagnostics back for ONE bounded retry (→ C2
  repair re-ask).

### D5. Other harnesses — mechanisms worth tracking
- Gemini CLI hooks: BeforeModel (mutate request) and BeforeToolSelection (per-turn tool
  filtering) — events Claude Code lacks. Nearest approximation here: task-gate already
  writes archetype state; a PreToolUse hook could read it for archetype-conditional
  warnings (e.g. Edit during [research] archetype → "assessment-only reminder"). Candidate
  only — deny-gating tools by archetype is too aggressive (false-positive cost is a
  blocked edit).
- Codex CLI hooks (v0.117+): near-identical event set — task-gate ports ~1:1 if ever
  needed.
- Kimi CLI hooks (beta, TOML): kimi-delegate agents could carry a gate of their own;
  "AgentHooks" cross-tool spec worth tracking for write-once hooks.
- Cursor .mdc / Windsurf rules: deterministic glob auto-attach + priority ordering +
  per-scope size budgets — the budget discipline (cap directive length, explicit
  precedence) is already ours; glob-attach by file-path context is a possible future
  signal source (PostToolUse file-type tracker).
- opencode: cannot yet read prompt text in plugins (open issues) — confirms
  UserPromptSubmit is the most capable prompt-conditioned injection point surveyed.

## E. What still NOT to build (unchanged + new)

- Per-prompt LLM classification (incl. the ecosystem's Haiku-scoring variant, D3),
  embedding index, ranked menus (Phase 1 evidence stands; D3 shows the menu-shaped
  competitor ships without data).
- Dynamic skillListing/skillOverrides per archetype — settings are static per session.
- Archetype-conditional tool DENY gating (Gemini BeforeToolSelection imitation, D5) —
  a false positive would block a legitimate edit; warnings maybe, denies no.
- Kimi-side schema enforcement — CLI has none (A5); wrapper validation is the only route.
- 2→7 tier model routing for kimi — only 2 aliases exist (A5); a binary hint is honest.
- fastText classifier — parked until telemetry both proves keyword ceiling AND provides
  the labeled corpus (D1).

## F. Recommended sequencing

1. **Now (defect-driven, not telemetry-gated)**: kimi_parallel.sh reliability fixes —
   timeout wrapper, quota classification, shebang, dup-name check (C1.5). These are latent
   defects under the own-the-codebase rule; two failure modes (hang, silent quota death)
   are already documented on this host.
2. **Now (defect-driven)**: task-gate word-boundary migration + compact-state clear +
   `event:"pass"` coverage logging (B1, B5) — three verified defects/blind spots, same
   evidence bar as the firing-#1 fix. NOT the new archetypes yet.
3. **After soak (~1 week, per design doc)**: evaluation query → tune/remove archetypes;
   only then add B2 archetypes + B3 effort hints + B4 plugin routes, informed by
   gates-vs-invokes data.
4. **With Phase 3 port (C1)**: frontmatter + salvage + skills: key; stream-json extraction
   and repair re-ask as flag-gated extras (C2).
5. **Write-up**: after soak, the gates-vs-invokes measurement is (per D3) the only
   quantitative evidence of directive-following in the ecosystem — bundle it as a short
   findings note.
