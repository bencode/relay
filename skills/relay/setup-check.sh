#!/usr/bin/env bash
# Relay setup-check — one-shot self-test (project-agnostic)
# Verifies gh / python / relay.py / issue-read access are all available.
# Usage: bash <skill-dir>/setup-check.sh
# Exit 0 = all passed; non-zero = something is missing
#
# Auto-detects repo + owner from the current git remote, no config needed.
# Works inside any GitHub-based project (personal repos and org repos alike).

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0
REPO=""

check() {
  local name="$1"; shift
  local hint="$1"; shift
  if "$@" > /dev/null 2>&1; then
    printf "  \033[32m✓\033[0m  %s\n" "$name"
    PASS=$((PASS + 1))
  else
    printf "  \033[31m✗\033[0m  %s\n" "$name"
    printf "      → %s\n" "$hint"
    FAIL=$((FAIL + 1))
  fi
}

printf "\n  Relay setup check\n  ─────────────────\n\n"

check "gh CLI installed" \
  "macOS: brew install gh    Linux: see https://github.com/cli/cli/blob/trunk/docs/install_linux.md" \
  command -v gh

check "gh authenticated" \
  "run: gh auth login" \
  bash -c "gh auth status 2>&1 | grep -q 'Logged in'"

check "inside a GitHub repo" \
  "cd into a project that has a GitHub remote (git remote -v should show github.com)" \
  bash -c "gh repo view --json nameWithOwner -q .nameWithOwner"

# Capture repo + authenticated user for downstream checks
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")
ME=$(gh api user --jq .login 2>/dev/null || echo "")

if [ -n "$REPO" ]; then
  OWNER="${REPO%%/*}"
  # The org-membership check only makes sense when the owner is an org (not yourself).
  # Personal repos (owner == you) skip it — repo access is covered by "can list issues".
  if [ -n "$OWNER" ] && [ "$OWNER" != "$ME" ]; then
    check "member of org '${OWNER}'" \
      "ask the org owner to invite you at https://github.com/orgs/${OWNER}/people" \
      bash -c "gh api user/memberships/orgs/${OWNER} 2>&1 | grep -q '\"state\": *\"active\"'"
  fi
fi

check "python3 >= 3.9" \
  "install Python 3.9+ (macOS 12+ / Ubuntu 20.04+ should already have it)" \
  python3 -c "import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)"

check "relay.py runnable" \
  "make sure relay.py sits next to this script in the skill dir" \
  python3 "$SCRIPT_DIR/relay.py" --help

check "can list issues in current repo" \
  "check repo permissions; or run 'gh repo set-default' if there are multiple remotes" \
  gh issue list --limit 1 --json number

printf "\n  ─────────────────\n"
if [ -n "$REPO" ]; then
  printf "  Repo: %s\n" "$REPO"
fi
if [ $FAIL -eq 0 ]; then
  printf "  \033[32m✓ All %d checks passed.\033[0m Setup OK — you can start using relay now.\n\n" $PASS
  exit 0
else
  printf "  \033[31m✗ %d / %d checks failed.\033[0m Fix the items above, then re-run this script.\n\n" $FAIL $((PASS + FAIL))
  exit 1
fi
