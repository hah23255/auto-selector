---
name: project-auto-selector
description: Task-gate + skill-telemetry hooks (Phase 1 live 2026-07-10) — automated task-archetype directives with evaluation loop; Phases 2/3 contingent on telemetry
metadata: 
  node_type: memory
  type: project
  originSessionId: e5d2d7bd-b62a-4ccb-b809-dcd604a81137
---

Auto-selector Phase 1 live since 2026-07-10 (project folder:
/storage/emulated/0/Documents/Auto-selector; spec: docs/superpowers/specs/2026-07-10-task-gate-design.md).

- task-gate.sh (UserPromptSubmit, 63ms): 7 deterministic archetypes (delegate>fix>review>
  config>deploy>research>build, EN+BG aliases) → ONE injected directive (process skill +
  delegation route); dedup per session via cache/task-gate-<sid>.state; silent fallback.
  v2 patterns since 2026-07-10 (same day): firing #1 exposed a substring false positive
  ("Hooks_project" matched *hook* → [config]); config archetype now uses space-bounded
  patterns. Lesson for future archetypes: case-glob substrings need word boundaries.
- skill-telemetry.sh (PostToolUse Skill|Agent, async): logs gate directives + actual
  invocations with archetype correlation to cache/skill-telemetry.jsonl (rotated at 2000).
- Design principle (evidence): single directives are followed, ranked menus are not
  (dead skill-router: 229 injections → ~3 invocations). NO per-prompt LLM calls (2s TTFT).

**Why:** user wanted Kimi/agy-style automated prompt/task analysis + skill/plugin selection;
code-level analyses showed Kimi = load-all + enforcement skill + LLM (no keyword matching),
agy = pre-LLM mode-gating — the gate borrows agy's pattern.

**How to apply:** after ~1 week soak, run the jq evaluation query in the design doc
(gates vs invokes per archetype); tune/remove archetypes that are ignored — same evidence
bar that killed the old router. Phase 2 (table expansion, effort hints) and Phase 3
(kimi-delegate frontmatter + salvage PARTIAL verdicts) only if telemetry supports.

Phase 2/3 expanded research 2026-07-10 (report: Auto-selector/phase23-research-brainstorm.md,
raw sweep in research/): 3 MORE verified gate false positives (prefix/suffix→fix,
preview→review, failover→fix) ⇒ whole table needs word-boundary matching; gate dedup has a
post-compact blind spot (state file suppresses re-inject after context wipe); kimi CLI is
v0.23.4 NOT the 1.41.x SKILL.md documents (no per-call timeout flag — config-only; no schema
enforcement; 2 model aliases only; telemetry session-level not per-tool). Ecosystem note: no
published quantitative evidence of directive-following anywhere — our gates-vs-invokes soak
is novel measurement.

Defect-driven fixes SHIPPED 2026-07-10 PM (TDD red→green; backups in
~/.claude/backups/phase2-defect-fixes-20260710/): task-gate v3→v4 (word-boundary matching;
event:"pass" coverage telemetry), state-reinject clears gate state post-compact,
kimi_parallel.sh reliability (host shebang, --timeout + `timeout -k 10` wrapper — kimi's ONLY
hang protection, FAILED(timeout|quota|exit) classification + fallback hint, dup-name guard).
A 57-agent adversarial workflow then confirmed 19 more defects (0 refuted), all fixed
same-day as v4: octal 09m trap (10# fix), 0-timeout=no-limit reject, dup-check %.* crossing
'/', rc-137 grace-kill=timeout, bare-429 quota false positive, relative-brief empty-prompt;
gate: BG morphology via left-anchored Cyrillic stems (*" грешк"* — suffixing language, safe
open suffix; English needs explicit inflections), char-based ${prompt:0:400} truncation
(printf %.Ns is BYTE-based), awk locale tolower folds Cyrillic (tr can't), Unicode
punctuation incl. typographic apostrophe. Suites: 52+20 checks green, latency 122ms.
Bash lessons: ${var%.*} glob crosses '/'; force 10# on user-supplied arithmetic.
Phase 2+3 SHIPPED 2026-07-10 evening (user-ordered): task-gate v5 (11 archetypes — added
test/commit/bundle/memory with precedence guards; explicit-intent effort overlay EN+BG;
kimi/haiku tier hints; 60-char normalized snippet in gate telemetry) and kimi-delegate v3
(per-brief frontmatter model:/timeout:/schema:/skills:, salvage PARTIAL verdicts via
vendored validate_output.py, --schema-mode strict|salvage|warn, --lint opt-in,
prelaunch-failure accounting; NO unbounded kimi calls ever — an unwrapped version probe
hung the suite). v6 same night after adversarial review (spend limit killed 45/66 agents
mid-workflow): precedence memory>commit + bundle>config, bounded think-hard,
[[:cntrl:]]-safe telemetry, copy-alias dropped, archetype+effort dedup (.eff state file),
CRLF-safe brief_lib, --json+schema and no-python3 rejected upfront. Suites 73/73 + 37/37.
Private repo github.com/hah23255/auto-selector: main = 6a0b2d2, all commits authored
hah23255 <hah23255@users.noreply.github.com> (GH007 blocks the real email — always use
the noreply identity for this account). The delegated agy agent's bot-authored commit
was replaced via user-run force-with-lease 2026-07-10; conduct lessons in
[[project-agy-delegate]].
Related: [[project-hook-modernisation]], [[reference-kimi-delegate]], [[project-agy-delegate]].
