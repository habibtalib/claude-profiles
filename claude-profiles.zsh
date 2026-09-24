# claude-profiles.zsh — run multiple Claude Code accounts from zsh without logout/login.
#
# Each profile is its own CLAUDE_CONFIG_DIR. Shared config (settings, plugins, skills,
# agents, commands, hooks, output-styles, CLAUDE.md) is symlinked back to your primary
# ~/.claude so every account sees the same setup; only the login + history are isolated.
# Your user-scoped MCP servers are seeded/synced from the primary account into each profile.
#
# Install: source this from ~/.zshrc:
#     source "/path/to/claude-profiles.zsh"
#
# Commands:
#     claude-profile-add <name>     scaffold a new profile (then `/login` once)
#     claude-profile <name> [args]  launch Claude as that account   (alias: ccp)
#     claude-profile-ls             list profiles + which account each is on
#     claude-profile-sync [name]    re-push shared MCP servers into profile(s)
#     claude-profile-share-sessions [name]  share conversation history so --resume/-c
#                                   in a profile sees all accounts' sessions
#     claude-profile-doctor         report credential isolation + per-profile login state
#
# Config (optional, set before sourcing):
#     CLAUDE_PROFILES_DIR            where profiles live      (default ~/.claude-profiles)
#     CLAUDE_PRIMARY_DIR            your main config dir      (default ~/.claude)
#     CLAUDE_PROFILE_SHARE_EXTRA    extra items to symlink, space-separated
#                                   e.g. export CLAUDE_PROFILE_SHARE_EXTRA=".my-plugin notes.md"
#     CLAUDE_PROFILE_SHARE_SESSIONS if non-empty, new profiles share conversation history
#                                   (--resume / -c see every account's sessions)

export CLAUDE_PROFILES_DIR="${CLAUDE_PROFILES_DIR:-$HOME/.claude-profiles}"
export CLAUDE_PRIMARY_DIR="${CLAUDE_PRIMARY_DIR:-$HOME/.claude}"

# Items under the primary config dir that are shared (symlinked) into every profile.
# settings.json carries enabledPlugins / extraKnownMarketplaces / hasCompletedOnboarding,
# so symlinking it shares plugins and skips the onboarding wizard.
_CLAUDE_SHARED=(settings.json plugins skills agents commands hooks output-styles CLAUDE.md)
# user-supplied extras (zsh word-splits the env var)
[ -n "$CLAUDE_PROFILE_SHARE_EXTRA" ] && _CLAUDE_SHARED+=(${(z)CLAUDE_PROFILE_SHARE_EXTRA})

# Session/history items linked when CLAUDE_PROFILE_SHARE_SESSIONS is non-empty, so that
# `--resume` / `-c` (continue) see the SAME conversations across every profile + primary.
# Off by default: each account normally keeps its own history.
_CLAUDE_SESSION_SHARED=(projects sessions session-env shell-snapshots tasks history.jsonl)

# Symlink the session set from the primary into a profile (non-destructive: any existing
# real file/dir is moved to <item>.preshare.bak first; already-linked items are left alone).
_claude_profile_link_sessions() {
  local dir="$1" item src dst
  for item in "${_CLAUDE_SESSION_SHARED[@]}"; do
    src="$CLAUDE_PRIMARY_DIR/$item"; dst="$dir/$item"
    { [ -e "$src" ] || [ -L "$src" ]; } || continue
    [ -L "$dst" ] && continue
    [ -e "$dst" ] && mv "$dst" "$dst.preshare.bak"
    ln -s "$src" "$dst"
  done
}

# Where the primary account's config JSON lives (HOME root when CLAUDE_CONFIG_DIR is unset).
_claude_primary_json() {
  if [ -f "$CLAUDE_PRIMARY_DIR/.claude.json" ]; then
    print -r -- "$CLAUDE_PRIMARY_DIR/.claude.json"
  else
    print -r -- "$HOME/.claude.json"
  fi
}

# ---- internal: merge the primary account's mcpServers into a profile's .claude.json ----
_claude_profile_sync_json() {
  local prof_json="$1" master; master="$(_claude_primary_json)"
  python3 - "$master" "$prof_json" <<'PY'
import json, sys, os
master, prof = sys.argv[1], sys.argv[2]
try:
    mcp = json.load(open(master)).get("mcpServers", {})
except Exception:
    mcp = {}
p = {}
if os.path.exists(prof):
    try:
        p = json.load(open(prof))
    except Exception:
        p = {}
p["mcpServers"] = mcp
os.makedirs(os.path.dirname(prof), exist_ok=True)
json.dump(p, open(prof, "w"), indent=2)
print(f"synced {len(mcp)} mcpServers -> {prof}")
PY
}

# ---- claude-profile-add <name>: scaffold a profile ----
claude-profile-add() {
  local name="$1"
  if [ -z "$name" ]; then echo "usage: claude-profile-add <name>"; return 1; fi
  local dir="$CLAUDE_PROFILES_DIR/$name"
  if [ -e "$dir" ]; then echo "profile '$name' already exists at $dir"; return 1; fi
  mkdir -p "$dir"
  local item
  for item in "${_CLAUDE_SHARED[@]}"; do
    [ -e "$CLAUDE_PRIMARY_DIR/$item" ] && ln -s "$CLAUDE_PRIMARY_DIR/$item" "$dir/$item"
  done
  _claude_profile_sync_json "$dir/.claude.json"
  [ -n "$CLAUDE_PROFILE_SHARE_SESSIONS" ] && _claude_profile_link_sessions "$dir"
  echo ""
  echo "✅ profile '$name' created: $dir"
  echo "   shared (symlinked): ${_CLAUDE_SHARED[*]}"
  [ -n "$CLAUDE_PROFILE_SHARE_SESSIONS" ] && echo "   history shared: --resume / -c will see all accounts' conversations"
  echo "   next: run  claude-profile $name   then  /login  with that account (one time)."
}

