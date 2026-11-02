#!/bin/bash
# Regenerate docs/preview.svg from the scripts' real output with sample data.
# Usage: bash docs/make-preview.sh   (needs bash, jq, git and python3; runs offline)

set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export TZ=UTC LC_ALL=C HOME="$tmp/home" CLAUDE_PULSE_CACHE_DIR="$tmp/cache" COLUMNS=140
mkdir -p "$HOME" "$CLAUDE_PULSE_CACHE_DIR"

# A project on a feature branch with uncommitted work
repo="$tmp/myproject"
git init -q -b feature/login "$repo"
git -C "$repo" -c user.name=preview -c user.email=preview@example.com commit -q --allow-empty -m init
: > "$repo/wip.txt"

# A fresh extra-usage cache, so nothing is fetched
echo '{"extra_usage":{"is_enabled":true,"utilization":55,"used_credits":2337,"monthly_limit":4250}}' \
    > "$CLAUDE_PULSE_CACHE_DIR/statusline-usage-cache.json"

now_ms=$(( $(date +%s) * 1000 ))

# Agent panel input; rendering it also saves it for the status line's agents line
rows=$(jq -n --argjson now "$now_ms" --arg cwd "$repo" '{
    session_id: "preview", cwd: $cwd, columns: 118,
    tasks: [
      {id: "1", name: "reviewer", type: "local_agent", agentType: "code-reviewer", status: "running",
       label: "Checking token refresh paths in src/auth/session.ts", startTime: ($now - 128000),
       model: "claude-opus-5-5", effort: "high", contextWindowSize: 1000000, tokenCount: 48200,
       tokenSamples: [1000, 1000, 5000, 9000, 20000, 26000, 40000, 48200], cwd: $cwd},
      {id: "2", name: "test-runner", type: "local_agent", agentType: "general-purpose", status: "running",
       label: "Running the auth test suite", startTime: ($now - 41000),
       model: "claude-sonnet-5-5", effort: "medium", contextWindowSize: 1000000, tokenCount: 21900,
       tokenSamples: [3000, 6000, 8000, 15000, 17000, 21900], cwd: $cwd},
      {id: "3", type: "local_agent", agentType: "Explore", status: "completed",
       label: "Find every caller of refreshToken()", startTime: ($now - 300000),
       model: "claude-haiku-4-5", contextWindowSize: 200000, tokenCount: 150000, tokenSamples: [150000], cwd: $cwd},
      {id: "4", name: "builder", type: "local_agent", agentType: "general-purpose", status: "failed",
       label: "Build in an isolated worktree", startTime: ($now - 90000),
       model: "claude-sonnet-5-5", tokenCount: 950, tokenSamples: [], cwd: ($cwd + "/.claude/worktrees/builder")}
    ]}' | bash "$root/subagent-statusline.sh" | jq -r .content | tr -d '\r')

status=$(jq -n --arg cwd "$repo" '{
    session_id: "preview",
    model: {id: "claude-opus-5-5", display_name: "Opus 5.5"}, version: "2.1.316",
    workspace: {current_dir: $cwd},
    context_window: {context_window_size: 1000000, used_percentage: 42},
    exceeds_200k_tokens: true, effort: {level: "xhigh"}, thinking: {enabled: true},
    pr: {number: 128, url: "https://github.com/acme/myproject/pull/128", review_state: "approved"},
    rate_limits: {five_hour: {used_percentage: 34, resets_at: 1793639400},
                  seven_day: {used_percentage: 61, resets_at: 1794211200}},
    cost: {total_cost_usd: 7.21, total_duration_ms: 4320000, total_lines_added: 1046, total_lines_removed: 351},
    prompt_cache: {warm: true, caching_observed: true, ttl: "1h", hit_ratio: 0.96}
  }' | bash "$root/statusline.sh")

{
    echo "---status line"
    printf '%s\n' "$status"
    echo "---agent panel"
    printf '%s\n' "$rows"
} | python3 "$root/docs/ansi2svg.py" > "$root/docs/preview.svg"

echo "wrote docs/preview.svg"
