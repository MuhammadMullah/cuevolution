# Code Review Instructions

You are performing a focused code review of the diff between the current
branch and the target branch. You are NOT being asked to refactor or fix
anything — only to review and report.

## Process

1. Run `git diff <target>...HEAD` (or `git diff <target> HEAD` if no merge
   base divergence) to see exactly what changed. Do not review the whole
   repo — only the diff.
2. For any changed file where the diff alone isn't enough context, read the
   full file to understand surrounding logic.
3. Write your findings to `./test/claude/reviews/REVIEW_<branch>_<date>.md`
   using the structure in REVIEW_TEMPLATE.md (already copied into that
   folder).

## What to look for, in priority order

1. **Correctness bugs** — logic errors, off-by-one, race conditions,
   unhandled edge cases, incorrect error handling.
2. **Security** — injection risks, unsafe deserialization, secrets in code,
   missing auth checks, unvalidated input.
3. **Concurrency/state issues** — especially relevant for Elixir/OTP code:
   GenServer state mutation bugs, supervision tree issues, blocking calls
   inside GenServer callbacks, unsupervised processes.
4. **Test coverage** — flag any new logic branch with no corresponding test.
5. **Style/conventions** — only flag if it violates the conventions below;
   don't nitpick personal preference.
6. **Performance** — N+1 queries, unnecessary Enum passes over large
   collections, missing indexes implied by new query patterns.

## Project conventions

- Language/framework: Elixir / Phoenix (LiveView where relevant)
- Formatting: `mix format` is the source of truth — don't flag pure
  formatting issues, only logic
- Naming: snake_case for functions/variables, PascalCase for modules
- Tests: ExUnit, colocated under `test/`, mirroring `lib/` structure
- Avoid flagging anything already covered by Credo/Dialyzer in CI

## Output rules

- Be specific: cite file paths and line numbers for every finding.
- Severity-tag every finding: 🔴 Critical / 🟡 Warning / 🔵 Suggestion.
- If the diff is clean, say so explicitly — don't invent issues to fill
  space.
- Keep prose tight. Bullet points over paragraphs.