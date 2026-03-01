#!/usr/bin/env bash
# Tests for global/hooks/config-check.sh — SessionStart hook
source "$(dirname "$0")/test-helpers.sh"

HOOK_SCRIPT="$REPO_ROOT/global/hooks/config-check.sh"

suite_header "config-check.sh (SessionStart hook)"

# ── Helpers ──────────────────────────────────────────────────────────────────

# Create a git repo on branch "main" regardless of global git config
create_git_repo_main() {
    local path="$1"
    mkdir -p "$path"
    (
        cd "$path"
        git init -b main >/dev/null 2>&1
        git config user.email "test@test.com"
        git config user.name "Test"
        echo "init" > README.md
        git add README.md
        git commit -m "Initial commit" >/dev/null 2>&1
    )
}

# Create a tracked repo on branch "main"
create_tracked_repo_main() {
    local repo_path="$1"
    local remote_path="$2"
    local remote_name="${3:-origin}"

    mkdir -p "$remote_path"
    git init --bare -b main "$remote_path" >/dev/null 2>&1
    create_git_repo_main "$repo_path"
    (
        cd "$repo_path"
        git remote add "$remote_name" "$remote_path"
        git push -u "$remote_name" main >/dev/null 2>&1
    )
}

# Create a minimal config repo structure that _detect_config_repo() will find
create_mock_config_repo() {
    local dir="$1"
    mkdir -p "$dir/setup/scripts"
    touch "$dir/sync.sh"
    # Copy clean-permissions.sh so Check 10 can find it
    if [ -f "$REPO_ROOT/setup/scripts/clean-permissions.sh" ]; then
        cp "$REPO_ROOT/setup/scripts/clean-permissions.sh" "$dir/setup/scripts/"
    fi
    create_git_repo_main "$dir"
}

# Build a patched version of config-check.sh that:
#   - Uses a hardcoded CONFIG_REPO instead of _detect_config_repo()
#   - Runs with a controlled HOME
#   - Runs from a controlled working directory (for PROJECT_DIR = $(pwd))
#
# Instead of fragile sed on the multi-line function, we write a wrapper
# that defines _detect_config_repo first, then evals the rest of the
# original script with the function redefined.
create_patched_script() {
    local config_repo="$1"
    local mock_home="$2"
    local project_dir="$3"
    local patched="$TEST_TMPDIR/config-check-patched.sh"

    cat > "$patched" << WRAPPER_EOF
#!/usr/bin/env bash
# Patched config-check.sh for testing

# Override HOME
export HOME="$mock_home"

# cd into project dir so \$(pwd) returns what we want
cd "$project_dir"

# Pre-define _detect_config_repo so when the script defines it, ours
# has already been used. Actually — the script calls _detect_config_repo
# at definition time via CONFIG_REPO="\$(_detect_config_repo)". So we
# need to redefine it BEFORE the script runs, and then skip the script's
# definition.
#
# Strategy: use sed to remove the function body and replace the
# CONFIG_REPO assignment line, then eval.

_detect_config_repo() {
    echo "$config_repo"
}

# Read the original script, remove the _detect_config_repo function body
# (lines 6-17 approximately), and eval the rest
eval "\$(awk '
    /^_detect_config_repo\(\)/ { skip=1; next }
    skip && /^\}/ { skip=0; next }
    skip { next }
    { print }
' "$HOOK_SCRIPT")"
WRAPPER_EOF

    chmod +x "$patched"
    echo "$patched"
}

# Run the patched script. Captures stdout.
run_hook() {
    local patched="$1"
    shift
    bash "$patched" "$@" 2>/dev/null
}

# ── Tests ────────────────────────────────────────────────────────────────────

# ── 1. Sync failure detection ────────────────────────────────────────────────

test_sync_failure_detection() {
    local config_repo="$TEST_TMPDIR/config-repo"
    local mock_home="$TEST_TMPDIR/home"
    local project_dir="$TEST_TMPDIR/project"
    mkdir -p "$mock_home/.claude" "$project_dir"

    create_mock_config_repo "$config_repo"
    # Create CLAUDE.md as symlink so check 2 passes
    touch "$config_repo/CLAUDE.md"
    ln -sf "$config_repo/CLAUDE.md" "$mock_home/.claude/CLAUDE.md"

    # Create .sync-failed marker
    cat > "$config_repo/.sync-failed" << 'EOF'
stage=collect
time=2026-03-01T10:00:00Z
detail=git push failed
EOF

    local patched
    patched=$(create_patched_script "$config_repo" "$mock_home" "$project_dir")
    local output
    output=$(run_hook "$patched")

    assert_contains "$output" "CONFIG SYNC FAILED" "should warn about sync failure"
    assert_contains "$output" "collect" "should include stage"
    assert_contains "$output" "2026-03-01" "should include time"
    assert_contains "$output" "git push failed" "should include detail"
}
run_test "sync failure: warns with stage, time, and detail" test_sync_failure_detection

# ── 2. Symlink health check ─────────────────────────────────────────────────

