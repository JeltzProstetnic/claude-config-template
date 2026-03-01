# Cross-Project Boundary & Sync Rules

**Load this file when:** writing files outside current project, syncing between public/private repos, or using filtered push.

## Cross-Project Boundary Rule — HARD CONSTRAINT

You may ONLY write to files inside your current working project. Writing to ANY file in another project's directory is FORBIDDEN — even if you know the path, even if it seems convenient, even for "shared" files in `~/cfg-agent-fleet/`. The ONLY legal way to affect another project is through the cross-project inbox. Violations of this rule cause silent data corruption and task loss.

**EXCEPTION — developer template repo:** If `~/cfg-agent-fleet/` exists (developer machine), then cfg-agent-fleet **MUST write directly** to the template repo (`~/agent-fleet/`). The template has no active sessions — inbox tasks there will never be consumed. Always commit AND push in the same step. Strip personal data before propagating. This exception applies ONLY to the cfg-agent-fleet→agent-fleet direction.

**EXCEPTION — system projects (elevated privileges):** `cfg-agent-fleet` and `infrastructure` are system-level projects with maintenance responsibility. When operating from these projects, they MAY write to any project's `.claude/` config directory (e.g., `settings.local.json`, project rules) and deploy scripts. This is necessary for: fixing broken permissions, deploying MCP configs, repairing settings, and maintaining agent infrastructure. This does NOT extend to modifying project source code, backlogs, or session contexts — only agent/tool configuration files. The inbox is still preferred for changes that require the project's own session to act on.

### Path Ownership (concrete mapping)

- `~/cfg-agent-fleet/*` and `~/.claude/*` — owned by **cfg-agent-fleet** project
- `~/agent-fleet/*` — writable from cfg-agent-fleet (developer template exception, see above)
- `~/<project>/.claude/*` — writable from cfg-agent-fleet/infrastructure (system project exception, see above)
- `~/<project>/*` (except `.claude/`) — owned by that specific project (writable only when working in it)
- `~/cfg-agent-fleet/cross-project/inbox.md` — writable from any project (always)
- `~/cfg-agent-fleet/cross-project/contacts.md` — append-only from any project (new contacts, status updates)
- `~/cfg-agent-fleet/cross-project/engagement-log.md` — append-only from any project (new log entries)
- `~/cfg-agent-fleet/cross-project/*.md` strategy files — writable during shutdown only (see shutdown checklist)

Reading files and executing scripts from any project is always permitted. Only writing/editing files outside your current working project is forbidden (except the inbox, shutdown strategy files, and developer template exception listed above).

## Cross-Project Inbox

`~/cfg-agent-fleet/cross-project/inbox.md`
- The inbox is the ONLY mechanism for cross-project communication
- Tasks are per-project (one entry per project, not broadcasts)
- Pick up YOUR project's tasks, delete them from inbox after integrating
- To request changes in another project: write an inbox entry, NEVER edit their files directly
- Format: `- [ ] **target-project-name**: what needs to happen`

## Public/Private Sync Direction Rule

When a project has both public and private repos (e.g., aIware public + aIware-private, cfg-agent-fleet + agent-fleet), diffs between them are NOT always bugs. Before syncing, classify each diff: (1) **intentional personalization** — private has personal names/accounts/paths, public has generic placeholders → leave both as-is; (2) **structural improvement in private** that public should get → propagate after stripping personal details; (3) **public-only change** → backport to private. Never blindly sync private→public — that leaks personal data. Never blindly sync public→private — that overwrites intentional customizations.

## Dual-Remote Push Rule — HARD CONSTRAINT

For projects with a filtered public remote (identified by `.push-filter.conf` in project root): NEVER `git pull`, `git fetch --merge`, or `git merge` from the public remote into the working branch. The public remote is **write-only** — it contains a filtered subset and merging it contaminates the working tree (deletes files that were intentionally excluded). Only pull/merge from the private remote. Push to public ONLY via `bash ~/cfg-agent-fleet/setup/scripts/filtered-push.sh`. If `git-sync-check.sh` runs in a dual-remote project, it must ONLY sync with the private remote, never the public one.
