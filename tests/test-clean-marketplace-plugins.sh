#!/usr/bin/env bash
# Tests for clean-marketplace-plugins.sh
source "$(dirname "$0")/test-helpers.sh"

suite_header "Clean Marketplace Plugins"

SCRIPT="$REPO_ROOT/setup/scripts/clean-marketplace-plugins.sh"

# Helper: create a fake plugin directory
create_fake_plugin() {
    local base_dir="$1"
    local name="$2"
    local plugin_dir="$base_dir/$name"
    mkdir -p "$plugin_dir/.claude-plugin"
    echo '{"name":"'"$name"'"}' > "$plugin_dir/.claude-plugin/plugin.json"
    echo '{"'"$name"'":{"command":"test"}}' > "$plugin_dir/.mcp.json"
}

# Helper: run script with fake config dir
run_clean() {
    local config_dir="$1"
    shift
    CLEAN_PLUGINS_CONFIG_DIR="$config_dir" bash "$SCRIPT" "$@" 2>&1
}

# ── Tests ────────────────────────────────────────────────────────────────────

test_removes_unwanted_plugins() {
    local config_dir="$TEST_TMPDIR/config"
    local ext_dir="$config_dir/plugins/marketplaces/claude-plugins-official/external_plugins"
    mkdir -p "$ext_dir"

    create_fake_plugin "$ext_dir" "asana"
    create_fake_plugin "$ext_dir" "firebase"
    create_fake_plugin "$ext_dir" "gitlab"
    create_fake_plugin "$ext_dir" "context7"

    run_clean "$config_dir"

    # context7 should be kept
    assert_dir_exists "$ext_dir/context7"
    # Others should be removed
    assert_file_not_exists "$ext_dir/asana/.claude-plugin/plugin.json"
    assert_file_not_exists "$ext_dir/firebase/.claude-plugin/plugin.json"
    assert_file_not_exists "$ext_dir/gitlab/.claude-plugin/plugin.json"
}
run_test "removes unwanted plugins, keeps context7" test_removes_unwanted_plugins

test_dry_run_preserves_all() {
    local config_dir="$TEST_TMPDIR/config"
    local ext_dir="$config_dir/plugins/marketplaces/claude-plugins-official/external_plugins"
    mkdir -p "$ext_dir"

    create_fake_plugin "$ext_dir" "asana"
    create_fake_plugin "$ext_dir" "stripe"
    create_fake_plugin "$ext_dir" "context7"

    run_clean "$config_dir" --dry-run

    # All should still exist in dry-run mode
    assert_dir_exists "$ext_dir/asana"
    assert_dir_exists "$ext_dir/stripe"
    assert_dir_exists "$ext_dir/context7"
}
run_test "dry-run mode preserves all plugins" test_dry_run_preserves_all

test_no_external_plugins_dir() {
    local config_dir="$TEST_TMPDIR/config"
    mkdir -p "$config_dir"
    # No external_plugins dir at all

    local output
    output=$(run_clean "$config_dir")

    assert_contains "$output" "nothing to clean"
}
run_test "handles missing external_plugins directory gracefully" test_no_external_plugins_dir

test_empty_external_plugins_dir() {
    local config_dir="$TEST_TMPDIR/config"
    local ext_dir="$config_dir/plugins/marketplaces/claude-plugins-official/external_plugins"
    mkdir -p "$ext_dir"
    # Empty — no plugins at all

    local output
    output=$(run_clean "$config_dir")

    assert_contains "$output" "No external plugins found"
}
run_test "handles empty external_plugins directory" test_empty_external_plugins_dir

test_idempotent() {
    local config_dir="$TEST_TMPDIR/config"
    local ext_dir="$config_dir/plugins/marketplaces/claude-plugins-official/external_plugins"
    mkdir -p "$ext_dir"

    create_fake_plugin "$ext_dir" "asana"
    create_fake_plugin "$ext_dir" "context7"

    # Run twice
    run_clean "$config_dir"
    run_clean "$config_dir"

    # context7 still there, asana still gone
    assert_dir_exists "$ext_dir/context7"
    assert_file_not_exists "$ext_dir/asana/.claude-plugin/plugin.json"
}
run_test "idempotent — running twice produces same result" test_idempotent

