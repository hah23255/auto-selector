#!/data/data/com.termux/files/usr/bin/bash
# UserPromptSubmit hook: deterministic task-archetype gate (agy-style mode-gating).
# Classifies the prompt into an archetype and injects ONE directive line naming
# the mandated process skill + delegation route. Evidence-shaped design: single
# directives are followed (superpowers pattern); ranked menus are not (dead
# skill-router, 2026-07-06). Dedup: injects only when the archetype CHANGES
# within a session (state cleared post-compact by state-reinject.sh).
# v3 (2026-07-10): word-boundary matching kills the verified substring
# false-positive class (prefix/suffix->fix, preview->review, failover->fix).
# v4 (2026-07-10, post adversarial review): character-based truncation; one awk
# pass does locale-aware lowercasing (Cyrillic capitals now fold), ASCII+Unicode
# punctuation-to-space (em-dash, ellipsis, typographic quotes/apostrophe), and
# newline joining; Bulgarian aliases match as left-anchored stems (suffixing
# morphology: грешката/бъгът/делегирайте); genuine-intent compounds and common
# derived forms restored (buggy/hotfix/misconfigured/rebuilding/publishing...).
# v5 (2026-07-10, Phase 2): four new archetypes (test, commit, bundle, memory;
# precedence delegate>fix>review>test>commit>config>deploy>research>bundle>build>
# memory), explicit-intent effort overlay (GPT-5-router lesson: stated intent
# beats inference), kimi/subagent tier hints in delegate/research directives,
# and a 60-char normalized-prompt snippet on gate telemetry for FP auditing.
# Unmatched prompts log event:"pass" (coverage). Always exits 0; fail-open.
CACHE_DIR="$HOME/.claude/hooks/cache"
mkdir -p "$CACHE_DIR" 2>/dev/null
IN=$(cat 2>/dev/null)
SID=$(printf '%s' "$IN" | jq -r '.session_id // "nosid"' 2>/dev/null)
prompt=$(printf '%s' "$IN" | jq -r '.prompt // empty' 2>/dev/null)
[ -n "$prompt" ] || exit 0

# Skip slash commands, injected/system content, and trivial one-word prompts.
case "$prompt" in
"/"* | "<"* | "!"*) exit 0 ;;
esac
[ "${#prompt}" -lt 8 ] && exit 0

# Normalize: character-based truncation (bash slicing is char-aware under UTF-8;
# printf %.400s was byte-based and halved the window for Cyrillic), then one awk
# pass: locale-aware tolower + every separator to space. Underscore is NOT a
# separator (identifiers like Hooks_project stay one token). The string form of
# gsub avoids ERE /-escaping pitfalls; ranges cover all ASCII punct except _.
p=$(printf '%s' "${prompt:0:400}" | awk 'BEGIN { ORS = " " } {
	$0 = tolower($0)
	gsub("[!-/:-@[-^`{-~]", " ")
	gsub(/[—–…„“”’‘«»·]/, " ")
	gsub(/[\t\r]/, " ")
	print
}' 2>/dev/null)
case "$p" in *[![:space:]]*) ;; *) exit 0 ;; esac # fail-open if awk broke
p=" $p "

arch="" directive=""
case "$p" in
*" delegate "* | *" delegated "* | *" delegating "* | *" hand off "* | *" hand this "* | *" делегира"* | *" пусни на "* | *" let kimi "* | *" to kimi "* | *" to agy "* | *" fan out "*)
	arch="delegate"
	directive="TASK-GATE [delegate]: use the kimi-delegate skill (agy-delegate if Kimi quota is out); invoke kimi ONLY as kimi --print -p (non-TTY). Kimi tiers: -highspeed alias for mechanical briefs, kimi-for-coding for reasoning-heavy."
	;;
*" fix "* | *" fixes "* | *" fixed "* | *" fixing "* | *" hotfix "* | *" hotfixes "* | *" bugfix "* | *" bugfixes "* | *" bug "* | *" bugs "* | *" buggy "* | *" debug "* | *" debugging "* | *" error "* | *" errors "* | *" erroring "* | *" fail "* | *" fails "* | *" failed "* | *" failing "* | *" failure "* | *" failures "* | *" broken "* | *" crash "* | *" crashes "* | *" crashed "* | *" crashing "* | *" not work"* | *" doesn t work "* | *" won t work "* | *" поправ"* | *" бъг"* | *" грешк"*)
	arch="fix"
	directive="TASK-GATE [fix]: invoke superpowers:systematic-debugging BEFORE proposing any fix; reproduce first, then root-cause. Own pre-existing defects too."
	;;
*" review "* | *" reviews "* | *" reviewed "* | *" reviewing "* | *" провери кода "* | *" check the pr "* | *" pull request "*)
	arch="review"
	directive="TASK-GATE [review]: invoke code-review (or superpowers:requesting-code-review for own work); report findings, do not auto-fix unless asked."
	;;
*" test "* | *" tests "* | *" testing "* | *" coverage "* | *" tdd "* | *" тест"*)
	arch="test"
	directive="TASK-GATE [test]: invoke superpowers:test-driven-development; write the failing test FIRST; never weaken a test or hack the mock to make it pass."
	;;
