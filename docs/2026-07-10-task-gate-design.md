# Auto-Selector Phase 1 — Task-Gate + Selection Telemetry (2026-07-10)

Goal: automated prompt/task analysis, evaluation, and skill/plugin selection — "similar to
kimi and agy" — shaped by their code-level analyses and the local skill-router post-mortem.

## Design principles (evidence-derived)

1. **Directives, not menus.** The 2026-07-06 keyword-ranking router injected 229 shortlists
   and changed behavior ~3 times. Superpowers-style single directives ARE followed. The gate
   therefore emits exactly one directive line per archetype change.
2. **Deterministic and cheap.** agy hides its prompt classifier inside the main model call
   (free); a hook cannot — so no per-prompt LLM calls. Pure bash+jq case-match: measured
   63ms end-to-end (old router: 250–675ms).
3. **Evaluation before expansion.** Kimi's telemetry loop, done deterministically: every
   gate directive and every actual Skill/Agent invocation is logged with the active
   archetype. The data decides whether the gate grows, changes, or dies (same standard that
   killed the old router).

## Components

### task-gate.sh — UserPromptSubmit (sync, timeout 10s, measured 63ms)
- Extracts `.prompt`; skips slash-commands (`/`, `<`, `!` prefixes) and prompts <8 chars.
- First-match archetype table (delegate > fix > review > config > deploy > research > build;
  question/other = silent fallback). English + Bulgarian aliases (поправи, бъг, делегирай,
  пусни на, направи, добави, създай, проучи, намери...).
- Directive names the mandated process skill + delegation route per user policy
  (kimi-delegate w/ agy fallback; kimi-search for research legwork; brainstorming-first for
  build; systematic-debugging for fix incl. the own-the-codebase rule; update-config for
  config incl. pipe-test discipline; verify+finishing for deploy incl. no-bot-trailers).
- Dedup: state file per session (`cache/task-gate-<sid>.state`); injects only when the
  archetype CHANGES. Always exit 0, fail-open.

### skill-telemetry.sh — PostToolUse matcher Skill|Agent (async, fire-and-forget)
- Appends `{ts, sid, event:"invoke", tool, what, arch}` to `cache/skill-telemetry.jsonl`;
  `arch` read from the gate's state file (correlation key). Gate writes matching
  `event:"gate"` lines. Structurally unable to block or loop.

### Hygiene (log-rotate.sh extended)
- skill-telemetry.jsonl trimmed to last 2000 events; task-gate state files expire after 7d.

### Evaluation query (run after ~1 week of soak)
```bash
jq -s 'group_by(.arch) | map({arch: .[0].arch,
  gates: map(select(.event=="gate")) | length,
  invokes: map(select(.event=="invoke")) | length})' \
  ~/.claude/hooks/cache/skill-telemetry.jsonl
```
Decision rule (same evidence bar that killed the router): archetypes whose directives are
not followed get fixed or removed; if the whole gate is ignored, it dies.

## Validation record (2026-07-10)

- Pipe tests: all 7 archetypes route correctly; delegate wins precedence over build in mixed
  prompts; Bulgarian aliases work; dedup silences repeats and re-fires on archetype change;
  slash/short/question prompts silent; 63ms end-to-end.
- Telemetry: pipe-tested (Skill + Agent payloads, arch correlation) AND live-proven — a real
  Agent call logged with this session's actual ID.
- settings.json: 10 events / 15 registrations, jq-validated; snapshot
  `settings.json.post-taskgate` in backups/hook-modernisation-20260710/.
- task-gate LIVE-FIRED on the first real user prompt after wiring (2026-07-10) — and the
  first firing exposed a substring false positive: "Hooks_project" matched *hook* → [config]
  directive on a plain copy task. Fixed same-day to space-bounded patterns
  (*" hook "*, end-anchored *" hook", *" hooks "*, *" hooks"); 8-case regression passed
  (both Hooks_project mentions silent; a-hook/hook-to/settings.json/hooks-dir still gate;
  build/fix archetypes unaffected). Exactly the failure mode the telemetry loop exists to
  catch — caught on firing #1.

## Phase 2/3 (contingent on telemetry)
- Phase 2: tune/extend table; plugin-route hints; effort/model hints (agy tiers).
- Phase 3: delegation frontmatter (model:/skills:/timeout: in kimi-delegate briefs, mirroring
  agy_parallel.sh) + salvage-mode PARTIAL verdicts in kimi-delegate's validator.
- Expanded research + brainstorm (2026-07-10 PM): Auto-selector/phase23-research-brainstorm.md.

## v3 — defect-driven fixes (2026-07-10 PM, implemented + tested)