test_symlink_health_broken() {
    local config_repo="$TEST_TMPDIR/config-repo"
    local mock_home="$TEST_TMPDIR/home"
    local project_dir="$TEST_TMPDIR/project"
    mkdir -p "$mock_home/.claude" "$project_dir"

    create_mock_config_repo "$config_repo"

    # Create CLAUDE.md as a regular file (NOT a symlink)
    echo "not a symlink" > "$mock_home/.claude/CLAUDE.md"

    local patched
    patched=$(create_patched_script "$config_repo" "$mock_home" "$project_dir")
    local output
    output=$(run_hook "$patched")

    assert_contains "$output" "CLAUDE.md is not symlinked" "should warn about missing symlink"
    assert_contains "$output" "sync.sh setup" "should suggest fix"
}
run_test "symlink health: warns when CLAUDE.md is not a symlink" test_symlink_health_broken

# ── 3. Config repo missing (.git absent) ────────────────────────────────────

test_config_repo_missing() {
    local config_repo="$TEST_TMPDIR/config-repo-nogit"
    local mock_home="$TEST_TMPDIR/home"
    local project_dir="$TEST_TMPDIR/project"
    mkdir -p "$mock_home/.claude" "$project_dir"

    # Create config repo dir but WITHOUT .git (just the dir + sync.sh)
    mkdir -p "$config_repo"
    touch "$config_repo/sync.sh"

    # symlink to avoid symlink warning dominating
    touch "$config_repo/CLAUDE.md"
    ln -sf "$config_repo/CLAUDE.md" "$mock_home/.claude/CLAUDE.md"

    local patched
    patched=$(create_patched_script "$config_repo" "$mock_home" "$project_dir")
    local output
    output=$(run_hook "$patched")

    assert_contains "$output" "Config repo not found" "should warn about missing .git"
    assert_contains "$output" "sync.sh setup" "should suggest fix"
}
run_test "config repo missing: warns when .git is absent" test_config_repo_missing

# ── 4. Auto-pull success ────────────────────────────────────────────────────

test_auto_pull_success() {
    local config_repo="$TEST_TMPDIR/config-repo"
    local remote_repo="$TEST_TMPDIR/remote.git"
    local mock_home="$TEST_TMPDIR/home"
    local project_dir="$TEST_TMPDIR/project"
    mkdir -p "$mock_home/.claude" "$project_dir"

    # Create tracked repo with remote
    create_tracked_repo_main "$config_repo" "$remote_repo"

    # Add sync.sh so detection works
    (cd "$config_repo" && touch sync.sh && git add sync.sh && git commit -m "add sync.sh" >/dev/null 2>&1 && git push origin main >/dev/null 2>&1)

    # Add CLAUDE.md and set up symlink
    (cd "$config_repo" && touch CLAUDE.md && git add CLAUDE.md && git commit -m "add CLAUDE.md" >/dev/null 2>&1 && git push origin main >/dev/null 2>&1)
    ln -sf "$config_repo/CLAUDE.md" "$mock_home/.claude/CLAUDE.md"

    # Push a change from another clone
    git clone "$remote_repo" "$TEST_TMPDIR/other" --quiet 2>/dev/null
    (cd "$TEST_TMPDIR/other" && git config user.email "test@test.com" && git config user.name "Test" && echo "new content" > foundation.md && git add foundation.md && git commit -m "update foundation" >/dev/null 2>&1 && git push --quiet 2>/dev/null)

    local patched
    patched=$(create_patched_script "$config_repo" "$mock_home" "$project_dir")
    local output
    output=$(run_hook "$patched")

    assert_contains "$output" "Config updated from remote" "should report pulled changes"
    assert_contains "$output" "foundation.md" "should list changed files"
}
run_test "auto-pull: reports changed files on successful pull" test_auto_pull_success

# ── 5. Auto-pull failure (diverged) ─────────────────────────────────────────

test_auto_pull_diverged() {
    local config_repo="$TEST_TMPDIR/config-repo"
    local remote_repo="$TEST_TMPDIR/remote.git"
    local mock_home="$TEST_TMPDIR/home"
    local project_dir="$TEST_TMPDIR/project"
    mkdir -p "$mock_home/.claude" "$project_dir"

    create_tracked_repo_main "$config_repo" "$remote_repo"

    (cd "$config_repo" && touch sync.sh && git add sync.sh && git commit -m "add sync.sh" >/dev/null 2>&1 && git push origin main >/dev/null 2>&1)

    # CLAUDE.md symlink
    (cd "$config_repo" && touch CLAUDE.md && git add CLAUDE.md && git commit -m "add CLAUDE.md" >/dev/null 2>&1 && git push origin main >/dev/null 2>&1)
    ln -sf "$config_repo/CLAUDE.md" "$mock_home/.claude/CLAUDE.md"

    # Create divergence: push from another clone, commit locally
    git clone "$remote_repo" "$TEST_TMPDIR/other" --quiet 2>/dev/null
    (cd "$TEST_TMPDIR/other" && git config user.email "test@test.com" && git config user.name "Test" && echo "remote" > remote.txt && git add remote.txt && git commit -m "remote diverge" >/dev/null 2>&1 && git push --quiet 2>/dev/null)
    (cd "$config_repo" && echo "local" > local.txt && git add local.txt && git commit -m "local diverge" >/dev/null 2>&1)

    local patched
    patched=$(create_patched_script "$config_repo" "$mock_home" "$project_dir")
    local output
    output=$(run_hook "$patched")

    assert_contains "$output" "could not fast-forward" "should warn about divergence"
}
run_test "auto-pull failure: warns when branches have diverged" test_auto_pull_diverged

