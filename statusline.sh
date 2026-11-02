#!/bin/bash
# claude-pulse: two-line status line for Claude Code, styled like Claude Code's own footer:
# dim labels, " · " separators, and color only where it carries meaning.
# Line 1: model · dir@branch · worktree · PR · context · thinking off · effort · style · fast · agent
# Line 2: 5h · 7d · spend limit · extra usage · cost · duration · lines · prompt cache
# Line 3: agents ● running · ✔ done · ✘ failed (only while subagents are listed)

# Most fields are assigned by `eval "$fields"` below, which shellcheck cannot follow.
# shellcheck disable=SC2154

set -f  # disable globbing

CLAUDE_PULSE_VERSION="2.0.0"
if [ "${1:-}" = "--version" ]; then
    printf 'claude-pulse %s\n' "$CLAUDE_PULSE_VERSION"
    exit 0
fi

IFS= read -r -d '' input  # all of stdin, without spawning cat

if [ -z "$input" ]; then
    printf 'Claude\n'
    exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
    printf 'claude-pulse: jq not found (https://jqlang.org/download/)\n'
    exit 0
fi

# ANSI truecolor codes. $'...' stores the real escape byte, so output is printed with %s
# and backslashes in data (e.g. Windows paths) are never interpreted.
blue=$'\033[38;2;0;153;255m'
green=$'\033[38;2;0;160;0m'
orange=$'\033[38;2;255;176;85m'
yellow=$'\033[38;2;230;200;0m'
red=$'\033[38;2;255;85;85m'
dim=$'\033[2m'
reset=$'\033[0m'

sep=" ${dim}·${reset} "

