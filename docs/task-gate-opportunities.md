# Auto-activation block — opportunities report (2026-07-10)

Request: opportunities for a block that automates prompt/task analysis, evaluation, and
selection of the correct skills and plugins — "similar to kimi and agy".

## How the two references actually do it (code-level findings)

| Aspect | Kimi CLI | agy (Antigravity 1.1.1) |
| --- | --- | --- |
| Task analysis | None pre-LLM — fully LLM-driven | Pre-classifies prompt → mode (plan vs accept-edits) BEFORE tool exposure |
| Registry | System-prompt-as-registry (~50-60KB: all skill descriptions + skillInstructions) | Binds all tools post-mode-select; MCP lazy-loaded via schema files |
| Selection | LLM decides; "tool-select" experimental = LLM-side per-substep refinement (turSteps 0.1-0.8) | LLM function-calling; model-tier router (7 tiers); no tool filtering |
| Enforcement | Superpowers "using-superpowers" meta-skill: "1% chance → MUST invoke" + red-flags table | System-prompt templates per mode |
| Evaluation | Telemetry JSONL: {tool_name, outcome, duration_ms}; retry budget 3/step | Salvage-mode schema validation (_missing/_invalid → PARTIAL not FAILED); quota-detect regex |
| Overrides | config.toml flags | YAML frontmatter per brief (model:, timeout:, schema:) |

Decisive finding: **neither uses keyword matching or embeddings.** Kimi's "good prestart
selector" = native skill listing + the superpowers enforcement skill + the LLM. Claude Code
already ships 2 of those 3 natively (skill listing in system prompt; superpowers SessionStart
enforcement) — both live on this machine.

## Local evidence constraint (must-respect)

The 2026-07-06 skill-router (deterministic keyword shortlist, 250-675ms/prompt): 229
injections → ~3 Skill invocations; router-less days showed no behavior difference.
=> Injecting *suggestion lists* does not change model behavior. Any new block must inject a
*directive* (one mandated process skill / route), not a ranked menu — and must cost ~0 latency.

## Opportunities (ranked)

1. **Task-Gate hook** (agy's mode-gating, adapted) — UserPromptSubmit command hook,
   deterministic archetype table (~8 rows: build/fix/research/config/delegate/review/deploy/
   question), case-match on strong verbs/objects incl. Bulgarian aliases, <30ms, injects ONE
   directive line: mandated process skill + delegation route (kimi-search/agy-delegate/native)
   + effort hint. Differs from dead router: archetype→single-directive (superpowers-style,
   which the model demonstrably obeys), not scored menus. Transparent, tunable table.
2. **Selection telemetry** (Kimi's evaluation loop) — PostToolUse hook on Skill/Agent tools
   logging {skill, archetype-at-time, session} + SessionEnd rollup. Produces the
   suggested-vs-invoked evidence to tune or kill the Task-Gate empirically. Near-zero cost.
   This is the "evaluation" pillar the user asked for, done deterministically.
3. **Delegation frontmatter** (agy) — extend kimi-delegate briefs with model:/skills:/
   timeout:/schema: frontmatter parsed by kimi_parallel.sh; mirrors agy_parallel.sh.
4. **Salvage-mode verdicts** (agy) — structured PARTIAL results (_missing/_invalid) in
   delegation validators instead of binary pass/fail; agy-delegate already has it, port to
   kimi-delegate.
5. **Plugin activation hygiene** (native) — skillOverrides + skillListing budget tuning per
   archetype is NOT possible dynamically (settings are static); instead keep the catalog lean
   (done in modernisation) and let the enforcement skill do the work. Anti-opportunity noted
   to prevent scope creep.

## What NOT to build (evidence-based)

- Per-prompt keyword *ranking* router — already failed here.
- Per-prompt LLM classification call — +2s TTFT × every prompt on this device (Kimi's TTFT
  is ~2.1s; agy hides its classifier inside the main model call, effectively free — a hook
  cannot).
- Embedding index — maintenance cost, no evidence of need at 30-50 skills.

## Recommended shape of "the block"

Phase 1: Task-Gate hook + telemetry hook (both deterministic, ~30ms total, 2 scripts + 2
settings entries). Phase 2 (only if telemetry proves the gate's directives are followed):
extend table, add plugin-route hints, consider agy-style effort/model hints. Phase 3 (only
if quota telemetry demands): delegation frontmatter + salvage verdicts in kimi-delegate.

Full source analyses: research/kimi-code-pipeline.md notes in the session transcript,
agy report in tasks/a394befefa787c11f.output; Kimi selector config-level analysis and this
file bundled in Hooks_project/research/.