# ── 6. Unclean shutdown detection ────────────────────────────────────────────

test_unclean_shutdown_detection() {
    local config_repo="$TEST_TMPDIR/config-repo"
    local mock_home="$TEST_TMPDIR/home"
    local project_dir="$TEST_TMPDIR/project"
    mkdir -p "$mock_home/.claude" "$project_dir"

    create_mock_config_repo "$config_repo"
    touch "$config_repo/CLAUDE.md"
    ln -sf "$config_repo/CLAUDE.md" "$mock_home/.claude/CLAUDE.md"

    # Create session-context.md with a goal (simulates unrotated session)
    create_session_context "$project_dir" "Fix the deployment pipeline"

    local patched
    patched=$(create_patched_script "$config_repo" "$mock_home" "$project_dir")
    local output
    output=$(run_hook "$patched")

    assert_contains "$output" "Previous session may have ended unexpectedly" "should detect unclean shutdown"
    assert_contains "$output" "Fix the deployment pipeline" "should include the previous goal"
}
run_test "unclean shutdown: warns when session-context.md has a goal" test_unclean_shutdown_detection

# ── 7. Inbox task surfacing ──────────────────────────────────────────────────

test_inbox_task_surfacing() {
    local config_repo="$TEST_TMPDIR/config-repo"
    local mock_home="$TEST_TMPDIR/home"
    local project_dir="$TEST_TMPDIR/myproject"
    mkdir -p "$mock_home/.claude" "$project_dir"

    create_mock_config_repo "$config_repo"
    touch "$config_repo/CLAUDE.md"
    ln -sf "$config_repo/CLAUDE.md" "$mock_home/.claude/CLAUDE.md"

    # Create cross-project inbox with a task for our project
    mkdir -p "$config_repo/cross-project"
    cat > "$config_repo/cross-project/inbox.md" << 'EOF'
# Cross-Project Inbox

- [ ] **myproject**: Deploy new auth module after merge
- [ ] **otherproject**: Update API docs
EOF

    local patched
    patched=$(create_patched_script "$config_repo" "$mock_home" "$project_dir")
    local output
    output=$(run_hook "$patched")

    assert_contains "$output" "INBOX TASKS for myproject" "should surface inbox tasks for current project"
    assert_contains "$output" "Deploy new auth module" "should include the task description"
    assert_contains "$output" "2 pending task" "should report total pending tasks"
}
run_test "inbox: surfaces tasks for current project" test_inbox_task_surfacing

test_inbox_no_tasks_for_project() {
    local config_repo="$TEST_TMPDIR/config-repo"
    local mock_home="$TEST_TMPDIR/home"
    local project_dir="$TEST_TMPDIR/unrelated"
    mkdir -p "$mock_home/.claude" "$project_dir"

    create_mock_config_repo "$config_repo"
    touch "$config_repo/CLAUDE.md"
    ln -sf "$config_repo/CLAUDE.md" "$mock_home/.claude/CLAUDE.md"

    # Create inbox with tasks for OTHER projects only
    mkdir -p "$config_repo/cross-project"
    cat > "$config_repo/cross-project/inbox.md" << 'EOF'
# Cross-Project Inbox

- [ ] **otherproject**: Update API docs
EOF

    local patched
    patched=$(create_patched_script "$config_repo" "$mock_home" "$project_dir")
    local output
    output=$(run_hook "$patched")

    assert_not_contains "$output" "INBOX TASKS for unrelated" "should NOT surface tasks for other projects"
    # But it should still mention the inbox has pending tasks
    assert_contains "$output" "1 pending task" "should mention total inbox count"
}
run_test "inbox: no project-specific tasks, but still reports total count" test_inbox_no_tasks_for_project

# ── 8. settings.json validation ──────────────────────────────────────────────

test_settings_json_missing_blocks() {
    local config_repo="$TEST_TMPDIR/config-repo"
    local mock_home="$TEST_TMPDIR/home"
    local project_dir="$TEST_TMPDIR/project"
    mkdir -p "$mock_home/.claude" "$project_dir"

    create_mock_config_repo "$config_repo"
    touch "$config_repo/CLAUDE.md"
    ln -sf "$config_repo/CLAUDE.md" "$mock_home/.claude/CLAUDE.md"

    # Create settings.json missing "hooks" and "enabledPlugins"
    mkdir -p "$mock_home/.cc-mirror/mclaude/config"
    cat > "$mock_home/.cc-mirror/mclaude/config/settings.json" << 'EOF'
{
  "permissions": {
    "allow": ["Read"]
  }
}
EOF

    local patched
    patched=$(create_patched_script "$config_repo" "$mock_home" "$project_dir")
    local output
    output=$(run_hook "$patched")

    assert_contains "$output" "settings.json is missing critical blocks" "should warn about missing blocks"
    assert_contains "$output" "hooks" "should list missing hooks block"
    assert_contains "$output" "enabledPlugins" "should list missing enabledPlugins block"
}
run_test "settings.json: warns about missing critical blocks" test_settings_json_missing_blocks

