# claude-pulse

[![CI](https://github.com/moictab/claude-pulse/actions/workflows/ci.yml/badge.svg)](https://github.com/moictab/claude-pulse/actions/workflows/ci.yml)

A feature-rich status line for [Claude Code](https://code.claude.com/docs/en/overview) that shows real-time session info at a glance, plus custom rows for the subagent panel.

```
🤖 Opus 1M v2.1.314 | 📁 myproject@🌿 main* | 🔀 #1234 ✘ | 📊 45k/1.0m ░░░░░░░░ 4% | 🧠 thinking ✔ | 🎯 high
⚡ 5h █░░░░ 30% @3:15pm | 7d ███░░ 73% @nov 6, 2:10pm | 💰 $23.37/$42.50 ██░░░ | 💵 $0.40 · 12m · +156/-23 | 🔥 1h 91%
```

Subagent panel:

```
● reviewer (code-reviewer) · opus 5.5 high · 48k ░░░░░ 4% ▁▃▃▇▄█▅ · 2m 8s · Reading src/auth/session.ts and checking t…
✔ Explore · haiku 4.5 · 150k ███░░ 75% · Find status line callers
```

## What it shows

Segments only appear when Claude Code sends their data, so the line stays short when there is nothing to report.

### Line 1: session

| Segment | Emoji | Description |
|---------|-------|-------------|
| **Model** | 🤖 | Current model name, a `1M` badge on 1M-token context windows, and the Claude Code version |
| **Directory** | 📁 | Current working directory |
| **Git branch** | 🌿 | Current branch with a red `*` for uncommitted or untracked changes |
| **Worktree** | 🌳 | Worktree name when the session runs in a git worktree |
| **Pull request** | 🔀 | Open PR for the branch (`!` for GitLab merge requests), clickable, with its review state: green ✔ approved, yellow ● pending, red ✘ changes requested, `draft` |
| **Context usage** | 📊 | Tokens in context with a color-coded bar and percentage, plus a red `!200k` once the session crosses the 200k pricing tier |
| **Thinking** | 🧠 | Extended thinking status (green ✔ / red ✘) |
| **Effort** | 🎯 | Reasoning effort (`low` / `medium` / `high` / `xhigh` / `max`) on models that support it |
| **Output style** | 🎨 | Active output style (hidden when `default`) |
| **Fast mode** | 🚀 | Shown while fast mode is on |
| **Agent** | 🧩 | Agent name when Claude Code runs with `--agent` |

### Line 2: limits and cost

| Segment | Emoji | Description |
|---------|-------|-------------|
| **5h usage** | ⚡ | 5-hour rate limit with progress bar and local reset time (Pro/Max) |
| **7d usage** | | 7-day rate limit with progress bar and local reset date (Pro/Max) |
| **Spend limit** | 💳 | Spend and limit in dollars with a progress bar and reset date, behind a Claude apps gateway |
| **Extra usage** | 💰 | Extra usage credits spent vs. monthly limit, if enabled on your account |
| **Session cost** | 💵 | Estimated session cost, session duration and lines added/removed |
| **Prompt cache** | 🔥 / 🧊 | Whether the prompt cache is warm (with its 5m/1h TTL) or cold, and the session's cache hit ratio |

### Subagent rows

`subagent-statusline.sh` replaces the default row of each subagent in the panel below the prompt:

| Part | Description |
|------|-------------|
| **Status** | Yellow ● running, green ✔ completed, red ✘ failed, ⊘ stopped |
| **Name** | Subagent name and, in parentheses, its type (`Explore`, `Plan`, or a custom agent) |
| **Model** | Short model name and effort, e.g. `opus 5.5 high` |
| **Tokens** | Token count with a context bar and percentage |
| **Activity** | Sparkline of tokens added per refresh, while running |
| **Elapsed** | Time since the subagent started, while running |
| **Directory** | `@dir` when the subagent works in its own directory, such as an isolated worktree |
| **Task** | Progress summary, truncated to the panel width |

When the panel is narrow, the row drops the activity sparkline, directory, model and elapsed time, in that order, so it still fits on one line.

## Requirements

- [Claude Code](https://code.claude.com/docs/en/overview). Newer fields need recent versions, for example v2.1.251+ for the prompt cache and v2.1.293+ for subagent types. Missing fields simply hide their segment.
- `bash` 3.2 or later (the macOS system bash works)
- [`jq`](https://jqlang.org/download/) **(required)**:

  | OS | Install |
  |----|---------|
  | macOS | `brew install jq` |
  | Debian / Ubuntu | `sudo apt install jq` |
  | Fedora | `sudo dnf install jq` |
  | Windows | `winget install jqlang.jq` |

  Without `jq`, the status line only shows `claude-pulse: jq not found`.
- `git` (optional): branch and dirty marker
- `curl` (optional): extra usage segment (💰)

On Windows, Claude Code runs status line commands with Git Bash, which comes with [Git for Windows](https://gitforwindows.org/). If the status line still says `jq not found` after installing it, restart Claude Code so it picks up the new `PATH`.

## Installation

1. Download both scripts to your Claude config directory:

```bash
mkdir -p ~/.claude
curl -fsSL -o ~/.claude/statusline.sh https://raw.githubusercontent.com/moictab/claude-pulse/main/statusline.sh
curl -fsSL -o ~/.claude/subagent-statusline.sh https://raw.githubusercontent.com/moictab/claude-pulse/main/subagent-statusline.sh
chmod +x ~/.claude/statusline.sh ~/.claude/subagent-statusline.sh
```

2. Add them to your Claude Code settings (`~/.claude/settings.json`):

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline.sh",
    "refreshInterval": 30
  },
  "subagentStatusLine": {
    "type": "command",
    "command": "bash ~/.claude/subagent-statusline.sh"
  }
}
```

`refreshInterval` is optional. It re-runs the status line every N seconds, which keeps reset times and extra usage current while the session is idle. Without it, the status line only updates on events such as a new message. `padding` (number of characters) is also supported.

3. The status line appears at the bottom of Claude Code on its next update. To update claude-pulse later, run step 1 again.

## Managing subagents

The status line scripts only display subagents. Claude Code has no API for an external script to stop or message one, so you manage them with Claude Code's own controls:

| Where | Action |
|-------|--------|
| Agent panel | `↑` / `↓` to select a row, `Enter` to open its transcript and send it follow-up messages, `x` to stop it (or dismiss a finished row), `Esc` to go back to the prompt |
| `/tasks` | View and manage background work in the session, including subagents that have finished |
| `Ctrl+B` | Send running subagents and Bash commands to the background |
| `Ctrl+X Ctrl+K` | Stop all running background subagents (press twice within 3 seconds to confirm) |

You can cap how many subagents run at once with the `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` environment variable (default 20), and block a subagent type with a permission rule such as `"deny": ["Agent(Explore)"]`. See the [subagents documentation](https://code.claude.com/docs/en/sub-agents) for details.

## Features

### Color-coded progress bars

Progress bars change color based on usage level:
- **Green**: under 50%
- **Orange**: 50-69%
- **Yellow**: 70-89%
- **Red**: 90%+

### Rate limits

The 5-hour and 7-day rate limits, and the gateway spend limit, are read directly from the JSON Claude Code sends on stdin. No API call is needed. Reset times are shown in your local timezone.

### Extra usage

The extra usage segment (💰) is the only one that needs a network request, because Claude Code does not send that data on stdin. It reads your Claude Code OAuth token locally and calls the Anthropic OAuth usage endpoint (`https://api.anthropic.com/api/oauth/usage`), which is undocumented and may change without notice. The token is sent only to `api.anthropic.com`.

The response is cached for 60 seconds at `${TMPDIR:-/tmp}/claude/statusline-usage-cache.json`. Set `CLAUDE_PULSE_CACHE_DIR` to use another directory. The cache is refreshed in the background, so a slow request never delays the status line.

The OAuth token is resolved from, in order:
- `CLAUDE_CODE_OAUTH_TOKEN` environment variable
- macOS Keychain
- Linux and Windows credentials file (`~/.claude/.credentials.json`)
- GNOME Keyring

### Cross-platform

Works on macOS (BSD `date`, bash 3.2), Linux (GNU `date`) and Windows (Git Bash). CI runs the test suite on all three.

## Customization

The scripts use ANSI 24-bit (truecolor) escape codes. To change the colors, edit the variables at the top of `statusline.sh`:

```bash
blue=$'\033[38;2;0;153;255m'
orange=$'\033[38;2;255;176;85m'
green=$'\033[38;2;0;160;0m'
cyan=$'\033[38;2;46;149;153m'
red=$'\033[38;2;255;85;85m'
yellow=$'\033[38;2;230;200;0m'
white=$'\033[38;2;220;220;220m'
```

The subagent rows use the same palette, defined as `def blue: ...;` functions at the top of the `jq` program in `subagent-statusline.sh`.

## Development

```bash
bash tests/run.sh                                         # tests (needs jq and git, runs offline)
shellcheck statusline.sh subagent-statusline.sh tests/run.sh
```

The tests pipe the JSON fixtures in `tests/fixtures/` through both scripts and check the rendered output.

## License

MIT