# ===== Extract every field in a single jq call =====
# Each line is a shell assignment quoted with @sh, so eval is safe.
fields=$(jq -r '
    def num: if type == "number" then . else empty end;
    def round0: . + 0.5 | floor;
    def money:
        (. * 100 | round0) as $c
        | "\($c / 100 | floor).\($c % 100 | tostring | if length < 2 then "0" + . else . end)";
    def dur:
        (. / 1000 | floor) as $s
        | if $s >= 3600 then "\($s / 3600 | floor)h \($s % 3600 / 60 | floor)m"
          elif $s >= 60 then "\($s / 60 | floor)m"
          else "\($s)s" end;
    # resets_at is Unix epoch seconds; ISO 8601 strings are accepted for older Claude Code versions
    def epoch:
        if type == "number" then floor
        elif type == "string" then (try (sub("\\.[0-9]+"; "") | sub("[+-]00:00$"; "Z") | fromdateiso8601) catch empty)
        else empty end;

    (.context_window // {}) as $cw
    | ($cw.context_window_size // 0 | if . > 0 then . else 200000 end) as $size
    | ($cw.current_usage
        | if . then (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)
          else ($cw.total_input_tokens // 0) end) as $used
    | {
        now_epoch: (now | floor),
        session_id: (.session_id // "" | gsub("[^A-Za-z0-9_-]"; "")),
        model_name: (.model.display_name // .model.id // "Claude"),
        claude_version: (.version // ""),
        cwd: (.workspace.current_dir // .cwd // ""),
        ctx_size: $size,
        ctx_pct: (($cw.used_percentage | num) // ($used * 100 / $size) | floor),
        exceeds_200k: (.exceeds_200k_tokens // false),
        thinking_stdin: (.thinking.enabled | if . == null then "" else . end),
        effort_level: (.effort.level // ""),
        output_style: (.output_style.name // ""),
        fast_mode: (.fast_mode // false),
        agent_name: (.agent.name // ""),
        worktree_name: (.worktree.name // .workspace.git_worktree // ""),
        pr_number: (.pr.number // ""),
        pr_url: (.pr.url // ""),
        pr_state: (.pr.review_state // ""),
        pr_kind: (.pr.kind // ""),
        five_pct: ((.rate_limits.five_hour.used_percentage | num | round0) // ""),
        five_reset: ((.rate_limits.five_hour.resets_at | epoch) // ""),
        seven_pct: ((.rate_limits.seven_day.used_percentage | num | round0) // ""),
        seven_reset: ((.rate_limits.seven_day.resets_at | epoch) // ""),
        spend_pct: ((.rate_limits.spend_limit.used_percentage | num | round0) // ""),
        spend_reset: ((.rate_limits.spend_limit.resets_at | epoch) // ""),
        spend_used: ((.rate_limits.spend_limit.used_usd | num | money) // ""),
        spend_limit: ((.rate_limits.spend_limit.limit_usd | num | money) // ""),
        cost_usd: ((.cost.total_cost_usd | num | money) // ""),
        duration: ((.cost.total_duration_ms | num | dur) // ""),
        lines_added: (.cost.total_lines_added // 0),
        lines_removed: (.cost.total_lines_removed // 0),
        cache_observed: (.prompt_cache.caching_observed // false),
        cache_warm: (.prompt_cache.warm // false),
        cache_hit: ((.prompt_cache.hit_ratio | num | . * 100 | round0) // "")
      }
    | to_entries[]
    | "\(.key)=\(.value | tostring | @sh)"
' <<<"$input" 2>/dev/null)
fields="${fields//$'\r'/}"  # native jq.exe on Windows writes CRLF

if [ -z "$fields" ]; then
    printf 'Claude\n'
    exit 0
fi
eval "$fields"

# Build a thin progress bar into $bar: filled ━ colored by usage level, empty ─ dimmed
# Usage: build_bar <pct> <width>
build_bar() {
    local pct=$1
    local width=$2
    [ "$pct" -lt 0 ] 2>/dev/null && pct=0
    [ "$pct" -gt 100 ] 2>/dev/null && pct=100

    local filled=$(( (pct * width + 50) / 100 ))
    local empty=$(( width - filled ))

    local bar_color
    if [ "$pct" -ge 90 ]; then bar_color="$red"
    elif [ "$pct" -ge 70 ]; then bar_color="$yellow"
    elif [ "$pct" -ge 50 ]; then bar_color="$orange"
    else bar_color="$green"
    fi

    local filled_str="" empty_str="" i
    for ((i=0; i<filled; i++)); do filled_str+="━"; done
    for ((i=0; i<empty; i++)); do empty_str+="─"; done

    bar="${bar_color}${filled_str}${reset}${dim}${empty_str}${reset}"
}

# Format epoch seconds as local time (17:10) or date (9 nov)
# Usage: format_epoch <epoch> <style: time|date>
format_epoch() {
    local epoch=$1 fmt out
    [ -z "$epoch" ] && return
    case "$2" in
        time) fmt="%H:%M" ;;
        *)    fmt="%-d %b" ;;
    esac
    # BSD date (macOS) takes -r <epoch>; GNU date (Linux, Git Bash) takes -d @<epoch>.
    # Each attempt is checked on its own: inside a pipeline the exit status would come from the last command.
    out=$(date -r "$epoch" +"$fmt" 2>/dev/null) || out=$(date -d "@$epoch" +"$fmt" 2>/dev/null) || return
    printf '%s' "$out" | tr '[:upper:]' '[:lower:]'
}

# Append " ↻<when>" for a reset time, if there is one
# Usage: seg+=$(reset_suffix <epoch> <style>)
reset_suffix() {
    local when
    when=$(format_epoch "$1" "$2")
    [ -n "$when" ] && printf '%s' " ${dim}↻${when}${reset}"
}

# Wrap text in an OSC 8 hyperlink (clickable in terminals that support it)
# Usage: link <url> <text>
link() {
    printf '%s' $'\033]8;;'"$1"$'\a'"$2"$'\033]8;;\a'
}

line1=""
line2=""
line3=""
add1() { line1+="${line1:+$sep}$1"; }
add2() { line2+="${line2:+$sep}$1"; }

# Cache shared by the extra-usage segment and the subagent summary
cache_dir="${CLAUDE_PULSE_CACHE_DIR:-${TMPDIR:-/tmp}/claude}"
cache_dir="${cache_dir%/}"

# Seconds since a file was last modified; prints nothing if it doesn't exist
file_age() {
    local mtime
    mtime=$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null)
    [ -n "$mtime" ] && printf '%s' $(( now_epoch - mtime ))
}

# Thinking status (stdin first, fall back to settings, where a missing alwaysThinkingEnabled means on)
thinking_on=true
if [ "$thinking_stdin" = "false" ]; then
    thinking_on=false
elif [ -z "$thinking_stdin" ]; then
    settings_path="$HOME/.claude/settings.json"
    if [ -f "$settings_path" ]; then
        thinking_val=$(jq -r '.alwaysThinkingEnabled' "$settings_path" 2>/dev/null)
        [ "${thinking_val//$'\r'/}" = "false" ] && thinking_on=false
    fi
fi

# Claude Code version (stdin first, fall back to CLI)
if [ -z "$claude_version" ]; then
    claude_version=$(claude --version 2>/dev/null | head -1 | sed 's/[^0-9.].*//')
fi

# ===== Line 1: session =====
seg="${blue}${model_name}${reset}"
[ "$ctx_size" -ge 1000000 ] 2>/dev/null && seg+=" ${dim}1M${reset}"
[ -n "$claude_version" ] && seg+=" ${dim}v${claude_version}${reset}"
add1 "$seg"

# Current directory and git branch (one git call for both branch and dirty state)
if [ -n "$cwd" ]; then
    # Normalize backslashes to forward slashes (Windows paths) before taking the basename
    cwd_normalized="${cwd//\\//}"
    seg="${cwd_normalized##*/}"

    git_branch="" git_dirty=false
    git_status=$(git -C "$cwd" status --porcelain=v2 --branch 2>/dev/null)
    while IFS= read -r git_line; do
        case "$git_line" in
            '# branch.head '*) git_branch="${git_line#\# branch.head }" ;;
            '#'*) ;;
            ?*) git_dirty=true; break ;;
        esac
    done <<<"$git_status"

    if [ -n "$git_branch" ]; then
        seg+="${dim}@${reset}${green}${git_branch}${reset}"
        $git_dirty && seg+="${red}*${reset}"
    fi
    add1 "$seg"
fi

[ -n "$worktree_name" ] && add1 "${dim}worktree${reset} ${worktree_name}"

# Open PR (or GitLab MR) for the branch, with review state
if [ -n "$pr_number" ]; then
    if [ "$pr_kind" = "mr" ]; then
        seg="${dim}MR${reset} "
        pr_text="!${pr_number}"
    else
        seg="${dim}PR${reset} "
        pr_text="#${pr_number}"
    fi
    [ -n "$pr_url" ] && pr_text=$(link "$pr_url" "$pr_text")
    seg+="$pr_text"
    case "$pr_state" in
        approved)          seg+=" ${green}✔${reset}" ;;
        changes_requested) seg+=" ${red}✘${reset}" ;;
        pending)           seg+=" ${yellow}●${reset}" ;;
        draft)             seg+=" ${dim}draft${reset}" ;;
    esac
    add1 "$seg"
fi

build_bar "$ctx_pct" 10
seg="${dim}ctx${reset} ${bar} ${ctx_pct}%"
[ "$exceeds_200k" = "true" ] && seg+=" ${yellow}200k+${reset}"
add1 "$seg"

# Thinking is always on with current models, so only its absence is worth showing
$thinking_on || add1 "${yellow}no thinking${reset}"
[ -n "$effort_level" ] && add1 "$effort_level"
[ -n "$output_style" ] && [ "$output_style" != "default" ] && add1 "${dim}style${reset} ${output_style}"
[ "$fast_mode" = "true" ] && add1 "${yellow}fast${reset}"
[ -n "$agent_name" ] && add1 "${dim}agent${reset} ${agent_name}"

# ===== Line 2: limits and cost =====
bar_width=5

# 5-hour and 7-day rate limits (from stdin, Pro/Max only)
if [ -n "$five_pct" ]; then
    build_bar "$five_pct" "$bar_width"
    add2 "${dim}5h${reset} ${bar} ${five_pct}%$(reset_suffix "$five_reset" time)"
fi

if [ -n "$seven_pct" ]; then
    build_bar "$seven_pct" "$bar_width"
    add2 "${dim}7d${reset} ${bar} ${seven_pct}%$(reset_suffix "$seven_reset" date)"
fi

# Spend limit (stdin, Claude apps gateway only). Dollar amounts arrive later than the percentage.
if [ -n "$spend_pct" ]; then
    build_bar "$spend_pct" "$bar_width"
    seg="${dim}spend${reset} "
    [ -n "$spend_used" ] && [ -n "$spend_limit" ] && seg+="\$${spend_used}/\$${spend_limit} "
    add2 "${seg}${bar} ${spend_pct}%$(reset_suffix "$spend_reset" date)"
fi

# ---- Extra usage (OAuth /api/oauth/usage; not exposed via stdin) ----
# Tries credential sources in order: env var → macOS Keychain → Linux creds file → GNOME Keyring
get_oauth_token() {
    local token=""

    # 1. Explicit env var override
    if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
        echo "$CLAUDE_CODE_OAUTH_TOKEN"
        return 0
    fi

    # 2. macOS Keychain
    if command -v security >/dev/null 2>&1; then
        local blob
        blob=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
        if [ -n "$blob" ]; then
            token=$(echo "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
            if [ -n "$token" ] && [ "$token" != "null" ]; then
                echo "$token"
                return 0
            fi
        fi
    fi

    # 3. Linux credentials file
    local creds_file="${HOME}/.claude/.credentials.json"
    if [ -f "$creds_file" ]; then
        token=$(jq -r '.claudeAiOauth.accessToken // empty' "$creds_file" 2>/dev/null)
        if [ -n "$token" ] && [ "$token" != "null" ]; then
            echo "$token"
            return 0
        fi
    fi

    # 4. GNOME Keyring via secret-tool
    if command -v secret-tool >/dev/null 2>&1; then
        local blob
        blob=$(timeout 2 secret-tool lookup service "Claude Code-credentials" 2>/dev/null)
        if [ -n "$blob" ]; then
            token=$(echo "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
            if [ -n "$token" ] && [ "$token" != "null" ]; then
                echo "$token"
                return 0
            fi
        fi
    fi

    echo ""
}

cache_file="$cache_dir/statusline-usage-cache.json"
cache_max_age=60  # seconds between API calls

refresh_usage_cache() {
    local token response
    token=$(get_oauth_token)
    [ -n "$token" ] && [ "$token" != "null" ] || return
    response=$(curl -s --max-time 10 \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $token" \
        -H "anthropic-beta: oauth-2025-04-20" \
        -H "User-Agent: claude-code/${claude_version:-unknown}" \
        "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
    if [ -n "$response" ] && jq -e 'type == "object"' >/dev/null 2>&1 <<<"$response"; then
        printf '%s' "$response" > "$cache_file.tmp" && mv -f "$cache_file.tmp" "$cache_file"
    fi
}

# CLAUDE_PULSE_EXTRA_USAGE=0 turns the segment off: no token lookup and no network request
case "${CLAUDE_PULSE_EXTRA_USAGE:-1}" in
    0|false|off|no) extra_usage=false ;;
    *) extra_usage=true ;;
esac

mkdir -p "$cache_dir" 2>/dev/null
cache_age=$(file_age "$cache_file")
# Refresh in the background and render from the cache: Claude Code cancels a status line script
# that is still running when the next update arrives, so it must never wait on the network.
# Touching the cache first marks the attempt, so concurrent runs don't fetch again.
if [ "${cache_age:-$cache_max_age}" -ge "$cache_max_age" ]; then
    touch "$cache_file" 2>/dev/null
    $extra_usage && command -v curl >/dev/null 2>&1 && refresh_usage_cache </dev/null >/dev/null 2>&1 &
    # Subagent files from sessions that ended long ago (at most once a minute, like the refresh)
    find "$cache_dir" -maxdepth 1 -name 'subagents-*.json' -mmin +1440 -exec rm -f {} + </dev/null >/dev/null 2>&1 &
fi

if $extra_usage && [ -s "$cache_file" ]; then
    extra=$(jq -r '
        select(.extra_usage.is_enabled == true) | .extra_usage
        | def money: (. * 100 + 0.5 | floor) as $c
              | "\($c / 100 | floor).\($c % 100 | tostring | if length < 2 then "0" + . else . end)";
          "\(.utilization // 0 | . + 0.5 | floor) \(.used_credits // 0 | . / 100 | money) \(.monthly_limit // 0 | . / 100 | money)"
    ' "$cache_file" 2>/dev/null)
    if [ -n "$extra" ]; then
        read -r extra_pct extra_used extra_limit <<<"$extra"
        build_bar "$extra_pct" "$bar_width"
        add2 "${dim}extra${reset} \$${extra_used}/\$${extra_limit} ${bar} ${extra_pct}%"
    fi
fi

# Session cost, duration and lines changed
[ -n "$cost_usd" ] && add2 "\$${cost_usd}"
[ -n "$duration" ] && add2 "$duration"
if [ "$lines_added" != "0" ] || [ "$lines_removed" != "0" ]; then
    add2 "${green}+${lines_added}${reset} ${red}−${lines_removed}${reset}"
fi

# Prompt cache hit ratio, flagged when the cache has gone cold (only once caching has been seen)
if [ "$cache_observed" = "true" ]; then
    seg="${dim}cache${reset}"
    [ "$cache_warm" = "true" ] || seg+=" ${yellow}cold${reset}"
    [ -n "$cache_hit" ] && seg+=" ${cache_hit}%"
    add2 "$seg"
fi

# ===== Line 3: subagents =====
# Claude Code sends subagent data only to subagent-statusline.sh, which saves it on every panel
# refresh. A file that has not been refreshed lately means the panel has no rows left to show.
agents_max_age=15  # seconds
agents_file="$cache_dir/subagents-${session_id:-default}.json"
[ -f "$agents_file" ] || agents_file="$cache_dir/subagents-default.json"
agents_age=$(file_age "$agents_file")
if [ -n "$agents_age" ] && [ "$agents_age" -le "$agents_max_age" ]; then
    # Widest layout that fits COLUMNS: names with elapsed time, then names only, then counts
    line3=$(jq -r --argjson columns "${COLUMNS:-0}" '
        def green: "\u001b[38;2;0;160;0m";
        def yellow: "\u001b[38;2;230;200;0m";
        def red: "\u001b[38;2;255;85;85m";
        def dim: "\u001b[2m";
        def reset: "\u001b[0m";
        def sep: " \(dim)·\(reset) ";
        def visible_length: gsub("\u001b\\[[0-9;]*m"; "") | length;
        def dur:
            (. / 1000 | floor) as $s
            | if $s >= 3600 then "\($s / 3600 | floor)h \($s % 3600 / 60 | floor)m"
              elif $s >= 60 then "\($s / 60 | floor)m \($s % 60)s"
              else "\($s)s" end;
        def icon:
            (if . == "running" then yellow + "●"
             elif . == "completed" then green + "✔"
             elif . == "failed" then red + "✘"
             elif . == "killed" then dim + "⊘"
             else dim + "○" end) + reset;

        [.tasks[]? | select(.id)] as $tasks
        | select($tasks | length > 0)
        | ($tasks | map((.status // "" | icon) + " " + (.name // .agentType // "agent"))) as $names
        | ($tasks | map(if .status == "running" and .startTime
                        then " " + dim + ([now * 1000 - .startTime, 0] | max | dur) + reset
                        else "" end)) as $elapsed
        | ([range(0; $names | length) | $names[.] + $elapsed[.]]) as $full
        | ([["running", "running"], ["failed", "failed"], ["completed", "done"], ["killed", "stopped"]]
           | map(.[0] as $status | .[1] as $word
                 | ($tasks | map(select(.status == $status)) | length) as $n
                 | select($n > 0)
                 | ($status | icon) + " \($n) \($word)")) as $counts
        | [$full, $names, $counts]
        | map(dim + "agents" + reset + " " + join(sep))
        | if $columns > 0 then first(.[] | select(visible_length < $columns)) // .[-1] else .[0] end
    ' "$agents_file" 2>/dev/null)
    line3="${line3//$'\r'/}"
fi

printf '%s\n' "$line1"
[ -n "$line2" ] && printf '%s\n' "$line2"
[ -n "$line3" ] && printf '%s\n' "$line3"

exit 0