test_settings_json_all_present() {
    local config_repo="$TEST_TMPDIR/config-repo"
    local mock_home="$TEST_TMPDIR/home"
    local project_dir="$TEST_TMPDIR/project"
    mkdir -p "$mock_home/.claude" "$project_dir"

    create_mock_config_repo "$config_repo"
    touch "$config_repo/CLAUDE.md"
    ln -sf "$config_repo/CLAUDE.md" "$mock_home/.claude/CLAUDE.md"

    # Create settings.json with all critical blocks
    mkdir -p "$mock_home/.cc-mirror/mclaude/config"
    cat > "$mock_home/.cc-mirror/mclaude/config/settings.json" << 'EOF'
{
  "permissions": { "allow": ["Read"] },
  "hooks": { "SessionStart": [] },
  "enabledPlugins": []
}
EOF

    local patched
    patched=$(create_patched_script "$config_repo" "$mock_home" "$project_dir")
    local output
    output=$(run_hook "$patched")

    assert_not_contains "$output" "settings.json is missing" "should NOT warn when all blocks present"
}
run_test "settings.json: no warning when all critical blocks present" test_settings_json_all_present

# ── 9. Serena config enforcement ─────────────────────────────────────────────

test_serena_config_fixes_dashboard() {
    local config_repo="$TEST_TMPDIR/config-repo"
    local mock_home="$TEST_TMPDIR/home"
    local project_dir="$TEST_TMPDIR/project"
    mkdir -p "$mock_home/.claude" "$project_dir"

    create_mock_config_repo "$config_repo"
    touch "$config_repo/CLAUDE.md"
    ln -sf "$config_repo/CLAUDE.md" "$mock_home/.claude/CLAUDE.md"

    # Create serena config with web_dashboard_open_on_launch: true
    mkdir -p "$mock_home/.serena"
    cat > "$mock_home/.serena/serena_config.yml" << 'EOF'
web_dashboard_open_on_launch: true
gui_log_window: true
some_other_setting: value
EOF

    local patched
    patched=$(create_patched_script "$config_repo" "$mock_home" "$project_dir")
    run_hook "$patched" >/dev/null

    # Verify the config was fixed
    assert_file_contains "$mock_home/.serena/serena_config.yml" "web_dashboard_open_on_launch: false" \
        "should fix web_dashboard_open_on_launch to false"
    assert_file_contains "$mock_home/.serena/serena_config.yml" "gui_log_window: false" \
        "should fix gui_log_window to false"
    assert_file_contains "$mock_home/.serena/serena_config.yml" "some_other_setting: value" \
        "should preserve other settings"
}
run_test "serena config: fixes web_dashboard_open_on_launch and gui_log_window" test_serena_config_fixes_dashboard

test_serena_config_already_correct() {
    local config_repo="$TEST_TMPDIR/config-repo"
    local mock_home="$TEST_TMPDIR/home"
    local project_dir="$TEST_TMPDIR/project"
    mkdir -p "$mock_home/.claude" "$project_dir"

    create_mock_config_repo "$config_repo"
    touch "$config_repo/CLAUDE.md"
    ln -sf "$config_repo/CLAUDE.md" "$mock_home/.claude/CLAUDE.md"

    # Create serena config already correct
    mkdir -p "$mock_home/.serena"
    cat > "$mock_home/.serena/serena_config.yml" << 'EOF'
web_dashboard_open_on_launch: false
gui_log_window: false
EOF

    local patched
    patched=$(create_patched_script "$config_repo" "$mock_home" "$project_dir")
    run_hook "$patched" >/dev/null

    assert_file_contains "$mock_home/.serena/serena_config.yml" "web_dashboard_open_on_launch: false" \
        "should remain false"
    assert_file_contains "$mock_home/.serena/serena_config.yml" "gui_log_window: false" \
        "should remain false"
}
run_test "serena config: no change when already correct" test_serena_config_already_correct

# ── 10. JSON output format ───────────────────────────────────────────────────

test_json_output_format() {
    local config_repo="$TEST_TMPDIR/config-repo"
    local mock_home="$TEST_TMPDIR/home"
    local project_dir="$TEST_TMPDIR/project"
    mkdir -p "$mock_home/.claude" "$project_dir"

    create_mock_config_repo "$config_repo"

    # Create a warning: CLAUDE.md not a symlink
    echo "regular file" > "$mock_home/.claude/CLAUDE.md"

    local patched
    patched=$(create_patched_script "$config_repo" "$mock_home" "$project_dir")
    local output
    output=$(run_hook "$patched")

    # Output should be valid JSON
    local json_valid=0
    echo "$output" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null || json_valid=1
    assert_eq "0" "$json_valid" "output should be valid JSON"

    # Should have systemMessage key
    local has_key
    has_key=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print('yes' if 'systemMessage' in d else 'no')" 2>/dev/null)
    assert_eq "yes" "$has_key" "JSON should have systemMessage key"
}
run_test "JSON output: valid JSON with systemMessage key when warnings exist" test_json_output_format

