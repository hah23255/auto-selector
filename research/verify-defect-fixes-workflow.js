export const meta = {
  name: 'verify-defect-fixes',
  description: 'Adversarially review the 3 modified hook/delegation scripts for real defects',
  phases: [
    { title: 'Find', detail: '3 dimension-specific reviewers' },
    { title: 'Verify', detail: 'skeptic vote per finding' },
  ],
}

const FILES = `
CHANGED FILES (live paths):
- /data/data/com.termux/files/home/.claude/hooks/task-gate.sh (rewritten: word-boundary matching via bash punctuation-to-space normalization loop + space-bounded case globs; pass-event telemetry in fallback; dedup unchanged)
- /data/data/com.termux/files/home/.claude/hooks/state-reinject.sh (added: rm -f of task-gate-$SID.state after SID extraction)
- /data/data/com.termux/files/home/.claude/skills/kimi-delegate/scripts/kimi_parallel.sh (added: --timeout flag w/ validation, timeout -k 10 wrapper on kimi call, FAILED(timeout|quota|exit) classification via awk tail scan, dup-name check, awk-based show_help, host shebang)
PRE-CHANGE BACKUPS for diffing:
- /data/data/com.termux/files/home/.claude/backups/phase2-defect-fixes-20260710/*.pre
CONTEXT: Termux/Android host. plain grep/find are glibc-shadowed and BROKEN in hook context — scripts must not rely on them (awk/tail/jq/bash-globs OK). task-gate runs on EVERY user prompt (UserPromptSubmit, must always exit 0, fail-open, <10s timeout). Prompts can contain arbitrary UTF-8 incl. Bulgarian Cyrillic (aliases like делегирай must keep matching). kimi_parallel launches background subshells and waits on PIDs.
`

const FINDINGS = {
  type: 'object', required: ['findings'],
  properties: { findings: { type: 'array', items: {
    type: 'object', required: ['file', 'summary', 'scenario'],
    properties: { file: {type:'string'}, summary: {type:'string'}, scenario: {type:'string'} } } } }
}
const VERDICT = { type: 'object', required: ['refuted', 'reason'], properties: { refuted: {type:'boolean'}, reason: {type:'string'} } }

const DIMS = [
  { key: 'bash-correctness', prompt: `Review these bash scripts for CORRECTNESS bugs introduced by the recent changes: quoting/word-splitting, bash pattern-substitution edge cases (the punctuation loop in task-gate.sh — does \${p//"$c"/ } behave with chars like backslash, backtick, asterisk?), set -u interactions with new variables, exit-code propagation through subshells and the timeout wrapper, wait/$? semantics in the classification loop of kimi_parallel.sh. Read the changed files AND diff against the .pre backups. Report only defects with a concrete failing input; ignore style. ${FILES}` },
  { key: 'matching-semantics', prompt: `Review the archetype matcher in task-gate.sh for SEMANTIC regressions vs the .pre backup: aliases that matched before (incl. inflections and multi-word phrases like "doesn't work", "settings.json", Bulgarian делегирай/поправи/бъг/грешка/проучи/намери/направи/добави/създай/напиши) but can NO LONGER match after word-boundary normalization; punctuation cases where normalization breaks a multi-word alias; UTF-8/Cyrillic hazards in tr or bash globs; prompts >400 chars truncation interaction with the padding. For each: give the exact prompt string that misroutes and what it returns now vs before. Ignore intended changes (prefix/preview/suffix/failover/Hooks_project must now be silent or non-fix; that is the fix, not a bug). ${FILES}` },
  { key: 'runtime-behavior', prompt: `Review kimi_parallel.sh (and the two hook scripts) for RUNTIME hazards introduced by the changes: the timeout -k 10 wrapper (does rc=124 reliably reach the classification loop through the subshell? what about rc=137 KILL after grace? busy vs idle SIGTERM handling), the log_tail_matches_quota awk (false positives on innocent logs, e.g. a brief that legitimately mentions "quota"; broken pipes), the dup-name check subshell (does it handle briefs in different dirs with same basename? spaces in paths?), and state-reinject.sh's rm -f (any case where SID contains characters that would glob or escape?). Report only defects with a concrete failing scenario. ${FILES}` },
]

phase('Find')
const results = await pipeline(
  DIMS,
  d => agent(d.prompt, { label: `find:${d.key}`, phase: 'Find', schema: FINDINGS, effort: 'high' }),
  (r, d) => {
    const fs = (r && r.findings) ? r.findings : []
    log(`${d.key}: ${fs.length} candidate finding(s)`)
    return parallel(fs.map(f => () =>
      parallel([1, 2, 3].map(i => () =>
        agent(`Adversarially try to REFUTE this claimed defect (skeptic #${i}). Read the actual file and, if possible, construct and run the failing input via Bash to check whether it actually fails. Default to refuted=true unless you can demonstrate or strongly argue the failure is real.\nFILE: ${f.file}\nCLAIM: ${f.summary}\nSCENARIO: ${f.scenario}\n${FILES}`,
          { label: `verify:${d.key}#${i}`, phase: 'Verify', schema: VERDICT, effort: 'high' })
      )).then(votes => {
        const real = votes.filter(Boolean).filter(v => !v.refuted).length >= 2
        return { ...f, dim: d.key, real, votes: votes.filter(Boolean).map(v => v.reason) }
      })
    ))
  }
)
const all = results.filter(Boolean).flat().filter(Boolean)
return {
  confirmed: all.filter(f => f.real),
  refuted: all.filter(f => !f.real).map(f => ({ file: f.file, summary: f.summary })),
}