# Agent Fleet -- Onboarding Guide

Multi-project, multi-machine configuration system for Claude Code. One git repo manages your AI agent's behavior, knowledge, and state across all your projects and computers.

---

## 1. Prerequisites

| Requirement | Minimum | Install |
|-------------|---------|---------|
| **Git** | Any recent | `sudo apt install git` / `brew install git` |
| **Node.js** | 18+ | `sudo apt install nodejs npm` / `brew install node` |
| **Claude Code** | Latest | [docs.anthropic.com/en/docs/claude-code](https://docs.anthropic.com/en/docs/claude-code/getting-started) |
| **Python 3** | 3.8+ (optional) | Pre-installed on most systems. Enhances setup scripts. |

**Windows users:** Claude Code runs inside WSL (Windows Subsystem for Linux), not natively on Windows. Setup:

1. Open PowerShell as Administrator
2. Run `wsl --install` and restart
3. Open the "Ubuntu" app from the Start menu
4. All commands below happen inside that Linux terminal
5. Always work in `~/` (Linux filesystem) -- never in `/mnt/c/` (10-15x slower)

---

## 2. Setup (5 Minutes)

### Fork, clone, run

```bash
# 1. Fork the repo on GitHub (click the Fork button), then:
git clone https://github.com/YOUR_USERNAME/agent-fleet ~/agent-fleet

# 2. Run setup
cd ~/agent-fleet && bash setup.sh

# 3. Verify
bash sync.sh status
```

### What setup.sh does

The script runs automatically with no interactive prompts:

| Step | What happens |
|------|-------------|
| Platform detection | Identifies Ubuntu, Fedora, Arch/SteamOS, macOS, or WSL automatically |
| Dependency install | Installs Node.js, npm, and cc-mirror if not present |
| Symlinks | Links `global/` files into `~/.claude/` so Claude reads them at startup |
| Hooks | Installs session start/end scripts for auto-sync and crash recovery |
| Machine file | Creates a stub machine config with detected platform info |

After setup, `~/.claude/` contains symlinks pointing back to the repo. Edit in either location -- same files.

### First-run onboarding (conversational)

The first time you open Claude Code after `setup.sh`, the agent detects a `.setup-pending` marker and starts a **conversational onboarding** -- no forms, no prompts, no data entry. The agent asks about:

- Who you are and what you work on
- Your communication style preferences (formal, casual, humor, etc.)
- Whether you want multiple personas (e.g., a workhorse default and an encouraging mode when frustrated)
- Which MCP integrations you need (GitHub, Gmail, Jira, etc.)

Everything is gathered through natural conversation and written to the appropriate config files automatically. You can skip any topic or come back to it later.

### Credential setup (optional)

If you use MCP servers that need API tokens:

```bash
cp secrets/vault.json.example secrets/vault.json
nano secrets/vault.json                          # Add your tokens
bash secrets/vault-manage.sh encrypt             # Encrypt (plaintext is gitignored)
```

On other machines, decrypt and deploy:

```bash
bash secrets/vault-manage.sh deploy              # Decrypt + write tokens to MCP configs
```

---

## 3. Key Concepts

### Registry

**File:** `registry.md`

The master list of all your projects. Each entry has a name, path, priority tier (P1--P5), type, and optional parent project. Claude reads this to know what exists and how important it is. The `lsd` dashboard renders from here.

Add a row whenever you create a new project. Remove rows for abandoned ones.

### Session Context

**File:** `session-context.md` (per project)

Tracks what Claude is working on, what's done, and how to resume if the session crashes. Created automatically in each project directory. Claude updates it continuously and archives it at shutdown.

This is the crash-recovery mechanism. If a session dies unexpectedly, the next session reads the file and picks up where things left off.

### Cross-Project Inbox

**File:** `cross-project/inbox.md`

The only way for projects to communicate with each other. Format:

```markdown
- [ ] **target-project**: Description of what needs to happen
```

At startup, Claude checks the inbox for tasks targeting the current project, acts on them, and deletes the entry. Each entry targets exactly one project -- no broadcasts.

### Backlogs

**File:** `backlog.md` (per project)

Prioritized task lists with a standard format:

```markdown
## Open
- [ ] [P1] **Critical bug**: Fix auth before release
- [ ] [P2] **New feature**: Add export to CSV
- [ ] [P3] **Cleanup**: Refactor utils module

## Done
### 2026-03-01
- [x] Deployed v2.1 hotfix
```

P1 = do now, P2 = this week, P3 = when time allows, P4 = paused, P5 = dormant. Claude reads backlogs on demand, not at startup.

### Knowledge Layers

Configuration loads in five layers. Each layer is more specific and loads conditionally:

| Layer | Source | Loaded |
|-------|--------|--------|
| 1. Global prompt | `global/CLAUDE.md` | Always -- the dispatcher that tells Claude what else to load |
| 2. Foundation | `global/foundation/` | Always -- session protocol, user identity, personas |
| 3. Domains | `global/domains/` | Per project -- declared in the project's CLAUDE.md manifest |
| 4. References | `global/reference/` | On demand -- triggered by context (e.g., MCP troubleshooting) |
| 5. Project rules | `<project>/.claude/CLAUDE.md` | Per project -- project-specific instructions and session state |

A coding project loads TDD rules. An infrastructure project loads server protocols. A writing project loads neither. This keeps context usage low.

### Personas

Multiple named personalities with automatic context-based switching. Each persona has:

| Field | Purpose | Example |
|-------|---------|---------|
| Name | Display prefix on responses | Atlas, Sage |
| Traits | Communication style descriptors | efficient, warm, dry-humor |
| Activates | When this persona takes over | default, when user is frustrated |
| Style | Free-text personality description | Gets the job done, no fluff... |

Define personas in `global/foundation/personas.md`. The default persona (marked `Activates: default`) is active at startup. Others switch in automatically based on conversation context. You can also force a switch by saying "switch to [Name]".

Per-machine overrides: add a `## Persona` section to a machine's config file in `global/machines/` to fully replace global personas for that device.

---

## 4. Daily Workflow

### Startup (automatic)

```bash
cd ~/my-project
claude                 # or your launcher alias
```

Claude automatically: pulls latest config from git, loads knowledge layers, restores session context, and checks the inbox for pending tasks. Takes a few seconds.

### Working

Use Claude normally. Session state saves continuously. Domain rules enforce quality automatically (TDD requires tests before implementation, publishing rules enforce PDF output, etc.). No manual infrastructure work needed.

### Shutdown

When done, type one of:

| Command | Effect |
|---------|--------|
| `cls` | Full shutdown (save, archive, commit, push), then ready for `/clear` |
| `end` | Full shutdown (save, archive, commit, push), then exit |

Both run the complete shutdown protocol: update session context, archive to history, drop cross-project tasks if needed, commit and push. The difference is whether you stay in the terminal afterward.

### Dashboard

Type `lsd` to see all your projects at a glance:

```
lsd              Show projects grouped by priority tier (P1--P3)
lsd all          Include paused and dormant projects (P4--P5)
lsd refresh      Re-scan all backlogs and disk sizes, then display
switch N         Open project #N in a new terminal tab
```

The dashboard shows task counts, P1 task names, sub-project trees, disk sizes, and deadline flags -- all in box-drawing tables grouped by priority tier.

---

## 5. Adding a New Project

### Option A: Interactive

Navigate to the project directory and tell Claude to set it up:

```bash
cd ~/my-new-project
claude
# Then type: "Set up this project"
```

Claude will create `.claude/CLAUDE.md`, add the project to `registry.md`, and initialize session tracking.

### Option B: Manual

1. Create the project config:

```bash
mkdir -p ~/my-new-project/.claude
cp ~/agent-fleet/projects/_example/rules/CLAUDE.md ~/my-new-project/.claude/CLAUDE.md
```

2. Edit `.claude/CLAUDE.md` -- declare which knowledge domains to load:

```markdown
## Knowledge Loading

| Domain | File | Load when... |
|--------|------|-------------|
| Software Development | `~/.claude/domains/software-development/tdd-protocol.md` | Writing code |
```

3. Add a row to `~/agent-fleet/registry.md` with the project name, path, priority, and type.

Session tracking begins the next time Claude opens in that directory.

---

## 6. Adding a New Machine

On the new machine:

```bash
git clone YOUR_REPO_URL ~/agent-fleet
cd ~/agent-fleet && bash setup.sh
```

The setup script creates a machine file in `global/machines/` with your platform details, installed tools, and auth state. Then commit and push:

```bash
git add -A && git commit -m "Add machine: $(hostname)" && git push
```

On your other machines, the next session start auto-pulls via hooks -- no manual action needed.

### What syncs vs. what stays local

| Syncs via git | Stays on each machine |
|---------------|----------------------|
| Global rules, foundation, domains | `~/.mcp.json` (API tokens differ per machine) |
| Session history, project configs | OAuth tokens, credentials |
| Cross-project inbox and strategy | `~/CLAUDE.local.md` (points to local machine file) |
| Registry, backlogs | Machine-specific tool paths |

No machine is special. Any machine with the repo and `setup.sh` run is a full participant.

---

## Quick Reference

| Task | Command / Action |
|------|-----------------|
| End session cleanly | `cls` (stay in terminal) or `end` (exit) |
| View all projects | `lsd` |
| Switch to project #3 | `switch 3` (after `lsd`) |
| Add a new project | `cd ~/project && claude`, then "set up this project" |
| Check system health | `bash sync.sh status` |
| Push config changes live | `bash sync.sh deploy` |
| Pull changes back to repo | `bash sync.sh collect` |
| Pass task to another project | Add `- [ ] **project**: task` to `cross-project/inbox.md` |
| Add a new machine | Clone repo, run `bash setup.sh`, commit and push |
| Encrypt credentials | `bash secrets/vault-manage.sh encrypt` |
| Deploy credentials | `bash secrets/vault-manage.sh deploy` |
| Install skill packs | `bash setup/scripts/install-skill-collections.sh` |
| Add a knowledge domain | Copy `global/domains/_template/`, edit, reference from project |

---

## Directory Structure

```
agent-fleet/
+-- setup.sh                        Setup script (run once per machine)
+-- sync.sh                         Config sync tool (deploy/collect/status)
+-- registry.md                     Project phone book
|
+-- global/
|   +-- CLAUDE.md                   Main prompt (the dispatcher)
|   +-- foundation/                 Session rules, identity, personas
|   +-- domains/                    Topic-specific rule sets (TDD, infra, etc.)
|   +-- reference/                  Tool guides, troubleshooting (on-demand)
|   +-- knowledge/                  Operational tips and workarounds
|   +-- machines/                   Per-computer configuration
|   +-- hooks/                      SessionStart/End automation
|
+-- projects/
|   +-- _example/rules/CLAUDE.md    Example project config
|
+-- cross-project/
|   +-- inbox.md                    Inter-project task passing
|   +-- *-strategy.md               Shared state files
|
+-- secrets/
|   +-- vault.json.enc              Encrypted token vault
|   +-- vault-manage.sh             Vault management script
|
+-- tests/
    +-- run.sh                      Test runner (all suites)
    +-- test_*.sh                   Individual test suites
```

---

## MCP Servers

MCP (Model Context Protocol) servers let Claude interact with external services. Setup prompts for each one individually.

| Server | Purpose | Credentials? |
|--------|---------|:------------:|
| GitHub | Repos, issues, PRs, code search | Yes (PAT) |
| Google Workspace | Gmail, Docs, Calendar, Drive | Yes (OAuth) |
| Twitter/X | Post tweets | Yes (API keys) |
| Jira | Issues, sprints, Confluence | Yes (API token) |
| Postgres | Database queries | Yes (connection URL) |
| Serena | Semantic code navigation | No |
| Playwright | Browser automation, screenshots | No |
| Memory | Persistent knowledge graph | No |
| Diagram | Mermaid diagram generation | No |

Skip any you don't need during setup. Add them later by editing `~/.mcp.json` or re-running the relevant setup section.

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Claude doesn't see MCP servers | Restart Claude Code. Check `settings.local.json` for `enabledMcpjsonServers` whitelist. |
| GitHub "Not Found" on private repos | Use `GITHUB_PERSONAL_ACCESS_TOKEN` (not `GITHUB_TOKEN`) in `~/.mcp.json` |
| Permission prompts every session | Remove the `permissions` block from the project's `.claude/settings.local.json` |
| Session state not persisting | Ensure `session-context.md` exists in the project directory |
| Symlinks broken after git pull | Run `bash sync.sh setup` to recreate them |
| General health check | Run `bash sync.sh status` |