test_json_output_contains_warning_text() {
    local config_repo="$TEST_TMPDIR/config-repo"
    local mock_home="$TEST_TMPDIR/home"
    local project_dir="$TEST_TMPDIR/project"
    mkdir -p "$mock_home/.claude" "$project_dir"

    create_mock_config_repo "$config_repo"
    echo "regular file" > "$mock_home/.claude/CLAUDE.md"

    local patched
    patched=$(create_patched_script "$config_repo" "$mock_home" "$project_dir")
    local output
    output=$(run_hook "$patched")

    # Extract the systemMessage value
    local msg
    msg=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['systemMessage'])" 2>/dev/null)
    assert_contains "$msg" "WARNING:" "systemMessage should start with WARNING:"
    assert_contains "$msg" "CLAUDE.md" "systemMessage should contain the actual warning"
}
run_test "JSON output: systemMessage contains warning text" test_json_output_contains_warning_text

# ── 11. Clean state produces no output ───────────────────────────────────────

test_clean_state_no_output() {
    local config_repo="$TEST_TMPDIR/config-repo"
    local remote_repo="$TEST_TMPDIR/remote.git"
    local mock_home="$TEST_TMPDIR/home"
    local project_dir="$TEST_TMPDIR/project"
    mkdir -p "$mock_home/.claude" "$project_dir"

    # Create a proper tracked repo so the git pull works
    create_tracked_repo_main "$config_repo" "$remote_repo"

    (cd "$config_repo" && touch sync.sh && git add sync.sh && git commit -m "add sync.sh" >/dev/null 2>&1 && git push origin main >/dev/null 2>&1)

    # Create CLAUDE.md as symlink
    (cd "$config_repo" && touch CLAUDE.md && git add CLAUDE.md && git commit -m "add CLAUDE.md" >/dev/null 2>&1 && git push origin main >/dev/null 2>&1)
    ln -sf "$config_repo/CLAUDE.md" "$mock_home/.claude/CLAUDE.md"

    # No .sync-failed, no session-context, no inbox, no settings.json, no serena config

    local patched
    patched=$(create_patched_script "$config_repo" "$mock_home" "$project_dir")
    local output rc=0
    output=$(run_hook "$patched") || rc=$?

    assert_eq "0" "$rc" "should exit 0"
    # git pull may output "Already up to date." — that's expected non-JSON noise.
    # The key assertion: no JSON warning output (no systemMessage).
    assert_not_contains "$output" "systemMessage" "should produce no JSON warnings when everything is clean"
    assert_not_contains "$output" "WARNING" "should produce no WARNING text when everything is clean"
}
run_test "clean state: no JSON warnings and exit 0" test_clean_state_no_output

# ── 12. Exit code is always 0 ────────────────────────────────────────────────

test_exit_code_always_zero() {
    local config_repo="$TEST_TMPDIR/config-repo"
    local mock_home="$TEST_TMPDIR/home"
    local project_dir="$TEST_TMPDIR/project"
    mkdir -p "$mock_home/.claude" "$project_dir"

    create_mock_config_repo "$config_repo"
    # Trigger multiple warnings
    echo "not a symlink" > "$mock_home/.claude/CLAUDE.md"
    cat > "$config_repo/.sync-failed" << 'EOF'
stage=deploy
time=2026-03-01
detail=error
EOF

    local patched
    patched=$(create_patched_script "$config_repo" "$mock_home" "$project_dir")
    local rc=0
    run_hook "$patched" >/dev/null || rc=$?

    assert_eq "0" "$rc" "should always exit 0 even with multiple warnings"
}
run_test "exit code: always 0 even with warnings" test_exit_code_always_zero

# ── 13. Multiple warnings combined in single JSON ────────────────────────────

test_multiple_warnings_combined() {
    local config_repo="$TEST_TMPDIR/config-repo"
    local mock_home="$TEST_TMPDIR/home"
    local project_dir="$TEST_TMPDIR/project"
    mkdir -p "$mock_home/.claude" "$project_dir"

    create_mock_config_repo "$config_repo"

    # Trigger: sync failure + broken symlink
    cat > "$config_repo/.sync-failed" << 'EOF'
stage=collect
time=2026-03-01T09:00Z
detail=push failed
EOF
    echo "not a symlink" > "$mock_home/.claude/CLAUDE.md"

    local patched
    patched=$(create_patched_script "$config_repo" "$mock_home" "$project_dir")
    local output
    output=$(run_hook "$patched")

    # Should be single valid JSON
    local json_valid=0
    echo "$output" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null || json_valid=1
    assert_eq "0" "$json_valid" "combined output should be valid JSON"

    local msg
    msg=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['systemMessage'])" 2>/dev/null)
    assert_contains "$msg" "CONFIG SYNC FAILED" "should contain sync failure warning"
    assert_contains "$msg" "CLAUDE.md is not symlinked" "should contain symlink warning"
}
run_test "multiple warnings: combined into single JSON systemMessage" test_multiple_warnings_combined

# ── 14. Empty session-context.md does NOT trigger warning ─────────────────────

