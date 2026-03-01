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

# ── Summary ──────────────────────────────────────────────────────────────────

suite_summary
