# Learn Protocol (`lrn` / `learn`)

Self-audit command. Designed for low-context situations — uses subagents with their own context windows for analysis.

## Execution

Launch **3 parallel Explore subagents** (read-only, each with full context budget):

### Subagent 1 — Rule Compliance

Prompt the subagent with:
- Read `~/.claude/CLAUDE.md` (global rules), the project's `CLAUDE.md`, and `~/.claude/foundation/session-protocol.md`
- Read `session-context.md` in the current project
- Read `git log --oneline -10` output for the current project
- Check: Were any rules violated this session? Common violations:
  - Skipped startup steps
  - Wrote rules without user consent
  - Used `cd &&` compound commands
  - Created new files for daily state
  - Forgot to update session-context.md
  - Committed secrets or gitignored files
  - Skipped TDD
  - Wrote to files outside project boundary
- Report each violation with: rule text, evidence, suggested fix

### Subagent 2 — Knowledge Capture

Prompt the subagent with:
- Read `session-context.md` in the current project
- Read machine file (`~/.claude/machines/<machine>.md`) for the current machine
- Check: Did the user share information this session that isn't captured?
  - New hardware/equipment details → machine files
  - New people/contacts → relationships or people KB files
  - New preferences/habits → appropriate KB file
  - Decisions made → docs/decisions.md
- Also check: Is anything in the KB files contradicted by session activity?
- Report each gap with: what info, where it should go, proposed content

### Subagent 3 — Improvement Finder

Prompt the subagent with:
- Read `session-context.md` and `session-history.md` in the current project
- Read `backlog.md` in the current project
- Read `docs/decisions.md` if it exists
- Check: Are there patterns across recent sessions?
  - Repeated manual steps that could be automated (hooks, scripts)
  - Recurring mistakes that need a rule
  - Missing or stale backlog items
  - Processes that could be streamlined
- Report each finding with: pattern observed, suggested fix (rule, script, or backlog item)

## Presenting Results

After all 3 subagents return:

1. **Consolidate** — group findings by type (violations, gaps, improvements)
2. **Prioritize** — critical violations first, then high-value captures, then improvements
3. **Present** — concise report to user with proposed actions
4. **Approve** — rule changes and KB updates require explicit user approval before persisting
5. **Execute** — after approval, make the changes (edit files, add backlog items)

## Context Efficiency

The `lrn` command is typically issued when context is running low (end of session, after auto-compact). Design choices:
- **Subagents over inline analysis** — each gets a fresh context window
- **Explore agents** — read-only, can't accidentally modify files
- **Parallel execution** — all 3 run simultaneously, minimizing wall-clock time
- **File-based evidence** — subagents read files, not conversation history (which may be compressed)
- **Session-context.md as anchor** — this file should be up-to-date before `lrn` runs; update it first if needed
