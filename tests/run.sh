#!/bin/bash
# Tests for statusline.sh and subagent-statusline.sh. Usage: bash tests/run.sh
# Needs bash, jq and git. Runs offline with a throwaway HOME and usage cache.

# Expected strings with dollar amounts ('$0.40') are single-quoted on purpose.
# shellcheck disable=SC2016

set -u

root=$(cd "$(dirname "$0")/.." && pwd)
fixtures="$root/tests/fixtures"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export TZ=UTC LC_ALL=C HOME="$tmp/home"
unset CLAUDE_CODE_OAUTH_TOKEN
mkdir -p "$HOME" "$tmp/cache" "$tmp/cache-empty"
# A fresh cache file means no refresh is attempted for 60s, so the tests never touch the network
cp "$fixtures/usage-cache.json" "$tmp/cache/statusline-usage-cache.json"
: > "$tmp/cache-empty/statusline-usage-cache.json"
export CLAUDE_PULSE_CACHE_DIR="$tmp/cache"

esc=$'\033'
bel=$'\a'
passed=0
failed=0

# Native jq.exe on Windows writes CRLF; normalize the jq calls made by the tests themselves
jq() { command jq "$@" | tr -d '\r'; }

statusline() { "$BASH" "$root/statusline.sh"; }
subagents() { "$BASH" "$root/subagent-statusline.sh"; }

# Remove color codes and OSC 8 link wrappers
strip() { sed "s/${esc}\[[0-9;]*m//g; s/${esc}]8;;[^${bel}]*${bel}//g"; }
line() { printf '%s\n' "$2" | sed -n "${1}p"; }
line_count() { printf '%s' "$1" | awk 'END { print NR }'; }

pass() { passed=$((passed + 1)); }
fail() { failed=$((failed + 1)); printf 'FAIL: %s\n' "$1"; shift; printf '  %s\n' "$@"; }

expect() {  # <description> <text> <substring>
    if [[ "$2" == *"$3"* ]]; then pass; else fail "$1" "expected: ...$3..." "got:      $2"; fi
}
reject() {  # <description> <text> <substring>
    if [[ "$2" != *"$3"* ]]; then pass; else fail "$1" "unexpected: $3" "got:        $2"; fi
}
equal() {  # <description> <actual> <expected>
    if [ "$2" = "$3" ]; then pass; else fail "$1" "expected: $3" "got:      $2"; fi
}

# ===== statusline.sh =====

# ---- Full payload ----
raw=$(statusline < "$fixtures/statusline-full.json")
out=$(printf '%s\n' "$raw" | strip)
l1=$(line 1 "$out")
l2=$(line 2 "$out")
equal  "full: two lines" "$(line_count "$out")" 2
expect "full: model, 1M badge, version" "$l1" "Opus 1M v2.1.314 · "
expect "full: directory" "$l1" " · claude-pulse · "
expect "full: worktree" "$l1" " · worktree my-feature · "
expect "full: PR with changes requested" "$l1" " · PR #1234 ✘ · "
expect "full: PR is an OSC 8 link" "$raw" "${esc}]8;;https://github.com/moictab/claude-pulse/pull/1234${bel}#1234${esc}]8;;${bel}"
expect "full: context bar, percentage, 200k tier" "$l1" " · ctx ────────── 4% 200k+ · "
reject "full: tokens are not shown in absolute numbers" "$l1" "45k"
reject "full: thinking hidden while on" "$l1" "thinking"
expect "full: effort, style, fast mode, agent" "$l1" " · high · style Explanatory · fast · agent security-reviewer"
expect "full: 5h limit with reset time" "$l2" "5h ━━─── 30% ↻15:15 · "
expect "full: 7d limit with reset date" "$l2" " · 7d ━━━━─ 73% ↻6 nov · "
expect "full: gateway spend limit" "$l2" ' · spend $314.12/$500.00 ━━━── 63% ↻13 nov · '
expect "full: extra usage from cache" "$l2" ' · extra $23.37/$42.50 ━━━── 55% · '
expect "full: cost, duration, lines" "$l2" ' · $0.40 · 12m · +156 −23 · '
expect "full: prompt cache" "$l2" " · cache 91%"
if printf '%s' "$out" | LC_ALL=C grep -q $'\xf0\x9f'; then fail "full: no emoji" "got: $out"; else pass; fi

