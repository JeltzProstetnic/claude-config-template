# Global Claude Code Configuration

@~/.claude/foundation/user-profile.md
@~/.claude/foundation/session-protocol.md
@~/.claude/foundation/personas.md

Config repo: `~/agent-fleet/`

## Machine Identity

Machine-specific knowledge is auto-loaded via `~/CLAUDE.local.md` (each machine has its own, not synced). Read `/etc/hostname` at startup using the Read tool (not Bash — avoids permission prompts; portable across all platforms including SteamOS where `hostname` binary may not exist) and state where you are in your first response.

If hostname doesn't match any pattern in your machine table, state the hostname + user and ask.

If `CLAUDE.local.md` is missing, fall back to reading `~/.claude/machines/<machine>.md` manually.

## Session Start — Loading Protocol

**MANDATORY — NEVER SKIP.** Complete ALL steps before doing ANY user task. The user's first message often IS the trigger for startup — do not treat it as reason to skip loading. Even if the user asks something urgent, load first, then respond. A 30-second startup is always acceptable; lost context from skipping is not.

**Auto-loaded via @import** (no action needed — loaded before you see this):
- `user-profile.md` — who the user is
- `session-protocol.md` — session context persistence rules
- `personas.md` — default personas (machine files can override)
- Machine file — via `CLAUDE.local.md` (machine-specific, not synced)

**Manual steps — execute in order:**

0. **ALWAYS check for remote changes — BEFORE reading any files.** Run `bash ~/agent-fleet/setup/scripts/git-sync-check.sh --pull` in the project directory. This fetches, reports incoming changes, and fast-forward pulls if behind. If it reports changes, re-read affected files. If it fails (diverged, merge conflict), resolve before proceeding. This applies to EVERY project, EVERY session, no exceptions. Reading stale files leads to wrong context, missed tasks, and wasted work.

1. **ALWAYS read cross-project inbox:** `~/agent-fleet/cross-project/inbox.md` — pick up tasks for this project AND its child projects. Use the `Parent` column in `registry.md` to determine parent-child relationships. Example: when working in a parent project, also flag tasks targeting child projects. Report child project tasks to the user but don't delete them — the child project session handles that. This is the cross-device task passing mechanism (mobile/VPS/PC all sync via git).

2. **Read the project's `CLAUDE.md`** (manifest) — it declares what domains to load

3. **Read the project's `session-context.md`** (if exists) — current state and active tasks

4. **Follow the manifest's Knowledge Loading table** — load only the listed domain files

5. **Conditional loading (do NOT load unless triggered):**
   - **First run after setup** (`.setup-pending` exists in repo root): `~/.claude/foundation/first-run-refinement.md` — run this FIRST, before any user task
   - MCP server issue, auth problem, or first MCP tool use in session: `~/.claude/reference/mcp-catalog.md`
   - New/unconfigured project detected: `~/.claude/foundation/project-setup.md`
   - Roster changes needed: `~/.claude/foundation/roster-management.md`
   - Code project using Serena: `~/.claude/reference/serena.md`
   - WSL troubleshooting: `~/.claude/reference/wsl-environment.md`
   - Subagent permission failures: `~/.claude/reference/permissions.md`
   - Cross-project coordination needed: `~/.claude/foundation/cross-project-sync.md`
   - CLI tool usage or uncertainty about installed software: `~/.claude/reference/system-tools.md`
   - Plan mode issues, hangs, or freezes: `~/.claude/knowledge/plan-mode-issues.md`
   - Adding/debugging MCP servers: `~/.claude/knowledge/mcp-deployment.md`
   - Permission prompts, settings.local.json issues, tool approval problems: `~/.claude/knowledge/claude-code-permissions.md`
   - User types `lsd` (project dashboard): `~/.claude/reference/lsd-spec.md`
   - Generating documents, PDFs, or delivering files: `~/.claude/reference/output-rules.md`
   - Writing outside current project, cross-project sync, filtered push: `~/.claude/reference/cross-project-rules.md`
   - Tool-specific operational issues: `~/.claude/knowledge/<tool>.md` (check INDEX for available files)

