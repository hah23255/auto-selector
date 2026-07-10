#!/data/data/com.termux/files/usr/bin/bash

export T="$(mktemp -d)"
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

DEL="$(pwd)/scripts/delegate.sh"

export DELEGATE_KIMI_LAUNCHER="$T/kimi-launcher.sh"
export DELEGATE_AGY_LAUNCHER="$T/agy-launcher.sh"
export PATH="$T/bin:$PATH"
mkdir -p "$T/bin"

# Stubs
cat >"$T/kimi-launcher.sh" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
printf '%s\n' "$@" > "$T/kimi-args"
case "${STUB_KIMI_MODE:-ok}" in
ok) echo "kimi OK"; exit 0 ;;
quota) echo "FAILED(quota)"; exit 2 ;;
err) echo "FAILED(exit)"; exit 1 ;;
esac
EOF

cat >"$T/agy-launcher.sh" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
printf '%s\n' "$@" > "$T/agy-args"
case "${STUB_AGY_MODE:-ok}" in
ok) echo "agy OK"; exit 0 ;;
err) echo "agy err"; exit 3 ;;
esac
EOF

chmod +x "$T/kimi-launcher.sh" "$T/agy-launcher.sh"

echo "== T1: args are forwarded verbatim in order =="
rm -f "$T/kimi-args"
bash "$DEL" --engine kimi --some-flag "with space" arg2 >/dev/null
rc=$?
[ $rc -eq 0 ] && ok "exit 0" || ko "exit 0"
{
	echo "--some-flag"
	echo "with space"
	echo "arg2"
} > "$T/expected-args"
cmp -s "$T/expected-args" "$T/kimi-args" && ok "forwarding" || ko "forwarding (got: $(cat "$T/kimi-args" 2>/dev/null))"

echo "== T2: --engine kimi and --engine agy force respective launcher =="
rm -f "$T/kimi-args" "$T/agy-args"
bash "$DEL" --engine agy foo >/dev/null
[ -f "$T/agy-args" ] && [ ! -f "$T/kimi-args" ] && ok "forced agy" || ko "forced agy"

echo "== T3: auto picks kimi when kimi CLI is on PATH =="
rm -f "$T/kimi-args" "$T/agy-args"
cat >"$T/bin/kimi" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
echo dummy
EOF
chmod +x "$T/bin/kimi"
bash "$DEL" --engine auto foo >/dev/null
[ -f "$T/kimi-args" ] && [ ! -f "$T/agy-args" ] && ok "auto kimi" || ko "auto kimi"

echo "== T4: auto picks agy when kimi CLI not on PATH but agy launcher exists =="
rm -f "$T/kimi-args" "$T/agy-args"
rm -f "$T/bin/kimi"
mkdir -p "$T/fake-bin"
for p in $(echo "$PATH" | tr ':' ' '); do
	for f in "$p"/*; do
		if [ -f "$f" ] && [ "${f##*/}" != "kimi" ]; then
			ln -s "$f" "$T/fake-bin/${f##*/}" 2>/dev/null || true
		fi
	done
done
PATH="$T/fake-bin" bash "$DEL" --engine auto foo >/dev/null
[ -f "$T/agy-args" ] && [ ! -f "$T/kimi-args" ] && ok "auto agy" || ko "auto agy"

echo "== T5: exit codes propagate exactly =="
STUB_KIMI_MODE=err bash "$DEL" --engine kimi foo >/dev/null
rc=$?
[ $rc -eq 1 ] && ok "kimi exit 1 propagates" || ko "kimi exit 1 propagates (rc=$rc)"
STUB_AGY_MODE=err bash "$DEL" --engine agy foo >/dev/null
rc=$?
[ $rc -eq 3 ] && ok "agy exit 3 propagates" || ko "agy exit 3 propagates (rc=$rc)"

echo "== T6: --failover reruns on quota output =="
rm -f "$T/agy-args"
STUB_KIMI_MODE=quota bash "$DEL" --engine kimi --failover foo >"$T/out6"
rc=$?
[ $rc -eq 0 ] && ok "quota failover exits 0 (agy OK)" || ko "quota failover exits 0 (rc=$rc)"
grep -q "failover: kimi quota -> agy" "$T/out6" && ok "failover message printed" || ko "failover message printed"
[ -f "$T/agy-args" ] && ok "agy actually ran" || ko "agy actually ran"

echo "== T7: --failover does NOT rerun on plain failure =="
rm -f "$T/agy-args"
STUB_KIMI_MODE=err bash "$DEL" --engine kimi --failover foo >"$T/out7"
rc=$?
[ $rc -eq 1 ] && ok "plain failure keeps exit 1" || ko "plain failure keeps exit 1 (rc=$rc)"
[ ! -f "$T/agy-args" ] && ok "agy did not run" || ko "agy did not run"
grep -q "failover" "$T/out7" && ko "no failover message" || ok "no failover message"

echo
echo "RESULT: $pass passed, $fail failed"
exit "$fail"