test_empty_session_context_no_warning() {
    local config_repo="$TEST_TMPDIR/config-repo"
    local remote_repo="$TEST_TMPDIR/remote.git"
    local mock_home="$TEST_TMPDIR/home"
    local project_dir="$TEST_TMPDIR/project"
    mkdir -p "$mock_home/.claude" "$project_dir"

    create_tracked_repo_main "$config_repo" "$remote_repo"
    (cd "$config_repo" && touch sync.sh && git add sync.sh && git commit -m "add sync.sh" >/dev/null 2>&1 && git push origin main >/dev/null 2>&1)
    (cd "$config_repo" && touch CLAUDE.md && git add CLAUDE.md && git commit -m "add CLAUDE.md" >/dev/null 2>&1 && git push origin main >/dev/null 2>&1)
    ln -sf "$config_repo/CLAUDE.md" "$mock_home/.claude/CLAUDE.md"

    # Create session-context.md with empty goal line
    cat > "$project_dir/session-context.md" << 'EOF'
# Session Context

## Session Info
- **Session Goal**:

## Current State
EOF

    local patched
    patched=$(create_patched_script "$config_repo" "$mock_home" "$project_dir")
    local output
    output=$(run_hook "$patched")

    assert_not_contains "$output" "Previous session may have ended unexpectedly" \
        "should not warn on empty session goal"
}
run_test "empty session goal: no unclean shutdown warning" test_empty_session_context_no_warning

# ── 15. Inbox with no pending tasks produces no inbox message ─────────────────

test_inbox_all_done() {
    local config_repo="$TEST_TMPDIR/config-repo"
    local remote_repo="$TEST_TMPDIR/remote.git"
    local mock_home="$TEST_TMPDIR/home"
    local project_dir="$TEST_TMPDIR/project"
    mkdir -p "$mock_home/.claude" "$project_dir"

    create_tracked_repo_main "$config_repo" "$remote_repo"
    (cd "$config_repo" && touch sync.sh && git add sync.sh && git commit -m "add sync.sh" >/dev/null 2>&1 && git push origin main >/dev/null 2>&1)
    (cd "$config_repo" && touch CLAUDE.md && git add CLAUDE.md && git commit -m "add CLAUDE.md" >/dev/null 2>&1 && git push origin main >/dev/null 2>&1)
    ln -sf "$config_repo/CLAUDE.md" "$mock_home/.claude/CLAUDE.md"

    # Create inbox with only completed tasks
    mkdir -p "$config_repo/cross-project"
    cat > "$config_repo/cross-project/inbox.md" << 'EOF'
# Cross-Project Inbox

- [x] **project**: Already done task
EOF

    local patched
    patched=$(create_patched_script "$config_repo" "$mock_home" "$project_dir")
    local output
    output=$(run_hook "$patched")

    # git pull may output "Already up to date." — that's expected non-JSON noise.
    assert_not_contains "$output" "systemMessage" "should produce no JSON warnings when inbox is done"
    assert_not_contains "$output" "WARNING" "should produce no WARNING when inbox is done"
}
run_test "inbox: no warnings when all tasks are completed" test_inbox_all_done

# ── 16. Settings.json not present produces no warning ─────────────────────────

test_no_settings_json() {
    local config_repo="$TEST_TMPDIR/config-repo"
    local remote_repo="$TEST_TMPDIR/remote.git"
    local mock_home="$TEST_TMPDIR/home"
    local project_dir="$TEST_TMPDIR/project"
    mkdir -p "$mock_home/.claude" "$project_dir"

    create_tracked_repo_main "$config_repo" "$remote_repo"
    (cd "$config_repo" && touch sync.sh && git add sync.sh && git commit -m "add sync.sh" >/dev/null 2>&1 && git push origin main >/dev/null 2>&1)
    (cd "$config_repo" && touch CLAUDE.md && git add CLAUDE.md && git commit -m "add CLAUDE.md" >/dev/null 2>&1 && git push origin main >/dev/null 2>&1)
    ln -sf "$config_repo/CLAUDE.md" "$mock_home/.claude/CLAUDE.md"

    # No settings.json file created at all

    local patched
    patched=$(create_patched_script "$config_repo" "$mock_home" "$project_dir")
    local output
    output=$(run_hook "$patched")

    assert_not_contains "$output" "settings.json" "should not warn when settings.json doesn't exist"
}
run_test "settings.json: no warning when file does not exist" test_no_settings_json

# ── 17. Check 10: Auto-remove permissions from project settings.local.json ────