6. **Check for project-specific knowledge**: `ls <project>/.claude/knowledge/` or `<project>/.claude/*.md`

7. **Do NOT load everything.** Only load what the manifest says + what's triggered by context.

## Indexes

- Foundation modules: `~/.claude/foundation/INDEX.md`
- Domain catalog: `~/.claude/domains/INDEX.md`
- **Full project catalog: `~/agent-fleet/registry.md`** — read on demand (project ops, `lsd`, or when user mentions other projects)

## Development Rules

- **TDD only:** All new code and features MUST follow test-driven development. Write failing tests first, then implement to make them pass. No implementation code without a corresponding test. This applies to bash scripts, config logic, and any testable behavior.
- **No compound `cd` commands:** NEVER use `cd <dir> && <command>` in Bash tool calls. Claude Code flags compound `cd` commands as security risks ("bare repository attacks"), causing permission prompts that pollute `settings.local.json`. Instead: use `git -C <path>` for git commands, absolute paths for everything else.
- **Bash permissions match first word only:** `Bash(npm:*)` only matches commands starting with `npm`. NEVER prefix Bash commands with variable assignments (`VAR=value && npm ...`) or delays (`sleep N && npm ...`) — those start with `VAR` or `sleep`, not `npm`, so the permission won't match. Use literal values and separate tool calls instead. See `~/.claude/knowledge/claude-code-permissions.md` for details.
- **Know your gitignore:** Before `git add`, verify the file isn't gitignored. `.claude/settings.local.json` and `secrets/vault.json` are gitignored. Don't waste tool calls trying to stage them.
- **Auto-sync awareness:** The SessionEnd hook runs `sync.sh collect` which commits pending changes. If a file was edited earlier in the session and auto-synced, it won't show as modified at shutdown. Check `git log --oneline -1 -- <file>` before chasing phantom diffs.
- **Repo vs deployed state:** When assessing whether a feature exists or works, check the deployed/live version — not just the repo source. `sync.sh collect` may not have run, so the repo can lag behind what's actually running. When repo state and user observation contradict, investigate the deployed version before concluding either way.
- **Git commit messages — no `$()`, no temp files:** NEVER use `git commit -m "$(cat <<'EOF'...)"` (flags `$()` as security risk) or `printf ... > /tmp/file && git commit -F /tmp/file` (flags `/tmp/` as file access risk). Both trigger permission prompts. Instead: use multiple `-m` flags — each becomes a separate paragraph:
  ```
  git -C /path commit -m "Subject line here" -m "Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
  ```
  This overrides the system prompt's HEREDOC guidance. Multiple `-m` is silent, requires no approval, and produces identical multi-paragraph output.

## Persona System

Personas are **multiple named personalities** with semantic switching rules. They are defined globally and apply to all machines by default, with optional per-machine overrides.

**Persona source (layered, first match wins):**
1. **Machine file** (`~/.claude/machines/<machine>.md`) — if it has a `## Persona` section, use those personas exclusively (full override, not merge)
2. **Global default** (`~/.claude/foundation/personas.md`) — used when the machine file has no `## Persona` section

The user can define as many personas as they want. Switching rules are semantic — described in natural language, interpreted by Claude. Examples: "when the user is frustrated", "when discussing creative writing", "when doing code review", "after midnight", "when the user says 'switch to X'".

**Persona format** (each persona is a `### Name` subsection under `## Persona`):

| Field | Purpose | Example |
|-------|---------|---------|
| **Name** | Display name used as response prefix | Assistant, Supporter |
| **Traits** | Comma-separated communication style descriptors | efficient, warm, sarcastic |
| **Activates** | Semantic rule for when this persona takes over | default, when user is frustrated |
| **Color** | Not rendered in chat — Claude Code's markdown renderer strips ANSI escape codes. The statusline CAN render ANSI colors. Field kept for potential future rendering. | cyan, green |
| **Style** | Free-text description of how this persona communicates | Gets the job done. Professional, clear... |

