# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

claude-pulse is two standalone Bash scripts for Claude Code:

- `statusline.sh`: the `statusLine` command. Claude Code pipes the session JSON to it on stdin. It prints two lines, plus a third `agents` line while subagents are listed.
- `subagent-statusline.sh`: the `subagentStatusLine` command. It receives `{session_id, columns, cwd, tasks: [...]}` on stdin about every 5 seconds while the agent panel lists subagents. It writes one `{"id", "content"}` JSON line per row, and saves its input for the `agents` line.

`jq` is required. `git` and `curl` are optional. There is no build step. Users install by curling the scripts straight from `main` on GitHub (see README), so anything merged to `main` ships to users right away.

The stdin schemas are documented at https://code.claude.com/docs/en/statusline (see "Available data" and "Subagent status lines"). Check there before adding or changing fields.

## Commands

```bash
bash tests/run.sh                                              # all tests; offline, uses a temp HOME and cache
shellcheck statusline.sh subagent-statusline.sh tests/run.sh   # lint
bash statusline.sh < tests/fixtures/statusline-full.json       # render a fixture by hand
bash subagent-statusline.sh < tests/fixtures/subagents.json
bash docs/make-preview.sh                                      # regenerate docs/preview.svg (needs python3)
```

`tests/run.sh` is a list of `expect`/`reject`/`equal` assertions on ANSI-stripped output. Run it with `TZ=UTC LC_ALL=C`, as it already does. To check a single case, render the fixture by hand or comment out the other assertions; there is no per-test runner. Under GitHub Actions, failures are also printed as `::error` annotations, which the public API serves without auth (`/repos/moictab/claude-pulse/check-runs/<job id>/annotations`), unlike job logs.

CI (`.github/workflows/ci.yml`) runs on every push. It runs shellcheck, then the tests on:
- ubuntu-22.04 (jq 1.6)
- ubuntu-24.04 (jq 1.7.1, GNU coreutils)
- ubuntu-latest (26.04, Rust uutils coreutils)
- macOS (with `/bin/bash` 3.2)
- Windows (Git Bash)

Local runs on Windows use jq 1.8, which accepts things that 1.6 and 1.7 reject (see the jq rules below), so a green local run doesn't prove CI will pass.

`docs/preview.svg` (the README image) is generated from the scripts' real output by `docs/make-preview.sh` and `docs/ansi2svg.py`. Regenerate it when the visible output changes.

The version lives in `CLAUDE_PULSE_VERSION` in both scripts (`--version` prints it). Bump both, add a `CHANGELOG.md` entry, and tag `vX.Y.Z` after merging (see CONTRIBUTING.md).

Running the scripts by hand outside the tests uses the real cache in `${TMPDIR:-/tmp}/claude`. `statusline.sh` may start a background request to the OAuth usage endpoint. `subagent-statusline.sh` overwrites `subagents-<session_id>.json` there, which can show a fake agents line in a live session with the same id. Set `CLAUDE_PULSE_CACHE_DIR` to keep it elsewhere.

## statusline.sh architecture

1. Read stdin with `IFS= read -r -d '' input`, not `cat`.
2. Make **one** `jq` call that turns every field into `name='value'` lines with `@sh`, then `eval` them. Formatting (token counts, money, durations, epoch conversion) happens inside that jq program. To add a field, add a key to the jq object and use `$key` in bash. shellcheck's SC2154 is disabled file-wide because of this `eval`.
3. Segments are appended with `add1` (line 1: session) or `add2` (line 2: limits and cost). Both join with `$sep`. Print with `printf '%s\n'`. Line 2 is omitted when empty. The script always exits 0.
4. Line 3 (`agents`) is built by a second, separate jq program. It only runs when `$cache_dir/subagents-<session_id>.json` exists (falling back to `subagents-default.json`) and is at most `agents_max_age` (15) seconds old. The status line itself never receives subagent data; `subagent-statusline.sh` writes that file atomically on every panel tick (about 5 seconds, measured on v2.1.316). It picks the widest of three layouts that fits `$COLUMNS`: names with elapsed time, names only, then counts. With `COLUMNS` unset it uses the widest. `subagents-*.json` files older than a day are deleted in the background, at most once a minute (with the usage refresh).

