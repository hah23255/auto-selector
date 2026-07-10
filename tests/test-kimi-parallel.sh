#!/data/data/com.termux/files/usr/bin/bash
# Reliability-fix suite for kimi_parallel.sh (shebang, timeout, quota classify, dup names).
# Uses a fake `kimi` shim on PATH — burns zero quota.
# Usage: test-kimi-parallel.sh /path/to/kimi_parallel.sh
KP="${1:?usage: test-kimi-parallel.sh <kimi_parallel.sh>}"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
pass=0 fail=0

ok() {
	pass=$((pass + 1))
	echo "PASS  $1"
}
ko() {
	fail=$((fail + 1))
	echo "FAIL  $1"
}

# fake kimi: behavior keyed on FAKE_KIMI_MODE
mkdir -p "$T/bin"
cat >"$T/bin/kimi" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
[ "${1:-}" = "--help" ] && { printf '%s\n' "${FAKE_HELP:-usage: kimi -p <prompt> --output-format <fmt>}"; exit 0; }
case "${FAKE_KIMI_MODE:-ok}" in
ok)    echo "task done"; exit 0 ;;
hang)  sleep 300; exit 0 ;;
quota) echo "Error: insufficient_quota - your quota is exhausted" >&2; exit 1 ;;
err)   echo "boom" >&2; exit 3 ;;
esac
EOF
chmod +x "$T/bin/kimi"
export PATH="$T/bin:$PATH"

# briefs live in a NON-git dir so the script auto-falls back to --no-worktree
W="$T/work"
mkdir -p "$W"
printf 'do the thing\n' >"$T/brief-one.md"
printf 'do the other thing\n' >"$T/brief-two.md"

echo "== T1 syntax =="
if bash -n "$KP" 2>/dev/null; then ok "bash -n"; else ko "bash -n"; fi

echo "== T2 shebang + direct exec =="
head -1 "$KP" | grep -q '^#!/data/data/com.termux/files/usr/bin/bash$' &&
	ok "host shebang" || ko "host shebang (got: $(head -1 "$KP"))"
cp "$KP" "$T/kp.sh" && chmod +x "$T/kp.sh"
if "$T/kp.sh" --help >/dev/null 2>&1; then ok "direct exec works"; else ko "direct exec works"; fi

echo "== T3 happy path =="
out=$(FAKE_KIMI_MODE=ok bash "$KP" --repo "$W" --results-dir "$T/r3" "$T/brief-one.md" "$T/brief-two.md" 2>&1)
rc=$?
[ $rc -eq 0 ] && ok "exit 0 on success" || ko "exit 0 on success (rc=$rc)"
echo "$out" | grep -q "2/2 agent(s) succeeded" && ok "2/2 reported" || ko "2/2 reported"
grep -q "task done" "$T/r3/brief-one.log" 2>/dev/null && ok "log captured" || ko "log captured"

echo "== T4 timeout enforcement =="
start=$(date +%s)
out=$(FAKE_KIMI_MODE=hang bash "$KP" --repo "$W" --results-dir "$T/r4" --timeout 3s "$T/brief-one.md" 2>&1)
rc=$?
took=$(($(date +%s) - start))
[ $rc -ne 0 ] && ok "nonzero exit on timeout" || ko "nonzero exit on timeout"
echo "$out" | grep -q "FAILED(timeout)" && ok "FAILED(timeout) classified" || ko "FAILED(timeout) classified (out: $(echo "$out" | tail -3))"
[ "$took" -lt 60 ] && ok "killed promptly (${took}s)" || ko "killed promptly (took ${took}s)"

echo "== T5 quota classification =="
out=$(FAKE_KIMI_MODE=quota bash "$KP" --repo "$W" --results-dir "$T/r5" "$T/brief-one.md" 2>&1)
echo "$out" | grep -q "FAILED(quota)" && ok "FAILED(quota) classified" || ko "FAILED(quota) classified"
echo "$out" | grep -q "agy-delegate\|native subagents" && ok "fallback hint printed" || ko "fallback hint printed"

echo "== T6 plain failure stays FAILED(exit) =="
out=$(FAKE_KIMI_MODE=err bash "$KP" --repo "$W" --results-dir "$T/r6" "$T/brief-one.md" 2>&1)
echo "$out" | grep -q "FAILED(exit)" && ok "FAILED(exit) classified" || ko "FAILED(exit) classified"

echo "== T7 duplicate names rejected =="
printf 'x\n' >"$T/a b.md"
printf 'y\n' >"$T/a-b.md"
if bash "$KP" --repo "$W" --results-dir "$T/r7" "$T/a b.md" "$T/a-b.md" >/dev/null 2>&1; then
	ko "dup names rejected"
