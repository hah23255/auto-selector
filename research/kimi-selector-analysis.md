# Kimi CLI pre-start selector vs skill-router — agent findings (2026-07-10)

## Kimi CLI mechanism

- All skills/plugins loaded once at SessionStart (`merge_all_available_skills = true`); no per-prompt re-scoring; LLM decides tool/skill use at runtime.
- Experimental `tool-select` flag (v0.23.4) for dynamic tool selection (algorithm in compiled binary, not inspectable).
- Injection: SessionStart hook injects the "using-superpowers" meta-skill (full SKILL.md) as additionalContext; everything else available via tool set.
- Registry: `~/.kimi-code/plugins/installed.json`; config: `~/.kimi-code/config.toml`; SessionStart hook timeout 10s, typical <100ms.
- Philosophy: trust the LLM to navigate all tools; near-zero per-prompt latency; token cost paid upfront.

## skill-router (local, currently UNWIRED) mechanism

- UserPromptSubmit: tokenize prompt → stopword filter (130 words) → alias expansion (incl. non-ASCII, e.g. "делегирай"→"delegate") → keyword score (+1 description hit, +2 name hit, MIN_SCORE=2) → top-5 shortlist injected with rationale.
- Novelty/epoch dedup: MAX_INJECTIONS=4 per compaction epoch; state per session in `state/$SID.injected`; SessionStart(compact) resets epoch.
- Index: `index.tsv` (34 skills; user + flow-next, cartographer, superpowers), rebuilt `--if-stale` vs settings.json/installed_plugins.json mtimes.
- Observed latency: **250–675 ms per prompt** (router.log ms field).
- Never blocks (always exit 0), logs to router.log.

## Key evaluation points

- Kimi strengths: minimal latency, scales without index maintenance, meta-skill teaching pattern, offline algorithm iteration via flag.
- Kimi weaknesses: no visible ranking, upfront token cost, no novelty filter, uninspectable, blind plugin loading.
- skill-router strengths: deterministic/debuggable, low token cost (1–5 skills/prompt), novelty-aware, project-scope override, full logging.
- skill-router weaknesses: 250–675ms on EVERY prompt, keyword brittleness (synonyms/multilingual), hardcoded stopwords, epoch dedup can refuse useful re-injection, no conflict detection, **not wired into settings.json**.

## Agent's modernisation recommendations (for design consideration)

1. Hybrid scoring: keyword baseline (fast, visible) + optional async LLM re-rank of top-N (only worth it >100 skills; keyword-only fine <50).
2. Adopt from Kimi: meta-skill teaching pattern; index MCP servers alongside skills; lazy/parallel loading; experimental-flag pattern for testing ranking changes offline.
3. Fix skill-router: re-wire into settings.json; content-hash based index staleness (not mtime); async index warm; multilingual alias/stopword packs; conflict detection; confidence badges.
4. Context efficiency: inject shortlist + skill names only (lazy fetch via Skill tool), never full SKILL.md bodies.
5. Observability: skill health checks pre-injection; track suggested-vs-actually-invoked rate; feedback loop (upweight used, downweight ignored); CLI introspection command.

Latency note for impact assessment: current router costs 250–675ms × every user prompt; Kimi's model costs ~0ms per prompt but more context tokens at start.