# ---- First render: no usage yet, nulls everywhere ----
out=$(CLAUDE_PULSE_CACHE_DIR="$tmp/cache-empty" statusline < "$fixtures/statusline-minimal.json" | strip)
equal  "minimal: one line" "$(line_count "$out")" 1
equal  "minimal: whole line" "$out" "Sonnet v2.1.314 · project · ctx ────────── 0% · no thinking"

# ---- Variants of the full payload ----
variant() { jq "$1" "$fixtures/statusline-full.json" | statusline | strip; }

out=$(variant 'del(.thinking)')
reject "thinking: unknown without settings means on" "$out" "no thinking"
mkdir -p "$HOME/.claude"
echo '{"alwaysThinkingEnabled": false}' > "$HOME/.claude/settings.json"
out=$(variant 'del(.thinking)')
expect "thinking: off in settings when stdin doesn't say" "$out" " · no thinking · "
rm -f "$HOME/.claude/settings.json"

out=$(variant '.rate_limits.five_hour.resets_at = "2026-11-02T15:15:00Z" | .rate_limits.seven_day.resets_at = "2026-11-06T14:10:00.123+00:00"')
expect "ISO 8601 resets_at (older Claude Code): 5h" "$out" "30% ↻15:15"
expect "ISO 8601 resets_at (older Claude Code): 7d" "$out" "73% ↻6 nov"

out=$(variant '.pr = {number: 42, url: "https://gitlab.com/g/p/-/merge_requests/42", review_state: "approved", kind: "mr"}')
expect "GitLab MR uses ! and shows approval" "$out" " · MR !42 ✔ · "

out=$(variant 'del(.pr, .worktree, .workspace.git_worktree) | .prompt_cache.warm = false')
reject "no PR segment without pr" "$out" "PR "
reject "no worktree segment without worktree" "$out" "worktree"
expect "cold prompt cache" "$out" " · cache cold 91%"

out=$(variant 'del(.workspace) | .cwd = "/srv/legacy-project"')
expect "falls back to cwd without workspace" "$out" " · legacy-project · "

raw=$(jq '.workspace.current_dir = "C:\\Users\\dev\\repos\\my-repo"' "$fixtures/statusline-full.json" | statusline)
expect "Windows path basename" "$(printf '%s\n' "$raw" | strip)" " · my-repo · "
reject "Windows path does not leak a carriage return" "$raw" $'\r'

out=$(variant '.context_window.used_percentage = 95')
expect "context bar fills up at 95%" "$out" "ctx ━━━━━━━━━━ 95%"
out=$(variant '.context_window.used_percentage = 75')
expect "context bar rounds to the nearest cell" "$out" "ctx ━━━━━━━━── 75%"

out=$(variant 'del(.rate_limits, .cost, .prompt_cache)' | sed -n 2p)
equal "line 2 keeps extra usage when nothing else is present" "$out" 'extra $23.37/$42.50 ━━━── 55%'

# ---- Git branch and dirty marker ----
repo="$tmp/repo"
git init -q -b main "$repo"
git -C "$repo" -c user.name=test -c user.email=test@example.com commit -q --allow-empty -m init
payload=$(jq --arg dir "$repo" '.workspace.current_dir = $dir' "$fixtures/statusline-minimal.json")
out=$(CLAUDE_PULSE_CACHE_DIR="$tmp/cache-empty" statusline <<<"$payload" | strip)
expect "git: branch" "$out" " · repo@main · "
reject "git: clean tree has no dirty marker" "$out" "main*"
: > "$repo/untracked.txt"
out=$(CLAUDE_PULSE_CACHE_DIR="$tmp/cache-empty" statusline <<<"$payload" | strip)
expect "git: untracked file marks the tree dirty" "$out" " · repo@main* · "

# ---- Subagent summary (line 3), fed by subagent-statusline.sh through the cache ----
agents_cache="$tmp/cache-agents"
mkdir -p "$agents_cache"
: > "$agents_cache/statusline-usage-cache.json"
now_ms=$(( $(date +%s) * 1000 ))
jq --argjson now "$now_ms" '.tasks[0].startTime = $now - 128000 | .tasks[3].startTime = $now - 4000' \
    "$fixtures/subagents.json" | CLAUDE_PULSE_CACHE_DIR="$agents_cache" subagents > /dev/null