test_removes_duplicates_of_own_servers() {
    local config_dir="$TEST_TMPDIR/config"
    local ext_dir="$config_dir/plugins/marketplaces/claude-plugins-official/external_plugins"
    mkdir -p "$ext_dir"

    # These duplicate our own ~/.mcp.json servers
    create_fake_plugin "$ext_dir" "github"
    create_fake_plugin "$ext_dir" "serena"
    create_fake_plugin "$ext_dir" "playwright"
    create_fake_plugin "$ext_dir" "context7"

    run_clean "$config_dir"

    # Duplicates should be removed
    assert_file_not_exists "$ext_dir/github/.claude-plugin/plugin.json"
    assert_file_not_exists "$ext_dir/serena/.claude-plugin/plugin.json"
    assert_file_not_exists "$ext_dir/playwright/.claude-plugin/plugin.json"
    # context7 kept
    assert_dir_exists "$ext_dir/context7"
}
run_test "removes marketplace duplicates of our own MCP servers" test_removes_duplicates_of_own_servers

test_output_reports_counts() {
    local config_dir="$TEST_TMPDIR/config"
    local ext_dir="$config_dir/plugins/marketplaces/claude-plugins-official/external_plugins"
    mkdir -p "$ext_dir"

    create_fake_plugin "$ext_dir" "asana"
    create_fake_plugin "$ext_dir" "slack"
    create_fake_plugin "$ext_dir" "linear"
    create_fake_plugin "$ext_dir" "context7"

    local output
    output=$(run_clean "$config_dir")

    assert_contains "$output" "Cleaned 3 of 4"
    assert_contains "$output" "kept 1"
}
run_test "output reports correct counts" test_output_reports_counts

# ── Phase 2: enabledPlugins cleanup tests ────────────────────────────────────

test_cleans_stale_enabled_plugins() {
    local config_dir="$TEST_TMPDIR/config"
    local ext_dir="$config_dir/plugins/marketplaces/claude-plugins-official/external_plugins"
    mkdir -p "$ext_dir"
    create_fake_plugin "$ext_dir" "context7"

    # Create settings.json with stale enabledPlugins entries
    cat > "$config_dir/settings.json" << 'EOF'
{
  "enabledPlugins": {
    "voltagent-lang@voltagent-subagents": false,
    "sentry-skills@getsentry": true,
    "superpowers@superpowers-marketplace": true,
    "modern-python@trailofbits": true
  }
}
EOF

    run_clean "$config_dir"

    # All stale entries should be removed (non-claude-plugins-official marketplaces)
    local remaining
    remaining=$(python3 -c "import json; ep=json.load(open('$config_dir/settings.json')).get('enabledPlugins',{}); print(len(ep))")
    assert_eq "$remaining" "0"
}
run_test "removes stale enabledPlugins from non-existent marketplaces" test_cleans_stale_enabled_plugins

test_preserves_official_marketplace_plugins() {
    local config_dir="$TEST_TMPDIR/config"
    local ext_dir="$config_dir/plugins/marketplaces/claude-plugins-official/external_plugins"
    mkdir -p "$ext_dir"

    # Settings with mix of official and non-official plugins
    cat > "$config_dir/settings.json" << 'EOF'
{
  "enabledPlugins": {
    "some-plugin@claude-plugins-official": true,
    "stale-plugin@unknown-marketplace": true
  }
}
EOF

    run_clean "$config_dir"

    local remaining
    remaining=$(python3 -c "import json; ep=json.load(open('$config_dir/settings.json')).get('enabledPlugins',{}); print(len(ep))")
    assert_eq "$remaining" "1"

    # Verify the official one is kept
    local kept
    kept=$(python3 -c "import json; ep=json.load(open('$config_dir/settings.json')).get('enabledPlugins',{}); print(list(ep.keys())[0])")
    assert_eq "$kept" "some-plugin@claude-plugins-official"
}
run_test "preserves enabledPlugins from official marketplace" test_preserves_official_marketplace_plugins

test_stale_plugins_dry_run() {
    local config_dir="$TEST_TMPDIR/config"
    mkdir -p "$config_dir"

    cat > "$config_dir/settings.json" << 'EOF'
{
  "enabledPlugins": {
    "sentry-skills@getsentry": true,
    "superpowers@superpowers-marketplace": true
  }
}
EOF

    run_clean "$config_dir" --dry-run

    # Should NOT modify settings.json in dry-run
    local remaining
    remaining=$(python3 -c "import json; ep=json.load(open('$config_dir/settings.json')).get('enabledPlugins',{}); print(len(ep))")
    assert_eq "$remaining" "2"
}
run_test "dry-run does not modify stale enabledPlugins" test_stale_plugins_dry_run

# ── Summary ──────────────────────────────────────────────────────────────────

suite_summary
