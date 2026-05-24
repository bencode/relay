---
name: relay
description: GitHub Issue 上的 AI Agent 协同。在用户问"有哪些活/open issue""我手上有什么""创建/关闭 issue""把这个分给 @xxx / Claude Code / Helm""@xxx 在做什么""谁负责这个"等涉及任务流转时使用。**所有数据走 gh CLI；多步逻辑（lint / verify / close）走 relay.py。绝不要造本地 issue 文件（.relay/issues/*.yaml 等）。**
---

# relay

Issue 协同的事实层是 **GitHub Issues**（gh 自动识别当前 repo）。两个工具协同：
- **`gh` CLI** — 单步动作（list / view / create / edit / comment / reopen 等）
- **`relay.py`** — 多步逻辑（lint / verify / close）

## 前置

**第一次用前先跑自检**：

```bash
bash "${CLAUDE_SKILL_DIR}/setup-check.sh"
```

7 项全 ✓ 才能开始用。任何 ✗ 的项会给出修复提示。检查内容：
- `gh` CLI 已安装
- `gh` 已登录
- 当前目录在 GitHub repo 内
- 是该 repo 所属 org 的成员
- `python3` 3.9+ 可用
- `relay.py` 可跑
- 能读当前 repo 的 issues

自检通过后，所有 `gh` 命令自动作用于当前 repo（git remote 自动识别）。

## 输出风格（重要：默认行为）

**展示 issue 给用户时，永远先贴可点击 URL，不要在终端里渲染 body**。

默认输出形态：
```
#42  Extract shared validation helper  [state:verified]  @<handle>
     https://github.com/<owner>/<repo>/issues/42
```

**只展开 body 的情况**（必须用户明确要求）：
- "**分析**一下 #42 是什么需求"
- "**总结** #42 的关键点"
- "把 #42 跟 #43 **对比**一下"
- "接手 #42"（要开始动手，需要完整上下文）

## Issue 必含结构（v0.2 起）

所有 issue body 必须含 3 个 section。**relay.py lint 会校验，不合格不能 close**。

### `## Goal`
要做什么的定量描述。优先 "完成后系统会有 X 状态" 的可观测形式。

- 好例：`新增 user_settings 表 + GET/PUT /api/users/:id/settings 接口 + 测试覆盖`
- 差例：`改进用户设置体验`（不定量）

### `## Verification`（核心，code as sensor）
一个 ` ```bash ... ``` ` block，多条命令全过才允许 close。命令本身就是"完成"的形式化定义。

例：
```bash
test -f src/lib/validate.ts
grep -q "export function validate" src/lib/validate.ts
pnpm test src/lib/validate.test.ts --silent
```

**约束**：
- 只允许一个 bash block（relay.py 只提取第一个）
- 不要写 `# manual: 视觉确认...` 类的人工 step——v0.2 只接可执行命令，逼着把"完成"形式化
- 命令应该是真可重复跑的（dry-run 思维）

### `## Refs`
- `doc: docs/xxx.md` 或 markdown link
- 关联文件路径
- 相关 issue / PR 号（`#N`、`owner/other-repo#42`）

## 协作语义

### assignee = 主要负责的人
`assignee` 是 GitHub username（如 `<your-handle>`）。一个 issue 可有 0-N 个 assignee。
不要在 issue 里用别名 / 中文名做 assignee——必须是 GitHub user。需要喊昵称写在 body 里。

### AI 处理终端 = label，不占 assignee

| label | 含义 |
|---|---|
| `actor:claude-code` | 该 issue 想让 Claude Code 处理（人触发） |
| `actor:helm-agent` | Helm 自动 loop 处理 |
| `actor:scheduled` | 定时任务接管 |

加 label：`gh issue edit <num> --add-label actor:claude-code`

> 新项目安装本 skill 后，需要在 GitHub 上手动创建这些 label（一次性）：
> ```bash
> gh label create "actor:claude-code" --color "5319e7"
> gh label create "actor:helm-agent" --color "5319e7"
> gh label create "actor:scheduled" --color "5319e7"
> ```
> 或直接跑 `bash "${CLAUDE_SKILL_DIR}/init-labels.sh"` 一次性建好全部 7 个 label。

### issue 脱离分支
issue 是项目级协作对象，不要因为 issue 状态变化切 git 分支。在任何分支跑 `gh` 都直接打到 GitHub。

## Issue 生命周期（v0.2 状态机）

### 4 个 lifecycle labels

| label | 含义 | 加/移除 |
|---|---|---|
| `state:in-progress` | assignee 在干活 | assignee 加；relay.py close 自动移除 |
| `state:needs-clarification` | 等 creator 补信息 | assignee 加/移除 |
| `state:needs-verification` | 已 close、等 creator 亲自验收 | relay.py close 自动加；creator 验收时移除 |
| `state:verified` | creator 已亲自验收通过 | creator 满意时加 |

> 新项目安装本 skill 后，需要在 GitHub 上手动创建这些 label（一次性）：
> ```bash
> gh label create "state:in-progress" --color "fbca04"
> gh label create "state:needs-clarification" --color "d93f0b"
> gh label create "state:needs-verification" --color "1d76db"
> gh label create "state:verified" --color "0e8a16"
> ```
> 或直接跑 `bash "${CLAUDE_SKILL_DIR}/init-labels.sh"` 一次性建好（与 actor 标签共用一个脚本）。

### 状态语义矩阵

| open/closed | label | 含义 |
|---|---|---|
| open | 无 | 刚 assign，未开工 |
| open | `state:in-progress` | assignee 在干活 |
| open | `state:needs-clarification` | 等 creator 补信息 |
| closed | `state:needs-verification` | 等 creator 验收 |
| closed | `state:verified` | 已验收，结案 |
| closed | 无 lifecycle label | 异常（流程没走完 / 老 issue） |

### 角色边界

- **Creator (A)**：发起者。写清楚 body、close 后亲自验收（满意打 `state:verified`；不满意 reopen）
- **Assignee (B)**：执行者。推动 open → closed（含 verify 跑过），不负责验收

### 完整流程（8 阶段动作清单）

| 阶段 | 谁 | 动作 | 工具 | 命令 |
|---|---|---|---|---|
| 1 | A | 创建 + 自动 lint | gh + relay.py | `gh issue create --body-file ...` + `relay.py lint <num>` 复查 |
| 1 | A | 指派 | gh | `gh issue edit <num> --add-assignee <handle>` |
| 2 | B | 查看 | gh | `gh issue view <num>` |
| 3 | B | 开始干活 | gh | `gh issue edit <num> --add-label state:in-progress` |
| 3 | B | 提出澄清 | gh | `gh issue comment <num> --body "..."` + `gh issue edit --add-label state:needs-clarification` |
| 4 | B | 澄清结束 | gh | `gh issue edit --remove-label state:needs-clarification --add-label state:in-progress` |
| 5 | B | 进度报告 | gh | `gh issue comment`（可选） |
| 6 | B | 关闭 | relay.py | `python3 "${CLAUDE_SKILL_DIR}/relay.py" close <num>` |
| 7 | A | 验收满意 | gh | `gh issue edit <num> --remove-label state:needs-verification --add-label state:verified` |
| 7 | A | 验收不满意 | gh | `gh issue reopen <num>` + `gh issue edit --remove-label state:needs-verification --add-label state:in-progress` + comment |

**只有 close 走 relay.py**（多步：verify + close + 切 label + ping creator）。其它都是单行 gh。

## Verification 工作流

### close 必走 relay.py，不要 `gh issue close` 直接关

`relay.py close <num>` 内部：
1. 先 lint（结构不合格 → 拒绝 close）
2. 提取 Verification 的 bash block 跑（`set -e`，逐条执行）
3. 任一命令失败 → 输出失败项、**不** close
4. 全过 →
   - `gh issue close --reason completed --comment <verify-output + cc @creator>`
   - 移除 `state:in-progress`
   - 加 `state:needs-verification`
5. 输出 issue URL + ping 状态

### 用 lint 复查存量 issue

如果你接手一个老 issue（没有 3-section 结构）：
```bash
python3 "${CLAUDE_SKILL_DIR}/relay.py" lint <num>
```
不合格 → 跟 creator 来回澄清，retrofit body 后再开工。

### 用 verify 试跑

随时跑 verify 看 "现在做完了吗"，不必等 close：
```bash
python3 "${CLAUDE_SKILL_DIR}/relay.py" verify <num>
```

## Creator 验收流程

issue 被 `relay.py close` 关闭后，状态变成 `closed + state:needs-verification`。
GitHub 会通知 creator。creator 决定：

### 满意路径
亲自看代码 / 跑功能后觉得 OK：
```bash
gh issue edit <num> --remove-label state:needs-verification --add-label state:verified
```
（无评论也行；想留话用 `gh issue comment`）

终态：`closed + state:verified` = 彻底结案。

### 不满意路径
亲自验时发现问题（机器 verify 过但人工不满意）：
```bash
gh issue reopen <num>
gh issue edit <num> --remove-label state:needs-verification --add-label state:in-progress
gh issue comment <num> --body "重开原因：xxx 还不行 / 需要改..."
```

回到 open + in-progress，assignee 继续干。

## 核心操作（单步 gh 命令）

### 我手上有什么活
```bash
gh issue list --assignee @me --state open --json number,title,url,labels,createdAt
```

### 给 AI 处理的活
```bash
gh issue list --label actor:claude-code --state open --json number,title,url,assignees
```

### 等我验收的活（creator 视角）
```bash
gh issue list --author @me --state closed --label state:needs-verification --json number,title,url
```

### 看完整上下文（LLM 用）
```bash
gh issue view <num> --json number,title,body,state,stateReason,assignees,labels,comments,url,createdAt,closedAt,closedByPullRequestsReferences
```

### 创建 issue
```bash
gh issue create --title "标题" --body-file /tmp/issue-body.md \
  --assignee <handle> --label actor:claude-code
```
**注意**：body 必须含 Goal / Verification / Refs 三段。创建后跑 `relay.py lint <num>` 复查。

### 改 assignee / label / 转手
```bash
gh issue edit <num> --add-assignee <new> --remove-assignee <old>
gh issue edit <num> --add-label actor:helm-agent --remove-label actor:claude-code
```

### 评论 / 跨 issue 引用
```bash
gh issue comment <num> --body "..."
# body 里写 #123 / owner/other-repo#42 会自动 link
```

## 端到端示例

### A. 创建 issue 分给 Claude Code 处理

1. 跟用户确认 Goal / Verification / Refs 三段的具体内容
2. 写 body 文件：
```bash
cat > /tmp/issue-body.md <<'EOF'
## Goal

抽取共用 input 校验工具，让 API 路由和 worker pipeline 复用同一份逻辑。完成后：

- `src/lib/validate.ts` 导出 `validate(input)` 返回 typed result
- 所有调用方切换到公共函数，无重复实现

## Verification

​```bash
test -f src/lib/validate.ts
grep -q "export function validate" src/lib/validate.ts
pnpm test src/lib/validate.test.ts --silent
​```

## Refs

- doc: [design doc](https://github.com/<owner>/<repo>/blob/main/docs/validation-design.md)
EOF
```
3. 创建 + lint 复查：
```bash
gh issue create --title "Extract shared validation helper" \
  --body-file /tmp/issue-body.md \
  --assignee <handle> --label actor:claude-code
python3 "${CLAUDE_SKILL_DIR}/relay.py" lint <num>
```
4. 把 URL 贴给用户：
```
✓ 创建: #42 Extract shared validation helper
  https://github.com/<owner>/<repo>/issues/42
```

### B. 看自己手上有什么活

```bash
gh issue list --assignee @me --state open --json number,title,url,labels
```

带 URL 按状态分组：
```
@<me> open issues (N):

[state:in-progress] 进行中:
  #42  Extract shared validation helper
       https://github.com/<owner>/<repo>/issues/42

[state:needs-clarification] 等回复:
  #43  ...
       https://...

[无 state label] 等领取:
  #44  ...
       https://...
```

### C. 我做完 #42 了，关掉

**不要**用 `gh issue close` 直接关。走 relay.py：

```bash
python3 "${CLAUDE_SKILL_DIR}/relay.py" close 42
```

内部：lint → verify → close + 切 label + cc creator。
任一步失败会输出原因不 close。

成功后给用户：
```
✓ closed: https://github.com/<owner>/<repo>/issues/42
  cc'd creator @<name> for verification

等待 creator 验收（label: state:needs-verification）
```

### D. 我是 creator，#42 验收

先亲自看 / 跑功能确认满意。

**满意**：
```bash
gh issue edit 42 --remove-label state:needs-verification --add-label state:verified
```

**不满意**：
```bash
gh issue reopen 42
gh issue edit 42 --remove-label state:needs-verification --add-label state:in-progress
gh issue comment 42 --body "重开原因：xxx 还差一点 / 没考虑 yyy 情况"
```

### E. 把 #42 转手给另一个人

```bash
gh issue edit 42 --remove-assignee <old> --add-assignee <new> \
  --remove-label actor:claude-code
gh issue comment 42 --body "转给 @<new> 接手"
```

### F. 列出本周关闭的 issue

```bash
gh issue list --state closed --search "closed:>$(date -v-7d +%Y-%m-%d)" \
  --json number,title,url,closedAt,stateReason,labels
```

## 反模式（绝不要做）

- ❌ **不要造 `.relay/issues/*.yaml` 等本地 issue 文件** —— 数据源是 GitHub Issues，本地维护必然双轨
- ❌ **不要建 actors.yaml** 做 nickname 映射 —— 直接用 GitHub handle 简单无歧义；除非团队大到 handle 难记，再考虑
- ❌ **不要用 GitHub Issue 替代代码 review** —— PR/commit message 仍是讨论代码的地方
- ❌ **不要因为 issue 状态变化切 git 分支** —— 互相独立
- ❌ **不要写不带 3-section 结构的 issue body** —— relay.py lint 会拒绝，浪费来回
- ❌ **不要在 Verification 里写 `# manual: ...`** —— v0.2 只接可执行命令
- ❌ **不要用 `gh issue close` 直接关，必须走 `relay.py close`** —— 绕过 verify 等于自报完成
- ❌ **不要在没有 `state:in-progress` label 时静默干活** —— 其他人不知道你在做
- ❌ **不要遗忘切 `state:needs-verification` ↔ `state:verified`** —— closed 但无 lifecycle label = 异常
- ❌ **creator 满意时不要 reopen** —— 移除 needs-verification、加 verified 即可；reopen 表示要继续干

## 何时 / 何处不用此 skill

- 用户问"git push / pull / 合并代码" → 走 git，不走 relay
- 用户问"部署/上线" → 走项目的 deploy skill
- 用户问"查数据库" → 走项目的数据查询 skill
- 跟 PR review 强相关 → 在 PR comment 上做，不开 issue

## 装到新项目

推荐透明四步（agent 自己装时走这条，别用 `curl | bash`——会被权限/自动模式拦）。在目标项目根目录：

```bash
git clone --depth 1 https://github.com/bencode/relay /tmp/relay
mkdir -p .claude/skills && cp -r /tmp/relay/.claude/skills/relay .claude/skills/ && rm -rf /tmp/relay
bash .claude/skills/relay/init-labels.sh      # 建 7 个 label（幂等）
bash .claude/skills/relay/setup-check.sh       # 自检
```

装好后：把 `.claude/skills/relay/` 提交进 git；在项目 `AGENTS.md` / `CLAUDE.md` 加一行指向本 skill。

人手图省事可 `curl -fsSL https://raw.githubusercontent.com/bencode/relay/main/install.sh | bash`（等价四步）。

**项目特定约定**（如团队成员、特定流程偏好）可写在项目自己的 AGENTS.md 里，不污染本 skill。
