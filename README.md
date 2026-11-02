# claude-pulse

[![CI](https://github.com/moictab/claude-pulse/actions/workflows/ci.yml/badge.svg)](https://github.com/moictab/claude-pulse/actions/workflows/ci.yml)

A clean, information-dense status line for [Claude Code](https://code.claude.com/docs/en/overview), plus custom rows for the subagent panel.

```
Opus 5.5 1M v2.1.316 · myproject@main* · PR #1234 ✘ · ctx ━━━─────── 29% 200k+ · xhigh
5h ━──── 12% ↻17:10 · 7d ───── 1% ↻9 nov · extra $23.37/$42.50 ━━━── 55% · $7.21 · 12h 5m · +1046 −351 · cache 96%
agents ● reviewer 2m 8s · ● Plan 4s · ✔ Explore · ✘ builder
```

Subagent panel:

```
● reviewer (code-reviewer) · opus 5.5 high · 48k ───── 4% ▁▃▃▇▄█▅ · 2m 8s · Reading src/auth/session.ts and checking t…
✔ Explore · haiku 4.5 · 150k ━━━━─ 75% · Find status line callers
```

It follows the look of Claude Code's own footer: no emoji, dim labels, ` · ` separators, and color only where it means something (the model in blue, the branch in green, warnings in yellow or red, and bars that go from green to red as they fill).

## What it shows

The model and context segments are always there. The rest only appear when Claude Code sends their data, so the line stays short when there is nothing to report.

### Line 1: session

| Segment | Example | Description |
|---------|---------|-------------|
| **Model** | `Opus 5.5 1M v2.1.316` | Current model, `1M` on 1M-token context windows, and the Claude Code version |
| **Directory and branch** | `myproject@main*` | Working directory and git branch, with a red `*` for uncommitted or untracked changes |
| **Worktree** | `worktree my-feature` | Worktree name when the session runs in a git worktree |
| **Pull request** | `PR #1234 ✘` | Open PR for the branch (`MR !42` for GitLab), clickable, with its review state: green ✔ approved, yellow ● pending, red ✘ changes requested, `draft` |
| **Context** | `ctx ━━━─────── 29% 200k+` | Context window usage, plus a yellow `200k+` once the session crosses the 200k pricing tier |
| **Thinking** | `no thinking` | Only shown when extended thinking is off |
| **Effort** | `xhigh` | Reasoning effort on models that support it |
| **Output style** | `style Explanatory` | Active output style (hidden when `default`) |
| **Fast mode** | `fast` | Shown while fast mode is on |
| **Agent** | `agent reviewer` | Agent name when Claude Code runs with `--agent` |

### Line 2: limits and cost

| Segment | Example | Description |
|---------|---------|-------------|
| **5h usage** | `5h ━──── 12% ↻17:10` | 5-hour rate limit and the local time it resets (Pro/Max) |
| **7d usage** | `7d ───── 1% ↻9 nov` | 7-day rate limit and the date it resets (Pro/Max) |
| **Spend limit** | `spend $314.12/$500.00 ━━━── 63% ↻13 nov` | Spend and limit behind a Claude apps gateway |
| **Extra usage** | `extra $23.37/$42.50 ━━━── 55%` | Extra usage credits spent vs. monthly limit, if enabled on your account |
| **Session cost** | `$7.21 · 12h 5m · +1046 −351` | Estimated session cost, session duration and lines added/removed |
| **Prompt cache** | `cache 96%` | Session cache hit ratio, with a yellow `cold` when the cache has expired |

### Line 3: subagents

While subagents are listed in the agent panel, a third line shows each one's state and name, and how long the running ones have been working: yellow ● running, green ✔ done, red ✘ failed, dim ⊘ stopped. If the line is wider than the terminal (`$COLUMNS`, which Claude Code sets), it drops the times first and then switches to counts (`agents ● 2 running · ✔ 3 done`).

Claude Code sends subagent data only to the `subagentStatusLine` command, so this line needs `subagent-statusline.sh` installed too. That script runs about every 5 seconds while the panel lists subagents, and saves the rows to the cache directory, one file per session. `statusline.sh` reads that file and hides the line once it is more than 15 seconds old, which means the panel is empty.

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

  Without `jq`, the status line only shows `claude-pulse: jq not found (https://jqlang.org/download/)`.
- `git` (optional): branch and dirty marker
- `curl` (optional): extra usage segment

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
    "refreshInterval": 5
  },
  "subagentStatusLine": {
    "type": "command",
    "command": "bash ~/.claude/subagent-statusline.sh"
  }
}
```

`refreshInterval` is optional but recommended. Without it, the status line only updates on events such as a new message, so it goes quiet while Claude waits for subagents. With it, the status line re-runs every N seconds. 5 matches how often Claude Code refreshes the agent panel, which keeps the agents line and its timers current. A larger value costs less CPU, at the price of a staler agents line. `padding` (number of characters) is also supported.

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

Bars are thin lines: the filled part `━` changes color with usage, and the empty part `─` stays dim.
- **Green**: under 50%
- **Orange**: 50-69%
- **Yellow**: 70-89%
- **Red**: 90%+

### Rate limits

The 5-hour and 7-day rate limits, and the gateway spend limit, are read directly from the JSON Claude Code sends on stdin. No API call is needed. Reset times (`↻`) are in your local timezone: a 24-hour clock for the 5-hour limit, and a date for the others.

### Extra usage

The extra usage segment is the only one that needs a network request, because Claude Code does not send that data on stdin. It reads your Claude Code OAuth token locally and calls the Anthropic OAuth usage endpoint (`https://api.anthropic.com/api/oauth/usage`), which is undocumented and may change without notice. The token is sent only to `api.anthropic.com`.

The response is cached for 60 seconds at `${TMPDIR:-/tmp}/claude/statusline-usage-cache.json`. Set `CLAUDE_PULSE_CACHE_DIR` to use another directory. The cache is refreshed in the background, so a slow request never delays the status line. The same directory holds the per-session `subagents-*.json` files for the agents line. Files older than a day are deleted during the refresh.

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
blue=$'\033[38;2;0;153;255m'    # model
green=$'\033[38;2;0;160;0m'     # branch, lines added, approved PR, bars under 50%
orange=$'\033[38;2;255;176;85m' # bars from 50%
yellow=$'\033[38;2;230;200;0m'  # warnings (200k+, fast, no thinking, cold cache), pending PR, bars from 70%
red=$'\033[38;2;255;85;85m'     # dirty marker, lines removed, changes requested, bars from 90%
dim=$'\033[2m'                  # labels, separators, reset times
```

`jq` programs can't read shell variables, so the agents line (at the end of `statusline.sh`) and the subagent rows (`subagent-statusline.sh`) define the same colors as `def green: ...;` functions. Change them there too.

## Development

```bash
bash tests/run.sh                                         # tests (needs jq and git, runs offline)
shellcheck statusline.sh subagent-statusline.sh tests/run.sh
```

The tests pipe the JSON fixtures in `tests/fixtures/` through both scripts and check the rendered output.

## License

MIT
