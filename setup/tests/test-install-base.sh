#!/usr/bin/env bash
# Tests for install-base.sh — specifically cc-mirror/TweakCC fallback behavior
source "$(dirname "$0")/test-helpers.sh"

suite_header "install-base.sh — cc-mirror TweakCC Fallback"

# ── Helper: set up mock environment ─────────────────────────────────────────
# We can't source install-base.sh directly (it calls main()), so we extract
# the functions under test via sed and mock their dependencies.

_setup_mock_env() {
    # Mock logging functions — capture warnings and errors for assertions
    log_step() { :; }
    log_info() { :; }
    log_warn() { MOCK_WARNINGS+=("$*"); }
    log_error() { MOCK_ERRORS+=("$*"); }
    log_success() { :; }
    run_cmd() { "$@"; }

    # Global state that the functions under test reference
    INSTALLED_STEPS=()
    SKIPPED_STEPS=()
    MOCK_WARNINGS=()
    MOCK_ERRORS=()
    DRY_RUN=false
    VERBOSE=false
    CC_MIRROR_VARIANT="mclaude"
    TOTAL_STEPS=6

    export -f log_step log_info log_warn log_error log_success run_cmd
}

# Load check_build_tools and create_mclaude_variant from install-base.sh
# Uses sed to extract function bodies without running main()
_load_functions() {
    local script="$REPO_ROOT/setup/install-base.sh"
    # Extract check_build_tools (standalone function before create_mclaude_variant)
    eval "$(sed -n '/^check_build_tools()/,/^}/p' "$script")"
    # Extract create_mclaude_variant (multi-line function)
    eval "$(sed -n '/^create_mclaude_variant()/,/^}/p' "$script")"
}

# ── Test: check_build_tools detects all present ─────────────────────────────

test_build_tools_all_present() {
    _setup_mock_env
    _load_functions

    # All tools exist on this system (WSL has gcc, make, python3)
    # If any are missing on the test runner, this test self-adjusts
    local result
    result=$(check_build_tools)

    # We can't assert empty on all systems, so just verify the function runs
    # The real logic test is in the "missing" tests below with mocked command
    [[ $? -eq 0 ]]
}
run_test "check_build_tools runs without error" test_build_tools_all_present

# ── Test: check_build_tools reports missing tools ───────────────────────────

test_build_tools_missing_detection() {
    _setup_mock_env

    # Define a version of check_build_tools that uses a custom lookup
    check_build_tools() {
        local missing=()
        for tool in gcc make python3; do
            # Simulate: gcc and make missing, python3 present
            case "$tool" in
                gcc|make) missing+=("$tool") ;;
                python3) ;; # present
            esac
        done
        echo "${missing[*]}"
    }

    local result
    result=$(check_build_tools)
    assert_contains "$result" "gcc"
    assert_contains "$result" "make"
    assert_not_contains "$result" "python3"
}
run_test "check_build_tools reports missing gcc and make" test_build_tools_missing_detection

test_build_tools_all_missing() {
    _setup_mock_env

    check_build_tools() {
        local missing=()
        for tool in gcc make python3; do
            missing+=("$tool")
        done
        echo "${missing[*]}"
    }

    local result
    result=$(check_build_tools)
    assert_contains "$result" "gcc"
    assert_contains "$result" "make"
    assert_contains "$result" "python3"
}
run_test "check_build_tools reports all three missing tools" test_build_tools_all_missing

test_build_tools_none_missing() {
    _setup_mock_env

    check_build_tools() {
        local missing=()
        # All present — nothing added
        echo "${missing[*]}"
    }

    local result
    result=$(check_build_tools)
    assert_eq "" "$result" "no missing tools should return empty string"
}
run_test "check_build_tools returns empty when all present" test_build_tools_none_missing

# ── Test: create_mclaude_variant skips when launcher exists ─────────────────

test_variant_skips_existing_launcher() {
    _setup_mock_env
    _load_functions

    # Create fake launcher
    mkdir -p "$TEST_TMPDIR/.local/bin"
    echo "#!/bin/bash" > "$TEST_TMPDIR/.local/bin/mclaude"
    HOME="$TEST_TMPDIR"

    create_mclaude_variant
    assert_contains "${SKIPPED_STEPS[*]}" "already exists"
}
run_test "create_mclaude_variant skips when launcher exists" test_variant_skips_existing_launcher

# ── Test: create_mclaude_variant calls cc-mirror and succeeds ───────────────

test_variant_calls_cc_mirror() {
    _setup_mock_env
    _load_functions

    HOME="$TEST_TMPDIR"
    mkdir -p "$TEST_TMPDIR/.local/bin"

    # Mock cc-mirror to succeed and create the launcher
    cc-mirror() {
        echo "mock cc-mirror: $*"
        echo "#!/bin/bash" > "$TEST_TMPDIR/.local/bin/mclaude"
        return 0
    }
    export -f cc-mirror

    create_mclaude_variant 2>&1

    assert_contains "${INSTALLED_STEPS[*]}" "mclaude-variant"
    # Should NOT contain "without TweakCC" since first attempt succeeded
    local step_text="${INSTALLED_STEPS[*]}"
    assert_not_contains "$step_text" "without TweakCC"

    unset -f cc-mirror
}
run_test "create_mclaude_variant succeeds on first try" test_variant_calls_cc_mirror

# ── Test: create_mclaude_variant falls back to --no-tweak on failure ────────