equal "summary: panel rows saved per session" "$(jq -r .session_id "$agents_cache/subagents-abc123.json")" "abc123"
out=$(COLUMNS=200 CLAUDE_PULSE_CACHE_DIR="$agents_cache" statusline < "$fixtures/statusline-full.json" | strip)
equal "summary: third line" "$(line_count "$out")" 3
l3=$(line 3 "$out")
if printf '%s\n' "$l3" | grep -Eq '^agents ● reviewer 2m [0-9]+s · ✔ Explore · ✘ builder · ● Plan [0-9]+s · ⊘ Explore$'; then
    pass
else
    fail "summary: states, names and elapsed time" "got: $l3"
fi
out=$(COLUMNS=60 CLAUDE_PULSE_CACHE_DIR="$agents_cache" statusline < "$fixtures/statusline-full.json" | strip | sed -n 3p)
equal "summary: counts when the names don't fit" "$out" "agents ● 2 running · ✘ 1 failed · ✔ 1 done · ⊘ 1 stopped"
out=$(jq '.session_id = "other-session"' "$fixtures/statusline-full.json" | CLAUDE_PULSE_CACHE_DIR="$agents_cache" statusline | strip)
equal "summary: other sessions don't show it" "$(line_count "$out")" 2
touch -t 202001010000 "$agents_cache/subagents-abc123.json"
out=$(CLAUDE_PULSE_CACHE_DIR="$agents_cache" statusline < "$fixtures/statusline-full.json" | strip)
equal "summary: hidden once the panel stops refreshing it" "$(line_count "$out")" 2

# ---- Degraded input ----
equal "empty stdin" "$(printf '' | statusline)" "Claude"
equal "invalid JSON" "$(echo 'not json' | statusline)" "Claude"
equal "jq missing" "$(PATH=/nonexistent statusline < "$fixtures/statusline-minimal.json")" \
    "claude-pulse: jq not found (https://jqlang.org/download/)"

# ===== subagent-statusline.sh =====

out=$(subagents < "$fixtures/subagents.json")
equal "subagents: one JSON line per task" "$(line_count "$out")" 5
equal "subagents: ids echoed in order" "$(printf '%s\n' "$out" | jq -r .id | tr '\n' ' ')" "t1 t2 t3 t4 t5 "
rows=$(printf '%s\n' "$out" | jq -r .content | strip)
r1=$(line 1 "$rows")
expect "subagents: running row" "$r1" "● reviewer (code-reviewer) · opus 5.5 high · 48k ───── 4% ▁▃▃▇▄█▅ · "
expect "subagents: label after the stats" "$r1" " · Reading src/auth/session.ts"
if printf '%s\n' "$r1" | grep -Eq ' · [0-9]+h [0-9]+m · '; then pass; else fail "subagents: elapsed time" "got: $r1"; fi
equal  "subagents: completed row" "$(line 2 "$rows")" "✔ Explore · haiku 4.5 · 150k ━━━━─ 75% · Find status line callers"
equal  "subagents: failed row in its own dir" "$(line 3 "$rows")" "✘ builder (general-purpose) · sonnet 5.5 32k tok · 950 · @builder · Build in worktree"
reject "subagents: label equal to the name is not repeated" "$(line 4 "$rows")" "· Plan"
expect "subagents: no activity sparkline when idle" "$(line 4 "$rows")" "● Plan · 0 · "
equal  "subagents: killed row" "$(line 5 "$rows")" "⊘ Explore · 10 · Search for callers"

widths=$(jq '.columns = 40' "$fixtures/subagents.json" | subagents \
    | jq -r '.content | gsub("\u001b\\[[0-9;]*m"; "") | length' | sort -n | tail -1)
if [ "$widths" -lt 40 ]; then pass; else fail "subagents: rows fit in 40 columns" "widest row: $widths"; fi

equal "subagents: no tasks" "$(echo '{"columns":80,"tasks":[]}' | subagents)" ""
equal "subagents: invalid JSON" "$(echo 'not json' | subagents)" ""
equal "subagents: jq missing" "$(PATH=/nonexistent subagents < "$fixtures/subagents.json")" ""

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