else
	ok "dup names rejected"
fi

echo "== T8 bad timeout rejected =="
if bash "$KP" --repo "$W" --results-dir "$T/r8" --timeout 5x "$T/brief-one.md" >/dev/null 2>&1; then
	ko "bad --timeout rejected"
else
	ok "bad --timeout rejected"
fi

echo "== T9 leading-zero timeout works (octal trap) =="
out=$(FAKE_KIMI_MODE=ok bash "$KP" --repo "$W" --results-dir "$T/r9" --timeout 09m "$T/brief-one.md" 2>&1)
rc=$?
[ $rc -eq 0 ] && echo "$out" | grep -q "1/1 agent(s) succeeded" && ok "--timeout 09m runs OK" || ko "--timeout 09m runs OK (rc=$rc)"

echo "== T10 zero timeout rejected (would disable protection) =="
r10=0
bash "$KP" --repo "$W" --results-dir "$T/r10a" --timeout 0 "$T/brief-one.md" >/dev/null 2>&1 && r10=1
bash "$KP" --repo "$W" --results-dir "$T/r10b" --timeout 0m "$T/brief-one.md" >/dev/null 2>&1 && r10=1
[ $r10 -eq 0 ] && ok "--timeout 0 / 0m rejected" || ko "--timeout 0 / 0m rejected"

echo "== T11 dup detection with dotted dirs =="
mkdir -p "$T/a.dir" "$T/b.dir"
printf 'x\n' >"$T/a.dir/task"
printf 'y\n' >"$T/b.dir/task"
if bash "$KP" --repo "$W" --results-dir "$T/r11" "$T/a.dir/task" "$T/b.dir/task" >/dev/null 2>&1; then
	ko "dotted-dir dup rejected"
else
	ok "dotted-dir dup rejected"
fi

echo "== T12 relative brief path =="
printf 'rel brief content\n' >"$T/rel-brief.md"
out=$(cd "$T" && FAKE_KIMI_MODE=ok bash "$KP" --repo "$W" --results-dir "$T/r12" "rel-brief.md" 2>&1)
rc=$?
[ $rc -eq 0 ] && grep -q "task done" "$T/r12/rel-brief.log" 2>/dev/null && ok "relative brief path works" || ko "relative brief path works (rc=$rc)"

echo "== T13 SIGKILL grace path classified as timeout (rc 137) =="
cat >"$T/bin/kimi" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
case "${FAKE_KIMI_MODE:-ok}" in
ok) echo "task done"; exit 0 ;;
hang) sleep 300; exit 0 ;;
stubborn) trap '' TERM; sleep 300; exit 0 ;;
quota) echo "Error: insufficient_quota - your quota is exhausted" >&2; exit 1 ;;
err) echo "boom" >&2; exit 3 ;;
err429) echo "assertion failed at line 429: unexpected token" >&2; exit 3 ;;
esac
EOF
chmod +x "$T/bin/kimi"
out=$(FAKE_KIMI_MODE=stubborn bash "$KP" --repo "$W" --results-dir "$T/r13" --timeout 2s "$T/brief-one.md" 2>&1)
echo "$out" | grep -q "FAILED(timeout)" && ok "rc-137 grace kill -> FAILED(timeout)" || ko "rc-137 grace kill -> FAILED(timeout) (got: $(echo "$out" | grep FAILED))"

echo "== T14 innocent 429 in log is NOT quota =="
out=$(FAKE_KIMI_MODE=err429 bash "$KP" --repo "$W" --results-dir "$T/r14" "$T/brief-one.md" 2>&1)
echo "$out" | grep -q "FAILED(exit)" && ok "line-429 text stays FAILED(exit)" || ko "line-429 text stays FAILED(exit) (got: $(echo "$out" | grep FAILED))"

# ---- Phase 3: frontmatter, schema salvage, skills ----
cat >"$T/bin/kimi" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
[ "${1:-}" = "--help" ] && { printf '%s\n' "${FAKE_HELP:-usage: kimi -p <prompt> --output-format <fmt>}"; exit 0; }
case "${FAKE_KIMI_MODE:-ok}" in
ok) echo "task done"; exit 0 ;;
args) printf 'ARGV>>>%s<<<\n' "$@"; exit 0 ;;
jsonpart) echo 'Here is the result:'; echo '{"a": 1}'; exit 0 ;;
hang) sleep 300; exit 0 ;;
stubborn) trap '' TERM; sleep 300; exit 0 ;;
quota) echo "Error: insufficient_quota - your quota is exhausted" >&2; exit 1 ;;
err) echo "boom" >&2; exit 3 ;;
err429) echo "assertion failed at line 429: unexpected token" >&2; exit 3 ;;
esac
EOF
chmod +x "$T/bin/kimi"

