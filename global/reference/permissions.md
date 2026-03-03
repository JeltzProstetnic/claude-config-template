# Permissions Reference

Load this file when: subagent tool calls are being auto-denied, or setting up permissions for non-interactive use.

## Why Global Permissions Matter

Subagents (spawned by Claude Code during multi-step tasks) run non-interactively. They cannot prompt you to approve a tool call. If a permission is not pre-granted in `settings.json`, the call is auto-denied and the task silently fails or errors.

Per-project permissions accumulate in `<project>/.claude/settings.local.json` as users approve tools interactively. But:

- **New projects start with zero permissions.**
- **Background subagents cannot prompt the user** for approval (they run non-interactively).
- Without global permissions, background agents (launched with `run_in_background: true`) **silently fail** because every tool use gets auto-denied.

Global permissions in `settings.json` solve this for all projects and all agents.

---

## What's Allowed Without Prompting

### Read-only tools
- `WebSearch`
- `WebFetch(*)`
- `Read(*)`
- `Glob(*)`
- `Grep(*)`

### File modification tools
- `Write(*)`
- `Edit(*)`

### Safe Bash commands

Common command prefixes to allow:

| Command | Pattern | Purpose |
|---------|---------|---------|
| `git` | `Bash(git:*)` | Version control |
| `npm` | `Bash(npm:*)` | Package management |
| `npx` | `Bash(npx:*)` | Package execution |
| `node` | `Bash(node:*)` | Node.js runtime |
| `python3` | `Bash(python3:*)` | Python runtime |
| `pip` | `Bash(pip:*)` | Python packages |
| `uvx` | `Bash(uvx:*)` | Python tool execution |
| `curl` | `Bash(curl:*)` | HTTP requests |
| `gh` | `Bash(gh:*)` | GitHub CLI |
| `docker` | `Bash(docker:*)` | Containers |
| `ls` | `Bash(ls:*)` | Directory listing |
| `cat` | `Bash(cat:*)` | File viewing |
| `echo` | `Bash(echo:*)` | Output |
| `mkdir` | `Bash(mkdir:*)` | Create directories |
| `cp` | `Bash(cp:*)` | Copy files |
| `mv` | `Bash(mv:*)` | Move/rename files |
| `chmod` | `Bash(chmod:*)` | Permissions |
| `kill` | `Bash(kill:*)` | Process management |
| `bash` | `Bash(bash:*)` | Shell scripts |
| `du` | `Bash(du:*)` | Disk usage |
| `wc` | `Bash(wc:*)` | Word/line count |
| `date` | `Bash(date:*)` | Date/time |
| `which` | `Bash(which:*)` | Locate commands |
| `pandoc` | `Bash(pandoc:*)` | Document conversion |
| `weasyprint` | `Bash(weasyprint:*)` | PDF generation |

Platform-specific (add as needed):
- `powershell.exe`, `cmd.exe`, `reg.exe` (WSL/Windows interop)
- `xdg-open` (native Linux)
- `tmux` (VPS/server)
- `qdbus` (KDE/Konsole)
- `dotnet` (.NET projects)

---

## What Still Prompts

- `rm` (file deletion)
- `sudo` (elevated privileges)
- Any command not in the allow list

---

## Example settings.json Permissions Block

Located at `~/.claude/settings.json` (or your launcher's config path):

```json
{
  "permissions": {
    "allow": [
      "Bash(git:*)",
      "Bash(npm:*)",
      "Bash(npx:*)",
      "Bash(node:*)",
      "Bash(python3:*)",
      "Bash(bash:*)",
      "Read(**)",
      "Write(**)",
      "Edit(**)"
    ],
    "deny": []
  }
}
```

Adjust the `allow` list to match the tools your workflows actually use. Overly broad permissions are a security risk; overly narrow ones break subagents.

---

## Diagnosing "Permission auto-denied" Errors

If a background subagent produces weak results or seems stuck:

1. Check its output for `"Permission to use X has been auto-denied"` errors
2. The output file path is shown when the agent is launched
3. If you find auto-denied errors, the tool needs to be added to the global allow list in `settings.json`

### Adding a new permission

Edit `settings.json` and add the command/tool to the `permissions.allow` array. Pattern syntax: `ToolName(glob)` — e.g., `Bash(gh:*)` allows all `gh` subcommands. Restart Claude Code for changes to take effect.

---

## Configuration Location

| What | Where |
|------|-------|
| Global permissions | `~/.claude/settings.json` → `permissions.allow` |
| Per-project permissions | `<project>/.claude/settings.local.json` (accumulated interactively) |

**CRITICAL: `permissions` blocks in `settings.local.json` REPLACE (not extend) global permissions.** Claude Code's "Always allow" button pollutes this file with random one-off approvals, destroying the comprehensive global permission set. If subagents suddenly can't do things they used to, check whether a `permissions` block appeared in the project's `settings.local.json` and remove it.
