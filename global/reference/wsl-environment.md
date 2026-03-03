# WSL Environment Reference

Load this file when: working in WSL, hitting path or performance issues, or setting up a new WSL environment.

## Performance

**NEVER work in `/mnt/c/` paths.** File I/O across the WSL/Windows boundary is 10-15x slower than native Linux paths. Keep all project files under `~/` (the Linux filesystem).

## Git

```bash
git config --global core.autocrlf input
```

This prevents CRLF line endings from being committed when editing files from the Windows side.

## /etc/wsl.conf

Recommended WSL configuration:

```ini
[automount]
enabled = true
options = "metadata,umask=22,fmask=11"
[interop]
enabled = true
appendWindowsPath = true
```

## Git Credential Helper

A custom credential helper (e.g., `git-credential-mcp` at `~/.local/bin/`) can read PATs from `.mcp.json`, enabling native `git push` without embedded tokens in remote URLs.

- Does NOT cover the `gh` CLI — use MCP GitHub tools or `curl` for GitHub API calls.

## Node.js PATH

WSL inherits the Windows PATH. If Windows has Node.js installed, its `node` may appear before the WSL one. Fix:

```bash
# In ~/.bashrc or ~/.zshrc — add WSL node before Windows node
export PATH="/usr/local/bin:$PATH"
```

Verify: `which node` should return a path under `/usr/` not `/mnt/c/`.

## Sandbox Dependencies

Claude Code's sandbox requires these packages:

```bash
sudo apt install socat bubblewrap
```

Without them, sandboxed tool calls fail silently.

## Windows Defender Exclusions

Run in PowerShell as Administrator to prevent Defender from scanning the WSL filesystem (significant performance impact):

```powershell
Add-MpPreference -ExclusionPath "$env:USERPROFILE\AppData\Local\WSL"
Add-MpPreference -ExclusionPath "\\wsl.localhost"
Add-MpPreference -ExclusionPath "\\wsl$"
```

## Common Issues

| Issue | Solution |
|-------|----------|
| UNC paths | Work from WSL terminal, not Windows Explorer |
| npm permission denied | `mkdir ~/.npm-global && npm config set prefix ~/.npm-global` |
| Git shows hundreds of changed files | Check line endings config (`core.autocrlf input`) |
| "dubious ownership" git errors | `git config --global --add safe.directory /path/to/repo` |