test_permissions_block_removed() {
    local config_repo="$TEST_TMPDIR/config-repo"
    local mock_home="$TEST_TMPDIR/home"
    local project_dir="$TEST_TMPDIR/project"
    mkdir -p "$mock_home/.claude" "$project_dir"

    create_mock_config_repo "$config_repo"
    touch "$config_repo/CLAUDE.md"
    ln -sf "$config_repo/CLAUDE.md" "$mock_home/.claude/CLAUDE.md"

    # Create a project with settings.local.json containing a permissions block
    mkdir -p "$mock_home/myproject/.claude"
    cat > "$mock_home/myproject/.claude/settings.local.json" << 'EOF'
{
  "permissions": {
    "allow": [
      "Bash(foo:*)"
    ]
  },
  "enableAllProjectMcpServers": true
}
EOF

    local patched
    patched=$(create_patched_script "$config_repo" "$mock_home" "$project_dir")
    run_hook "$patched" >/dev/null

    # Verify permissions key was removed
    assert_file_not_contains "$mock_home/myproject/.claude/settings.local.json" '"permissions"' \
        "should remove permissions key from settings.local.json"

    # Verify other keys are preserved
    assert_file_contains "$mock_home/myproject/.claude/settings.local.json" '"enableAllProjectMcpServers"' \
        "should preserve enableAllProjectMcpServers key"
    assert_file_contains "$mock_home/myproject/.claude/settings.local.json" 'true' \
        "should preserve enableAllProjectMcpServers value"
}
run_test "check 10: settings.local.json with permissions block gets cleaned" test_permissions_block_removed

test_permissions_block_absent_untouched() {
    local config_repo="$TEST_TMPDIR/config-repo"
    local mock_home="$TEST_TMPDIR/home"
    local project_dir="$TEST_TMPDIR/project"
    mkdir -p "$mock_home/.claude" "$project_dir"

    create_mock_config_repo "$config_repo"
    touch "$config_repo/CLAUDE.md"
    ln -sf "$config_repo/CLAUDE.md" "$mock_home/.claude/CLAUDE.md"

    # Create a project with settings.local.json WITHOUT permissions
    mkdir -p "$mock_home/cleanproject/.claude"
    cat > "$mock_home/cleanproject/.claude/settings.local.json" << 'EOF'
{
  "enableAllProjectMcpServers": true,
  "mcpServers": {
    "serena": {
      "command": "serena"
    }
  }
}
EOF

    # Save original content for comparison
    local original
    original=$(cat "$mock_home/cleanproject/.claude/settings.local.json")

    local patched
    patched=$(create_patched_script "$config_repo" "$mock_home" "$project_dir")
    run_hook "$patched" >/dev/null

    # Verify file is unchanged
    local after
    after=$(cat "$mock_home/cleanproject/.claude/settings.local.json")
    assert_eq "$original" "$after" "settings.local.json without permissions should be untouched"
}
run_test "check 10: settings.local.json without permissions block is untouched" test_permissions_block_absent_untouched

test_permissions_removal_silent_on_success() {
    local config_repo="$TEST_TMPDIR/config-repo"
    local mock_home="$TEST_TMPDIR/home"
    local project_dir="$TEST_TMPDIR/project"
    mkdir -p "$mock_home/.claude" "$project_dir"

    create_mock_config_repo "$config_repo"
    touch "$config_repo/CLAUDE.md"
    ln -sf "$config_repo/CLAUDE.md" "$mock_home/.claude/CLAUDE.md"

    # Create a project with permissions block
    mkdir -p "$mock_home/warnproject/.claude"
    cat > "$mock_home/warnproject/.claude/settings.local.json" << 'EOF'
{
  "permissions": {
    "allow": [
      "Bash(foo:*)"
    ]
  },
  "enableAllProjectMcpServers": true
}
EOF

    local patched
    patched=$(create_patched_script "$config_repo" "$mock_home" "$project_dir")
    local output
    output=$(run_hook "$patched")

    # Cleanup should have happened (permissions removed)
    assert_file_not_contains "$mock_home/warnproject/.claude/settings.local.json" '"permissions"' \
        "should remove permissions block"

    # But NO warning should be generated — successful cleanup is silent
    assert_not_contains "$output" "Auto-removed stale permissions" \
        "should NOT warn when cleanup succeeds silently"
    assert_not_contains "$output" "permissions override" \
        "should NOT mention permissions override"
}
run_test "check 10: successful permissions cleanup produces no warning" test_permissions_removal_silent_on_success

test_permissions_multiple_projects_cleaned() {
    local config_repo="$TEST_TMPDIR/config-repo"
    local mock_home="$TEST_TMPDIR/home"
    local project_dir="$TEST_TMPDIR/project"
    mkdir -p "$mock_home/.claude" "$project_dir"

    create_mock_config_repo "$config_repo"
    touch "$config_repo/CLAUDE.md"
    ln -sf "$config_repo/CLAUDE.md" "$mock_home/.claude/CLAUDE.md"

    # Create two projects with permissions blocks
    mkdir -p "$mock_home/projA/.claude"
    cat > "$mock_home/projA/.claude/settings.local.json" << 'EOF'
{
  "permissions": {
    "allow": [
      "Bash(bar:*)"
    ]
  },
  "enableAllProjectMcpServers": true
}
EOF

    mkdir -p "$mock_home/projB/.claude"
    cat > "$mock_home/projB/.claude/settings.local.json" << 'EOF'
{
  "permissions": {
    "allow": [
      "Read(*)"
    ]
  },
  "mcpServers": {
    "test": {
      "command": "test"
    }
  }
}
EOF

    local patched
    patched=$(create_patched_script "$config_repo" "$mock_home" "$project_dir")
    local output
    output=$(run_hook "$patched")

    # Both should have permissions removed
    assert_file_not_contains "$mock_home/projA/.claude/settings.local.json" '"permissions"' \
        "should remove permissions from projA"
    assert_file_not_contains "$mock_home/projB/.claude/settings.local.json" '"permissions"' \
        "should remove permissions from projB"

    # Both should preserve their other keys
    assert_file_contains "$mock_home/projA/.claude/settings.local.json" '"enableAllProjectMcpServers"' \
        "should preserve enableAllProjectMcpServers in projA"
    assert_file_contains "$mock_home/projB/.claude/settings.local.json" '"mcpServers"' \
        "should preserve mcpServers in projB"

    # Successful cleanup should be silent — no warning for either project
    assert_not_contains "$output" "Auto-removed stale permissions" \
        "should NOT warn when cleanup succeeds silently"
    assert_not_contains "$output" "projA" \
        "should NOT mention projA in output"
    assert_not_contains "$output" "projB" \
        "should NOT mention projB in output"
}
run_test "check 10: multiple projects with permissions blocks both get cleaned" test_permissions_multiple_projects_cleaned

