# claude-profiles

Run **multiple Claude Code accounts** from your terminal — a different account per window — **without `/logout` + `/login` each time**, while every account keeps sharing your MCP servers, skills, plugins, and `CLAUDE.md`.

A single, auditable zsh file. No dependencies beyond `python3` (for JSON) and, on macOS, the built-in `security` tool.

```zsh
ccp work        # this terminal is your "work" account
ccp personal    # another terminal, another account — at the same time
claude          # bare command stays your primary account, untouched
```

## Why

Claude Code has no first-party account switcher yet ([anthropics/claude-code#44687](https://github.com/anthropics/claude-code/issues/44687)). The one mechanism it exposes is the **`CLAUDE_CONFIG_DIR`** environment variable, which relocates its entire config directory. Point it at a different folder per shell and you get a fully isolated account — but naively that also throws away all your MCP servers, skills, and plugins.

`claude-profiles` fixes that: it **symlinks the shared config** back to your primary `~/.claude` and **seeds your MCP servers** into each profile, so switching accounts changes *only the login and history*, nothing else.

## What's shared vs. isolated

| Shared across all accounts (symlinked) | Isolated per account |
| --- | --- |
| `settings.json`, `plugins`, `skills`, `agents`, `commands`, `hooks`, `output-styles`, `CLAUDE.md` | login / credentials |
| your user-scoped MCP servers (seeded + kept in sync) | conversation history, `projects`, sessions |
| plus anything in `CLAUDE_PROFILE_SHARE_EXTRA` | account identity (`oauthAccount`) |

History is per-account by default — `--resume` / `-c` in a profile only sees that account's
conversations. To share it across all accounts instead, see [Shared history](#shared-history-resume-across-accounts).

## Install

```zsh
git clone https://github.com/habibtalib/claude-profiles.git ~/.claude-profiles-src
echo 'source "$HOME/.claude-profiles-src/claude-profiles.zsh"' >> ~/.zshrc
exec zsh
```

or run the bundled installer, which adds the `source` line idempotently:

```zsh
git clone https://github.com/habibtalib/claude-profiles.git ~/.claude-profiles-src
~/.claude-profiles-src/install.sh
exec zsh
```

## Usage

```zsh
claude-profile-add work        # scaffold a profile named "work"
claude-profile work            # launch it; run /login once with that account
# ...from now on:
ccp work                       # alias for `claude-profile work`
ccp work --resume              # any claude flag forwards through (name comes first)
ccp work --dangerously-skip-permissions

claude-profile-ls              # see every profile and the account it's on
claude-profile-sync --all      # re-push MCP servers after adding one to your primary
claude-profile-share-sessions --all   # share conversation history (opt-in; see below)
claude-profile-doctor          # show credential isolation + which profiles are logged in
```

**Rule:** the profile name is always the first argument — `ccp work --resume`, never `ccp --resume work`.

Bare `claude` is never wrapped or overridden — it keeps running your primary `~/.claude` account with all native flags.

## Credentials are isolated per account

Logins do **not** collide — you can run several accounts at the same time.

- **Linux / other** — Claude stores credentials in `<config-dir>/.credentials.json`, one file per profile.
- **macOS** — Claude stores them in the login **Keychain**, keyed per config dir: the service name is `Claude Code-credentials-<sha256(config-dir-path)[:8]>` (your primary `~/.claude` uses the unhashed `Claude Code-credentials`). A profile login never overwrites your primary or another profile.

Run `claude-profile-doctor` to see which profiles are logged in.

> Older write-ups claimed the macOS Keychain item was global and shared across accounts. That was true of earlier Claude Code builds; current versions hash the config-dir path into the service name, so profiles are fully isolated.

## Shared history (`--resume` across accounts)

By default each account has its own conversation history. If you'd rather have `--resume` and
`-c` (continue) reach **the same conversations from any account**, turn on session sharing —
it symlinks the session stores (`projects`, `sessions`, `session-env`, `shell-snapshots`,
`tasks`, `history.jsonl`) to your primary.

For new profiles, set the flag before sourcing:

```zsh
export CLAUDE_PROFILE_SHARE_SESSIONS=1
source "$HOME/.claude-profiles-src/claude-profiles.zsh"
```

For profiles you already created:

```zsh
claude-profile-share-sessions --all      # or: claude-profile-share-sessions work
```

It's non-destructive — any existing per-profile history is moved to `<item>.preshare.bak`
first. To revert a profile, delete the symlink and restore its `.preshare.bak`.

> Sharing history means every account can see every account's conversations via `--resume`.
> That's the point here, but keep it off if you want accounts kept fully separate.

## Configuration

Set these in `~/.zshrc` **before** the `source` line:

| Variable | Default | Purpose |
| --- | --- | --- |
| `CLAUDE_PROFILES_DIR` | `~/.claude-profiles` | where profile dirs live |
| `CLAUDE_PRIMARY_DIR` | `~/.claude` | your primary config dir / source of truth |
| `CLAUDE_PROFILE_SHARE_EXTRA` | *(empty)* | extra items under the primary dir to symlink, space-separated |
| `CLAUDE_PROFILE_SHARE_SESSIONS` | *(empty)* | if non-empty, new profiles share conversation history (`--resume` / `-c` see all accounts' sessions) |

Example — also share a custom plugin directory:

```zsh
export CLAUDE_PROFILE_SHARE_EXTRA=".my-tooling notes.md"
source "$HOME/.claude-profiles-src/claude-profiles.zsh"
```

## How it works

1. A profile is just a directory (`~/.claude-profiles/<name>/`).
2. On creation it's filled with **symlinks** to the shared items in your primary `~/.claude`, and a minimal `.claude.json` seeded with your MCP servers.
3. `claude-profile <name>` runs `CLAUDE_CONFIG_DIR="<that dir>" claude "$@"` — the env var is scoped to that one invocation, so it never leaks into your shell and bare `claude` stays primary.
4. Each launch re-syncs MCP servers from the primary, so a server you add later shows up everywhere.

## Notes

- The VS Code / JetBrains extension keeps its own auth and does **not** follow `CLAUDE_CONFIG_DIR` — it stays on your primary account. This tool is terminal-only.
- Nothing about your primary `~/.claude` is moved or rewritten; profiles are purely additive. Delete a profile with `rm -rf ~/.claude-profiles/<name>`.

## Prior art

The `CLAUDE_CONFIG_DIR` per-terminal model and the symlink-sharing / Keychain-snapshot ideas are well-trodden — see
[realiti4/claude-swap](https://github.com/realiti4/claude-swap),
[ukogan/claude-account-switcher](https://github.com/ukogan/claude-account-switcher),
[burakdede/aisw](https://github.com/burakdede/aisw), and others.
This is a deliberately small, single-file, dependency-light take.

## License

MIT © Habib Talib