Scope per report section F: defects only; NOT telemetry-gated (new archetypes/effort hints
still wait for the soak).

1. **task-gate.sh v3 word-boundary matching.** Pipe tests proved the firing-#1 substring
   class generalized: "add a prefix"→[fix], "open the preview"→[review], "rebuild the
   failover logic"→[fix]. Fix: pure-bash punctuation→space normalization (underscore kept —
   identifiers like Hooks_project stay one token; tr avoided: mangles multibyte Cyrillic)
   + all aliases as space-bounded whole words with explicit inflections (fix/fixes/fixed/
   fixing, debug, rebuild, configure..., BG plurals; typo alias "написи" dropped).
2. **Coverage telemetry.** Unmatched classifiable prompts now log {event:"pass"} — soak can
   measure recall, not just precision. First real pass event live-fired 2026-07-10T16:49Z.
3. **Post-compact blind spot.** state-reinject.sh (SessionStart matcher=compact) now clears
   cache/task-gate-<sid>.state so the first post-compact prompt re-injects its directive
   (compaction wipes the previous injection from context; dedup state must not outlive it).
4. **kimi_parallel.sh reliability** (kimi-delegate skill): host shebang (was /usr/bin/env —
   absent on this host; direct exec was broken), --timeout flag (agy-grade validation,
   default 15m) with `timeout -k 10` wrapping the kimi call — the ONLY hang protection
   (kimi CLI v0.23.4 has no per-call timeout flag), FAILED(timeout)/FAILED(quota)/
   FAILED(exit) classification (quota markers = subagent-kimi-guard set) + delegation-policy
   fallback hint, duplicate-brief-name guard, header-length-robust --help.

Validation record (TDD): suites written FIRST and run red against pre-fix scripts
(6+6 expected failures, 28 existing-behavior passes = no baseline drift), then green:
task-gate 35/35, kimi_parallel 14/14 (fake-kimi shim, zero quota), state-reinject 3/3
(state cleared; snapshot re-inject intact; silent no-snapshot path). Gate latency 97ms.
One test corrected with rationale: "add a prefix..." → [build] via the by-design "add a"
alias (v2 sent it to [fix] via substring — that defect is the thing fixed); split into
prefix-alone→SILENT + add-a-prefix→build-not-fix. Suites: Auto-selector/tests/.
Pre-change backups: ~/.claude/backups/phase2-defect-fixes-20260710/.
First live directive-followed pair in telemetry: [fix] gate 16:34Z → systematic-debugging
invoke 16:37Z. First live pass event 16:49Z.

## v4 — adversarial-review fixes (2026-07-10 PM, same day)

A 57-agent verification workflow (3 review dimensions, every finding judged by a 3-skeptic
panel with instructions to refute; skeptics reproduced findings end-to-end on this host)
confirmed 18 findings — 13 unique defects plus 5 cross-dimension duplicates — 0 refuted,
plus 1 side observation (relative brief paths) surfaced during a reproduction. All fixed
same-day (raw findings: Auto-selector/research/adversarial-review-findings.json):

