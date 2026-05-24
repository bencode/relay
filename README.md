# relay

GitHub Issue 上的 **AI Agent 协同 skill**。让 Claude Code（及其它读 SKILL.md 的 agent）按一套固定约定在 GitHub Issues 上协作：可验证的 issue 结构、生命周期状态机、两段验收（机器 verify + 人工验收）。

事实层是 **GitHub Issues**，全程走 `gh` CLI；多步逻辑（lint / verify / close）走随附的 `relay.py`。**不造任何本地 issue 文件**。

## 安装

### 推荐：透明四步（AI agent 也走这条）

把仓库地址（`https://github.com/bencode/relay`）丢给 Claude Code / Agent，让它「按 README 装到当前项目」。在**目标项目根目录**逐条执行（每条都可读、可单独确认，不需要 `curl | bash`）：

```bash
git clone --depth 1 https://github.com/bencode/relay /tmp/relay
mkdir -p .claude/skills && cp -r /tmp/relay/.claude/skills/relay .claude/skills/ && rm -rf /tmp/relay
bash .claude/skills/relay/init-labels.sh      # ① 在本 repo 建 7 个 label（幂等）
bash .claude/skills/relay/setup-check.sh       # ② 自检：gh/登录/python/读 issue
```

完成后把 `.claude/skills/relay/` 提交进 git，队友 clone 即得。

### 人手快捷：一行装

```bash
curl -fsSL https://raw.githubusercontent.com/bencode/relay/main/install.sh | bash
```

等价于上面四步（拷 skill → 建 label → 自检）。注意 `curl | bash` 会下载并执行远程脚本——AI agent / 受控环境通常会（也应该）拦它，那种场景请走上面的透明四步。

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
