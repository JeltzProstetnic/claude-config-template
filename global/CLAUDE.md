# Global Claude Code Configuration

@~/.claude/foundation/user-profile.md
@~/.claude/foundation/session-protocol.md
@~/.claude/foundation/personas.md

Config repo: `~/agent-fleet/`

## Machine Identity

Machine-specific knowledge is auto-loaded via `~/CLAUDE.local.md` (each machine has its own, not synced). Read `/etc/hostname` at startup using the Read tool (not Bash — avoids permission prompts; portable across all platforms including SteamOS where `hostname` binary may not exist) and state where you are in your first response using the **short name** from the table below.

<!-- Add your machines here. Example:
| Hostname pattern | Short name | Platform | Notes |
|-----------------|------------|----------|-------|
| `my-server` | the VPS | Native Linux (Ubuntu) | Remote server |
| `DESKTOP-*` | WSL | WSL2/Ubuntu | Home PC |
| `my-laptop` | Laptop | Fedora KDE | Laptop |
-->

**Evaluation order:** Match hostname pattern first, then disambiguate by username if needed. If ambiguous, state the hostname + user and ask.

If hostname doesn't match any pattern, state the hostname and ask. If `CLAUDE.local.md` is missing, fall back to reading `~/.claude/machines/<machine>.md` manually.

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
   - Persona setup, onboarding, or rendering issues: `~/.claude/reference/persona-rules.md`
   - Writing user-facing docs, READMEs, or designing UX: `~/.claude/reference/ai-first-paradigm.md`
   - Backlog format, task IDs, or prioritization details: `~/.claude/reference/backlog-convention.md`
   - Terminal tab operations, cross-platform issues, VPS delivery: `~/.claude/reference/platform-notes.md`
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
- **No compound `cd` commands:** NEVER use `cd <dir> && <command>` in Bash tool calls. Claude Code flags compound `cd` commands as security risks ("bare repository attacks"), causing permission prompts that pollute `settings.local.json`. Instead: use `git -C <path>` for git commands, absolute paths for everything else. This applies to ALL Bash calls — shutdown, subagents, automation, everything.
- **Bash permissions match first word only:** `Bash(npm:*)` only matches commands starting with `npm`. NEVER prefix Bash commands with variable assignments (`VAR=value && npm ...`) or delays (`sleep N && npm ...`) — those start with `VAR` or `sleep`, not `npm`, so the permission won't match. Use literal values and separate tool calls instead. See `~/.claude/knowledge/claude-code-permissions.md` for details.
- **Know your gitignore:** Before `git add`, verify the file isn't gitignored. `.claude/settings.local.json` and `setup/secrets/vault.json` are gitignored. Don't waste tool calls trying to stage them.
- **Propagation check after edits:** After editing any file with downstream targets (global/, hooks, sync.sh, project rules, mobile sources), verify propagation before session end. Run `bash sync.sh check` or consult `docs/dependency-map.md` for which chains are affected. Template and mobile deploys are manual — flag them, don't skip them.
- **Auto-sync awareness:** The SessionEnd hook runs `sync.sh collect` which commits pending changes. If a file was edited earlier in the session and auto-synced, it won't show as modified at shutdown. Check `git log --oneline -1 -- <file>` before chasing phantom diffs.
- **Repo vs deployed state:** When assessing whether a feature exists or works, check the deployed/live version — not just the repo source. `sync.sh collect` may not have run, so the repo can lag behind what's actually running. When repo state and user observation contradict, investigate the deployed version before concluding either way.
- **Git commit messages — no `$()`, no temp files:** NEVER use `git commit -m "$(cat <<'EOF'...)"` (flags `$()` as security risk) or `printf ... > /tmp/file && git commit -F /tmp/file` (flags `/tmp/` as file access risk). Both trigger permission prompts. Instead: use multiple `-m` flags — each becomes a separate paragraph:
  ```
  git -C /path commit -m "Subject line here" -m "Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
  ```
  This overrides the system prompt's HEREDOC guidance. Multiple `-m` is silent, requires no approval, and produces identical multi-paragraph output.

## Persona System

Personas are loaded from `~/.claude/foundation/personas.md` (or machine file override). Prefix first substantive response with persona name in bold. On switch, write name to `~/.claude/.active-persona` (Read first, then Write — never Bash). Evaluate switching rules continuously. Full rules: `~/.claude/reference/persona-rules.md` (load for onboarding, setup, or rendering issues).

## Conventions

