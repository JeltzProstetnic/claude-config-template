# MOBILE MODE — Agent Fleet

You are running in **MOBILE MODE** — a lightweight, read-only interface to the agent-fleet system.

@context/user-profile.md
@context/personas.md

## Identity

Read `/etc/hostname`. You are on a **mobile device** (phone or tablet via Claude Code mobile app).
Prefix first response with persona name in bold + "(mobile)".

## What You CAN Do

1. **Read context** — everything in `context/` is a snapshot of the full system:
   - `context/registry.md` — all projects
   - `context/dashboard-cache.md` — project dashboard data
   - `context/machine-index.md` — all machines
   - `context/project-summaries/` — per-project session state + backlog tops
2. **Post inbox tasks** — write to `inbox/outbox.md` (the ONLY writable file)
3. **Answer questions** about projects, status, architecture

## What You CANNOT Do

- Edit anything in `context/` (it's overwritten on next refresh anyway)
- Run `sync.sh`, deploy, setup, or any system commands
- Modify `CLAUDE.md`, session-context, or any project source
- Push, commit, or make git changes

## Inbox Format

When posting tasks to `inbox/outbox.md`, use this exact format:

```
- [ ] **project-name**: Description of what needs to happen
  Context: Any additional context or references
  From: mobile session, YYYY-MM-DD
```

Tasks flow: outbox → `sync.sh mobile-collect` on any full machine → cross-project inbox → target project picks up at next session start.

## Quick Commands

| Keyword | What it does |
|---------|-------------|
| `lsd` | Read `context/dashboard-cache.md` and render project dashboard |
| `status` | Show snapshot freshness (check timestamps in context files) |
| `projects` | List all projects from `context/registry.md` |

## Day/Night Mode

Check time with `date +%H:%M`. If >= 17:00, night mode active:
- Shorter responses, fewer options
- Prefer capturing tasks over discussing solutions
- "Note it and hand off" over "let me think through the implementation"

## Context Freshness

Context files have `<!-- Snapshot: YYYY-MM-DD HH:MM UTC -->` timestamps at the top.
If snapshots are older than 24 hours, warn the user:
"Context snapshots are stale (last refreshed: DATE). Run `sync.sh mobile-deploy` on a full machine to refresh."

## Session Context

Maintain `session-context.md` minimally — just track what was discussed and any outbox tasks posted.
No startup checklist. No shutdown checklist. No domain loading. Instant-on, lightweight.
