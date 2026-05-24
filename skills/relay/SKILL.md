---
name: relay
description: AI agent collaboration on GitHub Issues. Use when the user asks "what work is open / list open issues", "what's on my plate", "create/close an issue", "assign this to @xxx / Claude Code / Helm", "what is @xxx working on", "who owns this", or anything about routing tasks. **All data goes through the gh CLI; multi-step logic (lint / verify / close) goes through relay.py. Never create local issue files (.relay/issues/*.yaml etc.).**
---

# relay

The source of truth for collaboration is **GitHub Issues** (gh auto-detects the current repo). Two tools work together:
- **`gh` CLI** — single-step actions (list / view / create / edit / comment / reopen, ...)
- **`relay.py`** — multi-step logic (lint / verify / close)

## Prerequisites

**Run the self-check before first use:**

```bash
bash "${CLAUDE_SKILL_DIR}/setup-check.sh"
```

All checks must be ✓ before you start. Any ✗ prints a fix hint. It checks:
- `gh` CLI installed
- `gh` authenticated
- current directory is inside a GitHub repo
- member of the repo's org (skipped automatically for personal repos)
- `python3` 3.9+ available
- `relay.py` runnable
- can read issues in the current repo

Once it passes, every `gh` command targets the current repo (resolved from the git remote).

## Output style (important: default behavior)

**When showing an issue to the user, always paste the clickable URL first; do not render the body in the terminal.**

Default form:
```
#42  Extract shared validation helper  [state:verified]  @<handle>
     https://github.com/<owner>/<repo>/issues/42
```

**Expand the body only when the user explicitly asks**, e.g.:
- "**analyze** what #42 is asking for"
- "**summarize** the key points of #42"
- "**compare** #42 with #43"
- "take over #42" (you're about to start, so you need full context)

## Required issue structure (since v0.2)

Every issue body must contain 3 sections. **`relay.py lint` enforces this; an issue that fails lint cannot be closed.**

### `## Goal`
A quantified description of what to do. Prefer the observable form: "after this, the system will have state X".

- Good: `Add user_settings table + GET/PUT /api/users/:id/settings endpoint + test coverage`
- Bad: `Improve the user settings experience` (not quantified)

### `## Verification` (the core — code as sensor)
One ` ```bash ... ``` ` block; every command must pass before close is allowed. The commands themselves are the formal definition of "done".

Example:
```bash
test -f src/lib/validate.ts
grep -q "export function validate" src/lib/validate.ts
pnpm test src/lib/validate.test.ts --silent
```

**Constraints:**
- Only one bash block is allowed (relay.py extracts the first one).
- Don't write manual steps like `# manual: visually confirm ...` — v0.2 only accepts executable commands, forcing "done" to be formalized.
- Commands should be genuinely repeatable (dry-run mindset).

### `## Refs`
- `doc: docs/xxx.md` or a markdown link
- related file paths
- related issue / PR numbers (`#N`, `owner/other-repo#42`)

## Collaboration semantics

### assignee = the person primarily responsible
`assignee` is a GitHub username (e.g. `<your-handle>`). An issue can have 0-N assignees.
Don't use aliases / nicknames as the assignee — it must be a real GitHub user. Put nickname call-outs in the body.

### AI handler = a label, not an assignee slot

| label | meaning |
|---|---|
| `actor:claude-code` | this issue is meant for Claude Code (human-triggered) |
| `actor:helm-agent` | handled by Helm's automatic loop |
| `actor:scheduled` | taken over by a scheduled job |

Add a label: `gh issue edit <num> --add-label actor:claude-code`

> After installing this skill in a new repo, create these labels once on GitHub:
> ```bash
> gh label create "actor:claude-code" --color "5319e7"
> gh label create "actor:helm-agent" --color "5319e7"
> gh label create "actor:scheduled" --color "5319e7"
> ```
> Or just run `bash "${CLAUDE_SKILL_DIR}/init-labels.sh"` to create all 7 labels at once.

### issues are decoupled from branches
An issue is a project-level collaboration object; don't switch git branches because an issue's state changed. `gh` always talks to GitHub regardless of the branch you're on.

## Issue lifecycle (v0.2 state machine)

### The 4 lifecycle labels

| label | meaning | added / removed by |
|---|---|---|
| `state:in-progress` | assignee is working | assignee adds; `relay.py close` removes it automatically |
| `state:needs-clarification` | waiting for the creator to add info | assignee adds / removes |
| `state:needs-verification` | closed, waiting for the creator to verify in person | `relay.py close` adds it; creator removes it when verifying |
| `state:verified` | creator has personally verified | creator adds it when satisfied |

> After installing this skill in a new repo, create these labels once on GitHub:
> ```bash
> gh label create "state:in-progress" --color "fbca04"
> gh label create "state:needs-clarification" --color "d93f0b"
> gh label create "state:needs-verification" --color "1d76db"
> gh label create "state:verified" --color "0e8a16"
> ```
> Or just run `bash "${CLAUDE_SKILL_DIR}/init-labels.sh"` (one script covers actor labels too).

### State semantics matrix

| open/closed | label | meaning |
|---|---|---|
| open | none | just assigned, not started |
| open | `state:in-progress` | assignee is working |
| open | `state:needs-clarification` | waiting for the creator to add info |
| closed | `state:needs-verification` | waiting for the creator to verify |
| closed | `state:verified` | verified, fully done |
| closed | no lifecycle label | anomaly (process not completed / legacy issue) |

### Role boundaries

- **Creator (A)**: the originator. Writes a clear body and verifies in person after close (adds `state:verified` if satisfied; reopens if not).
- **Assignee (B)**: the doer. Drives open → closed (including a passing verify); not responsible for acceptance.

### Full flow (8-stage action checklist)

| stage | who | action | tool | command |
|---|---|---|---|---|
| 1 | A | create + auto lint | gh + relay.py | `gh issue create --body-file ...` then `relay.py lint <num>` to re-check |
| 1 | A | assign | gh | `gh issue edit <num> --add-assignee <handle>` |
| 2 | B | view | gh | `gh issue view <num>` |
| 3 | B | start work | gh | `gh issue edit <num> --add-label state:in-progress` |
| 3 | B | ask for clarification | gh | `gh issue comment <num> --body "..."` + `gh issue edit --add-label state:needs-clarification` |
| 4 | B | clarification resolved | gh | `gh issue edit --remove-label state:needs-clarification --add-label state:in-progress` |
| 5 | B | progress update | gh | `gh issue comment` (optional) |
| 6 | B | close | relay.py | `python3 "${CLAUDE_SKILL_DIR}/relay.py" close <num>` |
| 7 | A | accept (satisfied) | gh | `gh issue edit <num> --remove-label state:needs-verification --add-label state:verified` |
| 7 | A | reject (not satisfied) | gh | `gh issue reopen <num>` + `gh issue edit --remove-label state:needs-verification --add-label state:in-progress` + comment |

**Only close goes through relay.py** (multi-step: verify + close + switch labels + ping creator). Everything else is a single gh command.

## Verification workflow

### Always close via relay.py — never `gh issue close` directly

What `relay.py close <num>` does internally:
1. Lint first (bad structure → close is refused).
2. Extract the Verification bash block and run it (`set -e`, command by command).
3. Any command fails → print the failure and do **not** close.
4. All pass →
   - `gh issue close --reason completed --comment <verify-output + cc @creator>`
   - remove `state:in-progress`
   - add `state:needs-verification`
5. Print the issue URL + ping status.

### Use lint to re-check an existing issue

If you take over a legacy issue (no 3-section structure):
```bash
python3 "${CLAUDE_SKILL_DIR}/relay.py" lint <num>
```
Fails → clarify back and forth with the creator, retrofit the body, then start.

### Use verify as a trial run

Run verify anytime to ask "is it done yet?" without closing:
```bash
python3 "${CLAUDE_SKILL_DIR}/relay.py" verify <num>
```

## Creator acceptance flow

After `relay.py close`, the issue becomes `closed + state:needs-verification`.
GitHub notifies the creator. The creator decides:

### Satisfied
After reviewing the code / running the feature in person and it looks OK:
```bash
gh issue edit <num> --remove-label state:needs-verification --add-label state:verified
```
(No comment required; use `gh issue comment` if you want to say something.)

Final state: `closed + state:verified` = fully done.

### Not satisfied
Found a problem during personal verification (machine verify passed but human acceptance failed):
```bash
gh issue reopen <num>
gh issue edit <num> --remove-label state:needs-verification --add-label state:in-progress
gh issue comment <num> --body "Reopen reason: xxx still doesn't work / needs change ..."
```

Back to open + in-progress; the assignee continues.

## Core operations (single-step gh commands)

### What's on my plate
```bash
gh issue list --assignee @me --state open --json number,title,url,labels,createdAt
```

### Work assigned to AI
```bash
gh issue list --label actor:claude-code --state open --json number,title,url,assignees
```

### Work waiting for my acceptance (creator view)
```bash
gh issue list --author @me --state closed --label state:needs-verification --json number,title,url
```

### Full context (for the LLM)
```bash
gh issue view <num> --json number,title,body,state,stateReason,assignees,labels,comments,url,createdAt,closedAt,closedByPullRequestsReferences
```

### Create an issue
```bash
gh issue create --title "Title" --body-file /tmp/issue-body.md \
  --assignee <handle> --label actor:claude-code
```
**Note**: the body must contain the Goal / Verification / Refs sections. Run `relay.py lint <num>` after creating to re-check.

### Change assignee / label / hand off
```bash
gh issue edit <num> --add-assignee <new> --remove-assignee <old>
gh issue edit <num> --add-label actor:helm-agent --remove-label actor:claude-code
```

### Comment / cross-issue references
```bash
gh issue comment <num> --body "..."
# writing #123 / owner/other-repo#42 in the body auto-links
```

## End-to-end examples

### A. Create an issue for Claude Code to handle

1. Confirm the concrete Goal / Verification / Refs sections with the user.
2. Write the body file:
```bash
cat > /tmp/issue-body.md <<'EOF'
## Goal

Extract a shared input validation helper so the API routes and the worker pipeline reuse one implementation. After this:

- `src/lib/validate.ts` exports `validate(input)` returning a typed result
- all callers switch to the shared function, no duplicate implementations

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
3. Create + re-lint:
```bash
gh issue create --title "Extract shared validation helper" \
  --body-file /tmp/issue-body.md \
  --assignee <handle> --label actor:claude-code
python3 "${CLAUDE_SKILL_DIR}/relay.py" lint <num>
```
4. Paste the URL to the user:
```
✓ created: #42 Extract shared validation helper
  https://github.com/<owner>/<repo>/issues/42
```

### B. See what's on my plate

```bash
gh issue list --assignee @me --state open --json number,title,url,labels
```

With URLs, grouped by state:
```
@<me> open issues (N):

[state:in-progress]:
  #42  Extract shared validation helper
       https://github.com/<owner>/<repo>/issues/42

[state:needs-clarification]:
  #43  ...
       https://...

[no state label] waiting to be picked up:
  #44  ...
       https://...
```

### C. I finished #42, close it

**Do not** close with `gh issue close`. Go through relay.py:

```bash
python3 "${CLAUDE_SKILL_DIR}/relay.py" close 42
```

Internally: lint → verify → close + switch labels + cc creator.
Any failing step prints the reason and does not close.

On success, tell the user:
```
✓ closed: https://github.com/<owner>/<repo>/issues/42
  cc'd creator @<name> for verification

Waiting for creator acceptance (label: state:needs-verification)
```

### D. I'm the creator, accepting #42

Review / run the feature in person first.

**Satisfied:**
```bash
gh issue edit 42 --remove-label state:needs-verification --add-label state:verified
```

**Not satisfied:**
```bash
gh issue reopen 42
gh issue edit 42 --remove-label state:needs-verification --add-label state:in-progress
gh issue comment 42 --body "Reopen reason: xxx is still a bit off / didn't account for yyy"
```

### E. Hand #42 off to someone else

```bash
gh issue edit 42 --remove-assignee <old> --add-assignee <new> \
  --remove-label actor:claude-code
gh issue comment 42 --body "Handing off to @<new>"
```

### F. List issues closed this week

```bash
gh issue list --state closed --search "closed:>$(date -v-7d +%Y-%m-%d)" \
  --json number,title,url,closedAt,stateReason,labels
```

## Anti-patterns (never do these)

- ❌ **Don't create local issue files** like `.relay/issues/*.yaml` — the source of truth is GitHub Issues; a local copy means two diverging tracks.
- ❌ **Don't build an actors.yaml** nickname map — use GitHub handles directly; simple and unambiguous. Reconsider only if the team is large enough that handles are hard to remember.
- ❌ **Don't use a GitHub Issue as a substitute for code review** — PRs / commit messages are still where you discuss code.
- ❌ **Don't switch git branches because an issue's state changed** — they're independent.
- ❌ **Don't write an issue body without the 3-section structure** — `relay.py lint` rejects it, wasting round-trips.
- ❌ **Don't write `# manual: ...` in Verification** — v0.2 only accepts executable commands.
- ❌ **Don't close with `gh issue close` directly; always use `relay.py close`** — bypassing verify is self-reporting "done".
- ❌ **Don't work silently without the `state:in-progress` label** — others won't know you're on it.
- ❌ **Don't forget to switch `state:needs-verification` ↔ `state:verified`** — closed with no lifecycle label = anomaly.
- ❌ **When the creator is satisfied, don't reopen** — just remove needs-verification and add verified; reopening signals more work is needed.

## When / where NOT to use this skill

- User asks about "git push / pull / merge code" → use git, not relay.
- User asks about "deploy / ship" → use the project's deploy skill.
- User asks about "query the database" → use the project's data-query skill.
- Strongly tied to PR review → do it in PR comments, don't open an issue.

## Installing into a new project

Recommended transparent steps (use these when an agent installs it itself; don't use `curl | bash` — the permission/auto mode will block it). From the target project root:

```bash
git clone --depth 1 https://github.com/bencode/relay /tmp/relay
mkdir -p .claude/skills && cp -r /tmp/relay/skills/relay .claude/skills/ && rm -rf /tmp/relay
bash .claude/skills/relay/init-labels.sh      # create the 7 labels (idempotent)
bash .claude/skills/relay/setup-check.sh       # self-check
```

After installing: commit `.claude/skills/relay/` into git; add a line in the project's `AGENTS.md` / `CLAUDE.md` pointing to this skill.

For a quick manual install you can run `curl -fsSL https://raw.githubusercontent.com/bencode/relay/main/install.sh | bash` (equivalent to the steps above).

**Project-specific conventions** (team members, particular process preferences) belong in the project's own AGENTS.md, not in this skill.
