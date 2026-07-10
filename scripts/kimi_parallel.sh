#!/data/data/com.termux/files/usr/bin/bash
# kimi_parallel.sh — fan a set of task briefs out to parallel Kimi Code CLI agents.
#
# Each brief file is handed to `kimi -p` running non-interactively. By default each
# agent gets its own git worktree on a fresh branch (kimi/<brief-name>) so parallel
# agents cannot corrupt each other's working tree and you can review/merge each
# branch independently.
#
# Usage:
#   kimi_parallel.sh --repo <path> [options] BRIEF_FILE [BRIEF_FILE ...]
#
# Options:
#   --repo <path>          Target git repository (default: current directory)
#   --model <alias>        Kimi model alias, e.g. kimi-code/kimi-for-coding
#   --timeout <dur>        Per-agent wall-clock limit, Ns/Nm/Nh or bare seconds
#                          (default 15m; kimi has no native per-call timeout flag)
#   --no-worktree          Run all agents directly in --repo (only safe if scopes
#                          are truly disjoint; no per-agent isolation)
#   --json                 Use Kimi's --output-format stream-json (machine-readable logs)
#   --results-dir <path>   Where to write logs (default: <repo>/.kimi-runs/<timestamp>)
#   --max-parallel <n>     Cap concurrent agents (default: all at once)
#   --base <ref>           Branch/ref to base worktrees on (default: current HEAD)
#   --schema-mode <m>      strict|salvage|warn (default salvage; applies to briefs
#                          that declare a schema:)
#   --repair               If a schema-gated agent fails validation, re-ask it ONCE
#                          with the validator's error report (default off)
#   --lint                 Require ## Goal / ## Scope / ## Requirements /
#                          ## Verification sections in every brief (opt-in)
#   -h, --help             Show this help
#
# Brief frontmatter (optional YAML block; each key overrides the flags per brief):
#   ---
#   model: kimi-code/kimi-for-coding-highspeed
#   timeout: 20m
#   schema: relative/or/absolute/path.json   (agent's final JSON validated; salvage
#                                             writes <name>.partial.json with _missing/_invalid)
#   skills: skill-a, skill-b                 (injected as MUST-use mandates)
#   ---
#
# Each brief's filename (without extension) becomes the agent name and branch suffix.
#
# Exit status: 0 if all agents exited 0, otherwise the number of failed agents.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=brief_lib.sh
source "$SCRIPT_DIR/brief_lib.sh"

REPO="$(pwd)"
MODEL=""
TIMEOUT="15m"
USE_WORKTREE=1
JSON=0
RESULTS_DIR=""
MAX_PARALLEL=0
BASE_REF=""
SCHEMA_MODE="salvage"
REPAIR=0
LINT=0
BRIEFS=()

die() {
	echo "error: $*" >&2
	exit 1
}

show_help() {
	# print the leading comment block (robust to header length changes)
	awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0"
	exit 0
}

# ---- parse args ----
while [[ $# -gt 0 ]]; do
	case "$1" in
	--repo)
		REPO="${2:?}"
		shift 2
		;;
	--model)
		MODEL="${2:?}"
		shift 2
		;;
	--timeout)
		TIMEOUT="${2:?}"
		shift 2
		;;
	--no-worktree)
		USE_WORKTREE=0
		shift
		;;
	--json)
		JSON=1
		shift
		;;
	--results-dir)
		RESULTS_DIR="${2:?}"
		shift 2
		;;
	--max-parallel)
		MAX_PARALLEL="${2:?}"
		shift 2
		;;
	--base)
		BASE_REF="${2:?}"
		shift 2
		;;
	--schema-mode)
		SCHEMA_MODE="${2:?}"
		shift 2
		;;
	--repair)
		REPAIR=1
		shift
		;;
	--lint)
		LINT=1
		shift
		;;
	-h | --help) show_help ;;
	-*) die "unknown option: $1" ;;
	*)
		BRIEFS+=("$1")
		shift
		;;
	esac
done

command -v kimi >/dev/null 2>&1 || die "kimi CLI not found on PATH. Install from https://github.com/MoonshotAI/kimi-code and run 'kimi login'."

