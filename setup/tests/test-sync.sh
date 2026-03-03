#!/usr/bin/env bash
# Tests for sync.sh — focused on testable functions and structural behaviors
source "$(dirname "$0")/test-helpers.sh"

SYNC_SCRIPT="$REPO_ROOT/sync.sh"

suite_header "sync.sh"

# ── Help/usage ───────────────────────────────────────────────────────────────

test_help() {
    local out
    out=$(bash "$SYNC_SCRIPT" help 2>&1)
    assert_contains "$out" "setup"
    assert_contains "$out" "deploy"
    assert_contains "$out" "collect"
    assert_contains "$out" "status"
}
run_test "help shows all subcommands" test_help

test_no_args() {
    local out
    out=$(bash "$SYNC_SCRIPT" 2>&1)
    assert_contains "$out" "Usage"
}
run_test "no arguments shows usage" test_no_args

# ── find_project_path ────────────────────────────────────────────────────────

test_find_project_by_home_dir() {
    # Source sync.sh functions (need SCRIPT_DIR set)
    # find_project_path checks $HOME/<name> first
    # We can't test this without creating dirs in HOME, so test via the function
    local result
    result=$(
        SCRIPT_DIR="$REPO_ROOT"
        source <(grep -A 30 '^find_project_path()' "$SYNC_SCRIPT") 2>/dev/null
        find_project_path "cfg-agent-fleet"
    )
    assert_eq "$HOME/cfg-agent-fleet" "$result"
}
run_test "find_project_path finds project in home directory" test_find_project_by_home_dir

