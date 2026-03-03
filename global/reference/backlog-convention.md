# Backlog Convention — Full Reference

Load this when: creating a new project backlog, managing task IDs, or reviewing prioritization rules.

## Format

Every project has `backlog.md` at root. Do NOT read at session start — only when active tasks are done or user asks.

```
# Backlog — <project-name>

## Open

- [ ] [P1] `PRJ-01` **Task title**: Description

## Done

### YYYY-MM-DD (most recent session only)
- [x] Completed task description

Older completed items: `docs/backlog-archive.md`
```

## Task IDs

Every open task gets a stable ID: `PRJ-NN` where `PRJ` is a short project prefix (2-4 uppercase letters) and `NN` is a zero-padded sequential number. IDs are unique within a project — never reused, even after completion. The user can reference tasks by ID across sessions.

Standard prefixes (customize for your projects):

| Prefix | Project |
|--------|---------|
| `CFG` | Config/meta project |
| `INF` | Infrastructure |
| `APP` | Application project |
| `WEB` | Web frontend |
| `API` | Backend/API service |
| `DOC` | Documentation project |

New projects: pick a 2-4 letter prefix, add to this table.

## Keep Backlogs Lean

Only the last session's Done section stays in `backlog.md`. Older completed items move to `docs/backlog-archive.md` (append-only, oldest first). This prevents backlogs from growing into multi-hundred-line token sinks.

## Project Prioritization

Registry has a `Priority` column (P1-P5). Backlog tasks carry a priority tag.

- **Project priority** (in `registry.md`): P1 = critical/daily, P2 = active/weekly, P3 = ongoing/as-needed, P4 = paused, P5 = dormant
- **Task priority** (in backlogs): prefix task line with `[P1]`-`[P5]`, e.g. `- [ ] [P1] `PRJ-01` **Fix deployment bug**: Description`. Untagged tasks default to P3.
- **Cross-project ranking**: sort by project priority first, then task priority within each project. A P2 task in a P1 project outranks a P1 task in a P3 project.
- **Open section**: flat list sorted by priority (P1 first), no subsections. Keep it scannable.
- **Done section**: group by date, most recent first. Move tasks here when completed — don't delete them.