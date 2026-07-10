#!/data/data/com.termux/files/usr/bin/bash
# brief_lib.sh — pure helper functions for kimi_parallel.sh (no side effects on
# source). Vendored from agy-delegate/scripts/agy_lib.sh (v0.1.1) with fixes:
# duration arithmetic forces base-10 (leading zeros are NOT octal) and rejects 0
# (GNU `timeout 0` means NO limit). NOTE: agy_lib.sh upstream still has the
# octal bug — port these fixes there.

fm_get() { # FILE KEY -> print frontmatter value or nothing
	awk -v key="$2" '
    NR==1 && $0 != "---" { exit }
    NR==1 { infm=1; next }
    infm && $0 == "---" { exit }
    infm && index($0, key ":") == 1 {
      v = substr($0, length(key) + 2)
      sub(/^[ \t]+/, "", v); print v; exit
    }' "$1"
}

brief_body() { # FILE -> print brief with frontmatter stripped
	awk '
    NR==1 && $0 != "---" { nofm=1 }
    nofm { print; next }
    NR==1 { infm=1; buf[bn++]=$0; next }
    infm && $0 == "---" { infm=0; body=1; bn=0; next }
    infm { buf[bn++]=$0; next }
    body { print }
    END { if (infm) for (i=0; i<bn; i++) print buf[i] }' "$1"
}

lint_brief() { # FILE -> 0 if all required sections present, else 1 + stderr
	local f="$1" missing=""
	local sec
	for sec in "## Goal" "## Scope" "## Requirements" "## Verification"; do
		if ! awk -v s="$sec" '{ line=$0; sub(/[ \t]+$/, "", line) } line == s { found=1 } END { exit !found }' "$f"; then
			missing="$missing $sec;"
		fi
	done
	if [[ -n "$missing" ]]; then
		echo "error: brief $f is missing required sections:$missing (drop --lint to bypass)" >&2
		return 1
	fi
	return 0
}

sanitize_name() { # printf avoids trailing-newline artifacts (kimi lesson)
	printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-'
}

duration_secs_checked() { # Ns/Nm/Nh or bare seconds -> print secs; 1 if invalid/zero
	local d="$1" secs
	case "$d" in
	'' | *[!0-9hms]*) return 1 ;;
	*[hms]*[hms]*) return 1 ;;
	*[hms]) case "${d%?}" in '' | *[!0-9]*) return 1 ;; esac ;;
	*) case "$d" in *[!0-9]*) return 1 ;; esac ;;
	esac
	case "$d" in
	*h) secs=$((10#${d%h} * 3600)) ;;
	*m) secs=$((10#${d%m} * 60)) ;;
	*s) secs=$((10#${d%s})) ;;
	*) secs=$((10#$d)) ;;
	esac
	[[ $secs -gt 0 ]] || return 1
	printf '%s' "$secs"
}