# kimi CLI contract drift (verified live 2026-07-10): 1.41.x needs --print for
# non-interactive prompt mode; 0.23.x REJECTS --print (bare -p IS prompt mode,
# non-TTY-safe). Sniff the static help once — costs no quota. Timeout-wrapped:
# NO unbounded kimi call anywhere in this script, the sniff included.
PRINT_ARGS=()
case "$(timeout -k 2 5 kimi --help 2>/dev/null)" in *--print*) PRINT_ARGS=(--print) ;; esac
[[ ${#BRIEFS[@]} -gt 0 ]] || die "no brief files given. See --help."
[[ -d "$REPO" ]] || die "repo path not found: $REPO"
REPO="$(cd "$REPO" && pwd)"

for b in "${BRIEFS[@]}"; do
	[[ -f "$b" ]] || die "brief file not found: $b"
done

case "$SCHEMA_MODE" in strict | salvage | warn) ;; *) die "bad --schema-mode: $SCHEMA_MODE (strict|salvage|warn)" ;; esac

# schema: briefs need python3, and are incompatible with --json (the stream-json
# wrapper event is what the validator would extract, never the agent's answer).
has_schema=0
for b in "${BRIEFS[@]}"; do
	[[ -n "$(fm_get "$b" schema)" ]] && has_schema=1
done
if [[ $has_schema -eq 1 ]]; then
	[[ $JSON -eq 0 ]] || die "--json cannot be combined with schema: briefs (stream wrapper breaks validation); drop --json"
	command -v python3 >/dev/null 2>&1 || die "schema: briefs need python3 on PATH (validate_output.py)"
fi

if [[ $LINT -eq 1 ]]; then
	for b in "${BRIEFS[@]}"; do
		lint_brief "$b" || exit 1
	done
fi

# Validate the default --timeout early. Kimi has no native per-call timeout flag
# (config-only), so the outer `timeout` wrapper is the ONLY hang protection — a
# documented kimi failure mode (termios, quota stalls). Base-10 + zero-reject
# handled inside duration_secs_checked (brief_lib.sh).
SECS="$(duration_secs_checked "$TIMEOUT")" || die "invalid --timeout: '$TIMEOUT' (use e.g. 90s, 15m, 1h; must be > 0)"

# Resolve briefs to absolute paths — each agent cd's into its worktree before
# the brief is read, so relative paths would silently produce an empty prompt.
for bi in "${!BRIEFS[@]}"; do
	b="${BRIEFS[$bi]}"
	[[ "$b" == /* ]] || BRIEFS[$bi]="$(cd "$(dirname "$b")" && pwd)/$(basename "$b")"
done

# Sanitized brief names must be unique — collisions would share a branch and log.
# Name derivation must match run_one exactly: basename FIRST, then strip the
# extension (the ${b%.*} glob crosses '/' — dotted dirs would fool the check).
dup="$(for b in "${BRIEFS[@]}"; do
	n="$(basename "$b")"
	n="${n%.*}"
	printf '%s\n' "$(sanitize_name "$n")"
done | sort | uniq -d | head -n 1)"
[[ -z "$dup" ]] || die "duplicate brief name after sanitization: $dup (rename one brief)"

IS_GIT=0
if git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then IS_GIT=1; fi

if [[ $USE_WORKTREE -eq 1 && $IS_GIT -eq 0 ]]; then
	echo "note: $REPO is not a git repo — falling back to --no-worktree." >&2
	USE_WORKTREE=0
fi

if [[ -z "$BASE_REF" && $IS_GIT -eq 1 ]]; then
	BASE_REF="$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)"
fi

# Pin commit identity repo-locally when absent: delegated agents must never
# author as a container/global bot identity (agy-in-proot committed as "Agy
# Developer" 2026-07-10 — GitHub ban risk; GIT_AUTHOR_* env does not cross
# proot, repo-local config is the mitigation that works, and kimi host-side
# respects it too). Worktrees share the repo-local config, so one pin covers
# every agent. A pre-existing local identity is respected UNLESS it is itself
# a bot identity — the agy CLI leaves "Antigravity <antigravity@gemini.google>"
# repo-local config behind, which this guard must overwrite, not trust
# (observed live 2026-07-10). Override via DELEGATE_GIT_NAME/EMAIL.
if [[ $IS_GIT -eq 1 ]]; then
	bot_re='antigravity|gemini\.google|@example\.(com|org)|noreply@anthropic|\[bot\]'
	cur_name="$(git -C "$REPO" config --local user.name 2>/dev/null || true)"
	cur_email="$(git -C "$REPO" config --local user.email 2>/dev/null || true)"
	ident="${cur_name,,} ${cur_email,,}"
	if [[ -z "$cur_name" || "$ident" =~ $bot_re ]]; then
		git -C "$REPO" config user.name "${DELEGATE_GIT_NAME:-hah23255}"
	fi
	if [[ -z "$cur_email" || "$ident" =~ $bot_re ]]; then
		git -C "$REPO" config user.email "${DELEGATE_GIT_EMAIL:-hah23255@users.noreply.github.com}"
	fi
fi

TS="$(date +%Y%m%d-%H%M%S)"
[[ -n "$RESULTS_DIR" ]] || RESULTS_DIR="$REPO/.kimi-runs/$TS"
mkdir -p "$RESULTS_DIR"

{
	# timeout-wrapped: kimi hangs are the documented failure mode this script
	# exists to contain — no unbounded kimi call anywhere, including this probe.
	echo "kimi version: $(timeout -k 2 5 kimi --version 2>/dev/null || echo unknown)"
	echo "started: $(date)"
	echo "schema-mode: $SCHEMA_MODE"
} >"$RESULTS_DIR/meta.txt"

OUTPUT_FMT_ARGS=()
[[ $JSON -eq 1 ]] && OUTPUT_FMT_ARGS=(--output-format stream-json)

echo "Kimi parallel delegation"
echo "  repo:        $REPO"
echo "  briefs:      ${#BRIEFS[@]}"
echo "  isolation:   $([[ $USE_WORKTREE -eq 1 ]] && echo "git worktree (base: $BASE_REF)" || echo "none (in-place)")"
[[ -n "$MODEL" ]] && echo "  model:       $MODEL (default)"
echo "  timeout:     $TIMEOUT/agent (default)"
echo "  schema mode: $SCHEMA_MODE"
echo "  results dir: $RESULTS_DIR"
echo

declare -a NAMES PIDS WORKDIRS BRANCHES SCHEMAS START_EPOCHS PROMPTS BMODELS BSECS
run_count=0
failed_prelaunch=0

run_one() {
	local brief="$1" name workdir branch logfile bmodel btimeout bschema bskills bsecs prompt sk
	local -a _sk_arr margs
	name="$(basename "$brief")"
	name="${name%.*}"
	# sanitize for branch/dir use (sanitize_name avoids trailing-newline artifacts)
	name="$(sanitize_name "$name")"
	logfile="$RESULTS_DIR/$name.log"
	branch="kimi/$name"

	# Per-brief frontmatter overrides; fall back to the CLI flags/defaults.
	bmodel="$(fm_get "$brief" model)"
	[[ -n "$bmodel" ]] || bmodel="$MODEL"
	btimeout="$(fm_get "$brief" timeout)"
	[[ -n "$btimeout" ]] || btimeout="$TIMEOUT"
	if ! bsecs="$(duration_secs_checked "$btimeout")"; then
		echo "  FAILED(bad-timeout)  [$name]  invalid timeout: '$btimeout'"
		return 1
	fi
	bschema="$(fm_get "$brief" schema)"
	if [[ -n "$bschema" && "$bschema" != /* ]]; then
		bschema="$(cd "$(dirname "$brief")" && pwd)/$bschema"
	fi
	if [[ -n "$bschema" && ! -f "$bschema" ]]; then
		echo "  FAILED(schema-file)  [$name]  schema not found: $bschema"
		return 1
	fi
	bskills="$(fm_get "$brief" skills)"

	prompt="$(brief_body "$brief")"
	if [[ -z "${prompt//[[:space:]]/}" ]]; then
		echo "  FAILED(empty-brief)  [$name]  brief body is empty"
		return 1
	fi
	if [[ -n "$bskills" ]]; then
		IFS=',' read -ra _sk_arr <<<"$bskills"
		for sk in "${_sk_arr[@]}"; do
			sk="${sk#"${sk%%[![:space:]]*}"}"
			sk="${sk%"${sk##*[![:space:]]}"}"
			[[ -n "$sk" ]] && prompt="$prompt
You MUST use your $sk skill for this task."
		done
	fi
	if [[ -n "$bschema" ]]; then
		prompt="$prompt

Your final message must be exactly one JSON object matching this schema, and no other text:
$(cat "$bschema")"
	fi

	if [[ $USE_WORKTREE -eq 1 ]]; then
		workdir="$RESULTS_DIR/worktrees/$name"
		mkdir -p "$(dirname "$workdir")"
		if ! git -C "$REPO" worktree add -b "$branch" "$workdir" "$BASE_REF" >>"$logfile" 2>&1; then
			# branch may already exist; try without -b
			git -C "$REPO" worktree add "$workdir" "$branch" >>"$logfile" 2>&1 ||
				{
					echo "  [$name] FAILED to create worktree (see $logfile)"
					return 1
				}
		fi
	else
		workdir="$REPO"
		branch="(in-place)"
	fi

	margs=()
	[[ -n "$bmodel" ]] && margs=(-m "$bmodel")

	echo "  launching [$name]  ->  branch: $branch  model: ${bmodel:-default}  timeout: $btimeout"
	# Run in a subshell so the job's exit status is Kimi's exit status. We must
	# `exit $rc` as the very last action — otherwise a trailing echo (exit 0) would
	# mask a failed agent and it'd be wrongly reported as OK.
	(
		echo "=== brief: $brief ==="
		echo "=== started: $(date) ==="
		echo
		cd "$workdir" || exit 98
		timeout -k 10 "$bsecs" kimi "${PRINT_ARGS[@]}" "${margs[@]}" "${OUTPUT_FMT_ARGS[@]}" -p "$prompt"
		rc=$?
		echo
		echo "=== finished: $(date) (exit $rc) ==="
		exit $rc
	) >>"$logfile" 2>&1 &

	NAMES+=("$name")
	PIDS+=("$!")
	WORKDIRS+=("$workdir")
	BRANCHES+=("$branch")
	SCHEMAS+=("$bschema")
	START_EPOCHS+=("$(date +%s)")
	PROMPTS+=("$prompt")
	BMODELS+=("$bmodel")
	BSECS+=("$bsecs")
	return 0
}

# throttle helper
wait_for_slot() {
	[[ $MAX_PARALLEL -le 0 ]] && return 0
	while :; do
		local alive=0
		for p in "${PIDS[@]}"; do kill -0 "$p" 2>/dev/null && alive=$((alive + 1)); done
		[[ $alive -lt $MAX_PARALLEL ]] && return 0
		sleep 1
	done
}

for brief in "${BRIEFS[@]}"; do
	wait_for_slot
	if run_one "$brief"; then
		run_count=$((run_count + 1))
	else
		failed_prelaunch=$((failed_prelaunch + 1))
	fi
done

echo
echo "Waiting for $run_count agent(s) to finish..."
echo

log_tail_matches_quota() { # LOGFILE -> 0 if quota/auth failure text present
	# Marker set aligned with subagent-kimi-guard.sh (proven kimi failure strings).
	# 429 must carry HTTP context — bare 429 matches line numbers/byte counts.
	tail -n 20 "$1" 2>/dev/null | awk '{ l = tolower($0) }
	l ~ /quota|rate[_ ]limit|rpm limit|too many requests|(status|http|code|error)[: ]+429|termios|unauthorized|not logged in|auth[._ ]?error|api key .*(invalid|expired)/ { found = 1 }
	END { exit !found }'
}

failed=0
quota_seen=0
partial=0
repaired=0
mkdir -p "$REPO/.kimi-runs"
for i in "${!PIDS[@]}"; do
	if wait "${PIDS[$i]}"; then
		rc=0
		status="OK"
		schema="${SCHEMAS[$i]}"
		if [[ -n "$schema" && "$SCHEMA_MODE" != "warn" ]]; then
			python3 "$SCRIPT_DIR/validate_output.py" \
				"$RESULTS_DIR/${NAMES[$i]}.log" "$schema" \
				--out "$RESULTS_DIR/${NAMES[$i]}.partial.json"
			vrc=$?

			if [[ $vrc -ne 0 && $REPAIR -eq 1 ]]; then
				rep_log="$RESULTS_DIR/${NAMES[$i]}.repair.log"
				if [[ -f "$RESULTS_DIR/${NAMES[$i]}.partial.json" ]]; then
					rep_err="$(cat "$RESULTS_DIR/${NAMES[$i]}.partial.json")"
				else
					rep_err="No valid JSON object could be extracted."
				fi

				rep_prompt="${PROMPTS[$i]}

Your previous reply failed JSON schema validation:
$rep_err
Reply with ONLY one JSON object that satisfies the schema. No prose."

				rep_margs=()
				[[ -n "${BMODELS[$i]}" ]] && rep_margs=(-m "${BMODELS[$i]}")

				echo "  [${NAMES[$i]}] schema validation failed (exit $vrc), attempting repair..."

				(
					cd "${WORKDIRS[$i]}" || exit 98
					timeout -k 10 "${BSECS[$i]}" kimi "${PRINT_ARGS[@]}" "${rep_margs[@]}" "${OUTPUT_FMT_ARGS[@]}" -p "$rep_prompt"
				) >"$rep_log" 2>&1

				# re-validate against repair output
				python3 "$SCRIPT_DIR/validate_output.py" \
					"$rep_log" "$schema" \
					--out "$RESULTS_DIR/${NAMES[$i]}.partial.json"
				vrc=$?
				if [[ $vrc -eq 0 ]]; then
					repaired=$((repaired + 1))
				fi
			fi

			case "$SCHEMA_MODE:$vrc" in
			*:0) status="OK" ;;
			salvage:2)
				status="PARTIAL(schema)"
				partial=$((partial + 1))
				;;
			*)
				status="FAILED(schema)"
				failed=$((failed + 1))
				;;
			esac
		elif [[ -n "$schema" && "$SCHEMA_MODE" == "warn" ]]; then
			if ! python3 "$SCRIPT_DIR/validate_output.py" \
				"$RESULTS_DIR/${NAMES[$i]}.log" "$schema" \
				--out "$RESULTS_DIR/${NAMES[$i]}.partial.json" >/dev/null 2>&1; then
				if [[ -f "$RESULTS_DIR/${NAMES[$i]}.partial.json" ]]; then
					echo "  warn: [${NAMES[$i]}] schema violations (see ${NAMES[$i]}.partial.json)"
				else
					echo "  warn: [${NAMES[$i]}] no JSON object extractable from log"
				fi
			fi
		fi
	else
		rc=$?
		# 124 = timeout via SIGTERM; 137 = the -k SIGKILL grace path (agent
		# ignored TERM). Both are wall-clock kills, not agent errors.
		if [[ $rc -eq 124 || $rc -eq 137 ]]; then
			status="FAILED(timeout)"
		elif log_tail_matches_quota "$RESULTS_DIR/${NAMES[$i]}.log"; then
			status="FAILED(quota)"
			quota_seen=1
		else
			status="FAILED(exit)"
		fi
		failed=$((failed + 1))
	fi
	printf "  %-16s [%s]  branch: %-24s log: %s\n" \
		"$status" "${NAMES[$i]}" "${BRANCHES[$i]}" "$RESULTS_DIR/${NAMES[$i]}.log"

	end_epoch=$(date +%s)
	secs=$((end_epoch - ${START_EPOCHS[$i]}))
	jq -cn \
		--arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
		--arg run "$TS" \
		--arg name "${NAMES[$i]}" \
		--arg status "$status" \
		--argjson rc "$rc" \
		--argjson secs "$secs" \
		'{ts: $ts, run: $run, name: $name, status: $status, rc: $rc, secs: $secs}' >>"$REPO/.kimi-runs/summary.jsonl" 2>/dev/null || true
done

if [[ $quota_seen -eq 1 ]]; then
	echo "hint: quota/auth failures detected — fall back to agy-delegate or native subagents (delegation policy)."
fi

echo
if [[ $USE_WORKTREE -eq 1 ]]; then
	echo "Review a branch:   git -C \"$REPO\" diff $BASE_REF..kimi/<name>"
	echo "Merge a branch:    git -C \"$REPO\" merge kimi/<name>"
	echo "Clean up worktree: git -C \"$REPO\" worktree remove \"$RESULTS_DIR/worktrees/<name>\""
fi
# PARTIAL counts as succeeded by design (salvaged output is reviewable), but is
# surfaced here so a salvaged run is never mistaken for a fully clean one.
if [[ $REPAIR -eq 1 ]]; then
	echo "Done. $((run_count - failed))/$((run_count + failed_prelaunch)) agent(s) succeeded ($partial partial) ($repaired repaired)."
else
	echo "Done. $((run_count - failed))/$((run_count + failed_prelaunch)) agent(s) succeeded ($partial partial)."
fi
echo "summary: $REPO/.kimi-runs/summary.jsonl"
# Exit = failure count, capped: 256 failures would wrap to exit 0.
total_failed=$((failed + failed_prelaunch))
[[ $total_failed -gt 254 ]] && total_failed=254
exit $total_failed
