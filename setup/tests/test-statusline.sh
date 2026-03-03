#!/usr/bin/env bash
# Tests for setup/config/statusline.sh — context usage statusline rendering
source "$(dirname "$0")/test-helpers.sh"

suite_header "statusline.sh"

SCRIPT_PATH="$REPO_ROOT/setup/config/statusline.sh"

# ── Helpers ──────────────────────────────────────────────────────────────────

# Build a valid JSON input payload for the statusline script.
# Args: model_name percentage window_size input_tokens cache_creation cache_read
make_json() {
    local model="${1:-Opus 4.6}"
    local pct="${2:-54}"
    local win="${3:-200000}"
    local input_tok="${4:-50000}"
    local cache_create="${5:-30000}"
    local cache_read="${6:-28000}"
    printf '{"model":{"display_name":"%s"},"context_window":{"used_percentage":%s,"context_window_size":%s,"current_usage":{"input_tokens":%s,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s}}}' \
        "$model" "$pct" "$win" "$input_tok" "$cache_create" "$cache_read"
}

# Unicode block characters used in the bar
FILLED=$'\u2593'   # ▓
EMPTY=$'\u2591'    # ░

# ── Tests ────────────────────────────────────────────────────────────────────

test_basic_output_format() {
    local output
    output=$(echo "$(make_json "Opus 4.6" 54)" | bash "$SCRIPT_PATH")
    assert_contains "$output" "[Opus 4.6]" "output should contain model name in brackets"
}
run_test "basic output format: model name in brackets" test_basic_output_format

test_percentage_bar_54pct() {
    local output
    output=$(echo "$(make_json "Opus 4.6" 54)" | bash "$SCRIPT_PATH")
    # 54% of 10 chars = 5 filled, 5 empty (int(54*10/100) = 5)
    local expected_bar
    expected_bar=$(printf '%s' "${FILLED}${FILLED}${FILLED}${FILLED}${FILLED}${EMPTY}${EMPTY}${EMPTY}${EMPTY}${EMPTY}")
    assert_contains "$output" "$expected_bar" "54% should produce 5 filled + 5 empty"
}
run_test "percentage calculation: 54% bar width" test_percentage_bar_54pct

test_percentage_bar_25pct() {
    local output
    output=$(echo "$(make_json "Test" 25 200000 25000 0 0)" | bash "$SCRIPT_PATH")
    # 25% of 10 = 2 filled, 8 empty (int(25*10/100) = 2)
    local expected_bar
    expected_bar=$(printf '%s' "${FILLED}${FILLED}${EMPTY}${EMPTY}${EMPTY}${EMPTY}${EMPTY}${EMPTY}${EMPTY}${EMPTY}")
    assert_contains "$output" "$expected_bar" "25% should produce 2 filled + 8 empty"
}
run_test "percentage calculation: 25% bar width" test_percentage_bar_25pct

test_green_color_low_usage() {
    local raw_output
    raw_output=$(echo "$(make_json "Test" 50 200000 50000 0 0)" | bash "$SCRIPT_PATH")
    # Green ANSI: \033[32m — in raw output it appears as ESC[32m
    local green_esc=$'\033[32m'
    assert_contains "$raw_output" "$green_esc" "<70% usage should use green ANSI color"
}
run_test "green color for low usage (<70%)" test_green_color_low_usage

test_yellow_color_medium_usage() {
    local raw_output
    raw_output=$(echo "$(make_json "Test" 75 200000 75000 0 0)" | bash "$SCRIPT_PATH")
    local yellow_esc=$'\033[33m'
    assert_contains "$raw_output" "$yellow_esc" "70-89% usage should use yellow ANSI color"
}
run_test "yellow color for medium usage (70-89%)" test_yellow_color_medium_usage

test_yellow_at_boundary_70() {
    local raw_output
    raw_output=$(echo "$(make_json "Test" 70 200000 70000 0 0)" | bash "$SCRIPT_PATH")
    local yellow_esc=$'\033[33m'
    assert_contains "$raw_output" "$yellow_esc" "exactly 70% should use yellow"
}
run_test "yellow color at boundary (exactly 70%)" test_yellow_at_boundary_70

test_red_color_high_usage() {
    local raw_output
    raw_output=$(echo "$(make_json "Test" 95 200000 95000 0 0)" | bash "$SCRIPT_PATH")
    local red_esc=$'\033[31m'
    assert_contains "$raw_output" "$red_esc" "90%+ usage should use red ANSI color"
}
run_test "red color for high usage (90%+)" test_red_color_high_usage