echo "== T27 version-adaptive --print detection =="
printf 'v27 body\n' >"$T/v27.md"
FAKE_KIMI_MODE=args bash "$KP" --repo "$W" --results-dir "$T/r27a" "$T/v27.md" >/dev/null 2>&1
grep -q 'ARGV>>>--print<<<' "$T/r27a/v27.log" 2>/dev/null && ko "0.23-style help: --print omitted" || ok "0.23-style help: --print omitted"
FAKE_HELP='--print   run non-interactively' FAKE_KIMI_MODE=args bash "$KP" --repo "$W" --results-dir "$T/r27b" "$T/v27.md" >/dev/null 2>&1
grep -q 'ARGV>>>--print<<<' "$T/r27b/v27.log" 2>/dev/null && ok "1.41-style help: --print passed" || ko "1.41-style help: --print passed"

echo "== T15 frontmatter model + body stripping =="
printf -- '---\nmodel: custom/model-x\n---\nthe brief body only\n' >"$T/fm-model.md"
out=$(FAKE_KIMI_MODE=args bash "$KP" --repo "$W" --results-dir "$T/r15" "$T/fm-model.md" 2>&1)
grep -q "custom/model-x" "$T/r15/fm-model.log" && ok "frontmatter model passed via -m" || ko "frontmatter model passed via -m"
grep -q "the brief body only" "$T/r15/fm-model.log" && ok "body reaches prompt" || ko "body reaches prompt"
grep -q "model: custom/model-x" "$T/r15/fm-model.log" && ko "frontmatter stripped from prompt" || ok "frontmatter stripped from prompt"

echo "== T16 frontmatter timeout override =="
printf -- '---\ntimeout: 1s\n---\ndo something\n' >"$T/fm-to.md"
out=$(FAKE_KIMI_MODE=hang bash "$KP" --repo "$W" --results-dir "$T/r16" "$T/fm-to.md" 2>&1)
echo "$out" | grep -q "FAILED(timeout)" && ok "frontmatter timeout enforced" || ko "frontmatter timeout enforced"

echo "== T17 invalid frontmatter timeout fails prelaunch =="
printf -- '---\ntimeout: 5x\n---\ndo something\n' >"$T/fm-badto.md"
out=$(FAKE_KIMI_MODE=ok bash "$KP" --repo "$W" --results-dir "$T/r17" "$T/fm-badto.md" 2>&1)
rc=$?
echo "$out" | grep -q "FAILED(bad-timeout)" && [ $rc -ne 0 ] && ok "bad frontmatter timeout -> FAILED(bad-timeout), rc!=0" || ko "bad frontmatter timeout (rc=$rc)"

echo "== T18 schema salvage -> PARTIAL =="
printf '%s\n' '{"type":"object","properties":{"a":{"type":"integer"},"b":{"type":"string"}},"required":["a","b"]}' >"$T/schema.json"
printf -- '---\nschema: schema.json\n---\nreturn json\n' >"$T/fm-schema.md"
out=$(FAKE_KIMI_MODE=jsonpart bash "$KP" --repo "$W" --results-dir "$T/r18" "$T/fm-schema.md" 2>&1)
rc=$?
echo "$out" | grep -q "PARTIAL(schema)" && [ $rc -eq 0 ] && ok "salvage -> PARTIAL(schema), rc=0" || ko "salvage -> PARTIAL(schema) (rc=$rc, got: $(echo "$out" | grep -E 'PARTIAL|FAILED'))"
jq -e '._missing == ["b"] and .a == 1' "$T/r18/fm-schema.partial.json" >/dev/null 2>&1 && ok "partial.json has _missing + salvaged field" || ko "partial.json has _missing + salvaged field"
echo "$out" | grep -q "(1 partial)" && ok "summary surfaces partial count" || ko "summary surfaces partial count"

echo "== T19 schema strict -> FAILED =="
out=$(FAKE_KIMI_MODE=jsonpart bash "$KP" --repo "$W" --results-dir "$T/r19" --schema-mode strict "$T/fm-schema.md" 2>&1)
rc=$?
echo "$out" | grep -q "FAILED(schema)" && [ $rc -ne 0 ] && ok "strict -> FAILED(schema), rc!=0" || ko "strict -> FAILED(schema) (rc=$rc)"

echo "== T20 schema warn -> OK + warning =="
out=$(FAKE_KIMI_MODE=jsonpart bash "$KP" --repo "$W" --results-dir "$T/r20" --schema-mode warn "$T/fm-schema.md" 2>&1)
rc=$?
echo "$out" | grep -qE "^  OK|  OK " && [ $rc -eq 0 ] && echo "$out" | grep -qi "warn" && ok "warn -> OK + warning, rc=0" || ko "warn -> OK + warning (rc=$rc)"

