# Security policy

claude-pulse runs on every status line update and, for the extra usage segment, reads your Claude Code OAuth token. Security issues are taken seriously.

## Reporting a vulnerability

Please report vulnerabilities **privately**, through [GitHub's private vulnerability reporting](https://github.com/moictab/claude-pulse/security/advisories/new), not in a public issue. Include steps to reproduce, and the output of `bash ~/.claude/statusline.sh --version`.

You should get a reply within a week. Fixes are released on `main`, which is what the install instructions download.

## Supported versions

Only the latest version on `main` gets fixes.

## What the scripts access

See [Privacy](README.md#privacy) in the README. In short: the OAuth token is only read for the extra usage segment, is only sent to `api.anthropic.com`, and is never read at all with `CLAUDE_PULSE_EXTRA_USAGE=0`.