# ── 18. CLAUDE.local.md @import target validation ─────────────────────────────

test_claude_local_broken_import() {
    local config_repo="$TEST_TMPDIR/config-repo"
    local mock_home="$TEST_TMPDIR/home"
    local project_dir="$TEST_TMPDIR/project"
    mkdir -p "$mock_home/.claude" "$project_dir"

    create_mock_config_repo "$config_repo"
    touch "$config_repo/CLAUDE.md"
    ln -sf "$config_repo/CLAUDE.md" "$mock_home/.claude/CLAUDE.md"

    # Create CLAUDE.local.md with @import pointing to nonexistent file
    echo '@~/.claude/machines/NonExistent.md' > "$mock_home/CLAUDE.local.md"

    local patched
    patched=$(create_patched_script "$config_repo" "$mock_home" "$project_dir")
    local output
    output=$(run_hook "$patched")

    local msg
    msg=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['systemMessage'])" 2>/dev/null)
    assert_contains "$msg" "CLAUDE.local.md" "should mention CLAUDE.local.md"
    assert_contains "$msg" "NonExistent.md" "should mention the missing target file"
}
run_test "CLAUDE.local.md: warns when @import target does not exist" test_claude_local_broken_import

test_claude_local_valid_import() {
    local config_repo="$TEST_TMPDIR/config-repo"
    local remote_repo="$TEST_TMPDIR/remote.git"
    local mock_home="$TEST_TMPDIR/home"
    local project_dir="$TEST_TMPDIR/project"
    mkdir -p "$mock_home/.claude/machines" "$project_dir"

    create_tracked_repo_main "$config_repo" "$remote_repo"
    (cd "$config_repo" && touch sync.sh && git add sync.sh && git commit -m "add sync.sh" >/dev/null 2>&1 && git push origin main >/dev/null 2>&1)
    (cd "$config_repo" && touch CLAUDE.md && git add CLAUDE.md && git commit -m "add CLAUDE.md" >/dev/null 2>&1 && git push origin main >/dev/null 2>&1)
    ln -sf "$config_repo/CLAUDE.md" "$mock_home/.claude/CLAUDE.md"

    # Create valid machine file and CLAUDE.local.md pointing to it
    echo "# Steam Deck" > "$mock_home/.claude/machines/steamdeck.md"
    echo '@~/.claude/machines/steamdeck.md' > "$mock_home/CLAUDE.local.md"

    local patched
    patched=$(create_patched_script "$config_repo" "$mock_home" "$project_dir")
    local output
    output=$(run_hook "$patched")

    assert_not_contains "$output" "CLAUDE.local.md" "should NOT warn when @import target exists"
}
run_test "CLAUDE.local.md: no warning when @import target exists" test_claude_local_valid_import

test_claude_local_missing_file() {
    local config_repo="$TEST_TMPDIR/config-repo"
    local remote_repo="$TEST_TMPDIR/remote.git"
    local mock_home="$TEST_TMPDIR/home"
    local project_dir="$TEST_TMPDIR/project"
    mkdir -p "$mock_home/.claude" "$project_dir"

    create_tracked_repo_main "$config_repo" "$remote_repo"
    (cd "$config_repo" && touch sync.sh && git add sync.sh && git commit -m "add sync.sh" >/dev/null 2>&1 && git push origin main >/dev/null 2>&1)
    (cd "$config_repo" && touch CLAUDE.md && git add CLAUDE.md && git commit -m "add CLAUDE.md" >/dev/null 2>&1 && git push origin main >/dev/null 2>&1)
    ln -sf "$config_repo/CLAUDE.md" "$mock_home/.claude/CLAUDE.md"

    # No CLAUDE.local.md at all — should not warn (it's optional)

    local patched
    patched=$(create_patched_script "$config_repo" "$mock_home" "$project_dir")
    local output
    output=$(run_hook "$patched")

    assert_not_contains "$output" "CLAUDE.local.md" "should NOT warn when CLAUDE.local.md doesn't exist"
}
run_test "CLAUDE.local.md: no warning when file does not exist (optional)" test_claude_local_missing_file

# ── Summary ──────────────────────────────────────────────────────────────────

suite_summary
