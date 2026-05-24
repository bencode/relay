#!/usr/bin/env python3
"""
relay.py — GitHub Issue 协作 CLI (Relay v0.2)

只承担多步逻辑：lint / verify / close。
单步动作（assign / 加标签 / 评论）走 gh CLI 直接调用。

约束：Python 3.9+ stdlib only，跨平台 macOS/Linux。
GitHub 操作全部通过 subprocess 调 `gh`。
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass

REQUIRED_SECTIONS = ("Goal", "Verification", "Refs")
VERIFICATION_BLOCK_PATTERN = re.compile(
    r"^## Verification\s*\n+```bash\n(.*?)\n```",
    re.MULTILINE | re.DOTALL,
)
SECTION_PATTERN = re.compile(r"^## (\w+)", re.MULTILINE)


def run_gh(args: list[str], check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["gh", *args],
        capture_output=True,
        text=True,
        check=check,
    )


def fetch_body(num: str) -> str:
    result = run_gh(["issue", "view", num, "--json", "body", "--jq", ".body"])
    return result.stdout


def fetch_author(num: str) -> str:
    result = run_gh(["issue", "view", num, "--json", "author", "--jq", ".author.login"])
    return result.stdout.strip()


def fetch_assignees(num: str) -> list[str]:
    result = run_gh(["issue", "view", num, "--json", "assignees", "--jq", "[.assignees[].login]"])
    return json.loads(result.stdout)


@dataclass
class LintResult:
    ok: bool
    missing_sections: list[str]
    has_verification_block: bool

    def render(self) -> str:
        if self.ok:
            return "✓ lint passed"
        lines = ["✗ lint failed"]
        if self.missing_sections:
            lines.append(f"  missing sections: {', '.join('## ' + s for s in self.missing_sections)}")
        if not self.has_verification_block and "Verification" not in self.missing_sections:
            lines.append("  ## Verification exists but no ```bash block found")
        return "\n".join(lines)


def lint_body(body: str) -> LintResult:
    found = set(SECTION_PATTERN.findall(body))
    missing = [s for s in REQUIRED_SECTIONS if s not in found]
    has_block = bool(VERIFICATION_BLOCK_PATTERN.search(body))
    ok = not missing and has_block
    return LintResult(ok=ok, missing_sections=missing, has_verification_block=has_block)


def extract_verification_block(body: str) -> str | None:
    match = VERIFICATION_BLOCK_PATTERN.search(body)
    return match.group(1) if match else None


@dataclass
class VerifyResult:
    ok: bool
    exit_code: int
    stdout: str
    stderr: str

    def render(self) -> str:
        status = "✓ verify passed" if self.ok else f"✗ verify failed (exit {self.exit_code})"
        parts = [status]
        if self.stdout.strip():
            parts.append("--- stdout ---")
            parts.append(self.stdout.rstrip())
        if self.stderr.strip():
            parts.append("--- stderr ---")
            parts.append(self.stderr.rstrip())
        return "\n".join(parts)


def run_verification(block: str) -> VerifyResult:
    with tempfile.NamedTemporaryFile(mode="w", suffix=".sh", delete=False) as tmp:
        tmp.write("set -e\n")
        tmp.write(block)
        tmp_path = tmp.name
    try:
        result = subprocess.run(
            ["bash", tmp_path],
            capture_output=True,
            text=True,
        )
        return VerifyResult(
            ok=result.returncode == 0,
            exit_code=result.returncode,
            stdout=result.stdout,
            stderr=result.stderr,
        )
    finally:
        import os
        os.unlink(tmp_path)


def cmd_lint(num: str) -> int:
    body = fetch_body(num)
    result = lint_body(body)
    print(result.render())
    return 0 if result.ok else 1


def cmd_verify(num: str) -> int:
    body = fetch_body(num)
    lint_result = lint_body(body)
    if not lint_result.ok:
        print(lint_result.render(), file=sys.stderr)
        print("\nverify aborted: lint failed", file=sys.stderr)
        return 1

    block = extract_verification_block(body)
    assert block is not None
    print(f"running Verification block ({len(block.splitlines())} lines)...")
    print("---")
    result = run_verification(block)
    print(result.render())
    return 0 if result.ok else result.exit_code or 1


def cmd_close(num: str) -> int:
    body = fetch_body(num)
    lint_result = lint_body(body)
    if not lint_result.ok:
        print(lint_result.render(), file=sys.stderr)
        print("\nclose aborted: lint failed", file=sys.stderr)
        return 1

    block = extract_verification_block(body)
    assert block is not None
    print(f"running Verification block before close...")
    verify_result = run_verification(block)
    print(verify_result.render())

    if not verify_result.ok:
        print("\n✗ close aborted: verification failed", file=sys.stderr)
        return verify_result.exit_code or 1

    author = fetch_author(num)
    assignees = fetch_assignees(num)
    cc_creator = author and author not in assignees
    ping_line = f"\n\ncc @{author} 请验收" if cc_creator else ""

    comment_body = (
        f"✓ Verification passed\n\n"
        f"```\n{verify_result.stdout.rstrip() or '(no stdout)'}\n```"
        f"{ping_line}"
    )

    print("\nclosing issue...")
    run_gh([
        "issue", "close", num,
        "--reason", "completed",
        "--comment", comment_body,
    ])
    run_gh(["issue", "edit", num, "--remove-label", "state:in-progress"], check=False)
    run_gh(["issue", "edit", num, "--add-label", "state:needs-verification"])

    url_result = run_gh(["issue", "view", num, "--json", "url", "--jq", ".url"])
    print(f"\n✓ closed: {url_result.stdout.strip()}")
    if cc_creator:
        print(f"  cc'd creator @{author} for verification")
    else:
        print(f"  (creator == assignee, no cc needed)")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="relay.py",
        description="GitHub Issue collaboration CLI (Relay v0.2)",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    p_lint = subparsers.add_parser("lint", help="check issue body structure")
    p_lint.add_argument("num", help="issue number")

    p_verify = subparsers.add_parser("verify", help="run Verification block")
    p_verify.add_argument("num", help="issue number")

    p_close = subparsers.add_parser("close", help="verify + close + label switch")
    p_close.add_argument("num", help="issue number")

    args = parser.parse_args()

    dispatch = {
        "lint": cmd_lint,
        "verify": cmd_verify,
        "close": cmd_close,
    }
    return dispatch[args.command](args.num)


if __name__ == "__main__":
    sys.exit(main())
