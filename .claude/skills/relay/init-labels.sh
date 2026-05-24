#!/usr/bin/env bash
# Relay init-labels — 在当前 repo 一次性创建 relay 用到的 7 个 label（幂等）
# Usage: bash <skill-dir>/init-labels.sh
# 自动作用于当前 git remote 对应的 GitHub repo。--force 让已存在的 label 被更新而非报错。

set -u

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")
if [ -z "$REPO" ]; then
  printf "\033[31m✗\033[0m 不在 GitHub repo 内，或 gh 未登录。先 cd 到目标项目并 gh auth login。\n"
  exit 1
fi

printf "\n  在 %s 创建 relay labels\n  ─────────────────\n" "$REPO"

# label  color  description
create() {
  local name="$1" color="$2" desc="$3"
  if gh label create "$name" --color "$color" --description "$desc" --force >/dev/null 2>&1; then
    printf "  \033[32m✓\033[0m  %s\n" "$name"
  else
    printf "  \033[31m✗\033[0m  %s (创建失败，检查权限)\n" "$name"
  fi
}

# AI 处理终端（紫）
create "actor:claude-code"  "5319e7" "想让 Claude Code 处理（人触发）"
create "actor:helm-agent"   "5319e7" "Helm 自动 loop 处理"
create "actor:scheduled"    "5319e7" "定时任务接管"

# 生命周期状态
create "state:in-progress"        "fbca04" "assignee 在干活"
create "state:needs-clarification" "d93f0b" "等 creator 补信息"
create "state:needs-verification"  "1d76db" "已 close、等 creator 亲自验收"
create "state:verified"           "0e8a16" "creator 已亲自验收通过"

printf "  ─────────────────\n  done.\n\n"
