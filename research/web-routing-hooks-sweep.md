# Raw web/community sweep — routing, hooks, salvage (2026-07-10, native web agent)

Collected for Auto-selector Phase 2/3 expansion. Native agent (WebSearch/WebFetch); kimi
web search unavailable (v0.23.4). Condensed synthesis lives in
phase23-research-brainstorm.md section D; this file preserves the raw findings + URLs.

## Q1 — Prompt/task classification without an LLM call

- RouteLLM (lm-sys): 4 routers trained on Chatbot Arena preference data — similarity-weighted
  embedding ranking, matrix factorization, BERT classifier, causal-LLM classifier. All emit a
  scalar "strong-model win probability" thresholded against a cost target; 95% of GPT-4
  quality at 26% GPT-4 calls. https://github.com/lm-sys/routellm ,
  https://www.lmsys.org/blog/2024-07-01-routellm/ , https://arxiv.org/pdf/2406.18665
  Portable: no (torch/embeddings), but scalar-score+threshold design ports.
- semantic-router (aurelio-labs): routes = utterance lists embedded at build time; runtime =
  embed query + cosine top-1; no LLM; ~100ms vs ~5000ms LLM routing.
  https://github.com/aurelio-labs/semantic-router
  Portable: encoder no; "route = utterance list compiled offline" data model yes.
- vLLM Semantic Router signal-decision architecture (strongest match): layered independent
  signals — keyword (radix tree, 10k+ rules, flat latency, traceable), embedding (HNSW),
  domain classifier (ModernBERT) — combined via boolean AND/OR decision trees in YAML;
  guidance: "start with keywords, add embeddings later."
  https://blog.vllm.ai/2025/11/19/signal-decision.html , https://arxiv.org/pdf/2603.04444 ,
  https://vllm-semantic-router.com/docs/v0.1/installation/configuration/
  Portable: keyword layer + boolean combiner is bash+jq-implementable today.
- Aho-Corasick: O(text+matches) multi-pattern matching; GNU grep `-F -f patterns.txt` uses
  it internally — one pass over tagged keyword files = sub-10ms at any table size.
  https://banay.me/post/aho-corasick/ ,
  https://www.sciencedirect.com/science/article/abs/pii/S014036642100493X
- fastText quantized: >2000 docs/s CPU; single C++ binary + .ftz model, ARM/Termux-buildable;
  needs a few hundred labeled prompts (bootstrap from case-glob matches).
  https://dataloop.ai/library/model/kenhktsui_llm-data-textbook-quality-fasttext-classifier-v2/
  Portable: yes-as-tiny-binary; only realistic ML step-up under no-vector-infra constraint.
- NVIDIA prompt-task-and-complexity-classifier (DeBERTa multi-head; powers llm-router
  blueprint): heads = task type + 6 complexity dims (creativity, reasoning,
  contextual-knowledge, few-shot, domain-knowledge, constraint).
  https://huggingface.co/nvidia/prompt-task-and-complexity-classifier ,
  https://github.com/NVIDIA-AI-Blueprints/llm-router
  Portable: model no; complexity-dimension taxonomy = deterministic feature checklist.
  Martian "model mapping" is closed-source — not portable.

## Q2 — Model-tier / effort routing signals

- OpenRouter Auto Router (NotDiamond): signals = prompt complexity, task type, model
  capabilities; cost_quality_tradeoff dial 0-10 (default 7); pins model+provider per
  conversation via fingerprint of first system + first user message.
  https://openrouter.ai/docs/guides/routing/routers/auto-router
  Portable: dial + sticky pinning (hash session → stable tier hint).
- GPT-5 real-time router: routes on conversation type, complexity, tool needs, explicit
  intent phrases ("think hard about this"); trained on switch behavior/preference/measured
  correctness. Backlash over aggressive cheap-defaulting forced manual toggles.
  https://openai.com/index/introducing-gpt-5/ ,
  https://fortune.com/2025/08/12/openai-gpt-5-model-router-backlash-ai-future/
  Portable: explicit-intent phrases = highest-precision signal; provide manual override;
  route UP when in doubt.
- Claude effort parameter (official): low/medium/high = thinking budget ceilings; low for
  classification/lookups/high-volume, high (default) for complex reasoning/difficult coding.
  https://platform.claude.com/docs/en/build-with-claude/effort ,
  https://code.claude.com/docs/en/model-config
- "When to Reason" (arXiv 2025): category classification alone toggles reasoning mode per
  query with accuracy retained + large token savings. https://arxiv.org/html/2510.08731v1
  Direct evidence coarse archetype→effort mapping works.
- Signal inventory (union): prompt length, code-fence presence, question-vs-imperative,
  constraint count, few-shot examples, reasoning verbs, explicit intent phrases, tool-need
  markers — all bash-measurable within 60ms.