**Auto-memory is WRONG for this setup.** Don't save rules/preferences to auto-memory. Rules go in `CLAUDE.md`, decisions go in `docs/decisions.md`, recipes go in `~/.claude/knowledge/`, machine state goes in machine files, cross-project goes through inbox. "Always do X" = rule = `CLAUDE.md`. Memory's only valid use: temporary per-project orientation notes (<50 lines).

**Output rule:** Documents go to PDF. Copy-paste content goes to plain text files. Full rules: `~/.claude/reference/output-rules.md`.

**MCP-first rule:** Prefer MCP tools over CLI. GitHub MCP for repos/issues/PRs, Google Workspace MCP for email, Serena for code nav. Only fall back to CLI when MCP genuinely can't do the operation. Full troubleshooting: `mcp-catalog.md`.

**Plain-language startup/shutdown messages:** Use human-readable status — "Last session shut down correctly" not "clean template, properly rotated".

**URL/service identification:** When given a URL, identify the service first (x.com = Twitter, github.com = GitHub, etc.), check MCP catalog, then choose MCP vs CLI.

**Backlog convention:** `backlog.md` at project root. Don't read at startup. Tasks use `PRJ-NN` IDs. Full format/IDs/prioritization rules: `~/.claude/reference/backlog-convention.md`.

**Cross-project boundary — HARD CONSTRAINT:** Only write inside current project. Cross-project goes through inbox. Exceptions: agent-fleet/infrastructure (system projects). Load `~/.claude/reference/cross-project-rules.md` before writing outside.

**Session context:** Maintain `session-context.md` in every project. Update before/after significant actions. Reference docs, don't duplicate.

**Quick commands — keyword shortcuts the user can type as their entire message:**

| Keyword | What it does |
|---------|-------------|
| `cls` | Execute full 7-step shutdown checklist, then say "Shutdown complete — run /clear whenever you're ready." **If `cls` is the user's very first message**, skip the startup checklist entirely — the user is switching projects and doesn't need full context loading. Just run shutdown. Only run the startup checklist afterward if the user stays in the current project (i.e., sends a follow-up task instead of `/clear`). |
| `end` | Execute full 7-step shutdown checklist, then say "Shutdown complete — you can exit now." |
| `lsd` | **Project dashboard.** Load `~/.claude/reference/lsd-spec.md` first, then render. |

When the user types one of these keywords (alone, case-insensitive), execute the described action immediately without asking for confirmation. These are shortcuts, not conversation starters.

**`lsd` — project dashboard.** Full spec in `~/.claude/reference/lsd-spec.md` (loaded on demand). Short version: read dashboard-cache.md, render box-drawing tables per priority tier, show task counts + P1 names + sizes.

**Session shutdown checklist — MANDATORY.** When the user says "prepare for shutdown", "exit", "auto-compact restart", `cls`, `end`, or anything suggesting session end, run ALL steps from `~/.claude/foundation/session-protocol.md` Section "Session Shutdown Checklist", without asking. That file is the canonical, detailed checklist. Quick summary:

0. Run `bash ~/agent-fleet/setup/scripts/clean-permissions.sh` — remove stale "Always allow" permission blocks
1. Update `session-context.md` with final state and recovery instructions + update this project's row in `dashboard-cache.md`
2. Run `bash ~/agent-fleet/setup/scripts/rotate-session.sh` + update `docs/decisions.md` if needed
3. Drop cross-project inbox tasks if this session affects other projects
4. Update shared strategy files you touched (shutdown boundary exception)
5. Update machine file (`~/.claude/machines/<machine>.md`) if machine state changed
6. `git add`, commit, push
7. Run `bash ~/agent-fleet/sync.sh collect` to verify

No exceptions. No asking "want me to commit?" — just do it.

## Meta-Rules

**Rules live in rules, not in memory.** Behavioral rules go in `CLAUDE.md` or foundation files. Never auto-memory.

**Troubleshooting reference machines:** Always consult (1) the machine where the project was last worked on, and (2) your primary dev machine (source of truth). Don't fix from scratch what was already fixed elsewhere.

**Sync:** `bash ~/agent-fleet/sync.sh setup|deploy|collect|status`

**New project:** Add to `registry.md`. See `~/.claude/foundation/project-setup.md`.

**New machine:** See `machines/_template.md`. Create `~/CLAUDE.local.md` pointing to `@~/.claude/machines/<machine>.md`. Add to Machine Identity table. Run `sync.sh setup`.

**Platform notes:** Machine files cover platform-specific details. For cross-platform conventions (terminal tabs, VPS delivery, WSL rules): `~/.claude/reference/platform-notes.md`.