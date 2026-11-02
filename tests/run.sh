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
expect "full: model, 1M badge, version" "$l1" "🤖 Opus 1M v2.1.314"
expect "full: directory" "$l1" "📁 claude-pulse"
expect "full: worktree" "$l1" "🌳 my-feature"
expect "full: PR with changes requested" "$l1" "🔀 #1234 ✘"
expect "full: PR is an OSC 8 link" "$raw" "${esc}]8;;https://github.com/moictab/claude-pulse/pull/1234${bel}#1234${esc}]8;;${bel}"
expect "full: context" "$l1" "📊 45k/1.0m ░░░░░░░░ 4% !200k"
expect "full: thinking" "$l1" "🧠 thinking ✔"
expect "full: effort" "$l1" "🎯 high"
expect "full: output style" "$l1" "🎨 Explanatory"
expect "full: fast mode" "$l1" "🚀 fast"
expect "full: agent" "$l1" "🧩 security-reviewer"
expect "full: 5h limit with reset time" "$l2" "⚡ 5h █░░░░ 30% @3:15pm"
expect "full: 7d limit with reset date" "$l2" "7d ███░░ 73% @nov 6, 2:10pm"
expect "full: gateway spend limit" "$l2" '💳 $314.12/$500.00 ███░░ 63% @nov 13'
expect "full: extra usage from cache" "$l2" '💰 $23.37/$42.50 ██░░░'
expect "full: cost, duration, lines" "$l2" '💵 $0.40 · 12m · +156/-23'
expect "full: prompt cache" "$l2" "🔥 1h 91%"

# ---- First render: no usage yet, nulls everywhere ----
out=$(CLAUDE_PULSE_CACHE_DIR="$tmp/cache-empty" statusline < "$fixtures/statusline-minimal.json" | strip)
equal  "minimal: one line" "$(line_count "$out")" 1
expect "minimal: model and version" "$out" "🤖 Sonnet v2.1.314"
expect "minimal: empty context" "$out" "📊 0/200k ░░░░░░░░ 0%"
expect "minimal: thinking off" "$out" "🧠 thinking ✘"
reject "minimal: default output style hidden" "$out" "🎨"
reject "minimal: no effort" "$out" "🎯"
reject "minimal: no fast mode" "$out" "🚀"

# ---- Variants of the full payload ----
variant() { jq "$1" "$fixtures/statusline-full.json" | statusline | strip; }

out=$(variant '.rate_limits.five_hour.resets_at = "2026-11-02T15:15:00Z" | .rate_limits.seven_day.resets_at = "2026-11-06T14:10:00.123+00:00"')
expect "ISO 8601 resets_at (older Claude Code): 5h" "$out" "30% @3:15pm"
expect "ISO 8601 resets_at (older Claude Code): 7d" "$out" "73% @nov 6, 2:10pm"

out=$(variant '.pr = {number: 42, url: "https://gitlab.com/g/p/-/merge_requests/42", review_state: "approved", kind: "mr"}')
expect "GitLab MR uses ! and shows approval" "$out" "🔀 !42 ✔"

out=$(variant 'del(.pr, .worktree, .workspace.git_worktree) | .prompt_cache.warm = false')
reject "no PR segment without pr" "$out" "🔀"
reject "no worktree segment without worktree" "$out" "🌳"
expect "cold prompt cache" "$out" "🧊 cold 91%"

out=$(variant 'del(.workspace) | .cwd = "/srv/legacy-project"')
expect "falls back to cwd without workspace" "$out" "📁 legacy-project"

raw=$(jq '.workspace.current_dir = "C:\\Users\\dev\\repos\\my-repo"' "$fixtures/statusline-full.json" | statusline)
expect "Windows path basename" "$(printf '%s\n' "$raw" | strip)" "📁 my-repo"
reject "Windows path does not leak a carriage return" "$raw" $'\r'

out=$(variant '.context_window.used_percentage = 95')
expect "context bar turns full and red at 95%" "$out" "███████░ 95%"

out=$(variant 'del(.rate_limits, .cost, .prompt_cache)' | sed -n 2p)
expect "line 2 keeps extra usage when nothing else is present" "$out" "💰"

# ---- Git branch and dirty marker ----
repo="$tmp/repo"
git init -q -b main "$repo"
git -C "$repo" -c user.name=test -c user.email=test@example.com commit -q --allow-empty -m init
payload=$(jq --arg dir "$repo" '.workspace.current_dir = $dir' "$fixtures/statusline-minimal.json")
out=$(CLAUDE_PULSE_CACHE_DIR="$tmp/cache-empty" statusline <<<"$payload" | strip)
expect "git: branch" "$out" "📁 repo@🌿 main"
reject "git: clean tree has no dirty marker" "$out" "main*"
: > "$repo/untracked.txt"
out=$(CLAUDE_PULSE_CACHE_DIR="$tmp/cache-empty" statusline <<<"$payload" | strip)
expect "git: untracked file marks the tree dirty" "$out" "🌿 main*"

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
expect "subagents: running row" "$r1" "● reviewer (code-reviewer) · opus 5.5 high · 48k ░░░░░ 4% ▁▃▃▇▄█▅ · "
expect "subagents: label after the stats" "$r1" " · Reading src/auth/session.ts"
if printf '%s\n' "$r1" | grep -Eq ' · [0-9]+h [0-9]+m · '; then pass; else fail "subagents: elapsed time" "got: $r1"; fi
equal  "subagents: completed row" "$(line 2 "$rows")" "✔ Explore · haiku 4.5 · 150k ███░░ 75% · Find status line callers"
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