## Q3 — Claude Code hooks ecosystem

- Official contract: UserPromptSubmit is one of three events where stdout on exit 0 is
  injected as context; hookSpecificOutput.additionalContext; injected as system-reminder
  prompt-adjacent; decision:"block"/exit 2 erases the prompt.
  https://code.claude.com/docs/en/hooks
- diet103/claude-code-infrastructure-showcase: skill-rules.json with promptTriggers
  {keywords, intentPatterns} + file-context via PostToolUse tracker; injects tiered "SKILL
  ACTIVATION CHECK" (Critical/High/Medium/Low); 6 months production claimed, NO quantitative
  data. https://github.com/diet103/claude-code-infrastructure-showcase ,
  https://claudefa.st/blog/tools/hooks/skill-activation-hook
  Ships ranked menus — the shape our transcript evidence says gets ignored.
- umputun gist: static unconditional "MANDATORY SKILL ACTIVATION" on every prompt — zero
  classification. https://gist.github.com/umputun/570c77f8d5f3ab621498e1449d2b98b6
- disler/claude-code-hooks-mastery: canonical UserPromptSubmit reference (log /
  validate-and-block / inject context). https://github.com/disler/claude-code-hooks-mastery
- jefflester/claude-skills-supercharged: Haiku scores skill relevance per prompt —
  latency/tokens per prompt. https://github.com/jefflester/claude-skills-supercharged
- SuperClaude: "auto-activating personas" = prose in always-loaded .md files, model-side.
  https://github.com/SuperClaude-Org/SuperClaude_Framework
- NO published quantitative evidence anywhere that injected directives change behavior —
  all ecosystem claims anecdotal; our gates-vs-invokes soak = novel measurement.

## Q4 — Structured-output salvage validation

- BAML Schema-Aligned Parsing: Rust, <10ms, extracts schema-shaped data from malformed
  output; typed object, no retry. https://boundaryml.com/blog/structured-output-from-llms
- instructor create_partial + Pydantic experimental_allow_partial="trailing-strings":
  missing required fields → Missing marker, not hard-fail.
  https://python.useinstructor.com/learning/validation/field_level_validation/ ,
  https://docs.pydantic.dev/latest/concepts/experimental/
- partial-json-parser (promplate; used by OpenAI): bracket/string-stack completion of
  parseable prefix. https://github.com/promplate/partial-json-parser
- json_repair (mangiucugna) / kaptinlin/jsonrepair (Go, single ARM binary): broader repair
  (prose, comments, unquoted keys, truncation). https://github.com/mangiucugna/json_repair ,
  https://github.com/kaptinlin/jsonrepair
- TypeChat repair loop: feed validator diagnostics back for ONE bounded retry.
  https://microsoft.github.io/TypeChat/docs/faq/
- Minimal jq recipe: (1) strip fences/prose before first "{"; (2) jq -e . → on fail append
  bracket-stack closers, retry; (3) mark don't fail:
  def salvage($req): . as $o | ($req - ($o|keys)) as $miss
    | $o + {_missing:$miss, _partial:($miss|length>0)};
  plus per-field type checks appending to _invalid.

## Q5 — Lifecycle-hook mechanisms in other harnesses

- Gemini CLI hooks (GA): BeforeAgent (=UserPromptSubmit; additionalContext, deny), plus
  BeforeModel (mutate LLM request) and BeforeToolSelection (per-turn tool filtering),
  AfterModel (redaction). https://github.com/google-gemini/gemini-cli/blob/main/docs/hooks/reference.md
- Codex CLI hooks (GA ~v0.117, Mar 2026): UserPromptSubmit, Pre/PostToolUse,
  PermissionRequest, Pre/PostCompact, SessionStart, Stop, SubagentStart/Stop; exit-2-stderr
  contract. https://developers.openai.com/codex/hooks
- Kimi CLI hooks (Beta): TOML [[hooks]] (event/matcher/command/timeout) incl.
  UserPromptSubmit; fail-open; "AgentHooks" cross-tool spec.
  https://www.kimi-cli.com/en/customization/hooks.html ,
  https://github.com/MoonshotAI/kimi-cli/issues/785
- Cursor .mdc rules: {description, globs, alwaysApply} → always / glob auto-attach /
  agent-requested / manual. https://forum.cursor.com/t/cursor-rules-mdc-clarification/104879
- Windsurf rules: same 4 modes + priority ordering + per-scope character budgets.
  https://windsurf.com/university/general-education/creating-modifying-rules
- opencode plugins: system-prompt transform cannot yet see user prompt text (issues
  #17637/#27401) — UserPromptSubmit remains the most capable prompt-conditioned injection
  point surveyed. https://opencode.ai/docs/plugins/
