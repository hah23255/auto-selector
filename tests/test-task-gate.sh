#!/data/data/com.termux/files/usr/bin/bash
# Regression suite for task-gate.sh v3 (word-boundary matching, pass telemetry).
# Usage: test-task-gate.sh /path/to/task-gate.sh
# Isolation: HOME is pointed at a temp dir so state+telemetry never touch the real cache.
GATE="${1:?usage: test-task-gate.sh <task-gate.sh>}"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/.claude/hooks/cache"

pass=0 fail=0 n=0

# run PROMPT SID -> prints archetype or SILENT
run() {
	local out
	out=$(printf '%s' "$2" | jq -Rs --arg sid "$1" '{session_id:$sid, prompt:.}' |
		HOME="$T" bash "$GATE" 2>/dev/null)
	if [ -z "$out" ]; then
		echo "SILENT"
	else
		printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null |
			sed -n 's/^TASK-GATE \[\([a-z]*\)\].*/\1/p'
	fi
}

check() { # DESC EXPECTED PROMPT  (fresh sid per check unless embedded in desc)
	local desc="$1" want="$2" prompt="$3" sid got
	n=$((n + 1))
	sid="t$n"
	got=$(run "$sid" "$prompt")
	if [ "$got" = "$want" ]; then
		pass=$((pass + 1))
		echo "PASS  $desc -> $got"
	else
		fail=$((fail + 1))
		echo "FAIL  $desc -> got:${got:-EMPTY} want:$want"
	fi
}

echo "== must gate (existing behavior preserved) =="
check "fix verb" fix "fix the login flow please"
check "error noun" fix "there is an error in the parser output"
check "inflection fixing" fix "fixing the broken tests now"
check "inflection failed" fix "the build failed again"
check "debug verb" fix "debug this crash for me"
check "review" review "review the pull request please"
check "BG review" review "провери кода в модула"
check "hook -> config" config "add a hook for linting please"
check "settings.json" config "update settings.json permissions now"
check "configure" config "configure the statusline colors"
check "deploy" deploy "deploy the release to production"
check "research" research "research the best approach for caching"
check "BG research" research "проучи наличните опции"
check "build create" build "create a new feature for exports"
check "BG build" build "направи нов скрипт за архивиране"
check "rebuild -> build" build "rebuild the parser module"
check "delegate" delegate "delegate this to kimi please"
check "BG delegate" delegate "делегирай задачата на агентите"
check "fan out" delegate "fan out the work to agents"
check "precedence delegate>fix" delegate "delegate the bug fixing work"
check "multiline keyword at line start" fix "the tests are red
fix them please"

echo "== must stay silent (verified false positives) =="
check "prefix !fix" SILENT "the prefix on those log lines looks inconsistent"
check "preview !review" SILENT "open the preview of the page"
check "suffix !fix" SILENT "change the suffix handling please"
# Since Phase 2 these gate [bundle] (copy/sync aliases); the original defect —
# routing to [config] via the *hook* substring — must stay dead.
check "Hooks_project copy -> bundle not config" bundle "copy the report to Hooks_project please"
check "Hooks_project sync -> bundle not config" bundle "sync the Hooks_project folder now"
check "plain question" SILENT "explain the concept of closures"
check "slash cmd" SILENT "/compact focus on things"
check "short" SILENT "short"

echo "== disambiguation =="
# "add a X" routes to build BY DESIGN (v2 alias); the defect was the substring
# match sending these to [fix]. Assert build, i.e. NOT fix.
check "add a prefix -> build not fix" build "add a prefix to the log lines"
check "fixture !fix, add-a -> build" build "add a pytest fixture please"
check "failover !fix, rebuild -> build" build "rebuild the failover logic"

echo "== v4: BG morphology (definite articles, verb inflections) =="
check "BG грешката (article)" fix "поправи грешката в кода"
check "BG бъгът (article)" fix "бъгът се появява отново"
check "BG делегирайте (plural imper.)" delegate "делегирайте задачата на агентите"
check "BG създайте (plural imper.)" build "създайте нов модул"
check "BG precedence намерих+грешки" fix "намерих грешки в кода"
check "BG capital П folded" fix "Поправи Грешката в модула"

echo "== v4: genuine-intent compounds =="
check "buggy" fix "the app is buggy on rotation"
check "hotfix" fix "apply the hotfix now please"
check "misconfigured" config "the proxy is misconfigured badly"

echo "== v4: derived forms =="
check "rebuilding" build "rebuilding the index right now"
check "publishing" deploy "publishing the package today"
check "researching" research "researching alternatives currently"
check "will not work" fix "this will not work on old devices"

