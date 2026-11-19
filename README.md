# claude-statusline

Claude Code status line showing model, context tokens, session cost, directory, git info, effort and rate limits.

Based on [nilbuild/claude-statusline](https://github.com/nilbuild/claude-statusline) by Kamran Ahmed (MIT), with data fixes and a few changes.

```
Opus 5.5 │ ● 203k/1M (~$1.23) │ my-project/src (main*) │ ⏱ 12m │ ▮▮▮▮ xhigh

current ●●●●○○○○○○  40% ⟳ 2:26am · 1h 12m
weekly  ●○○○○○○○○○   8% ⟳ nov 3, 3:00pm · 3d 4h
```

## Install

```bash
npx @rushi-me/claude-statusline
```

Or straight from GitHub: `npx github:rushi-me/claude-statusline`

Installs the script to `~/.claude/statusline.sh` and sets `statusLine` in `~/.claude/settings.json` (with `refreshInterval: 1`). Restart Claude Code afterwards.

Backups go to `~/.claude/statusline-backups/` with timestamped names and are never overwritten:

- On first install, your existing statusline script is saved as `statusline-<time>-original.sh`, and your previous `statusLine` setting is recorded in `install.json`.
- On later installs (upgrades), the current script is saved as `statusline-<time>.sh` if it differs from the new one, so local edits are kept.
- Upgrading from 1.0.0 moves the old `statusline.sh.bak` into this folder as the original.

## Uninstall

```bash
npx @rushi-me/claude-statusline --uninstall
```

Saves the current script as `statusline-<time>-uninstalled.sh`, then restores your original script and `statusLine` setting. If there was none, it removes both. A `statusLine` setting you changed after installing is left alone. Backups stay in `~/.claude/statusline-backups/`.

## Requirements

- [jq](https://jqlang.github.io/jq/)
- curl (rate limit / extra usage data)
- git (branch info)

## Changes from upstream

**Display**
- Directory shows the repo name plus your position inside it (`repo/src`, `repo/…/tasks/graph`), the worktree name (`repo ⎇ wt`), where the session was launched if you've moved outside it (`‹ launch-dir`), and the number of `/add-dir` folders (`+2`).
- Branch: a detached HEAD shows the commit (`@6fcda85`); prefixes like `user/` are shortened to `…/`; names over 30 characters are truncated.
- Effort is a 4-cell meter (`▮▯▯▯ low`, `▮▮▯▯ medium`, `▮▮▮▯ high`, `▮▮▮▮ xhigh`/`max`) and is hidden when the level is unknown (upstream shows `default`). `low` is dim, `medium` sky blue, `high` magenta; `xhigh` fills with a violet→pink gradient and `max` with a pink→amber gradient.
- Rate-limit lines show the time left until each reset next to the reset time (`⟳ 2:26am · 1h 12m`).
- Removed the `⚡` skip-permissions marker (it cost up to 12 `ps` calls per render and only saw the launch flag).
- Context widget shows tokens used / window size plus estimated session cost (`● 203k/1M (~$1.23)`) instead of a percentage. Colour still reflects fill level. The circle blinks between empty and filled (`○ ●`), one frame per second.
- Shows a `spend` bar when running behind a Claude apps gateway with a spend limit (`rate_limits.spend_limit`).

**Installer**
- Backups are timestamped in `~/.claude/statusline-backups/` and never overwritten. Upstream keeps a single `statusline.sh.bak` that each install replaces.
- Uninstall restores your previous `statusLine` setting as well as the script. Upstream deletes the setting.
- Sets `refreshInterval: 1` so the status line re-runs every second (otherwise it updates only on events like new messages). Upgrades add it to an existing install.

**Performance**
- Stdin is parsed and formatted in one `jq` call; upstream runs a separate `jq`, `awk` or `date` process per field. Git info is cached for 5 seconds.

**Data fixes** (checked against the [official statusline schema](https://code.claude.com/docs/en/statusline))
- Session timer used `session.start_time`, which Claude Code doesn't send, so it never showed. Now uses `cost.total_duration_ms`.
- Context tokens come from `context_window.total_input_tokens` and `used_percentage` instead of being recomputed.
- Directory uses `workspace.current_dir` (preferred over `cwd`).
- Extra-usage line could be stale or missing: the usage cache was never refreshed when stdin supplied rate limits. It now refreshes every 60s regardless, and a failed request also waits 60s before retrying.
- Usage API request sends the real Claude Code version (from stdin `version`) instead of a hard-coded one.

## Notes

- Renders in roughly 40ms. Stdin is parsed in a single `jq` call, and git info is cached for 5 seconds per session in `$TMPDIR/claude-statusline-$UID/`, so a new commit or branch switch can take up to 5 seconds to appear.
- Cost is Claude Code's client-side estimate at list price; it may differ from your bill and resets on `/clear`.
- The extra-usage fallback calls `api.anthropic.com/api/oauth/usage`, an undocumented endpoint that may change.

## License

MIT — see [LICENSE](./LICENSE).
