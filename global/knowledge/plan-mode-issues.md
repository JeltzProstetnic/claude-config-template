# Plan Mode Issues

## Known Bug: Plan Mode Hang

**Status:** Active, unresolved. Observed on SteamOS (Arch-based), may affect other platforms.

### Symptoms
1. Plan mode entered (via EnterPlanMode or shift+tab)
2. Thinking indicator appears briefly (~30s)
3. UI freezes with pause symbol in status bar
4. No response rendered, UI completely unresponsive
5. Token counter still visible (context not lost)

### Root Cause Analysis

**Most likely: MCP + permission prompt deadlock.**
The pause symbol indicates Claude Code is waiting for user input (permission approval) that can't render because plan mode's UI state takes over the input area. With multiple MCP servers, the probability of a tool call requiring permission during planning is high.

**Contributing factors:**
- `tengu_plan_mode_interview_phase: False` — plan mode interview feature may be disabled. This could cause a fallback code path that doesn't handle the planning UI correctly.
- Some terminals may report different capabilities than others. `TERM_PROGRAM` being unset may contribute.
- The statusline subprocess (Python) is NOT the cause — it completes in <50ms.

### Workarounds

**Primary (recommended):** Don't use plan mode. Describe your approach in conversation and ask for feedback. Same result, no fragile UI state.

**If plan mode is needed:**
1. Reduce MCP servers — disable non-essential ones before entering plan mode
2. Pre-approve all tools — ensure no MCP tools require permission prompts
3. Try `tengu_plan_mode_interview_phase: true` in `.claude.json` (untested)

### Diagnostic Data to Collect
- `TERM`, `COLORTERM`, `TERM_PROGRAM` values
- StatusLine latency
- Feature flags: `tengu_plan_mode_interview_phase`, `tengu_mcp_elicitation`
- Number and names of active MCP servers

### To Report
File at https://github.com/anthropics/claude-code/issues with:
- OS and terminal
- Claude Code version
- MCP server count and names
- Feature flags
- Reproduction: enter plan mode, send any message, observe hang after ~30s
- Note any platforms where it does/doesn't occur