# ---- claude-profile <name> [args...]: launch claude as that account (alias: ccp) ----
claude-profile() {
  local name="$1"
  if [ -z "$name" ]; then echo "usage: claude-profile <name> [claude-args...]"; claude-profile-ls; return 1; fi
  shift
  local dir="$CLAUDE_PROFILES_DIR/$name"
  if [ ! -d "$dir" ]; then
    echo "no profile '$name'. create it:  claude-profile-add $name"; return 1
  fi
  _claude_profile_sync_json "$dir/.claude.json" >/dev/null   # keep shared MCP current
  printf '\033]0;claude:%s\007' "$name"                       # visible tell: tab title
  # env scoped to this invocation only (no leak) -> bare `claude` stays on the primary account
  CLAUDE_CONFIG_DIR="$dir" command claude "$@"
  local rc=$?
  printf '\033]0;%s\007' "${SHELL:t}"
  return $rc
}
alias ccp='claude-profile'

# ---- claude-profile-ls: list profiles and which account each is logged into ----
claude-profile-ls() {
  _cp_email() { python3 -c 'import json,sys
try: print(json.load(open(sys.argv[1])).get("oauthAccount",{}).get("emailAddress","(not logged in)"))
except Exception: print("(no config yet)")' "$1" 2>/dev/null; }
  echo "primary  ~/.claude            -> $(_cp_email "$(_claude_primary_json)")"
  local d
  for d in "$CLAUDE_PROFILES_DIR"/*(/N); do
    printf 'profile  %-20s -> %s\n' "${d:t}" "$(_cp_email "$d/.claude.json")"
  done
  unfunction _cp_email
}

# ---- claude-profile-sync [name|--all]: re-copy shared MCP servers into profile(s) ----
claude-profile-sync() {
  local target="${1:---all}" d dir
  if [ "$target" = "--all" ]; then
    for d in "$CLAUDE_PROFILES_DIR"/*(/N); do _claude_profile_sync_json "$d/.claude.json"; done
  else
    dir="$CLAUDE_PROFILES_DIR/$target"
    [ -d "$dir" ] || { echo "no profile '$target'"; return 1; }
    _claude_profile_sync_json "$dir/.claude.json"
  fi
}

# ---- claude-profile-share-sessions [name|--all]: share history with existing profile(s) ----
# Makes `--resume` / `-c` in the profile see the primary account's conversations too.
# Non-destructive: each profile's prior session data is moved to <item>.preshare.bak.
claude-profile-share-sessions() {
  local target="${1:---all}" d
  if [ "$target" = "--all" ]; then
    for d in "$CLAUDE_PROFILES_DIR"/*(/N); do
      _claude_profile_link_sessions "$d"; echo "history shared -> ${d:t}"
    done
  else
    d="$CLAUDE_PROFILES_DIR/$target"
    [ -d "$d" ] || { echo "no profile '$target'"; return 1; }
    _claude_profile_link_sessions "$d"; echo "history shared -> $target"
  fi
  echo "(reverse by removing the symlink and restoring the matching *.preshare.bak)"
}

# ---- internal: is a config dir logged in? (creds are isolated per dir) ----
# macOS: Keychain service "Claude Code-credentials-<sha256(path)[:8]>" per config dir
# (the default ~/.claude uses the unhashed "Claude Code-credentials").
# Linux/other: a <config-dir>/.credentials.json file.
_claude_profile_logged_in() {
  local dir="$1"
  [ -f "$dir/.credentials.json" ] && return 0
  if command -v security >/dev/null 2>&1; then
    local svc
    if [ "$dir" = "$CLAUDE_PRIMARY_DIR" ]; then
      svc="Claude Code-credentials"
    else
      svc="Claude Code-credentials-$(python3 -c 'import hashlib,sys;print(hashlib.sha256(sys.argv[1].encode()).hexdigest()[:8])' "$dir")"
    fi
    security find-generic-password -s "$svc" >/dev/null 2>&1 && return 0
  fi
  return 1
}

# ---- claude-profile-doctor: show credential isolation + per-profile login state ----
claude-profile-doctor() {
  if command -v security >/dev/null 2>&1; then
    echo "Credentials: macOS Keychain, isolated per config dir"
    echo "  service 'Claude Code-credentials-<sha256(dir)[:8]>' (primary uses the unhashed name)"
  else
    echo "Credentials: file per config dir (<config-dir>/.credentials.json)"
  fi
  echo "Logins are isolated per profile — running several accounts at once is fine."
  echo ""
  _claude_profile_logged_in "$CLAUDE_PRIMARY_DIR" \
    && echo "primary  ~/.claude            -> logged in" \
    || echo "primary  ~/.claude            -> not logged in"
  local d
  for d in "$CLAUDE_PROFILES_DIR"/*(/N); do
    _claude_profile_logged_in "$d" \
      && printf 'profile  %-20s -> logged in\n' "${d:t}" \
      || printf 'profile  %-20s -> not logged in (run: claude-profile %s then /login)\n' "${d:t}" "${d:t}"
  done
}
