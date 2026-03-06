#!/usr/bin/env bash
# Tests for install-base.sh — cc-mirror variant creation (always --no-tweak)
source "$(dirname "$0")/test-helpers.sh"

suite_header "install-base.sh — cc-mirror Variant Creation"

# ── Helper: set up mock environment ─────────────────────────────────────────

_setup_mock_env() {
    log_step() { :; }
    log_info() { MOCK_INFO+=("$*"); }
    log_warn() { MOCK_WARNINGS+=("$*"); }
    log_error() { MOCK_ERRORS+=("$*"); }
    log_success() { :; }
    run_cmd() { "$@"; }

    INSTALLED_STEPS=()
    SKIPPED_STEPS=()
    MOCK_INFO=()
    MOCK_WARNINGS=()
    MOCK_ERRORS=()
    DRY_RUN=false
    VERBOSE=false
    CC_MIRROR_VARIANT="mclaude"
    TOTAL_STEPS=6

    export -f log_step log_info log_warn log_error log_success run_cmd
}

_load_functions() {
    local script="$REPO_ROOT/setup/install-base.sh"
    eval "$(sed -n '/^create_mclaude_variant()/,/^}/p' "$script")"
}

# ── Test: skips when launcher exists ─────────────────────────────────────────

test_variant_skips_existing_launcher() {
    _setup_mock_env
    _load_functions

    mkdir -p "$TEST_TMPDIR/.local/bin"
    echo "#!/bin/bash" > "$TEST_TMPDIR/.local/bin/mclaude"
    HOME="$TEST_TMPDIR"

    create_mclaude_variant
    assert_contains "${SKIPPED_STEPS[*]}" "already exists"
}
run_test "create_mclaude_variant skips when launcher exists" test_variant_skips_existing_launcher

# ── Test: calls cc-mirror with --no-tweak and succeeds ───────────────────────

test_variant_calls_cc_mirror_no_tweak() {
    _setup_mock_env
    _load_functions

    HOME="$TEST_TMPDIR"
    mkdir -p "$TEST_TMPDIR/.local/bin"

    local cc_mirror_args=""
    cc-mirror() {
        cc_mirror_args="$*"
        echo "#!/bin/bash" > "$TEST_TMPDIR/.local/bin/mclaude"
        return 0
    }
    export -f cc-mirror

    create_mclaude_variant 2>&1

    assert_contains "$cc_mirror_args" "--no-tweak"
    assert_contains "${INSTALLED_STEPS[*]}" "mclaude-variant"

    unset -f cc-mirror
}
run_test "create_mclaude_variant always uses --no-tweak" test_variant_calls_cc_mirror_no_tweak

# ── Test: fails with clear error message ─────────────────────────────────────

test_variant_failure() {
    _setup_mock_env
    _load_functions

    HOME="$TEST_TMPDIR"
    mkdir -p "$TEST_TMPDIR/.local/bin"

    cc-mirror() { return 1; }
    export -f cc-mirror

    local exit_called=false
    exit() { exit_called=true; }
    export -f exit

    create_mclaude_variant 2>&1 || true

    local all_errors="${MOCK_ERRORS[*]}"
    assert_contains "$all_errors" "Failed"
    assert_eq "true" "$exit_called" "exit should be called on failure"

    unset -f cc-mirror exit
}
run_test "create_mclaude_variant exits on failure with clear error" test_variant_failure

# ── Test: dry run mode ──────────────────────────────────────────────────────

test_variant_dry_run() {
    _setup_mock_env
    _load_functions
    DRY_RUN=true
    HOME="$TEST_TMPDIR"

    create_mclaude_variant 2>&1

    assert_contains "${INSTALLED_STEPS[*]}" "dry-run"
    local all_info="${MOCK_INFO[*]}"
    assert_contains "$all_info" "--no-tweak"
}
run_test "create_mclaude_variant dry-run mentions --no-tweak" test_variant_dry_run

# ── Test: verify script documents TweakCC incompatibility ────────────────────

test_script_documents_tweakcc() {
    local script="$REPO_ROOT/setup/install-base.sh"
    assert_file_contains "$script" "TweakCC is DISABLED by default"
    assert_file_contains "$script" "incompatible with cc-mirror"
    assert_file_contains "$script" "statusline.*works independently of TweakCC"
}
run_test "install-base.sh documents TweakCC incompatibility" test_script_documents_tweakcc

# ── Test: no two-attempt fallback (always --no-tweak on first call) ──────────

test_no_fallback_logic() {
    _setup_mock_env
    _load_functions

    HOME="$TEST_TMPDIR"
    mkdir -p "$TEST_TMPDIR/.local/bin"

    local call_count=0
    cc-mirror() {
        ((call_count++)) || true
        echo "#!/bin/bash" > "$TEST_TMPDIR/.local/bin/mclaude"
        return 0
    }
    export -f cc-mirror

    create_mclaude_variant 2>&1

    assert_eq "1" "$call_count" "cc-mirror should be called exactly once (no retry logic)"

    unset -f cc-mirror
}
run_test "create_mclaude_variant calls cc-mirror exactly once (no fallback)" test_no_fallback_logic

# ── Test: settings.json has no TWEAKCC_CONFIG_DIR ────────────────────────────

test_settings_no_tweakcc_env() {
    local settings="$REPO_ROOT/setup/config/settings.json"
    assert_file_not_contains "$settings" "TWEAKCC_CONFIG_DIR"
}
run_test "settings.json has no TWEAKCC_CONFIG_DIR env var" test_settings_no_tweakcc_env

# ── Summary ─────────────────────────────────────────────────────────────────

suite_summary
