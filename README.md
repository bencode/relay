# relay

GitHub Issue 上的 **AI Agent 协同 skill**。让 Claude Code（及其它读 SKILL.md 的 agent）按一套固定约定在 GitHub Issues 上协作：可验证的 issue 结构、生命周期状态机、两段验收（机器 verify + 人工验收）。

事实层是 **GitHub Issues**，全程走 `gh` CLI；多步逻辑（lint / verify / close）走随附的 `relay.py`。**不造任何本地 issue 文件**。

## 安装

在**目标项目根目录**跑一行：

```bash
curl -fsSL https://raw.githubusercontent.com/bencode/relay/main/install.sh | bash
```

它会：
1. 把 skill 拷进 `<目标项目>/.claude/skills/relay/`
2. 在该项目对应的 GitHub repo 上建好 7 个 label（幂等）
3. 跑自检，逐项确认 `gh` / 登录 / python / 读 issue 权限齐备

> 把这个仓库地址（`https://github.com/bencode/relay`）丢给 Claude Code / Agent，让它「照 README 装到当前项目」即可——它读到的就是上面这一行。

### 手动安装

```bash
git clone --depth 1 https://github.com/bencode/relay /tmp/relay
mkdir -p .claude/skills && cp -r /tmp/relay/.claude/skills/relay .claude/skills/
bash .claude/skills/relay/init-labels.sh     # 建 7 个 label（幂等）
bash .claude/skills/relay/setup-check.sh      # 自检
```

## 依赖

- [`gh`](https://cli.github.com/) CLI，已 `gh auth login`
- `python3` ≥ 3.9（stdlib only，无需 pip / venv）
- 当前目录在一个有 GitHub remote 的仓库内

## 安装后怎么用

skill 装好后 Claude Code 会按 `.claude/skills/relay/SKILL.md` 的约定工作。核心：

- **Issue 必含 3 段**：`## Goal`（定量目标）/ `## Verification`（一个可执行 `bash` block，作为「完成」的形式化 sensor）/ `## Refs`
- **生命周期**：`state:in-progress` → `state:needs-verification`（`relay.py close` 自动切）→ `state:verified`（creator 亲自验收）
- **关闭走 `relay.py close <num>`**：先 lint 结构、跑 Verification、全过才 close 并切 label、cc creator
- 单步动作（list / view / create / edit / comment / reopen）直接走 `gh`

完整约定、状态机、端到端示例见 [`.claude/skills/relay/SKILL.md`](.claude/skills/relay/SKILL.md)。

## Codex / 其它 agent

Codex 不支持 Claude skill / plugin 机制。要在 Codex 里用：把 `relay.py` 拷进项目，并把 SKILL.md 里的协作约定摘到项目 `AGENTS.md`。`relay.py lint/verify/close` 本身是独立 CLI，任何 agent 都能调。

## Roadmap

当前以「拷文件 + 自检」方式分发。成熟后会打包成官方 Claude Code plugin 推到 marketplace——skill 内部已统一用 `${CLAUDE_SKILL_DIR}` 引用自带脚本，届时迁移零改动。