kimi_parallel.sh:
- Octal trap: --timeout 09m passed validation, then $((09*60)) aborted (octal), SECS unset,
  every agent died on set -u AFTER branch pollution → forced base-10 ($((10#...))).
- --timeout 0/0s/0m = GNU `timeout 0` = NO limit — silently disabled the only hang
  protection → rejected (must be > 0).
- Dup-name check derived names as basename "${b%.*}" — the %.* glob crosses '/', so dotted
  DIRS (a.dir/task vs b.dir/task) fooled the check while run_one collided both onto branch
  kimi/task and one brief was silently dropped ("1/1 succeeded") → derive exactly like
  run_one (basename first, then strip extension).
- rc=137 (the -k SIGKILL grace path when an agent ignores TERM) was misclassified
  FAILED(exit)/FAILED(quota) → 124 and 137 both classify FAILED(timeout).
- Bare "429" in the quota regex matched innocent line numbers/byte counts → requires HTTP
  context ((status|http|code|error) 429) + added "too many requests".
- Relative brief paths broke silently (agents cd into worktrees before reading the brief →
  empty prompt; pre-existing, surfaced by a skeptic) → briefs resolved to absolute upfront.

task-gate.sh v4:
- BG morphology regression (the v3 whole-word lists killed definite-article and inflected
  forms: грешката, бъгът, делегирайте, създайте...) → Bulgarian aliases are left-anchored
  stems (*" грешк"*, *" бъг"*, *" делегира"*, *" поправ"*, *" добав"*, *" създа"*,
  *" проуч"*, *" намери"*, *" направ"*, *" напиш"*) — suffixing morphology makes open
  suffixes safe where English needed explicit inflection lists.
- Byte-based printf %.400s truncation halved the window for Cyrillic and could split a
  multibyte char → character-based bash slicing ${prompt:0:400}.
- tr-based lowercasing never folded Cyrillic capitals (pre-existing) → single awk pass with
  locale-aware tolower (verified on-host: gawk 5.3 + en_US.UTF-8 folds Cyrillic).
- ASCII-only separator set → awk pass normalizes all ASCII punct except underscore (string-
  form gsub ranges) + Unicode marks (— – … „ “ ” ’ ‘ « » ·); typographic apostrophe in
  "doesn’t" now normalizes (v3 missed it).
- Genuine-intent compounds and derived forms restored explicitly: buggy/hotfix/bugfix,
  reconfigure/misconfigured, reviewing, researching/investigated, rebuilding/rebuilt,
  publishing/deployments/redeploy, erroring; " not work"* left-anchored (covers
  will/did/does not work, not working).
- NOT restored (documented no-fix): "implementation" ("explain the implementation" is a
  question); broad English stem-matching (fixture/prefix class) — recall tuning beyond
  this stays Phase 2, telemetry-informed.

## Phase 2 + 3 implementation (2026-07-10 evening, user-ordered "go phase 2 and 3")

Phase 2 — task-gate v5:
- Four new archetypes; precedence delegate > fix > review > TEST > COMMIT > config >
  deploy > research > BUNDLE > build > MEMORY. Guards verified: "tests are failing"→fix,
  "add a test"→test-not-build, "create a pr"→commit-not-build, "pull request" stays review.
- Effort overlay on explicit intent phrases only (GPT-5-router lesson: stated intent beats
  inference; EN+BG; HIGH wins ties): appends "EFFORT: user signalled HIGH/LOW..." to the
  directive. No question-suppression heuristic (rejected: "can you fix X?" class makes it
  net-negative; telemetry will arbitrate).
- Tier hints: delegate directive names kimi -highspeed vs kimi-for-coding; research
  directive routes bulk legwork to kimi/haiku tiers. Config directive adds
  plugin-dev:hook-development for plugin hooks.
- Gate telemetry events now carry a 60-char NORMALIZED prompt snippet (quote/backslash-free
  by construction → printf-safe JSON) for false-positive audits.
- Live-fired [bundle] on a real prompt the same evening.

Phase 3 — kimi-delegate v3 (mirrors agy-delegate):
- Per-brief YAML frontmatter: model: (-m), timeout: (per-agent wall clock), schema:
  (relative→brief dir; instruction appended to prompt; post-run validation), skills:
  (comma list → "You MUST use your X skill" mandates). Fallback precedence: frontmatter >
  CLI flag > default.
- validate_output.py vendored verbatim from agy-delegate (CLI-agnostic); --schema-mode
  strict|salvage|warn (default salvage); statuses OK / PARTIAL(schema) / FAILED(schema),
  PARTIAL writes <name>.partial.json with _missing/_invalid and does NOT count as failed.
- brief_lib.sh vendored from agy_lib.sh WITH the base-10/zero-reject duration fixes —
  upstream agy_lib.sh still has the octal bug (agy-delegate follow-up flagged).
- --lint opt-in (Goal/Scope/Requirements/Verification), deviating from agy's default-on:
  existing kimi briefs are free-form (SKILL.md documented both).
- Prelaunch failures (bad-timeout/schema-file/empty-brief/worktree) now counted in the
  exit code and the X/Y summary — fixed a silent accounting gap.
- meta.txt provenance; the kimi --version probe is timeout-wrapped — an unwrapped probe
  hung the test suite via the hang-mode fake (defect found and fixed pre-merge; rule:
  NO unbounded kimi call anywhere in this script).

Validation Phase 2/3: gate suite 68/68 (16 new: archetypes, precedence, effort overlay,
snippet); kimi suite 33/33 (13 new: frontmatter/model/timeout/schema salvage-strict-warn/
skills/lint/schema-file). SKILL.md updated (frontmatter grammar, statuses, --lint).

Validation v4: suites extended to 52 (gate) + 20 (kimi) checks — 17 new gate cases (BG
morphology incl. capitalized Cyrillic, compounds, derived forms, Unicode punctuation,
450-char Cyrillic truncation) and 6 new kimi cases (09m octal, 0-timeout reject, dotted-dir
dup, relative brief, stubborn-TERM rc-137, innocent-429) — ALL GREEN. Red-phase evidence
for v4 = the skeptic panels' independent end-to-end reproductions against pre-fix code.
Gate latency 122ms (one awk spawn). Workflow cost: 57 agents / ~1.74M subagent tokens.
