# Code Review: {current_branch} → {target_branch}

**Date:** {date}
**Reviewer:** Claude Code (automated first-pass)

## Summary

One or two sentences: what does this change do, and is it broadly safe to merge?

## Findings

### 🔴 Critical
- [ ] `path/to/file.ex:42` — description of the issue and why it's critical

### 🟡 Warnings
- [ ] `path/to/file.ex:88` — description

### 🔵 Suggestions
- [ ] `path/to/file.ex:120` — description (style/readability/minor perf)

## Test coverage

- New logic with no test: list files/functions, or "none found"

## Security notes

- Anything touching auth, input validation, secrets, external calls

## Verdict

One line: Ready to merge / Merge with fixes / Needs rework