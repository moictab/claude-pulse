# Changelog

All notable changes to claude-pulse are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [2.0.0] - 2026-11-02

A rewrite for the current Claude Code status line schema, with a new look and subagent support.

### Added

- **Subagents.** A third status line shows each subagent's state, name and elapsed time while the agent panel lists any. The new `subagent-statusline.sh` (for the `subagentStatusLine` setting) also redraws the panel rows with model, effort, context usage, activity and elapsed time.
- New segments: worktree, open PR or GitLab MR with its review state (clickable), fast mode, `--agent` name, gateway spend limit, session cost, session duration, lines added/removed, and prompt cache hit ratio.
- `--version` on both scripts.
- `CLAUDE_PULSE_EXTRA_USAGE=0` turns off the extra usage segment, so the scripts make no network requests and never read the OAuth token.
- `CLAUDE_PULSE_CACHE_DIR` sets the cache directory.
- A clear `claude-pulse: jq not found` message instead of a broken status line.
- Test suite and CI on Ubuntu 22.04, 24.04 and 26.04, macOS and Windows.

### Changed

- New design matching Claude Code's own footer: no emoji, dim labels, ` · ` separators, thin color-coded bars, and color only where it means something. Output is now two lines, plus the agents line.
- Context shows only the percentage. Thinking is shown only when it is off. `!200k` is now a yellow `200k+`.
- Reset times use a 24-hour clock for the 5-hour limit and a date for the 7-day limit.
- Extra usage is fetched in the background, so a slow request never delays the status line.
- About 2.7x faster on Windows: one `jq` call to read all fields instead of about twenty, and one `git` call.
- The cache directory is `${TMPDIR:-/tmp}/claude`, which is still `/tmp/claude` on most Linux systems.

### Fixed

- 5-hour and 7-day reset times never showed on Linux or Windows. Claude Code sends them as Unix timestamps, and the GNU `date` fallback never ran.
- Directory names with backslashes (Windows paths) could print escape sequences.
- Native `jq.exe` on Windows wrote CRLF line endings into the output.
- Thinking was reported as off when neither Claude Code nor `settings.json` said either way.
- The script is executable in git, and LF line endings are enforced, so Windows checkouts work with bash.

## [1.0.0] - 2026-04-28

The original single-line status line with emoji: model, version, directory, git branch, context usage, thinking, effort, output style, 5-hour and 7-day limits, and extra usage. Released from `main` without a tag.

[2.0.0]: https://github.com/moictab/claude-pulse/compare/3fe05a0...v2.0.0
[1.0.0]: https://github.com/moictab/claude-pulse/tree/3fe05a0
