# Contributing to claude-pulse

Thanks for helping. Bug reports and ideas go in [issues](https://github.com/moictab/claude-pulse/issues/new/choose); code changes go in pull requests.

## Setup

You need `bash`, `jq` and `git`. For linting, install [`shellcheck`](https://www.shellcheck.net/). To regenerate the README image, you also need `python3`.

```bash
bash tests/run.sh                                             # all tests, offline
shellcheck statusline.sh subagent-statusline.sh tests/run.sh  # lint
bash statusline.sh < tests/fixtures/statusline-full.json      # render a fixture by hand
bash subagent-statusline.sh < tests/fixtures/subagents.json
```

The tests pipe the JSON fixtures in `tests/fixtures/` through the scripts and check the output with the colors stripped. CI runs them on Ubuntu, macOS and Windows for every push and pull request.

If you run the scripts by hand outside the tests, set `CLAUDE_PULSE_CACHE_DIR` to a scratch directory, so you don't overwrite the cache that your own Claude Code sessions use.

## Guidelines

- **Users download `main` directly**, so keep it working. Every change needs passing tests.
- **Stay compatible:** bash 3.2 (the macOS default), jq 1.6, and both GNU and BSD tools. In bash, that means no `${var,,}`, `mapfile` or associative arrays. In jq:
  - Don't name variables after keywords: `$label` breaks jq 1.6.
  - Write `(a + b) as $x`, not `a + b as $x`; jq 1.7 reads the latter as `a + (b as $x | ...)`.
- **Keep the look:** no emoji, dim labels, ` · ` separators, and color only when it means something. The README's [Colors](README.md#colors) section lists what each color is for.
- **Never block on the network.** Claude Code cancels a status line run that is still going when the next update arrives.
- **Read new fields from the documented schema** at <https://code.claude.com/docs/en/statusline>. Guard every field with a default: fields can be missing or `null`.
- **When you change the output**, update the README tables, the tests, and, if it shows, the preview image (`bash docs/make-preview.sh`).

[CLAUDE.md](CLAUDE.md) has more on how the scripts are put together.

## Releasing

1. Update `CLAUDE_PULSE_VERSION` in both scripts and add an entry to [CHANGELOG.md](CHANGELOG.md).
2. Merge to `main`, then tag it: `git tag -a vX.Y.Z -m "claude-pulse X.Y.Z" && git push origin vX.Y.Z`.
3. Create a GitHub release from the tag, with the changelog entry as its notes.
