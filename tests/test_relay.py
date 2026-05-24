#!/usr/bin/env python3
"""Regression tests for relay.py lint / Verification-block parsing.

Run from the repo root:  python3 tests/test_relay.py
Lives at the repo root (not in skills/relay/) so it is NOT copied into installs.

Locks the *strict* Verification format: the bash block must immediately follow the
`## Verification` heading. A block with prose before it is rejected by design, but
lint must flag it as misplaced (not "missing") so the fix is obvious.
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "skills" / "relay"))
import relay  # noqa: E402

F = "```"  # fence, built indirectly to keep the source readable


def body(verification="canonical", refs=True):
    parts = ["## Goal\n\ndo a thing"]
    if verification == "canonical":
        parts.append(f"## Verification\n\n{F}bash\necho ok\n{F}")
    elif verification == "prose":
        parts.append(f"## Verification\n\nRun these checks:\n\n{F}bash\necho ok\n{F}")
    elif verification == "none":
        parts.append("## Verification\n\nnothing executable here")
    elif verification == "multi":
        parts.append(f"## Verification\n\n{F}bash\necho first\n{F}\n\n{F}bash\necho second\n{F}")
    if refs:
        parts.append("## Refs\n\n- x")
    return "\n\n".join(parts)


def check(name, cond):
    print(f"{'ok' if cond else 'FAIL'}: {name}")
    if not cond:
        check.failed += 1


check.failed = 0

# 1. canonical: block immediately after heading
r = relay.lint_body(body("canonical"))
check("canonical lints ok", r.ok and r.has_verification_block)
check("canonical extracts block", relay.extract_verification_block(body("canonical")) == "echo ok")

# 2. prose before block: rejected (strict) + flagged misplaced with a helpful hint
r = relay.lint_body(body("prose"))
check("prose-between rejected", not r.ok and not r.has_verification_block)
check("prose-between flagged misplaced", r.block_misplaced)
check("prose-between hint says 'must come first'", "must come first" in r.render())
check("prose-between extracts nothing", relay.extract_verification_block(body("prose")) is None)

# 3. Verification present but truly has no bash block
r = relay.lint_body(body("none"))
check("no-block rejected", not r.ok and not r.has_verification_block)
check("no-block not flagged misplaced", not r.block_misplaced)

# 4. missing Refs section
r = relay.lint_body(body("canonical", refs=False))
check("missing Refs rejected", not r.ok and "Refs" in r.missing_sections)

# 5. bash block only in Goal, Verification section has none -> not counted, not misplaced
goal_block = f"## Goal\n\n{F}bash\necho x\n{F}\n\n## Verification\n\ntext\n\n## Refs\n\n- x"
r = relay.lint_body(goal_block)
check("block-in-goal not counted", not r.has_verification_block and not r.block_misplaced)

# 6. multiple canonical blocks -> first is extracted
check("multi extracts first", relay.extract_verification_block(body("multi")) == "echo first")

if check.failed:
    print(f"\n{check.failed} test(s) failed")
    sys.exit(1)
print("\nall relay lint tests passed")