test_find_project_registry_fallback() {
    # Create a mock registry and a project dir
    mkdir -p "$TEST_TMPDIR/mock-project"
    cat > "$TEST_TMPDIR/registry.md" <<EOF
| Project | Priority | Path | GitHub | Machines | Type | Phase |
|---------|----------|------|--------|----------|------|-------|
| mock-project | P3 | \`$TEST_TMPDIR/mock-project\` | — | test | code | active |
EOF

    local result
    result=$(
        SCRIPT_DIR="$TEST_TMPDIR"
        HOME="/nonexistent"
        source <(grep -A 30 '^find_project_path()' "$SYNC_SCRIPT") 2>/dev/null
        find_project_path "mock-project"
    )
    assert_eq "$TEST_TMPDIR/mock-project" "$result"
}
run_test "find_project_path falls back to registry.md" test_find_project_registry_fallback

test_find_project_not_found() {
    local result
    result=$(
        SCRIPT_DIR="$TEST_TMPDIR"
        HOME="$TEST_TMPDIR"
        source <(grep -A 30 '^find_project_path()' "$SYNC_SCRIPT") 2>/dev/null
        find_project_path "nonexistent-project-xyz"
    )
    assert_eq "" "$result" "should return empty for unknown project"
}
run_test "find_project_path returns empty for unknown project" test_find_project_not_found

# ── deploy_hooks ─────────────────────────────────────────────────────────────

test_deploy_hooks_copies_files() {
    # Set up a mock environment
    mkdir -p "$TEST_TMPDIR/global/hooks"
    mkdir -p "$TEST_TMPDIR/claude-home/hooks"
    echo "#!/bin/bash" > "$TEST_TMPDIR/global/hooks/test-hook.sh"
    echo "echo test" >> "$TEST_TMPDIR/global/hooks/test-hook.sh"

    (
        GLOBAL_DIR="$TEST_TMPDIR/global"
        CLAUDE_HOME="$TEST_TMPDIR/claude-home"
        source <(sed -n '/^deploy_hooks()/,/^}/p' "$SYNC_SCRIPT" | sed 's/log_info/echo/g')
        deploy_hooks
    )

    assert_file_exists "$TEST_TMPDIR/claude-home/hooks/test-hook.sh"
    # Should be executable
    [[ -x "$TEST_TMPDIR/claude-home/hooks/test-hook.sh" ]]
}
run_test "deploy_hooks copies hook files and makes them executable" test_deploy_hooks_copies_files

# ── check_settings_health ────────────────────────────────────────────────────

test_settings_health_warns_missing_permissions() {
    mkdir -p "$TEST_TMPDIR/.cc-mirror/mclaude/config"
    echo '{"hooks": {}, "enabledPlugins": []}' > "$TEST_TMPDIR/.cc-mirror/mclaude/config/settings.json"

    local out
    out=$(
        HOME="$TEST_TMPDIR"
        source <(sed -n '/^check_settings_health()/,/^}/p' "$SYNC_SCRIPT" \
            | sed 's/log_warn/echo WARN/g; s/log_info/echo INFO/g')
        check_settings_health
    )
    assert_contains "$out" "permissions"
}
run_test "check_settings_health warns when permissions block missing" test_settings_health_warns_missing_permissions

test_settings_health_clean() {
    mkdir -p "$TEST_TMPDIR/.cc-mirror/mclaude/config"
    echo '{"permissions": {}, "hooks": {}, "enabledPlugins": []}' > "$TEST_TMPDIR/.cc-mirror/mclaude/config/settings.json"

    local out
    out=$(
        HOME="$TEST_TMPDIR"
        source <(sed -n '/^check_settings_health()/,/^}/p' "$SYNC_SCRIPT" \
            | sed 's/log_warn/echo WARN/g; s/log_info/echo INFO/g')
        check_settings_health
    )
    assert_not_contains "$out" "WARN"
}
run_test "check_settings_health is silent when all blocks present" test_settings_health_clean

# ── Platform detection ───────────────────────────────────────────────────────

test_platform_detection() {
    # Verify sync.sh sets PLATFORM to a known value
    local platform
    platform=$(bash -c "
        source <(head -30 '$SYNC_SCRIPT')
        echo \$PLATFORM
    ")
    assert_neq "" "$platform" "PLATFORM should be set"
    # Valid platforms: linux, wsl, macos, steamos
    assert_contains "linux wsl macos steamos" "$platform" "PLATFORM should be a known value"
}
run_test "platform detection works on current machine" test_platform_detection

# ── Status subcommand runs ───────────────────────────────────────────────────

test_status_runs() {
    local out rc=0
    out=$(bash "$SYNC_SCRIPT" status 2>&1) || rc=$?
    assert_eq "0" "$rc" "status should exit 0"
    assert_contains "$out" "CLAUDE.md"
    assert_contains "$out" "foundation"
}
run_test "status subcommand runs successfully" test_status_runs

# ── Hook deploy: executable permissions ──────────────────────────────────────

test_deploy_hooks_makes_executable() {
    mkdir -p "$TEST_TMPDIR/global/hooks"
    mkdir -p "$TEST_TMPDIR/claude-home/hooks"

    # Create a hook that is NOT executable
    echo '#!/bin/bash' > "$TEST_TMPDIR/global/hooks/my-hook.sh"
    echo 'echo hello' >> "$TEST_TMPDIR/global/hooks/my-hook.sh"
    chmod -x "$TEST_TMPDIR/global/hooks/my-hook.sh"

    (
        GLOBAL_DIR="$TEST_TMPDIR/global"
        CLAUDE_HOME="$TEST_TMPDIR/claude-home"
        source <(sed -n '/^deploy_hooks()/,/^}/p' "$SYNC_SCRIPT" | sed 's/log_info/echo/g')
        deploy_hooks
    )

    # Deployed hook must be executable
    [[ -x "$TEST_TMPDIR/claude-home/hooks/my-hook.sh" ]]
}
run_test "deploy_hooks makes hooks executable even if source isn't" test_deploy_hooks_makes_executable

# ── Hook collect: uncommitted edit safety ────────────────────────────────────

test_collect_hooks_skips_uncommitted() {
    # Set up a git repo as the "config repo"
    create_git_repo "$TEST_TMPDIR/repo"
    mkdir -p "$TEST_TMPDIR/repo/global/hooks"
    echo '#!/bin/bash' > "$TEST_TMPDIR/repo/global/hooks/test-hook.sh"
    echo 'echo original' >> "$TEST_TMPDIR/repo/global/hooks/test-hook.sh"
    (cd "$TEST_TMPDIR/repo" && git add -A && git commit -m "add hook" >/dev/null 2>&1)

    # Now make an uncommitted edit to the repo source
    echo 'echo EDITED IN REPO' >> "$TEST_TMPDIR/repo/global/hooks/test-hook.sh"

    # Set up the deployed hook (different content — simulates live edit)
    mkdir -p "$TEST_TMPDIR/claude-home/hooks"
    echo '#!/bin/bash' > "$TEST_TMPDIR/claude-home/hooks/test-hook.sh"
    echo 'echo deployed version' >> "$TEST_TMPDIR/claude-home/hooks/test-hook.sh"

    # Collect should SKIP this hook because repo has uncommitted changes
    local out
    out=$(
        SCRIPT_DIR="$TEST_TMPDIR/repo"
        GLOBAL_DIR="$TEST_TMPDIR/repo/global"
        CLAUDE_HOME="$TEST_TMPDIR/claude-home"
        PROJECTS_DIR="$TEST_TMPDIR/repo/projects"
        NC='\033[0m'; RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
        mkdir -p "$PROJECTS_DIR"
        source <(sed -n '/^log_info()/,/^}/p' "$SYNC_SCRIPT"; sed -n '/^log_warn()/,/^}/p' "$SYNC_SCRIPT")
        # Source the collect hook logic
        source <(awk '/^cmd_collect\(\)/,/^}/' "$SYNC_SCRIPT" | sed 's/find_project_path/echo/g')
        cmd_collect 2>&1
    )
    assert_contains "$out" "uncommitted"

    # Verify the repo source was NOT overwritten by the deployed version
    assert_file_contains "$TEST_TMPDIR/repo/global/hooks/test-hook.sh" "EDITED IN REPO"
}
run_test "collect_hooks skips hooks with uncommitted repo edits" test_collect_hooks_skips_uncommitted

# ── Hook collect: copies changed hooks ───────────────────────────────────────

test_collect_hooks_copies_changed() {
    # Set up a clean git repo
    create_git_repo "$TEST_TMPDIR/repo"
    mkdir -p "$TEST_TMPDIR/repo/global/hooks"
    echo '#!/bin/bash' > "$TEST_TMPDIR/repo/global/hooks/test-hook.sh"
    echo 'echo original' >> "$TEST_TMPDIR/repo/global/hooks/test-hook.sh"
    (cd "$TEST_TMPDIR/repo" && git add -A && git commit -m "add hook" >/dev/null 2>&1)

    # Set up a DIFFERENT deployed hook (simulates live modification)
    mkdir -p "$TEST_TMPDIR/claude-home/hooks"
    echo '#!/bin/bash' > "$TEST_TMPDIR/claude-home/hooks/test-hook.sh"
    echo 'echo modified at deploy target' >> "$TEST_TMPDIR/claude-home/hooks/test-hook.sh"

    # Collect should pick up the changed deployed hook
    local out
    out=$(
        SCRIPT_DIR="$TEST_TMPDIR/repo"
        GLOBAL_DIR="$TEST_TMPDIR/repo/global"
        CLAUDE_HOME="$TEST_TMPDIR/claude-home"
        PROJECTS_DIR="$TEST_TMPDIR/repo/projects"
        NC='\033[0m'; RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
        mkdir -p "$PROJECTS_DIR"
        source <(sed -n '/^log_info()/,/^}/p' "$SYNC_SCRIPT"; sed -n '/^log_warn()/,/^}/p' "$SYNC_SCRIPT")
        source <(awk '/^cmd_collect\(\)/,/^}/' "$SYNC_SCRIPT" | sed 's/find_project_path/echo/g')
        cmd_collect 2>&1
    )
    assert_contains "$out" "Collected hook"

    # Verify the repo source was updated with the deployed content
    assert_file_contains "$TEST_TMPDIR/repo/global/hooks/test-hook.sh" "modified at deploy target"
}
run_test "collect_hooks copies changed deployed hooks to repo" test_collect_hooks_copies_changed

# ── Project rule deploy ──────────────────────────────────────────────────────

test_deploy_project_rules_copies_to_target() {
    # Set up mock project rules in repo
    mkdir -p "$TEST_TMPDIR/repo/projects/myproject/rules"
    echo "# My Project Rules" > "$TEST_TMPDIR/repo/projects/myproject/rules/CLAUDE.md"

    # Set up mock project target
    mkdir -p "$TEST_TMPDIR/myproject"

    # Deploy should copy rules to the project's .claude/ dir
    (
        PROJECTS_DIR="$TEST_TMPDIR/repo/projects"
        NC='\033[0m'; RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
        source <(sed -n '/^log_info()/,/^}/p' "$SYNC_SCRIPT"; sed -n '/^log_warn()/,/^}/p' "$SYNC_SCRIPT")
        # Override find_project_path to return our mock
        find_project_path() { [[ "$1" == "myproject" ]] && echo "$TEST_TMPDIR/myproject"; }
        source <(sed -n '/^deploy_project_rules()/,/^}/p' "$SYNC_SCRIPT")
        deploy_project_rules
    )

    assert_file_exists "$TEST_TMPDIR/myproject/.claude/CLAUDE.md"
    assert_file_contains "$TEST_TMPDIR/myproject/.claude/CLAUDE.md" "My Project Rules"
}
run_test "deploy_project_rules copies rules to target project" test_deploy_project_rules_copies_to_target

test_deploy_project_rules_skips_missing_project() {
    # Set up mock project rules but NO target project dir
    mkdir -p "$TEST_TMPDIR/repo/projects/ghost/rules"
    echo "# Ghost Rules" > "$TEST_TMPDIR/repo/projects/ghost/rules/CLAUDE.md"

    local out
    out=$(
        PROJECTS_DIR="$TEST_TMPDIR/repo/projects"
        NC='\033[0m'; RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
        source <(sed -n '/^log_info()/,/^}/p' "$SYNC_SCRIPT"; sed -n '/^log_warn()/,/^}/p' "$SYNC_SCRIPT")
        find_project_path() { echo ""; }
        source <(sed -n '/^deploy_project_rules()/,/^}/p' "$SYNC_SCRIPT")
        deploy_project_rules 2>&1
    )
    assert_contains "$out" "not found"
}
run_test "deploy_project_rules skips projects not on this machine" test_deploy_project_rules_skips_missing_project

test_collect_project_rules_from_live() {
    # Set up repo project rules dir (empty)
    mkdir -p "$TEST_TMPDIR/repo/projects/myproject/rules"

    # Set up live project with modified rules
    mkdir -p "$TEST_TMPDIR/myproject/.claude"
    echo "# Modified at live" > "$TEST_TMPDIR/myproject/.claude/CLAUDE.md"

    # Collect should pick up the live rule
    local out
    out=$(
        SCRIPT_DIR="$TEST_TMPDIR/repo"
        GLOBAL_DIR="$TEST_TMPDIR/repo/global"
        CLAUDE_HOME="$TEST_TMPDIR/claude-home"
        PROJECTS_DIR="$TEST_TMPDIR/repo/projects"
        NC='\033[0m'; RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
        mkdir -p "$CLAUDE_HOME" "$GLOBAL_DIR"
        # Symlink CLAUDE.md so collect doesn't try to copy it
        ln -sf "$GLOBAL_DIR/CLAUDE.md" "$CLAUDE_HOME/CLAUDE.md" 2>/dev/null || true
        touch "$GLOBAL_DIR/CLAUDE.md"
        source <(sed -n '/^log_info()/,/^}/p' "$SYNC_SCRIPT"; sed -n '/^log_warn()/,/^}/p' "$SYNC_SCRIPT")
        find_project_path() { [[ "$1" == "myproject" ]] && echo "$TEST_TMPDIR/myproject"; }
        source <(awk '/^cmd_collect\(\)/,/^}/' "$SYNC_SCRIPT")
        cmd_collect 2>&1
    )
    assert_contains "$out" "Collected"
    assert_file_contains "$TEST_TMPDIR/repo/projects/myproject/rules/CLAUDE.md" "Modified at live"
}
run_test "collect picks up modified project rules from live" test_collect_project_rules_from_live

# ── Summary ──────────────────────────────────────────────────────────────────

suite_summary
