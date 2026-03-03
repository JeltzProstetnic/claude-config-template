#!/usr/bin/env bash
# Self-test for the test harness — verifies assertions, lifecycle, and fixtures work
source "$(dirname "$0")/test-helpers.sh"

suite_header "Test Harness Self-Test"

# ── Assertion tests ──────────────────────────────────────────────────────────

test_assert_eq_pass() {
    assert_eq "hello" "hello"
    assert_eq "" ""
    assert_eq "123" "123"
}
run_test "assert_eq passes on equal strings" test_assert_eq_pass

test_assert_eq_fail() {
    # This should fail — we capture the failure
    if assert_eq "hello" "world" 2>/dev/null; then
        return 1  # Should have failed
    fi
}
run_test "assert_eq fails on unequal strings" test_assert_eq_fail

test_assert_contains_pass() {
    assert_contains "hello world" "world"
    assert_contains "foobar" "oob"
}
run_test "assert_contains passes on substring match" test_assert_contains_pass

test_assert_contains_fail() {
    if assert_contains "hello world" "xyz" 2>/dev/null; then
        return 1
    fi
}
run_test "assert_contains fails on no match" test_assert_contains_fail

test_assert_not_contains() {
    assert_not_contains "hello world" "xyz"
    if assert_not_contains "hello world" "world" 2>/dev/null; then
        return 1
    fi
}
run_test "assert_not_contains works correctly" test_assert_not_contains

# ── File assertions ──────────────────────────────────────────────────────────

test_file_assertions() {
    local testfile="$TEST_TMPDIR/testfile.txt"
    echo "line one" > "$testfile"
    echo "line two" >> "$testfile"

    assert_file_exists "$testfile"
    assert_file_not_exists "$TEST_TMPDIR/nonexistent.txt"
    assert_dir_exists "$TEST_TMPDIR"
    assert_file_contains "$testfile" "line one"
    assert_file_not_contains "$testfile" "line three"
    assert_line_count "$testfile" 2
    assert_grep_count "$testfile" "line" 2
}
run_test "file assertions work correctly" test_file_assertions

# ── Exit code assertions ────────────────────────────────────────────────────

test_exit_code() {
    assert_exit_code 0 true
    assert_exit_code 1 false
    assert_success true
    assert_failure false
}
run_test "exit code assertions work correctly" test_exit_code

# ── Lifecycle ────────────────────────────────────────────────────────────────

test_tmpdir_isolation() {
    # Each test gets a unique tmpdir
    assert_dir_exists "$TEST_TMPDIR"
    local marker="$TEST_TMPDIR/marker.txt"
    echo "test" > "$marker"
    assert_file_exists "$marker"
}
run_test "test tmpdir is isolated and writable" test_tmpdir_isolation

test_tmpdir_cleanup() {
    # Verify previous test's tmpdir was cleaned up
    # We can't directly check, but we can verify our own is fresh
    local files
    files=$(ls -A "$TEST_TMPDIR" 2>/dev/null | wc -l)
    assert_eq "0" "$files" "tmpdir should be empty at test start"
}
run_test "test tmpdir is cleaned up between tests" test_tmpdir_cleanup

# ── Git fixtures ─────────────────────────────────────────────────────────────

test_create_git_repo() {
    local repo="$TEST_TMPDIR/repo"
    create_git_repo "$repo"

    assert_dir_exists "$repo/.git"
    assert_file_exists "$repo/README.md"

    local branch
    branch=$(cd "$repo" && git branch --show-current)
    # Accept either main or master
    [[ "$branch" == "main" ]] || [[ "$branch" == "master" ]]
}
run_test "create_git_repo creates a valid repo with initial commit" test_create_git_repo

test_create_tracked_repo() {
    local repo="$TEST_TMPDIR/repo"
    local remote="$TEST_TMPDIR/remote.git"
    create_tracked_repo "$repo" "$remote"

    assert_dir_exists "$repo/.git"
    assert_dir_exists "$remote"

    local remote_url
    remote_url=$(cd "$repo" && git remote get-url origin)
    assert_eq "$remote" "$remote_url"
}
run_test "create_tracked_repo sets up repo with remote tracking" test_create_tracked_repo

test_add_commit() {
    local repo="$TEST_TMPDIR/repo"
    create_git_repo "$repo"
    add_commit "$repo" "second commit"

    local count
    count=$(cd "$repo" && git rev-list --count HEAD)
    assert_eq "2" "$count" "should have 2 commits"
}
run_test "add_commit adds a commit to existing repo" test_add_commit

# ── Session context fixture ─────────────────────────────────────────────────

test_create_session_context() {
    local dir="$TEST_TMPDIR/project"
    create_session_context "$dir" "Test my goal" "test-box"

    assert_file_exists "$dir/session-context.md"
    assert_file_contains "$dir/session-context.md" "Test my goal"
    assert_file_contains "$dir/session-context.md" "test-box"
    assert_file_contains "$dir/session-context.md" '\- \[x\] Did something useful'
    assert_dir_exists "$dir/docs"
}
run_test "create_session_context generates valid session file" test_create_session_context

# ── Summary ──────────────────────────────────────────────────────────────────

suite_summary
