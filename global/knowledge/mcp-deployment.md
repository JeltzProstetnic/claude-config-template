# MCP Server Deployment — Lessons & Patterns

## Pre-deployment checklist for new MCP servers

When adding a new MCP server to the fleet, verify these BEFORE deploying to machines:

### 1. Config file defaults
- **Does the server create config files on first run?** (e.g., Serena → `~/.serena/serena_config.yml`)
- **Are any defaults problematic?** (GUI popups, browser opens, telemetry, auto-updates)
- **Pre-deploy the config** from bootstrap/configure scripts with sane defaults
- Example: Serena's `web_dashboard_open_on_launch: true` → browser opens every launch

### 2. Port conflicts
- **Does the server bind to a port?** Check for HTTP servers, OAuth callbacks, WebSocket endpoints
- **Does it have sub-processes that also bind ports?** (e.g., workspace-mcp: main server + OAuth callback both use 8000)
- **Always set ports explicitly** via env vars or args — never rely on defaults
- Example: `WORKSPACE_MCP_PORT=8001` in `.mcp.json` env

### 3. Auth flow requirements
- **Does it need OAuth?** If so, which port does the callback server use?
- **Does it need a browser?** Set `BROWSER` env var for non-standard environments (e.g., `flatpak run com.google.Chrome` on SteamOS)
- **Where are tokens cached?** Know the path so you can verify/reset auth state

### 4. Onboarding/nag suppression
- **Does the server have an onboarding flow?** (e.g., Serena's `check_onboarding_performed`)
- **What state does it check?** (memory files, config flags, marker files)
- **Pre-populate the required state** to suppress nag on every session start
- Example: Serena checks for project memories — write them once during activation

### 5. Platform compatibility
- **Does it require specific binaries?** (Node.js, Python, dotnet, etc.)
- **Does it work on all target platforms?** (SteamOS, WSL, VPS, Fedora)
- **PATH requirements**: always set explicit PATH in `.mcp.json` env — don't rely on shell PATH inheritance

## enabledMcpjsonServers — the silent killer

When adding a new MCP server to `~/.mcp.json`, you MUST also add its name to `enabledMcpjsonServers` in EVERY project's `settings.local.json`. This list acts as a whitelist — unlisted servers silently fail to connect, even if perfectly configured.

**The mclaude launcher should handle this automatically** (patching settings.local.json at startup). If it's not doing so, the launcher's patching logic needs fixing. When manually deploying, always update:
1. `~/.mcp.json` — add server definition
2. Every `<project>/.claude/settings.local.json` — add server name to `enabledMcpjsonServers`

**Deployment script (`configure-claude.sh`) MUST:**
- Set `enabledMcpjsonServers` to include ALL servers defined in `.mcp.json`
- Set `enableAllProjectMcpServers: true`
- NEVER include a `permissions` block (auto-clean hook will remove it anyway)

## Auto-clean: permissions contamination (config-check.sh Check 10)

Claude Code's "Always allow" button writes permission entries to `settings.local.json`. These REPLACE global permissions, causing prompt storms. The SessionStart hook `config-check.sh` Check 10 auto-removes any `permissions` block from all project `settings.local.json` files. See `~/.claude/knowledge/claude-code-permissions.md` for full details.

## Known server-specific notes

### Serena (code navigation)
- Config: `~/.serena/serena_config.yml` — pre-deployed by configure-claude.sh
- Key setting: `web_dashboard_open_on_launch: false`
- Onboarding: write memories for each project on first activation
- Context: `--context claude-code` (optimized tool set for Claude Code)

### workspace-mcp (Google Workspace / Gmail)
- Port: set `WORKSPACE_MCP_PORT=8001` (default 8000 conflicts with OAuth callback)
- Browser: set `BROWSER` env var for non-standard browsers
- Auth cache: `~/.google_workspace_mcp/credentials/`
- Scope: `--tools gmail` limits to Gmail only (faster startup, smaller tool set)

### GitHub MCP
- Auth: `GITHUB_PERSONAL_ACCESS_TOKEN` env var
- Multi-org: separate server entries for different PATs (e.g., `github` vs `github_ivoclar`)
- **DEPRECATED:** `@modelcontextprotocol/server-github` (npm) still works but is no longer maintained
- **Replacement:** `github/github-mcp-server` (Go-based) — requires Docker or Go. Migration pending.
- The old npx server emits deprecation warnings but functions correctly (26 tools)

### Twitter MCP
- Auth: 4 env vars (API_KEY, API_SECRET, ACCESS_TOKEN, ACCESS_SECRET)
- Known bug: `search_tweets` returns 402 (API tier limitation)

### Playwright MCP
- No config files, no auth
- Needs browser binary available

### Diagram (mcp-mermaid-image-gen)
- Requires `mmdc` globally installed (`npm install -g @mermaid-js/mermaid-cli`)
- Python-based via uvx
