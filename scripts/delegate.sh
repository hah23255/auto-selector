#!/data/data/com.termux/files/usr/bin/bash

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

ENGINE="auto"
FAILOVER=0
ARGS=()

die() {
	echo "error: $*" >&2
	exit 1
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--engine)
		ENGINE="${2:?}"
		shift 2
		;;
	--failover)
		FAILOVER=1
		shift
		;;
	*)
		ARGS+=("$1")
		shift
		;;
	esac
done

KIMI_LAUNCHER="${DELEGATE_KIMI_LAUNCHER:-$SCRIPT_DIR/kimi_parallel.sh}"
AGY_LAUNCHER="${DELEGATE_AGY_LAUNCHER:-$HOME/.claude/skills/agy-delegate/scripts/agy_parallel.sh}"

if [[ "$ENGINE" == "auto" ]]; then
	if command -v kimi >/dev/null 2>&1; then
		ENGINE="kimi"
	elif [[ -f "$AGY_LAUNCHER" ]]; then
		ENGINE="agy"
	else
		die "no available engine (kimi CLI not on PATH, and $AGY_LAUNCHER not found). Please use native subagents."
	fi
fi

if [[ "$ENGINE" == "kimi" ]]; then
	if [[ $FAILOVER -eq 1 ]]; then
		tmpdir="${TMPDIR:-$HOME/.cache}"
		mkdir -p "$tmpdir"
		TMP="$(mktemp "$tmpdir/delegate.XXXXXX")"
		bash "$KIMI_LAUNCHER" "${ARGS[@]}" 2>&1 | tee "$TMP"
		RC=${PIPESTATUS[0]}
		if [[ $RC -ne 0 ]] && grep -q "FAILED(quota)" "$TMP"; then
			echo "failover: kimi quota -> agy"
			rm -f "$TMP"
			bash "$AGY_LAUNCHER" "${ARGS[@]}"
			exit $?
		fi
		rm -f "$TMP"
		exit $RC
	else
		bash "$KIMI_LAUNCHER" "${ARGS[@]}"
		exit $?
	fi
elif [[ "$ENGINE" == "agy" ]]; then
	bash "$AGY_LAUNCHER" "${ARGS[@]}"
	exit $?
else
	die "unknown engine: $ENGINE"
fi
