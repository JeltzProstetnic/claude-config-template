# Claude Code Permissions — Known Issues & Best Practices

## The settings.local.json Override Problem

**Root cause:** When Claude Code prompts "Allow this tool?" and the user clicks "Allow", it appends the specific command pattern to the project's `.claude/settings.local.json` under `permissions.allow`. This creates a **project-level** permissions block that **completely replaces** the global `settings.json` permissions — it does NOT merge with or extend the global list.

**Symptom:** After a few sessions in a project, the `settings.local.json` accumulates random one-off approvals (e.g., `Bash(cat:*)`, `Bash(echo === grep -q:*)`) but is missing critical entries from the global config (e.g., `Bash(git:*)`, `Bash(du:*)`). This causes the shutdown checklist and common operations to prompt for permission every time.

**Fix:** Remove the entire `permissions` block from `settings.local.json`. The global `settings.json` (at `~/.cc-mirror/mclaude/config/settings.json`) has comprehensive auto-approvals that cover all standard operations.

**Prevention:**
1. When prompted to allow a tool in any project, prefer "Allow for this session" over "Always allow" to avoid polluting `settings.local.json`
2. If a command should be permanently allowed, add it to the global `settings.json` instead
3. cfg-agent-fleet's `config-check.sh` hook should detect and warn about permission blocks in project settings

**Which file controls what:**
| File | Scope | Override behavior |
|------|-------|-------------------|
| `~/.cc-mirror/mclaude/config/settings.json` | Global (all projects) | Base permissions |
| `<project>/.claude/settings.local.json` | One project | **REPLACES** global permissions if `permissions` key exists |
| `<project>/.claude/settings.json` | One project (committed) | Same override behavior |

**Key insight:** `settings.local.json` should ONLY contain project-specific MCP server configuration (`enabledMcpjsonServers`, `enableAllProjectMcpServers`). It should NEVER have a `permissions` block unless you intentionally want to restrict that project's permissions below the global baseline.

## Compound Command Permission Problem

**Root cause:** Bash permissions use prefix matching. `Bash(cd:*)` and `Bash(git:*)` individually don't cover compound commands like `cd ~/project && git status`. The compound command is evaluated as a whole string, and `cd ~/project && git status` starts with `cd` but Claude Code's security layer flags it as a compound command with `&&` — triggering the "bare repository attacks" safety warning regardless of individual permissions.

**Fix — avoid compound commands in automation:** When Claude needs to run git commands in another directory, use `git -C <path>` instead of `cd <path> && git`:
- Instead of: `cd ~/social && git status` → Use: `git -C ~/social status`
- Instead of: `cd ~/project && git add . && git commit` → Use: `git -C ~/project add . && git -C ~/project commit`

**Behavioral rule for Claude:** NEVER use `cd <dir> && <command>` patterns. Use `-C` flags, absolute paths, or `--work-tree`/`--git-dir` for git. For non-git commands, use absolute paths directly.

## Auto-Clean Hook (config-check.sh Check 10)

The SessionStart hook `config-check.sh` now includes Check 10, which automatically:
1. Scans all `~/*/.claude/settings.local.json` files
2. If a `"permissions"` key is found, removes it (keeping all other config)
3. Warns in the session startup message

This prevents permission contamination from persisting across sessions.