Visual style. The user chose this deliberately after the emoji version looked messy, so keep it:
- It matches Claude Code's own footer. No emoji. Labels (`ctx`, `5h`, `cache`, ...), separators and reset times are `$dim`. Values use the default text color.
- Color only carries meaning: blue for the model, green for the branch and added lines, red for the dirty `*` and removed lines, yellow for warnings (`200k+`, `fast`, `no thinking`, `cold`). Bars go from green to red. The palette is blue, green, orange, yellow, red and dim; there is no cyan or white.
- Hide what is always true. Thinking only shows as `no thinking`, and context shows only the percentage, not absolute tokens.
- Reset times use `↻` with a 24-hour clock for 5h, and `9 nov` dates for 7d and spend. The style is chosen by window, not by "now", so output stays deterministic in tests.

Conventions:
- Colors are `$'\033[...]'` variables holding real escape bytes, and output is printed with `%s`, so backslashes in data (Windows paths) are never interpreted. Don't go back to `printf "%b"`.
- Optional fields default to `""` in jq and their segment is added only when non-empty. Guard numbers with `num` (null → empty). `current_usage`, `used_percentage` and `hit_ratio` can be `null`.
- `build_bar <pct> <width>` sets the global `$bar` (no subshell). It draws a colored `━` filled part, rounded to the nearest cell, and a dim `─` empty part. Width is 10 for context and 5 for everything else. Colors: green below 50, orange from 50, yellow from 70, red from 90. `subagent-statusline.sh` has the same `bar` in jq.
- `resets_at` is Unix epoch seconds. The jq `epoch` helper also accepts ISO 8601 strings from older Claude Code versions. `format_epoch` tries BSD `date -r` and then GNU `date -d @`, each checked on its own. Never put the first attempt in a pipeline before `||`: the pipeline's exit status comes from its last command, so the fallback would never run.
- Git uses a single `git status --porcelain=v2 --branch` call for both the branch and the dirty state.
- The extra-usage segment is the only network use. It calls the undocumented `/api/oauth/usage` endpoint, which the user chose to keep. It renders from the cache and refreshes in a background subshell with stdio redirected to `/dev/null`. Claude Code cancels a status line run that is still going when the next update arrives, so the script must never block on the network. `CLAUDE_PULSE_EXTRA_USAGE=0` (or `false`, `off`, `no`) skips both the token lookup and the request.
- Native `jq.exe` on Windows writes CRLF. `statusline.sh` strips `\r` from the jq output, and `subagent-statusline.sh` pipes through `tr -d '\r'`.
- Keep everything bash 3.2 compatible: no `${var,,}`, `mapfile`, associative arrays or `printf -v` namerefs.
- Keep every jq program jq 1.6 compatible. The first two points below broke the subagent rows on Ubuntu's jq while local jq 1.8 passed:
  - Never name a variable after a keyword. `$label` is a syntax error in jq 1.6.
  - Parenthesize before `as`. `(x) + reset as $icon | ...` binds `as` to `reset` alone, and jq 1.7 then adds a string to the final object. Write `((x) + reset) as $icon`.
  - The Windows build of jq 1.6 lacks `strptime`, so `fromdateiso8601` fails there. Only the legacy ISO `resets_at` path uses it, inside `try`.

## subagent-statusline.sh architecture

The whole renderer is one `jq -c` program. Colors are zero-arity defs (`def blue: ...;`). For each task it builds candidate layouts from richest to leanest and picks the first one that is narrower than `columns`, measured with ANSI codes stripped. The label fills the remaining width and is truncated with `…`. If jq is missing or fails, the script prints nothing and Claude Code keeps its default rows.

Subagents can only be displayed, not managed, from these scripts. The docs offer no external stop or message API. The README's "Managing subagents" section lists Claude Code's built-in controls.

## Repo hygiene

- `.gitattributes` forces LF for `*.sh`, `*.py`, `*.json`, `*.yml` and `*.svg`, because bash breaks on CRLF and this repo is developed on Windows with `core.autocrlf=true`.
- The scripts are tracked as executable (mode 100755). Keep that when adding scripts (`git update-index --chmod=+x`).
- The repo is public. `README.md` is written for end users; it has the segment tables, the Privacy, Troubleshooting and Configuration sections, and the color block. Update them, and the fixtures and tests, whenever a segment, setting or env var changes.
- CONTRIBUTING.md, SECURITY.md, CHANGELOG.md, and the issue and PR templates in `.github/` exist too. Keep them consistent with any change to setup, privacy or versioning.
