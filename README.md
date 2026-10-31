# claude-statusline

Claude Code status line showing model, context tokens, session cost, directory, git info, effort and rate limits.

Based on [nilbuild/claude-statusline](https://github.com/nilbuild/claude-statusline) by Kamran Ahmed (MIT), with data fixes and a few changes.

```
Opus 5.5 │ ✍️ 203k/1M · $1.23 │ ⚡ my-project (main*) │ ⏱ 12m │ ● xhigh

current ●●●●○○○○○○  40% ⟳ 2:26am
weekly  ●○○○○○○○○○   8% ⟳ nov 3, 3:00pm
```

## Install

```bash
npx github:rushi-me/claude-statusline
```

Backs up any existing `~/.claude/statusline.sh` to `statusline.sh.bak`, installs the script, and sets `statusLine` in `~/.claude/settings.json`. Restart Claude Code afterwards.

## Uninstall

```bash
npx github:rushi-me/claude-statusline --uninstall
```

Restores the backup if one exists; otherwise removes the script and the `statusLine` setting.

## Requirements

- [jq](https://jqlang.github.io/jq/)
- curl (rate limit / extra usage data)
- git (branch info)

## Changes from upstream

**Display**
- Context widget shows tokens used / window size plus session cost (`203k/1M · $1.23`) instead of a percentage. Colour still reflects fill level.
- Shows a `spend` bar when running behind a Claude apps gateway with a spend limit (`rate_limits.spend_limit`).

**Data fixes** (checked against the [official statusline schema](https://code.claude.com/docs/en/statusline))
- Session timer used `session.start_time`, which Claude Code doesn't send, so it never showed. Now uses `cost.total_duration_ms`.
- Effort read `effortLevel` from `settings.json`, missing `/effort` changes. Now reads `effort.level` from stdin (settings as fallback). `xhigh`/`max` are highlighted like `high`.
- Context tokens come from `context_window.total_input_tokens` and `used_percentage` instead of being recomputed.
- Directory uses `workspace.current_dir` (preferred over `cwd`).
- Extra-usage line could be stale or missing: the usage cache was never refreshed when stdin supplied rate limits. It now refreshes every 60s regardless.
- Usage API request sends the real Claude Code version (from stdin `version`) instead of a hard-coded one.
- `⚡` skip-permissions marker checked only the direct parent process (usually a shell). Now walks up to 6 ancestors.

## Notes

- Cost is Claude Code's client-side estimate at list price; it may differ from your bill and resets on `/clear`.
- The extra-usage fallback calls `api.anthropic.com/api/oauth/usage`, an undocumented endpoint that may change.

## License

MIT — see [LICENSE](./LICENSE).