echo "== T21 skills mandate injected =="
printf -- '---\nskills: foo, bar-baz\n---\nimplement the thing\n' >"$T/fm-skills.md"
out=$(FAKE_KIMI_MODE=args bash "$KP" --repo "$W" --results-dir "$T/r21" "$T/fm-skills.md" 2>&1)
grep -q "You MUST use your foo skill" "$T/r21/fm-skills.log" && grep -q "You MUST use your bar-baz skill" "$T/r21/fm-skills.log" && ok "skills mandates in prompt" || ko "skills mandates in prompt"

echo "== T22 --lint =="
printf 'no sections here\n' >"$T/plain.md"
if bash "$KP" --repo "$W" --results-dir "$T/r22a" --lint "$T/plain.md" >/dev/null 2>&1; then
	ko "--lint rejects sectionless brief"
else
	ok "--lint rejects sectionless brief"
fi
printf -- '## Goal\ng\n## Scope\ns\n## Requirements\nr\n## Verification\nv\n' >"$T/sectioned.md"
FAKE_KIMI_MODE=ok bash "$KP" --repo "$W" --results-dir "$T/r22b" --lint "$T/sectioned.md" >/dev/null 2>&1 && ok "--lint passes sectioned brief" || ko "--lint passes sectioned brief"

echo "== T24 CRLF brief: frontmatter honored, lint passes =="
printf -- '---\r\nmodel: crlf/model\r\n---\r\n## Goal\r\ng\r\n## Scope\r\ns\r\n## Requirements\r\nr\r\n## Verification\r\nv\r\n' >"$T/crlf.md"
out=$(FAKE_KIMI_MODE=args bash "$KP" --repo "$W" --results-dir "$T/r24" --lint "$T/crlf.md" 2>&1)
rc=$?
grep -q "crlf/model" "$T/r24/crlf.log" 2>/dev/null && [ $rc -eq 0 ] && ok "CRLF frontmatter model honored + lint OK" || ko "CRLF frontmatter model honored + lint OK (rc=$rc)"
grep -q -- "---" "$T/r24/crlf.log" 2>/dev/null && ko "CRLF frontmatter stripped from prompt" || ok "CRLF frontmatter stripped from prompt"

echo "== T25 quoted + trailing-space frontmatter values normalized =="
printf -- '---\nmodel: "quoted/model"   \n---\nbody here\n' >"$T/quoted.md"
FAKE_KIMI_MODE=args bash "$KP" --repo "$W" --results-dir "$T/r25" "$T/quoted.md" >/dev/null 2>&1
grep -q 'ARGV>>>quoted/model<<<' "$T/r25/quoted.log" 2>/dev/null && ok "quotes + trailing spaces stripped from value" || ko "quotes + trailing spaces stripped from value"

echo "== T26 --json + schema brief rejected =="
if bash "$KP" --repo "$W" --results-dir "$T/r26" --json "$T/fm-schema.md" >/dev/null 2>&1; then
	ko "--json + schema rejected upfront"
else
	ok "--json + schema rejected upfront"
fi

echo "== T28 never-closed frontmatter is body, not overrides =="
printf -- '---\ntimeout: 5x\nthe dashes above were a horizontal rule, not frontmatter\n' >"$T/unclosed.md"
out=$(FAKE_KIMI_MODE=args bash "$KP" --repo "$W" --results-dir "$T/r28" "$T/unclosed.md" 2>&1)
rc=$?
[ $rc -eq 0 ] && ok "unclosed frontmatter: bogus timeout NOT honored (rc=0)" || ko "unclosed frontmatter: bogus timeout NOT honored (rc=$rc: $(echo "$out" | grep FAILED))"
grep -q "timeout: 5x" "$T/r28/unclosed.log" 2>/dev/null && ok "unclosed frontmatter kept as body" || ko "unclosed frontmatter kept as body"

echo "== T23 missing schema file fails prelaunch =="
printf -- '---\nschema: nope.json\n---\nx y z\n' >"$T/fm-noschema.md"
out=$(FAKE_KIMI_MODE=ok bash "$KP" --repo "$W" --results-dir "$T/r23" "$T/fm-noschema.md" 2>&1)
rc=$?
echo "$out" | grep -q "FAILED(schema-file)" && [ $rc -ne 0 ] && ok "missing schema -> FAILED(schema-file)" || ko "missing schema -> FAILED(schema-file) (rc=$rc)"

echo
echo "RESULT: $pass passed, $fail failed"
exit "$fail"