*" commit "* | *" commits "* | *" committed "* | *" committing "* | *" git push "* | *" push to "* | *" push the "* | *" open a pr "* | *" create a pr "* | *" raise a pr "*)
	arch="commit"
	directive="TASK-GATE [commit]: git fetch first; NO Claude/bot trailers in commits or PRs (GitHub ban risk); minimal diffs; Safety Net blocks destructive git — do not bypass it."
	;;
*" hook "* | *" hooks "* | *" permission "* | *" permissions "* | *" settings json "* | *" config "* | *" configs "* | *" configure "* | *" configured "* | *" configuring "* | *" configuration "* | *" reconfigure "* | *" reconfigured "* | *" misconfigured "* | *" misconfiguration "* | *" statusline "*)
	arch="config"
	directive="TASK-GATE [config]: invoke update-config for settings/hooks work; read-before-write, pipe-test hooks before wiring, backup settings first. Plugin hooks specifically → plugin-dev:hook-development."
	;;
*" deploy "* | *" deploys "* | *" deployed "* | *" deploying "* | *" deployment "* | *" deployments "* | *" redeploy "* | *" redeploying "* | *" redeployed "* | *" release "* | *" releases "* | *" publish "* | *" publishes "* | *" published "* | *" publishing "* | *" ship it "* | *" merge to main "*)
	arch="deploy"
	directive="TASK-GATE [deploy]: invoke verify (end-to-end) then superpowers:finishing-a-development-branch; no bot trailers in commits."
	;;
*" research "* | *" researching "* | *" investigate "* | *" investigating "* | *" investigated "* | *" investigation "* | *" find out "* | *" look up "* | *" search for "* | *" проуч"* | *" намери"* | *" deep dive "*)
	arch="research"
	directive="TASK-GATE [research]: route secondary search/summarization legwork to the kimi-search subagent (delegation policy); deep-research skill for multi-source cited reports. Bulk legwork on kimi/haiku tiers; synthesis stays in-session."
	;;
*" bundle "* | *" bundles "* | *" bundled "* | *" bundling "* | *" sync "* | *" syncs "* | *" synced "* | *" syncing "* | *" copy "* | *" copied "* | *" copying "* | *" копирай"*)
	arch="bundle"
	directive="TASK-GATE [bundle]: deterministic bundle procedure — cp then cmp-verify EVERY copy, refresh the bundle README, report counts; targets under /storage/emulated/0/Documents/."
	;;
*" build "* | *" builds "* | *" building "* | *" rebuild "* | *" rebuilding "* | *" rebuilt "* | *" create "* | *" creates "* | *" creating "* | *" implement "* | *" implements "* | *" implementing "* | *" add a "* | *" add an "* | *" new feature "* | *" develop "* | *" develops "* | *" developing "* | *" направ"* | *" добав"* | *" създа"* | *" напиш"*)
	arch="build"
	directive="TASK-GATE [build]: invoke superpowers:brainstorming FIRST (design before code — hard gate), then writing-plans; TDD during implementation."
	;;
*" remember "* | *" memorize "* | *" запомни "* | *" to memory "*)
	arch="memory"
	directive="TASK-GATE [memory]: update the persistent memory store — check for an existing memory file first (update, never duplicate), add a MEMORY.md index line, absolute dates only."
	;;
*)
	# Coverage telemetry: unmatched classifiable prompt (soak recall measurement).
	printf '{"ts":"%s","sid":"%s","event":"pass"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SID" >>"$CACHE_DIR/skill-telemetry.jsonl" 2>/dev/null
	exit 0
	;;
esac

# Effort overlay: explicit user intent phrases are the highest-precision effort
# signal (stated intent beats inference); HIGH wins if both appear.
case "$p" in
*" think hard"* | *" be thorough"* | *" exhaustive"* | *" ultrathink"* | *" внимателно "* | *" задълбочено "*)
	directive="$directive EFFORT: user signalled HIGH — be exhaustive, verify adversarially."
	;;
*" quickly "* | *" quick check "* | *" quick look "* | *" briefly "* | *" бързо "* | *" накратко "*)
	directive="$directive EFFORT: user signalled LOW — be brief, minimal fan-out."
	;;
esac

# Dedup: only inject when the archetype changes within this session.
state="$CACHE_DIR/task-gate-$SID.state"
[ "$(cat "$state" 2>/dev/null)" = "$arch" ] && exit 0
printf '%s' "$arch" >"$state" 2>/dev/null

# Telemetry: record the directive event for suggested-vs-invoked evaluation.
# The snippet is the NORMALIZED prompt (quotes/backslashes already stripped ->
# JSON-safe via printf), for false-positive auditing without transcript digs.
printf '{"ts":"%s","sid":"%s","event":"gate","arch":"%s","p":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SID" "$arch" "${p:1:60}" >>"$CACHE_DIR/skill-telemetry.jsonl" 2>/dev/null

jq -cn --arg d "$directive" '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $d}}' 2>/dev/null
exit 0
