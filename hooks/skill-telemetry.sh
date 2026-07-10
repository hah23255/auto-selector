#!/data/data/com.termux/files/usr/bin/bash
# PostToolUse hook (matcher Skill|Agent, async): log which skills/agents actually
# get invoked, tagged with the current task-gate archetype — produces the
# suggested-vs-invoked evidence that tunes or kills the gate. Fire-and-forget.
CACHE_DIR="$HOME/.claude/hooks/cache"
mkdir -p "$CACHE_DIR" 2>/dev/null
IN=$(cat 2>/dev/null)
SID=$(printf '%s' "$IN" | jq -r '.session_id // "nosid"' 2>/dev/null)
tool=$(printf '%s' "$IN" | jq -r '.tool_name // empty' 2>/dev/null)
what=$(printf '%s' "$IN" | jq -r '.tool_input.skill // .tool_input.subagent_type // .tool_input.description // "?"' 2>/dev/null | head -c 60)
[ -n "$tool" ] || exit 0
arch=$(cat "$CACHE_DIR/task-gate-$SID.state" 2>/dev/null || echo none)
printf '{"ts":"%s","sid":"%s","event":"invoke","tool":"%s","what":"%s","arch":"%s"}\n' \
	"$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SID" "$tool" "$what" "$arch" >>"$CACHE_DIR/skill-telemetry.jsonl" 2>/dev/null
exit 0