echo "== v4: unicode punctuation and typography =="
check "em-dash separator" fix "поправи грешката — спешно е"
check "typographic apostrophe doesn’t" fix "this doesn’t work at all"
check "ellipsis glued" fix "there is a bug… somewhere in it"

echo "== v4: char-based truncation (Cyrillic long prompt) =="
longbg="поправи грешката веднага $(printf 'и провери всичко отново %.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18)"
n=$((n + 1))
got=$(run trunc1 "$longbg")
if [ "$got" = "fix" ]; then
	pass=$((pass + 1))
	echo "PASS  long Cyrillic prompt (${#longbg} chars) -> fix"
else
	fail=$((fail + 1))
	echo "FAIL  long Cyrillic prompt (${#longbg} chars) -> got:${got:-EMPTY} want:fix"
fi

echo "== phase 2: new archetypes =="
check "write tests -> test" test "write tests for the parser module"
check "add a test -> test (precedence over build)" test "add a test for the login flow"
check "BG тестове" test "напиши тестове за модула"
check "coverage" test "improve the coverage of the auth module"
check "commit" commit "commit the changes and push to origin"
check "create a pr" commit "create a pr for this branch"
check "bundle verb" bundle "bundle the updated state please"
check "copy to" bundle "copy the docs to the project folder"
check "remember -> memory" memory "remember that the proxy needs auth"
check "BG запомни" memory "запомни че прокси сървърът иска парола"

echo "== phase 2: precedence guards =="
check "failing tests -> fix wins over test" fix "the tests are failing again"
check "fix the commit -> fix wins" fix "fix the broken commit message"
check "pull request stays review" review "check the pull request comments"

echo "== phase 2: effort overlay =="
n=$((n + 1))
d=$(printf '%s' '{"session_id":"ef1","prompt":"fix the parser error and think hard about edge cases"}' | HOME="$T" bash "$GATE" | jq -r '.hookSpecificOutput.additionalContext')
case "$d" in
*"[fix]"*"EFFORT: user signalled HIGH"*)
	pass=$((pass + 1))
	echo "PASS  high-effort overlay appended"
	;;
*)
	fail=$((fail + 1))
	echo "FAIL  high-effort overlay appended (got: $d)"
	;;
esac
n=$((n + 1))
d=$(printf '%s' '{"session_id":"ef2","prompt":"quickly fix the typo in the readme error message"}' | HOME="$T" bash "$GATE" | jq -r '.hookSpecificOutput.additionalContext')
case "$d" in
*"[fix]"*"EFFORT: user signalled LOW"*)
	pass=$((pass + 1))
	echo "PASS  low-effort overlay appended"
	;;
*)
	fail=$((fail + 1))
	echo "FAIL  low-effort overlay appended (got: $d)"
	;;
esac

echo "== phase 2: gate telemetry carries prompt snippet =="
n=$((n + 1))
run sn1 "fix the login flow please" >/dev/null
if jq -e 'select(.sid == "sn1" and .event == "gate" and (.p | type == "string") and (.p | contains("fix the login")))' "$T/.claude/hooks/cache/skill-telemetry.jsonl" >/dev/null 2>&1; then
	pass=$((pass + 1))
	echo "PASS  gate event has snippet field"
else
	fail=$((fail + 1))
	echo "FAIL  gate event has snippet field"
fi

echo "== dedup =="
n=$((n + 1))
a=$(run dd1 "fix the login flow")
b=$(run dd1 "fix the other error too")
c=$(run dd1 "now review the pull request")
if [ "$a" = "fix" ] && [ "$b" = "SILENT" ] && [ "$c" = "review" ]; then
	pass=$((pass + 1))
	echo "PASS  dedup: fire, suppress repeat, re-fire on change"
else
	fail=$((fail + 1))
	echo "FAIL  dedup: got [$a/$b/$c] want [fix/SILENT/review]"
fi

echo "== pass-event telemetry =="
n=$((n + 1))
run pe1 "explain the concept of promises" >/dev/null
if jq -e 'select(.sid == "pe1" and .event == "pass")' "$T/.claude/hooks/cache/skill-telemetry.jsonl" >/dev/null 2>&1; then
	pass=$((pass + 1))
	echo "PASS  pass event logged for unmatched prompt"
else
	fail=$((fail + 1))
	echo "FAIL  pass event missing for unmatched prompt"
fi
n=$((n + 1))
run pe2 "/compact stuff" >/dev/null
if jq -e 'select(.sid == "pe2")' "$T/.claude/hooks/cache/skill-telemetry.jsonl" >/dev/null 2>&1; then
	fail=$((fail + 1))
	echo "FAIL  slash command must not log any event"
else
	pass=$((pass + 1))
	echo "PASS  slash command logs nothing"
fi

echo
echo "RESULT: $pass passed, $fail failed, $n total"
exit "$fail"
