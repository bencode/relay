#!/usr/bin/env bash
# Relay installer — 把 relay skill 装进目标项目的 .claude/skills/relay/
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/bencode/relay/main/install.sh | bash
#   bash install.sh [target-project-dir]      # 默认当前目录
#
# 做三件事：拷贝 skill → 建好 7 个 label → 跑自检。
set -euo pipefail

REPO_URL="https://github.com/bencode/relay"
TARGET="${1:-$PWD}"
TARGET="$(cd "$TARGET" && pwd)"
DEST="$TARGET/.claude/skills/relay"

# 1) 定位 skill 源：脚本旁边有就用本地（从 clone 跑），否则浅克隆（curl 跑）
SRC=""
CLONE_TMP=""
cleanup() { [ -n "$CLONE_TMP" ] && rm -rf "$CLONE_TMP" || true; }
trap cleanup EXIT

if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]:-}" ]; then
  SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  [ -f "$SELF_DIR/.claude/skills/relay/SKILL.md" ] && SRC="$SELF_DIR/.claude/skills/relay"
fi
if [ -z "$SRC" ]; then
  CLONE_TMP="$(mktemp -d)"
  echo "→ 克隆 $REPO_URL ..."
  git clone --depth 1 "$REPO_URL" "$CLONE_TMP/relay" >/dev/null 2>&1
  SRC="$CLONE_TMP/relay/.claude/skills/relay"
fi

# 2) 拷贝（源与目标相同的话是"仓库内自装"，跳过）
if [ "$SRC" = "$DEST" ]; then
  echo "→ 源与目标相同（relay 仓库内自装），跳过拷贝"
else
  echo "→ 安装到 $DEST"
  mkdir -p "$TARGET/.claude/skills"
  rm -rf "$DEST"
  cp -r "$SRC" "$DEST"
fi
chmod +x "$DEST"/*.sh "$DEST/relay.py" 2>/dev/null || true

# 3) 建 label + 自检（在目标项目内跑，gh 自动识别其 repo）
cd "$TARGET"
echo "→ 创建 labels ..."
bash "$DEST/init-labels.sh" || echo "  (label 创建跳过/部分失败，可稍后手动跑 init-labels.sh)"
echo "→ 自检 ..."
bash "$DEST/setup-check.sh"
