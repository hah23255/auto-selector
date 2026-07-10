#!/data/data/com.termux/files/usr/bin/bash
# SessionStart hook (matcher: compact): re-inject the pre-compact state snapshot
# written by precompact-save.sh, then consume it (one-shot). Always exits 0.
CACHE_DIR="$HOME/.claude/hooks/cache"
IN=$(cat 2>/dev/null)
SID=$(printf '%s' "$IN" | jq -r '.session_id // empty' 2>/dev/null)
[ -n "$SID" ] || exit 0
# Compaction wiped any injected task-gate directive from context; clear the
# gate's dedup state (archetype + effort) so the next prompt re-injects.
rm -f "$CACHE_DIR/task-gate-$SID.state" "$CACHE_DIR/task-gate-$SID.eff" 2>/dev/null
f="$CACHE_DIR/precompact-$SID.md"
[ -f "$f" ] || exit 0
ctx=$(head -c 1500 "$f" 2>/dev/null)
rm -f "$f" 2>/dev/null
[ -n "$ctx" ] || exit 0
jq -cn --arg ctx "$ctx" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}' 2>/dev/null
exit 0