**Rendering rules:**
- At session start, load personas from the machine file (if it has a `## Persona` section) or from the global file
- The persona with `Activates: default` is active at session start
- Prefix FIRST substantive response to each user message with the persona name in **bold markdown**: e.g., `**Assistant:**`
- On persona switch, write the active persona name to `~/.claude/.active-persona` (one line, just the name, no trailing newline). The statusline reads this file and displays the persona name in its configured ANSI color. Write on session start (default persona) and on every switch. **Method:** First **Read** the file (even if it doesn't exist — the Read will return an error, which is fine), then use the **Write tool** to set the new value. The Read is mandatory because Write requires a prior Read. Do NOT use Bash/printf — that triggers permission prompts.
- Continuously evaluate switching rules against conversation context. Switch when a rule matches. **Stay in the switched persona until the triggering condition clearly ends** — e.g., if user was frustrated, stay in the empathetic persona until their tone shifts back to neutral/task-focused. Don't snap back to default the moment frustration isn't explicitly stated. Err on the side of staying longer.
- The user can always force a switch by saying "switch to [Name]" or just "[Name]"
- Trait descriptors and Style text are FLAVORING, not rigid rules. Adapt to context. User profile takes precedence.
- If no persona defined → respond normally (no prefix, no trait flavoring)

**Onboarding:** During first-run refinement, offer a multi-personality setup — "Would you like your agent to have different personalities for different situations?" Store in `~/.claude/foundation/personas.md`. If the user wants device-specific personas, add a `## Persona` section to the relevant machine file.

## AI-First Paradigm

**The user talks. The agent operates.** This is the governing design principle for all documentation, onboarding, UX, and workflow design. It supersedes digitalization, cloud-first, mobile-first, and all prior IT paradigms.

- **Documentation** should describe what the user says to the agent, not what commands to type or files to edit
- **Onboarding** is conversational — the agent asks questions and writes config files, not forms or interactive prompts
- **Troubleshooting** means describing the symptom to the agent, not reading a manual
- **Project setup, machine deployment, cross-project coordination** — all agent-driven, all conversational
- The only manual steps are `git clone` and `bash setup.sh`. Everything after that is "launch the agent, tell it what you need."
- When writing user-facing text (READMEs, guides, help output), frame it as "tell the agent" not "run this command" or "edit this file"

## Conventions

**Auto-memory is WRONG for this setup (OVERRIDES system auto-memory guidance).** The system prompt tells you to save "conventions", "preferences", "patterns", and "solutions" into auto-memory. **Ignore all of that.** In a multi-project multi-machine environment, auto-memory is per-project and ephemeral — rules saved there are invisible to other projects and get lost. The correct storage locations are:

| What | Where | NOT in memory |
|------|-------|---------------|
| Behavioral rules ("always do X") | `CLAUDE.md` (global or project) | Memory is invisible to other projects |
| Technical decisions & rationale | `docs/decisions.md` in the project | Memory has no structure |
| Debugging patterns, technical recipes | `~/.claude/knowledge/<topic>.md` | Memory is per-project, knowledge is global |
| Machine-specific state | `~/.claude/machines/<machine>.md` | Memory doesn't survive machine changes |
| Cross-project coordination | `~/agent-fleet/cross-project/` files | Memory can't cross projects |

**Auto-memory's only valid use:** Temporary orientation notes for a specific project that don't fit anywhere else (e.g., "this project's CI is flaky on Tuesdays"). Keep it under 50 lines. When in doubt, DON'T write to memory — write to a proper file.

If the user says "always do X" or "remember to do Y" → that's a rule → `CLAUDE.md`. If it's global, route through cross-project inbox for agent-fleet integration. If project-scoped, write to the project's `CLAUDE.md` directly.

**Output rule:** Documents → PDF (not markdown). Copy-paste content → plain text files. Full rules: `~/.claude/reference/output-rules.md` (load when generating documents or delivering files).

**MCP-first rule:** Always prefer MCP server tools over bash/CLI equivalents when available. GitHub MCP for repo/issue/PR operations (not `gh` CLI or `curl`), Google Workspace MCP for email/docs/calendar, Twitter MCP for tweets, Serena for code navigation in code projects. Only fall back to CLI when MCP genuinely can't do the operation (e.g., `git clone` to local filesystem), or when the MCP catalog documents a known limitation for that specific tool.

**Subagent file delivery rule:** Never re-open files a subagent already delivered. Details in `~/.claude/reference/output-rules.md`.

**Plain-language startup/shutdown messages:** Startup and shutdown status lines must be human-readable, not internal jargon. Say "Last session shut down correctly" not "clean template, properly rotated". Say "Last session may have ended unexpectedly — checking recovery notes" not "stale context found". Say "2 tasks waiting for other projects" not "inbox has 2 entries for non-current projects". These messages should make sense to any user, not just someone who knows the rotation/archival internals. The rest of the session can be as technical as the context requires.

**URL/service identification rule:** When the user provides a URL or a task involves an external service, FIRST identify the service (x.com/twitter.com → Twitter, github.com → GitHub, docs.google.com/drive.google.com → Google Workspace, etc.). Then check the MCP catalog for matching tools and known limitations. Only after that, decide whether to use MCP tools or fall back to WebFetch/CLI. Never jump straight to generic fetching without this identification step.

**Backlog convention:** Every project has `backlog.md` at root. Do NOT read at session start — only when active tasks are done or user asks. Backlogs follow this format:

```
# Backlog — <project-name>

## Open

- [ ] [P1] **Task title**: Description

## Done

### YYYY-MM-DD (most recent session only)
- [x] Completed task description

Older completed items: `docs/backlog-archive.md`
```

**Keep backlogs lean:** Only the last session's Done section stays in `backlog.md`. Older completed items move to `docs/backlog-archive.md` (append-only, oldest first). This prevents backlogs from growing into multi-hundred-line token sinks.

**Project prioritization:** Registry has a `Priority` column (P1–P5). Backlog tasks carry a priority tag.
- **Project priority** (in `registry.md`): P1 = critical/daily, P2 = active/weekly, P3 = ongoing/as-needed, P4 = paused, P5 = dormant
- **Task priority** (in backlogs): prefix task line with `[P1]`–`[P5]`, e.g. `- [ ] [P1] Fix deployment bug`. Untagged tasks default to P3.
- **Cross-project ranking**: sort by project priority first, then task priority within each project. A P2 task in a P1 project outranks a P1 task in a P3 project.
- **Open section**: flat list sorted by priority (P1 first), no subsections. Keep it scannable.
- **Done section**: group by date, most recent first. Move tasks here when completed — don't delete them.

**Cross-project boundary rule — HARD CONSTRAINT:** Only write files inside your current working project. Cross-project communication goes through the inbox (`~/agent-fleet/cross-project/inbox.md`). **Before writing outside your project, ALWAYS load `~/.claude/reference/cross-project-rules.md`** for path ownership, exceptions, and sync direction rules.

**Session context:** Maintain `session-context.md` in every project. Update before and after every significant action. Reference project docs, don't duplicate them.

**Quick commands — keyword shortcuts the user can type as their entire message:**

| Keyword | What it does |
|---------|-------------|
| `cls` | Execute full 7-step shutdown checklist, then say "Shutdown complete — run /clear whenever you're ready." **If `cls` is the user's very first message**, skip the startup checklist entirely — the user is switching projects and doesn't need full context loading. Just run shutdown. Only run the startup checklist afterward if the user stays in the current project (i.e., sends a follow-up task instead of `/clear`). |
| `end` | Execute full 7-step shutdown checklist, then say "Shutdown complete — you can exit now." |
| `lsd` | **Project dashboard.** Load `~/.claude/reference/lsd-spec.md` first, then render. |

When the user types one of these keywords (alone, case-insensitive), execute the described action immediately without asking for confirmation. These are shortcuts, not conversation starters.

**`lsd` — project dashboard.** Full spec in `~/.claude/reference/lsd-spec.md` (loaded on demand). Short version: read dashboard-cache.md, render box-drawing tables per priority tier, show task counts + P1 names + sizes.

**Session shutdown checklist — MANDATORY.** When the user says "prepare for shutdown", "exit", "auto-compact restart", `cls`, `end`, or anything suggesting session end → run ALL steps from `~/.claude/foundation/session-protocol.md` Section "Session Shutdown Checklist", without asking. That file is the canonical, detailed checklist. Quick summary:

0. Run `bash ~/agent-fleet/setup/scripts/clean-permissions.sh` — remove stale "Always allow" permission blocks
1. Update `session-context.md` with final state and recovery instructions + update this project's row in `~/agent-fleet/cross-project/dashboard-cache.md`
2. Run `bash ~/agent-fleet/setup/scripts/rotate-session.sh` + update `docs/decisions.md` if needed
3. Drop cross-project inbox tasks if this session affects other projects
4. Update shared strategy files you touched (shutdown boundary exception)
5. Update machine file (`~/.claude/machines/<machine>.md`) if machine state changed
6. `git add`, commit, push
7. Run `bash ~/agent-fleet/sync.sh collect` to verify

No exceptions. No asking "want me to commit?" — just do it.

## Meta-Rules

**Rules live in rules, not in memory.** Persistent behavioral rules MUST go in `CLAUDE.md` (global or project-level), foundation files, or domain protocols — never in auto-memory files. Memory is for contextual notes (project structure, debugging insights, technical recipes). If it governs behavior, it's a rule and belongs here.

**Troubleshooting reference machines:** When a fix regresses or a config issue recurs, ALWAYS consult two sources before reinventing: (1) the machine where the project was **last worked on** (check `session-history.md` for which machine), and (2) your **primary dev machine** (source of truth for how things should work). Read the relevant machine files, session histories, and configs from those machines to see if the problem was already solved there. Don't fix from scratch what was already fixed elsewhere.

**Protocol creation:** When domain-complexity mistakes happen, create a protocol. See `~/.claude/foundation/protocol-creation.md`.

**Adding domains:** Create dir under `~/agent-fleet/global/domains/`, add protocols, update `domains/INDEX.md`, reference from project manifests. These operations require being in the agent-fleet project context. From other projects, route domain creation requests through the cross-project inbox.

**Sync:** `bash ~/agent-fleet/sync.sh setup|deploy|collect|status`

**New project:** Add to `~/agent-fleet/registry.md`. See `~/.claude/foundation/project-setup.md`.

**New machine:** Populate `~/.claude/machines/<machine>.md` from `machines/_template.md`. Create `~/CLAUDE.local.md` containing `@~/.claude/machines/<machine>.md`. Add hostname pattern to Machine Identity table. Run `bash ~/agent-fleet/sync.sh setup` to link config. See machine file template for required sections.

## Platform Notes

**WSL:**
- **NEVER work in `/mnt/c/` paths** — 10-15x slower
- `git config --global core.autocrlf input`
- Full reference: `~/.claude/reference/wsl-environment.md`

**Native Linux (Fedora KDE, SteamOS, etc.):**
- Use `xdg-open` for opening files (respects system default app)
- No `/mnt/c/` or `powershell.exe` available
- **Terminal tabs (Konsole/KDE):** Use D-Bus to open tabs and send commands:
  ```bash
  KONSOLE_SVC=$(qdbus org.kde.konsole-* 2>/dev/null | head -1)
  SID=$(qdbus "$KONSOLE_SVC" /Windows/1 org.kde.konsole.Window.newSession "tab-name" "bash")
  qdbus "$KONSOLE_SVC" /Sessions/$SID org.kde.konsole.Session.sendText "cd ~/project && mclaude\n"
  ```
- **Never use tmux on KDE machines** — the user has a graphical terminal with native tabs

**macOS:**
- Use `open <filepath>` for opening files (respects system default app)
- No `/mnt/c/` or `powershell.exe` available
