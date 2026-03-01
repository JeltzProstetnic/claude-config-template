# Machine: <hostname-pattern>

## Identity
- **Short name**:
- **Platform**:
- **User**:
- **Hostname pattern**:

## Installed Tooling
| Tool | Version | Path/Notes |
|------|---------|-----------|
| | | |

## Applied Patches
| What | Location | Notes |
|------|----------|-------|
| | | |

## Auth State
| Service | Status | Notes |
|---------|--------|-------|
| | | |

## Terminal Tab Management (KDE Konsole)
Use D-Bus to open tabs and send commands:
```bash
# Find running Konsole
KONSOLE_SVC=$(qdbus org.kde.konsole-* 2>/dev/null | head -1)
# Open new tab (returns session ID)
SID=$(qdbus "$KONSOLE_SVC" /Windows/1 org.kde.konsole.Window.newSession "tab-name" "bash")
# Send command to new tab (note trailing newline)
qdbus "$KONSOLE_SVC" /Sessions/$SID org.kde.konsole.Session.sendText "cd ~/project\n"
```

### Terminal Tab Safety Rules
- **ALWAYS re-query `sessionList` before sending commands to ANY tab** — session IDs shift when tabs are closed/created.
- **Never send commands to a tab you didn't just create** without first verifying its title/identity.
- **Never rename a tab you didn't create** — `setTitle` on the wrong session clobbers the user's context.
- **"Project X is open" means HANDS OFF** — the user is saying it's already running in another session.
- **Never open a second agent instance for a project that's already running** — causes session conflicts and dual shutdowns.
- **When tab operations go wrong, STOP immediately.** Ask the user what state things are in.
- **Send cd and launch commands as separate Bash tool calls** — never compound them.
- **Bash permission matching is first-word only.** `Bash(qdbus:*)` only matches commands starting with `qdbus`. Never prefix with variable assignments (`VAR=... && qdbus`) — use literal values directly.

## Known Issues
-

## Machine-Specific Paths
| Purpose | Path |
|---------|------|
| | |