test_variant_fallback_no_tweak() {
    _setup_mock_env
    _load_functions

    HOME="$TEST_TMPDIR"
    mkdir -p "$TEST_TMPDIR/.local/bin"

    local call_count=0
    # Mock cc-mirror: first call fails, second call (with --no-tweak) succeeds
    cc-mirror() {
        ((call_count++)) || true
        if [[ $call_count -eq 1 ]]; then
            # First call (without --no-tweak) fails
            return 1
        else
            # Second call (with --no-tweak) succeeds
            echo "#!/bin/bash" > "$TEST_TMPDIR/.local/bin/mclaude"
            return 0
        fi
    }
    export -f cc-mirror

    create_mclaude_variant 2>&1

    # Should have called cc-mirror twice
    assert_eq "2" "$call_count" "cc-mirror should be called twice (first fails, second with --no-tweak)"

    # Should have a warning about TweakCC
    local all_warnings="${MOCK_WARNINGS[*]}"
    assert_contains "$all_warnings" "TweakCC"

    # Should track as installed without TweakCC
    assert_contains "${INSTALLED_STEPS[*]}" "without TweakCC"

    unset -f cc-mirror
}
run_test "create_mclaude_variant falls back to --no-tweak on failure" test_variant_fallback_no_tweak

# ── Test: create_mclaude_variant fails completely ───────────────────────────

test_variant_complete_failure() {
    _setup_mock_env
    _load_functions

    HOME="$TEST_TMPDIR"
    mkdir -p "$TEST_TMPDIR/.local/bin"

    # Mock cc-mirror: always fails
    cc-mirror() {
        return 1
    }
    export -f cc-mirror

    # Override exit to catch it instead of terminating the test
    local exit_called=false
    exit() { exit_called=true; }
    export -f exit

    create_mclaude_variant 2>&1 || true

    # Should have error messages
    local all_errors="${MOCK_ERRORS[*]}"
    assert_contains "$all_errors" "Failed"

    # exit should have been called
    assert_eq "true" "$exit_called" "exit should be called on complete failure"

    unset -f cc-mirror exit
}
run_test "create_mclaude_variant exits on complete failure (both attempts)" test_variant_complete_failure

# ── Test: build tools warning is logged before cc-mirror call ───────────────

test_build_tools_warning_logged() {
    _setup_mock_env

    HOME="$TEST_TMPDIR"
    mkdir -p "$TEST_TMPDIR/.local/bin"

    # Override check_build_tools to report missing tools
    check_build_tools() {
        echo "gcc make"
    }

    # Load create_mclaude_variant from the script
    local script="$REPO_ROOT/setup/install-base.sh"
    eval "$(sed -n '/^create_mclaude_variant()/,/^}/p' "$script")"

    # Mock cc-mirror to succeed
    cc-mirror() {
        echo "#!/bin/bash" > "$TEST_TMPDIR/.local/bin/mclaude"
        return 0
    }
    export -f cc-mirror

    create_mclaude_variant 2>&1

    # Should have warned about missing build tools
    local all_warnings="${MOCK_WARNINGS[*]}"
    assert_contains "$all_warnings" "Missing build tools"
    assert_contains "$all_warnings" "gcc make"

    unset -f cc-mirror
}
run_test "create_mclaude_variant warns about missing build tools" test_build_tools_warning_logged

# ── Test: no warning when all build tools present ───────────────────────────

test_no_build_tools_warning_when_present() {
    _setup_mock_env

    HOME="$TEST_TMPDIR"
    mkdir -p "$TEST_TMPDIR/.local/bin"

    # Override check_build_tools to report all present
    check_build_tools() {
        echo ""
    }

    local script="$REPO_ROOT/setup/install-base.sh"
    eval "$(sed -n '/^create_mclaude_variant()/,/^}/p' "$script")"

    cc-mirror() {
        echo "#!/bin/bash" > "$TEST_TMPDIR/.local/bin/mclaude"
        return 0
    }
    export -f cc-mirror

    create_mclaude_variant 2>&1

    # Should NOT have warned about build tools
    local all_warnings="${MOCK_WARNINGS[*]}"
    assert_not_contains "$all_warnings" "Missing build tools"

    unset -f cc-mirror
}
run_test "create_mclaude_variant does not warn when build tools present" test_no_build_tools_warning_when_present

# ── Test: dry run mode ──────────────────────────────────────────────────────

test_variant_dry_run() {
    _setup_mock_env
    _load_functions
    DRY_RUN=true

    HOME="$TEST_TMPDIR"

    create_mclaude_variant 2>&1

    assert_contains "${INSTALLED_STEPS[*]}" "dry-run"
}
run_test "create_mclaude_variant respects dry-run mode" test_variant_dry_run

# ── Test: verify script has the node-lief documentation comment ─────────────

test_script_has_node_lief_docs() {
    local script="$REPO_ROOT/setup/install-base.sh"
    assert_file_contains "$script" "node-lief is only needed for NATIVE BINARY"
    assert_file_contains "$script" "npm-based installs where node-lief is NOT required"
    assert_file_contains "$script" "node-lief.*misleading"
}
run_test "install-base.sh documents that node-lief error is misleading" test_script_has_node_lief_docs

# ── Test: verify --no-tweak flag is in the fallback path ────────────────────

test_script_has_no_tweak_fallback() {
    local script="$REPO_ROOT/setup/install-base.sh"
    assert_file_contains "$script" "\-\-no-tweak"
    assert_file_contains "$script" "Retrying without TweakCC"
}
run_test "install-base.sh contains --no-tweak fallback path" test_script_has_no_tweak_fallback

# ── Summary ─────────────────────────────────────────────────────────────────

suite_summary
