# claude-pulse

A feature-rich status line for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that displays real-time session info at a glance.

## What it shows

| Segment | Emoji | Description |
|---------|-------|-------------|
| **Model** | 🤖 | Current model name (e.g., Claude Opus 4.7) |
| **1M context** | | `1M` badge when running on a 1M-token context window |
| **Version** | | Claude Code CLI version |
| **Directory** | 📁 | Current working directory |
| **Git branch** | 🌿 | Current branch with red `*` for uncommitted changes |
| **Context usage** | 📊 | Token count with a color-coded progress bar and percentage |
| **200k+ flag** | | Red `!200k` indicator when the session has crossed the 200k pricing tier |
| **Thinking** | 🧠 | Extended thinking status (green ✔ / red ✘) |
| **Effort** | 🎯 | Reasoning effort level (`low` / `medium` / `high` / `xhigh` / `max`) when supported by the model |
| **Output style** | 🎨 | Active output style (hidden when `default`) |
| **5h usage** | ⚡ | 5-hour rate limit with progress bar and reset time (Pro/Max) |
| **7d usage** | | 7-day rate limit with progress bar and reset time (Pro/Max) |
| **Extra usage** | 💰 | Extra usage credits spent vs. limit (if enabled) |

### Example output

```
🤖 Claude Opus 4.7 1M v2.1.117 | 📁 myproject@🌿 main* | 📊 45k/1.0m █░░░░░░░ 4% | 🧠 thinking ✔ | 🎯 high | ⚡ 5h ██░░░ 30% @2:15pm | 7d █░░░░ 12% @may 5, 9:00am | 💰 $0.00/$42.50
```

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- `jq` for JSON parsing
- `curl` for API usage fetching (optional, for rate limit bars)
- `git` (optional, for branch/dirty detection)

## Installation

1. Copy the script to your Claude config directory:

```bash
mkdir -p ~/.claude
curl -o ~/.claude/statusline.sh https://raw.githubusercontent.com/moictab/claude-pulse/main/statusline.sh
chmod +x ~/.claude/statusline.sh
```

2. Add the status line to your Claude Code settings (`~/.claude/settings.json`):

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline.sh"
  }
}
```

3. Restart Claude Code. The status line will appear at the bottom of your terminal.

## Features

### Color-coded progress bars

Progress bars change color based on usage level:
- **Green** — under 50%
- **Orange** — 50-69%
- **Yellow** — 70-89%
- **Red** — 90%+

### Rate limits

5-hour and 7-day rate limits are read directly from the status line JSON Claude Code provides on stdin (Pro/Max accounts only) — no API call required.

### Extra usage caching

The extra-usage segment (💰) is fetched from the Anthropic OAuth usage endpoint and cached for 60 seconds at `/tmp/claude/statusline-usage-cache.json` to avoid excessive API calls. This is the only segment that still requires a network request.

### Cross-platform OAuth

Automatically resolves OAuth tokens from:
- `CLAUDE_CODE_OAUTH_TOKEN` environment variable
- macOS Keychain
- Linux credentials file (`~/.claude/.credentials.json`)
- GNOME Keyring

### Cross-platform date handling

Reset times are formatted in your local timezone, with support for both GNU date (Linux) and BSD date (macOS).

## Customization

The script uses ANSI 24-bit (truecolor) escape codes. You can customize colors by editing the variables at the top of `statusline.sh`:

```bash
blue='\033[38;2;0;153;255m'
orange='\033[38;2;255;176;85m'
green='\033[38;2;0;160;0m'
cyan='\033[38;2;46;149;153m'
red='\033[38;2;255;85;85m'
yellow='\033[38;2;230;200;0m'
white='\033[38;2;220;220;220m'
```

## License

MIT
