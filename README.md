# relay

An **AI-agent collaboration skill for GitHub Issues**. It teaches Claude Code (and any agent that reads SKILL.md) to collaborate on GitHub Issues by a fixed set of conventions: verifiable issue structure, a lifecycle state machine, and two-stage acceptance (machine `verify` + human acceptance).

The source of truth is **GitHub Issues**, driven entirely by the `gh` CLI; multi-step logic (lint / verify / close) goes through the bundled `relay.py`. **No local issue files, ever.**

## Install

### Recommended: transparent steps (agents use these too)

Hand the repo URL (`https://github.com/bencode/relay`) to Claude Code / an agent and ask it to "install relay into this project per the README". Run these from the **target project root** (each command is readable and individually approvable — no `curl | bash` needed):

```bash
git clone --depth 1 https://github.com/bencode/relay /tmp/relay
mkdir -p .claude/skills && cp -r /tmp/relay/skills/relay .claude/skills/ && rm -rf /tmp/relay
bash .claude/skills/relay/init-labels.sh      # ① create the 7 labels on this repo (idempotent)
bash .claude/skills/relay/setup-check.sh       # ② self-check: gh / auth / python / issue access
```

Then commit `.claude/skills/relay/` into git so teammates get it on clone.

### Quick: one-liner

```bash
curl -fsSL https://raw.githubusercontent.com/bencode/relay/main/install.sh | bash
```

Equivalent to the steps above (copy skill → create labels → self-check). Note: `curl | bash` downloads and runs a remote script — AI agents and sandboxed environments will (and should) block it, so use the transparent steps there.

## Requirements

- [`gh`](https://cli.github.com/) CLI, authenticated via `gh auth login`
- `python3` ≥ 3.9 (stdlib only — no pip / venv)
- the current directory is inside a repo with a GitHub remote

## How to use it after install

Once installed, Claude Code follows the conventions in `.claude/skills/relay/SKILL.md`. The essentials:

- **Every issue has 3 sections**: `## Goal` (quantified) / `## Verification` (one executable `bash` block — a formal "done" sensor) / `## Refs`.
- **Lifecycle**: `state:in-progress` → `state:needs-verification` (switched automatically by `relay.py close`) → `state:verified` (creator accepts in person).
- **Closing goes through `relay.py close <num>`**: it lints the structure, runs Verification, and only then closes, switches labels, and cc's the creator.
- Single-step actions (list / view / create / edit / comment / reopen) use `gh` directly.
- **Labels**: relay matches labels by name, so names + colors are the contract; their descriptions are cosmetic — localize them (e.g. Chinese) freely. `init-labels.sh` is create-only and won't overwrite labels you already have.

Full conventions, the state machine, and end-to-end examples are in [`skills/relay/SKILL.md`](skills/relay/SKILL.md).

## Codex / other agents

Codex doesn't support the Claude skill / plugin mechanism. To use relay there: copy `relay.py` into the project and lift the conventions from SKILL.md into the project's `AGENTS.md`. `relay.py lint/verify/close` is a standalone CLI any agent can call.

## Roadmap

Distribution is currently "copy files + self-check". Once it matures it will be packaged as an official Claude Code plugin and published to a marketplace — the skill already references its bundled scripts via `${CLAUDE_SKILL_DIR}`, so that migration needs zero path changes.
