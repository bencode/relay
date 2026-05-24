#!/usr/bin/env bash
# Relay init-labels — create the 7 labels relay uses, once, on the current repo (idempotent)
# Usage: bash <skill-dir>/init-labels.sh
# Targets the GitHub repo of the current git remote. --force updates existing labels instead of erroring.

set -u

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")
if [ -z "$REPO" ]; then
  printf "\033[31m✗\033[0m Not inside a GitHub repo, or gh is not authenticated. cd into the target project and run gh auth login.\n"
  exit 1
fi

printf "\n  Creating relay labels on %s\n  ─────────────────\n" "$REPO"

# name  color  description
create() {
  local name="$1" color="$2" desc="$3"
  if gh label create "$name" --color "$color" --description "$desc" --force >/dev/null 2>&1; then
    printf "  \033[32m✓\033[0m  %s\n" "$name"
  else
    printf "  \033[31m✗\033[0m  %s (creation failed, check permissions)\n" "$name"
  fi
}

# AI handler (purple)
create "actor:claude-code"  "5319e7" "Meant for Claude Code (human-triggered)"
create "actor:helm-agent"   "5319e7" "Handled by Helm's automatic loop"
create "actor:scheduled"    "5319e7" "Taken over by a scheduled job"

# Lifecycle states
create "state:in-progress"         "fbca04" "Assignee is working"
create "state:needs-clarification" "d93f0b" "Waiting for the creator to add info"
create "state:needs-verification"  "1d76db" "Closed, waiting for the creator to verify"
create "state:verified"            "0e8a16" "Creator has personally verified"

printf "  ─────────────────\n  done.\n\n"
