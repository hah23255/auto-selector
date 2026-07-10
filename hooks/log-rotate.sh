#!/data/data/com.termux/files/usr/bin/bash
# SessionEnd hook (async): hook-cache hygiene. No find (broken on this box in
# some PATHs) — pure bash globs + stat. Always exits 0.
CACHE_DIR="$HOME/.claude/hooks/cache"
[ -d "$CACHE_DIR" ] || exit 0
now=$(date +%s)

# stop-gate.log: keep last 500 lines.
if [ -f "$CACHE_DIR/stop-gate.log" ]; then
	tail -n 500 "$CACHE_DIR/stop-gate.log" >"$CACHE_DIR/stop-gate.log.new.$$" 2>/dev/null &&
		mv "$CACHE_DIR/stop-gate.log.new.$$" "$CACHE_DIR/stop-gate.log" 2>/dev/null
fi

# skill-telemetry.jsonl: keep last 2000 events; task-gate state files: drop after 7 days.
if [ -f "$CACHE_DIR/skill-telemetry.jsonl" ]; then
	tail -n 2000 "$CACHE_DIR/skill-telemetry.jsonl" >"$CACHE_DIR/skill-telemetry.jsonl.new.$$" 2>/dev/null &&
		mv "$CACHE_DIR/skill-telemetry.jsonl.new.$$" "$CACHE_DIR/skill-telemetry.jsonl" 2>/dev/null
fi
for f in "$CACHE_DIR"/task-gate-*.state "$CACHE_DIR"/task-gate-*.eff; do
	[ -f "$f" ] || continue
	age=$((now - $(stat -c %Y "$f" 2>/dev/null || echo "$now")))
	[ "$age" -gt 604800 ] && rm -f "$f" 2>/dev/null
done

# precompact snapshots: drop after 7 days (orphaned = compaction never happened).
for f in "$CACHE_DIR"/precompact-*.md; do
	[ -f "$f" ] || continue
	age=$((now - $(stat -c %Y "$f" 2>/dev/null || echo "$now")))
	[ "$age" -gt 604800 ] && rm -f "$f" 2>/dev/null
done

# kimi-guard dedup markers: drop after 1 day.
for f in "$CACHE_DIR"/kimi-guard-*.done; do
	[ -f "$f" ] || continue
	age=$((now - $(stat -c %Y "$f" 2>/dev/null || echo "$now")))
	[ "$age" -gt 86400 ] && rm -f "$f" 2>/dev/null
done
exit 0
