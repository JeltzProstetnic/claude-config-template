# Claude Code Permissions — Known Issues & Best Practices

## The settings.local.json Override Problem

**Root cause:** When Claude Code prompts "Allow this tool?" and the user clicks "Allow", it appends the specific command pattern to the project's `.claude/settings.local.json` under `permissions.allow`. This creates a **project-level** permissions block that **completely replaces** the global `settings.json` permissions — it does NOT merge with or extend the global list.

**Symptom:** After a few sessions in a project, the `settings.local.json` accumulates random one-off approvals (e.g., `Bash(cat:*)`, `Bash(echo === grep -q:*)`) but is missing critical entries from the global config (e.g., `Bash(git:*)`, `Bash(du:*)`). This causes the shutdown checklist and common operations to prompt for permission every time.

**Fix:** Remove the entire `permissions` block from `settings.local.json`. The global `settings.json` has comprehensive auto-approvals that cover all standard operations.

**Prevention:**
1. When prompted to allow a tool in any project, prefer "Allow for this session" over "Always allow" to avoid polluting `settings.local.json`
2. If a command should be permanently allowed, add it to the global `settings.json` instead
3. The `config-check.sh` hook should detect and warn about permission blocks in project settings

**Which file controls what:**
| File | Scope | Override behavior |
|------|-------|-------------------|
| Global `settings.json` | Global (all projects) | Base permissions |
| `<project>/.claude/settings.local.json` | One project | **REPLACES** global permissions if `permissions` key exists |
| `<project>/.claude/settings.json` | One project (committed) | Same override behavior |

**Key insight:** `settings.local.json` should ONLY contain project-specific MCP server configuration (`enabledMcpjsonServers`, `enableAllProjectMcpServers`). It should NEVER have a `permissions` block unless you intentionally want to restrict that project's permissions below the global baseline.
