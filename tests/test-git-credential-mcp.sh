#!/usr/bin/env bash
# Tests for git-credential-mcp helper script
source "$(dirname "$0")/test-helpers.sh"

suite_header "git-credential-mcp"

CRED_SCRIPT="$REPO_ROOT/setup/scripts/git-credential-mcp"

# ── Helper: create a mock MCP config ─────────────────────────────────────────
create_mock_mcp() {
    local dir="$1"
    local personal_token="${2:-ghp_personal_test_token}"
    local work_token="${3:-}"
    mkdir -p "$dir"
    local json='{
  "mcpServers": {
    "github": {
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "'"$personal_token"'"
      }
    }'
    if [[ -n "$work_token" ]]; then
        json="$json"',
    "github-work": {
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "'"$work_token"'"
      }
    }'
    fi
    json="$json"'
  }
}'
    echo "$json" > "$dir/.mcp.json"
}

# ── Tests ─────────────────────────────────────────────────────────────────────

test_exits_on_non_get() {
    local result
    result=$(echo "" | HOME="$TEST_TMPDIR" "$CRED_SCRIPT" store 2>&1) || true
    assert_eq "$result" ""
}
run_test "exits silently on non-get operations" test_exits_on_non_get

test_exits_on_non_github() {
    create_mock_mcp "$TEST_TMPDIR/.mcp.json_dir"
    local result
    result=$(printf 'protocol=https\nhost=gitlab.com\n' | HOME="$TEST_TMPDIR" "$CRED_SCRIPT" get 2>&1) || true
    assert_eq "$result" ""
}
run_test "exits silently for non-github hosts" test_exits_on_non_github

test_returns_personal_token() {
    create_mock_mcp "$TEST_TMPDIR"
    local result
    result=$(printf 'protocol=https\nhost=github.com\n' | HOME="$TEST_TMPDIR" "$CRED_SCRIPT" get)
    assert_contains "$result" "username=x-access-token"
    assert_contains "$result" "password=ghp_personal_test_token"
}
run_test "returns personal token for github.com" test_returns_personal_token

test_returns_personal_when_no_username() {
    create_mock_mcp "$TEST_TMPDIR" "ghp_personal123" "ghp_work456"
    local result
    result=$(printf 'protocol=https\nhost=github.com\n' | HOME="$TEST_TMPDIR" "$CRED_SCRIPT" get)
    assert_contains "$result" "password=ghp_personal123"
    assert_contains "$result" "username=x-access-token"
}
run_test "returns personal token when no username specified" test_returns_personal_when_no_username

test_returns_work_token_for_secondary_user() {
    create_mock_mcp "$TEST_TMPDIR" "ghp_personal123" "ghp_work456"
    local result
    result=$(
        export SECONDARY_GITHUB_USER="WorkUser"
        export SECONDARY_MCP_SERVER="github-work"
        printf 'protocol=https\nhost=github.com\nusername=WorkUser\n' | HOME="$TEST_TMPDIR" "$CRED_SCRIPT" get
    )
    assert_contains "$result" "password=ghp_work456"
    assert_contains "$result" "username=WorkUser"
}
run_test "returns work token for secondary username" test_returns_work_token_for_secondary_user

test_falls_back_personal_when_no_work_server() {
    create_mock_mcp "$TEST_TMPDIR" "ghp_personal_only"
    # No github-work server in config
    local result
    result=$(
        export SECONDARY_GITHUB_USER="WorkUser"
        export SECONDARY_MCP_SERVER="github-work"
        printf 'protocol=https\nhost=github.com\nusername=WorkUser\n' | HOME="$TEST_TMPDIR" "$CRED_SCRIPT" get
    )
    assert_contains "$result" "password=ghp_personal_only"
}
run_test "falls back to personal when work server absent" test_falls_back_personal_when_no_work_server

test_cc_mirror_config_preferred() {
    # Create cc-mirror config path
    mkdir -p "$TEST_TMPDIR/.cc-mirror/mclaude/config"
    create_mock_mcp "$TEST_TMPDIR/.cc-mirror/mclaude/config" "ghp_ccmirror_token"
    # Also create global fallback
    create_mock_mcp "$TEST_TMPDIR" "ghp_global_token"
    local result
    result=$(printf 'protocol=https\nhost=github.com\n' | HOME="$TEST_TMPDIR" "$CRED_SCRIPT" get)
    assert_contains "$result" "password=ghp_ccmirror_token"
}
run_test "prefers cc-mirror config over global .mcp.json" test_cc_mirror_config_preferred

test_global_fallback() {
    # No cc-mirror dir, only global .mcp.json
    create_mock_mcp "$TEST_TMPDIR" "ghp_global_fallback"
    local result
    result=$(printf 'protocol=https\nhost=github.com\n' | HOME="$TEST_TMPDIR" "$CRED_SCRIPT" get)
    assert_contains "$result" "password=ghp_global_fallback"
}
run_test "falls back to global .mcp.json when cc-mirror absent" test_global_fallback

suite_summary
