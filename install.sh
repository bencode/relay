#!/usr/bin/env bash
# Relay installer — install the relay skill into a target project's .claude/skills/relay/
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/bencode/relay/main/install.sh | bash
#   bash install.sh [target-project-dir]      # defaults to the current directory
#
# Does three things: copy the skill -> create the 7 labels -> run the self-check.
set -euo pipefail

REPO_URL="https://github.com/bencode/relay"
TARGET="${1:-$PWD}"
TARGET="$(cd "$TARGET" && pwd)"
DEST="$TARGET/.claude/skills/relay"

# 1) Locate the skill source: use the local copy if this script sits next to it
#    (running from a clone), otherwise shallow-clone (running via curl).
SRC=""
CLONE_TMP=""
cleanup() { [ -n "$CLONE_TMP" ] && rm -rf "$CLONE_TMP" || true; }
trap cleanup EXIT

if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]:-}" ]; then
  SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  [ -f "$SELF_DIR/skills/relay/SKILL.md" ] && SRC="$SELF_DIR/skills/relay"
fi
if [ -z "$SRC" ]; then
  CLONE_TMP="$(mktemp -d)"
  echo "→ cloning $REPO_URL ..."
  git clone --depth 1 "$REPO_URL" "$CLONE_TMP/relay" >/dev/null 2>&1
  SRC="$CLONE_TMP/relay/skills/relay"
fi

# 2) Copy
echo "→ installing into $DEST"
mkdir -p "$TARGET/.claude/skills"
rm -rf "$DEST"
cp -r "$SRC" "$DEST"
chmod +x "$DEST"/*.sh "$DEST/relay.py" 2>/dev/null || true

# 3) Create labels + self-check (run inside the target project so gh resolves its repo)
cd "$TARGET"
echo "→ creating labels ..."
bash "$DEST/init-labels.sh" || echo "  (label creation skipped/partially failed; run init-labels.sh later)"
echo "→ self-check ..."
bash "$DEST/setup-check.sh"
