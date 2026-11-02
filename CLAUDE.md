# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

claude-pulse is two standalone Bash scripts for Claude Code:

- `statusline.sh`: the `statusLine` command. Claude Code pipes the session JSON to it on stdin, and it prints two lines.
- `subagent-statusline.sh`: the `subagentStatusLine` command. It receives `{columns, cwd, tasks: [...]}` on stdin and writes one `{"id", "content"}` JSON line per subagent row in the agent panel.

`jq` is required. `git` and `curl` are optional. There is no build step. Users install by curling the scripts straight from `main` on GitHub (see README), so anything merged to `main` ships to users right away.

The stdin schemas are documented at https://code.claude.com/docs/en/statusline (see "Available data" and "Subagent status lines"). Check there before adding or changing fields.

## Commands

```bash
bash tests/run.sh                                              # all tests; offline, uses a temp HOME and cache
shellcheck statusline.sh subagent-statusline.sh tests/run.sh   # lint
bash statusline.sh < tests/fixtures/statusline-full.json       # render a fixture by hand
bash subagent-statusline.sh < tests/fixtures/subagents.json
```

`tests/run.sh` is a list of `expect`/`reject`/`equal` assertions on ANSI-stripped output. Run it with `TZ=UTC LC_ALL=C`, as it already does. To check a single case, render the fixture by hand or comment out the other assertions; there is no per-test runner. CI (`.github/workflows/ci.yml`) runs shellcheck, then the tests on Ubuntu, macOS (with `/bin/bash` 3.2) and Windows (Git Bash).

Running `statusline.sh` by hand outside the tests may start a background request to the OAuth usage endpoint and writes the cache in `${TMPDIR:-/tmp}/claude`. Set `CLAUDE_PULSE_CACHE_DIR` to keep it elsewhere.

## statusline.sh architecture

1. Read stdin with `IFS= read -r -d '' input`, not `cat`.
2. Make **one** `jq` call that turns every field into `name='value'` lines with `@sh`, then `eval` them. Formatting (token counts, money, durations, epoch conversion) happens inside that jq program. To add a field, add a key to the jq object and use `$key` in bash. shellcheck's SC2154 is disabled file-wide because of this `eval`.
3. Segments are appended with `add1` (line 1: session) or `add2` (line 2: limits and cost). Both join with `$sep`. Print with `printf '%s\n'`. Line 2 is omitted when empty. The script always exits 0.

Conventions:
- Colors are `$'\033[...]'` variables holding real escape bytes, and output is printed with `%s`, so backslashes in data (Windows paths) are never interpreted. Don't go back to `printf "%b"`.
- Optional fields default to `""` in jq and their segment is added only when non-empty. Guard numbers with `num` (null → empty). `current_usage`, `used_percentage` and `hit_ratio` can be `null`.
- `build_bar <pct> <width>` sets the global `$bar` (no subshell). Width is 8 for context and 5 for everything else. Colors: green below 50, orange from 50, yellow from 70, red from 90.
- `resets_at` is Unix epoch seconds. The jq `epoch` helper also accepts ISO 8601 strings from older Claude Code versions. `format_epoch` tries BSD `date -r` and then GNU `date -d @`, each checked on its own. Never put the first attempt in a pipeline before `||`: the pipeline's exit status comes from its last command, so the fallback would never run.
- Git uses a single `git status --porcelain=v2 --branch` call for both the branch and the dirty state.
- The 💰 extra-usage segment is the only network use. It calls the undocumented `/api/oauth/usage` endpoint, which the user chose to keep. It renders from the cache and refreshes in a background subshell with stdio redirected to `/dev/null`. Claude Code cancels a status line run that is still going when the next update arrives, so the script must never block on the network.
- Native `jq.exe` on Windows writes CRLF. `statusline.sh` strips `\r` from the jq output, and `subagent-statusline.sh` pipes through `tr -d '\r'`.
- Keep everything bash 3.2 compatible: no `${var,,}`, `mapfile`, associative arrays or `printf -v` namerefs.

## subagent-statusline.sh architecture

The whole renderer is one `jq -c` program. Colors are zero-arity defs (`def blue: ...;`). For each task it builds candidate layouts from richest to leanest and picks the first one that is narrower than `columns`, measured with ANSI codes stripped. The label fills the remaining width and is truncated with `…`. If jq is missing or fails, the script prints nothing and Claude Code keeps its default rows.

Subagents can only be displayed, not managed, from these scripts. The docs offer no external stop or message API. The README's "Managing subagents" section lists Claude Code's built-in controls.

## Repo hygiene

- `.gitattributes` forces LF for `*.sh`, `*.json` and `*.yml`, because bash breaks on CRLF and this repo is developed on Windows with `core.autocrlf=true`.
- The scripts are tracked as executable (mode 100755). Keep that when adding scripts (`git update-index --chmod=+x`).
- `README.md` has segment tables, example output and the color block. Update them, and the fixtures and tests, whenever a segment changes.
