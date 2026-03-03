# Plan Mode Issues

## Known Bug: Plan Mode Hang

**Status:** TWO bugs identified. Bug 1 fixed, Bug 2 still open (upstream).
**Filed:** https://github.com/anthropics/claude-code/issues/29712
**Upstream tracker:** https://github.com/anthropics/claude-code/issues/26224 (28 upvotes, Anthropic investigating)

### Bug 1: MCP Permission Deadlock (FIXED)

MCP tool calls during plan mode trigger permission prompts that can't render because plan mode's UI takes over the input area. Result: pause symbol, frozen UI.

**Fix:**
1. Pre-authorized ALL MCP tools in `settings.json` permissions (`mcp__serena__*`, etc.)
2. Set `TERM_PROGRAM=konsole` in `settings.json` env block
3. Added `printf` to Bash permissions

### Bug 2: Extended Thinking (Crystallize) Stream Stall (OPEN)

After Bug 1 fix, plan mode enters and tools execute fine. But the model hangs during extended thinking ("Crystallized for 2m 35s") with 0 output tokens. SSE stream from Anthropic stalls indefinitely. Not platform-specific — reported on macOS, Windows, Linux.

Related issues: #26224 (main tracker), #29725, #23836, #26651, #20079.

Feature flag `tengu_crystal_beam: { budgetTokens: 31999 }` controls thinking budget — may be a factor.

### Current Workaround

**Don't use plan mode.** Describe approach in conversation instead. Use Agent tool with Plan subagent for complex planning (runs in a subagent, avoids the plan mode UI entirely).

### Diagnostic Data
- `TERM=xterm-256color`, `COLORTERM=truecolor`, `TERM_PROGRAM=konsole`
- Feature flags: `tengu_plan_mode_interview_phase: false`, `tengu_crystal_beam: { budgetTokens: 31999 }`
