# Learn Protocol (`lrn` / `learn`)

Self-audit command. Designed for low-context situations — uses subagents with their own context windows for analysis.

## Execution

**Adaptive, not fixed.** Assess the situation first, then launch 1-3 parallel Explore subagents tailored to what's relevant. Don't run all 3 categories if only 1-2 apply.

### Step 1 — Triage (inline, no subagent)

Before launching subagents, quickly assess:
- **What went wrong?** Rule violation, missed info, process gap, architecture issue?
- **What's the user's tone?** Frustrated (→ root cause + fix), curious (→ deeper analysis), directive (→ just do it)?
- **Which audit categories are relevant?**

### Step 2 — Pick relevant agents

| Category | When to include | Skip when... |
|----------|----------------|-------------|
| **Rule Compliance** | Something broke, a protocol was violated, user says "learn from this" | Issue is purely architectural or forward-looking |
| **Knowledge Capture** | User shared personal/equipment/people info this session | Session was purely operational, no new info shared |
| **Process/Architecture** | Repeated pattern, automation opportunity, workflow gap, scaling issue | One-off mistake with obvious inline fix |

Launch only the relevant ones. 1 agent is fine if the issue is clear. All 3 only if the situation is genuinely multi-faceted.

### Agent Templates

#### Rule Compliance Agent
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

#### Knowledge Capture Agent
Prompt the subagent with:
- Read `session-context.md` in the current project
- Read machine file (`~/.claude/machines/<machine>.md`) for the current machine
- Read `~/.claude/domains/life-management/relationships.md` (people KB)
- Read `~/.claude/domains/life-management/family.md`
- Check: Did the user share information this session that isn't captured?
  - New hardware/equipment details → machine files
  - New people/contacts → relationships.md
  - New preferences/habits → appropriate KB file
  - Personal/family context → family.md
  - Decisions made → docs/decisions.md
- Also check: Is anything in the KB files contradicted by session activity?
- Report each gap with: what info, where it should go, proposed content

#### Process/Architecture Agent
Prompt the subagent with:
- Read `session-context.md` and `session-history.md` in the current project
- Read `backlog.md` in the current project
- Read `docs/decisions.md` if it exists
- Focus on the specific pattern/issue identified in triage
- Check: Are there systemic improvements needed?
  - Repeated manual steps that could be automated (hooks, scripts)
  - Recurring mistakes that need a rule
  - Missing classification or metadata (e.g., task recurrence types)
  - Processes that could be streamlined
- Report each finding with: pattern observed, suggested fix (rule, script, or backlog item)

## Presenting Results

After subagents return:

1. **Consolidate** — group findings by type
2. **Prioritize** — critical fixes first, then high-value improvements
3. **Present** — concise report to user with proposed actions
4. **Approve** — rule changes and KB updates require explicit user approval before persisting
5. **Execute** — after approval, make the changes (edit files, add backlog items)

## Context Efficiency

- **Subagents over inline analysis** — each gets a fresh context window
- **Explore agents** — read-only, can't accidentally modify files
- **Parallel execution** — all selected agents run simultaneously
- **File-based evidence** — subagents read files, not conversation history (which may be compressed)
- **Session-context.md as anchor** — this file should be up-to-date before `lrn` runs; update it first if needed
- **Adaptive count** — 1 agent for clear issues, 2-3 for multi-faceted situations. Don't waste tokens on categories that obviously don't apply.
