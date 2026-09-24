#!/usr/bin/env bash
# Idempotently add claude-profiles to your ~/.zshrc.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/claude-profiles.zsh"
RC="${ZDOTDIR:-$HOME}/.zshrc"
LINE="source \"$SRC\""

if [ ! -f "$SRC" ]; then
  echo "error: $SRC not found" >&2
  exit 1
fi

if grep -qF "$SRC" "$RC" 2>/dev/null; then
  echo "already installed in $RC"
else
  {
    echo ""
    echo "# claude-profiles — multiple Claude Code accounts per terminal"
    echo "$LINE"
  } >> "$RC"
  echo "added to $RC"
fi

echo "run 'exec zsh' (or open a new terminal), then: claude-profile-add <name>"