test_red_at_boundary_90() {
    local raw_output
    raw_output=$(echo "$(make_json "Test" 90 200000 90000 0 0)" | bash "$SCRIPT_PATH")
    local red_esc=$'\033[31m'
    assert_contains "$raw_output" "$red_esc" "exactly 90% should use red"
}
run_test "red color at boundary (exactly 90%)" test_red_at_boundary_90

test_green_at_boundary_69() {
    local raw_output
    raw_output=$(echo "$(make_json "Test" 69 200000 69000 0 0)" | bash "$SCRIPT_PATH")
    local green_esc=$'\033[32m'
    assert_contains "$raw_output" "$green_esc" "69% should still be green"
}
run_test "green color at boundary (69%)" test_green_at_boundary_69

test_token_count_display() {
    local output
    # 54% of 200000 = 108000 tokens → 108k. used_k = int(200000 * 54 / 100000) = 108
    output=$(echo "$(make_json "Opus 4.6" 54 200000 50000 30000 28000)" | bash "$SCRIPT_PATH")
    assert_contains "$output" "108k/200k" "should show derived token count as Xk/Yk"
}
run_test "token count display: Xk/Yk format" test_token_count_display

test_token_count_percentage_display() {
    local output
    output=$(echo "$(make_json "Opus 4.6" 54 200000 50000 30000 28000)" | bash "$SCRIPT_PATH")
    assert_contains "$output" "(54%)" "should show percentage in parentheses"
}
run_test "token count display: percentage in parens" test_token_count_percentage_display

test_error_handling_invalid_json() {
    local output
    output=$(echo "this is not json at all" | bash "$SCRIPT_PATH")
    assert_eq "[?] ..." "$output" "invalid JSON should produce fallback output"
}
run_test "error handling: invalid JSON produces fallback" test_error_handling_invalid_json

test_error_handling_partial_json() {
    local output
    output=$(echo '{"model": {}}' | bash "$SCRIPT_PATH")
    # This is valid JSON but with missing fields — python should handle gracefully
    # with defaults: model=?, pct=0, win=200000
    assert_contains "$output" "[?]" "partial JSON should use ? as model name"
}
run_test "error handling: partial JSON uses fallback model name" test_error_handling_partial_json

test_empty_input() {
    local output
    output=$(echo "" | bash "$SCRIPT_PATH")
    assert_eq "[?] ..." "$output" "empty stdin should produce fallback output"
}
run_test "empty input: produces fallback output" test_empty_input

test_zero_usage() {
    local output
    output=$(echo "$(make_json "Test" 0 200000 0 0 0)" | bash "$SCRIPT_PATH")
    # 0% → 0 filled, 10 empty
    local all_empty
    all_empty=$(printf '%s' "${EMPTY}${EMPTY}${EMPTY}${EMPTY}${EMPTY}${EMPTY}${EMPTY}${EMPTY}${EMPTY}${EMPTY}")
    assert_contains "$output" "$all_empty" "0% should show all empty bar characters"
    assert_contains "$output" "(0%)" "should show 0%"
}
run_test "zero usage: empty bar with all light shade chars" test_zero_usage

test_full_usage() {
    local output
    output=$(echo "$(make_json "Test" 100 200000 100000 50000 50000)" | bash "$SCRIPT_PATH")
    # 100% → 10 filled, 0 empty
    local all_filled
    all_filled=$(printf '%s' "${FILLED}${FILLED}${FILLED}${FILLED}${FILLED}${FILLED}${FILLED}${FILLED}${FILLED}${FILLED}")
    assert_contains "$output" "$all_filled" "100% should show all filled bar characters"
    assert_contains "$output" "(100%)" "should show 100%"
}
run_test "full usage: full bar with all dark shade chars" test_full_usage

test_reset_ansi_at_end() {
    local raw_output
    raw_output=$(echo "$(make_json "Test" 50 200000 50000 0 0)" | bash "$SCRIPT_PATH")
    local reset_esc=$'\033[0m'
    assert_contains "$raw_output" "$reset_esc" "output should end with ANSI reset code"
}
run_test "ANSI reset code at end of output" test_reset_ansi_at_end

test_different_window_size() {
    local output
    # 50% of 128000 → used_k = int(128000 * 50 / 100000) = 64
    output=$(echo "$(make_json "Sonnet" 50 128000 32000 16000 16000)" | bash "$SCRIPT_PATH")
    assert_contains "$output" "[Sonnet]" "should show correct model name"
    assert_contains "$output" "64k/128k" "should compute token counts from window size"
    assert_contains "$output" "(50%)" "should show correct percentage"
}
run_test "different window size: 128k context" test_different_window_size

suite_summary
