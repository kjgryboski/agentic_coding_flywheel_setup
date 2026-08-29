#!/usr/bin/env bash
# Focused unit tests for the R1 no-resume and read-only diagnostic contract.

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
LOG_INFO_TEXT=""
STATE_SET_RESUME_HINT_CALLS=0

log_info() {
    LOG_INFO_TEXT="${LOG_INFO_TEXT}${*}"$'\n'
}

log_detail() {
    LOG_INFO_TEXT="${LOG_INFO_TEXT}${*}"$'\n'
}

state_set_resume_hint() {
    ((STATE_SET_RESUME_HINT_CALLS++))
    return 0
}

acfs_r1_runtime_admit_entry() {
    [[ "${1:-}" != "resume" ]]
}

extract_function() {
    local function_name="$1"
    sed -n "/^${function_name}()/,/^}$/p" "$REPO_ROOT/install.sh"
}

# shellcheck disable=SC1090
eval "$(extract_function generate_resume_hint)"
# shellcheck disable=SC1090
eval "$(extract_function print_resume_hint)"
# shellcheck disable=SC1090
eval "$(extract_function acfs_is_read_only_mode)"
# shellcheck disable=SC1090
eval "$(extract_function normalize_read_only_modes)"

setup_test_env() {
    SCRIPT_DIR=""
    ACFS_VERIFIED_BOOTSTRAP_SOURCE=""
    ACFS_COMMIT_SHA_FULL=""
    ACFS_REF_INPUT="main"
    ACFS_REPO_OWNER="Dicklesworthstone"
    ACFS_REPO_NAME="agentic_coding_flywheel_setup"
    DRY_RUN=false
    PRINT_MODE=false
    LIST_MODULES=false
    PRINT_PLAN_MODE=false
    AUTO_FIX_MODE="prompt"
    LOG_INFO_TEXT=""
    STATE_SET_RESUME_HINT_CALLS=0
}

assert_license_hold_text() {
    local output_text="$1"
    [[ "$output_text" == *"LIC1+LIC2 HOLD: no restart command is authorized"* ]] || return 1
    [[ "$output_text" == *"9bfd85c340c6223482e07b96c668600e0db9a18b8a4f25e45f77f0129af63300"* ]] || return 1
    [[ "$output_text" == *"89b56c5a62cea238a9e9d3b6ff88a2923a88bafd45c982a523dba5c7de5b51ee"* ]] || return 1
    [[ "$output_text" != *"--only"* ]] || return 1
    [[ "$output_text" != *"--resume"* ]] || return 1
    [[ "$output_text" != *"curl "* ]]
}

test_generate_resume_hint_is_hard_rejected() {
    setup_test_env
    local output=""
    if output="$(generate_resume_hint languages install_rust 2>/dev/null)"; then
        printf 'generate_resume_hint unexpectedly admitted resume: %s\n' "$output" >&2
        return 1
    fi
    [[ -z "$output" ]]
}

test_print_resume_hint_does_not_write_state() {
    setup_test_env
    local state_file=""
    local before=""
    local after=""
    state_file="$(mktemp "${TMPDIR:-/tmp}/acfs-resume-state.XXXXXX")" || return 1
    printf '{"sentinel":"unchanged"}\n' > "$state_file"
    ACFS_STATE_FILE="$state_file"
    before="$(/usr/bin/shasum -a 256 "$state_file" | awk '{print $1}')"

    print_resume_hint languages install_rust

    after="$(/usr/bin/shasum -a 256 "$state_file" | awk '{print $1}')"
    rm -f "$state_file"
    [[ "$before" == "$after" ]] || return 1
    [[ "$STATE_SET_RESUME_HINT_CALLS" -eq 0 ]] || return 1
    assert_license_hold_text "$LOG_INFO_TEXT"
}

test_local_failure_path_emits_no_restart_command() {
    setup_test_env
    SCRIPT_DIR="/tmp/acfs local checkout"
    print_resume_hint stack install_stack
    [[ "$LOG_INFO_TEXT" != *"bash /tmp/acfs"* ]] || return 1
    assert_license_hold_text "$LOG_INFO_TEXT"
}

test_streamed_failure_path_emits_no_restart_command() {
    setup_test_env
    print_resume_hint stack install_stack
    [[ "$LOG_INFO_TEXT" != *"https://acfs.sh"* ]] || return 1
    assert_license_hold_text "$LOG_INFO_TEXT"
}

test_all_preview_modes_normalize_read_only() {
    local mode_var=""
    for mode_var in DRY_RUN PRINT_MODE LIST_MODULES PRINT_PLAN_MODE; do
        setup_test_env
        printf -v "$mode_var" '%s' true
        normalize_read_only_modes
        [[ "$AUTO_FIX_MODE" == "dry-run" ]] || return 1
        acfs_is_read_only_mode || return 1
    done
}

test_explicit_no_autofix_is_preserved() {
    setup_test_env
    DRY_RUN=true
    AUTO_FIX_MODE="no"
    normalize_read_only_modes
    [[ "$AUTO_FIX_MODE" == "no" ]] && acfs_is_read_only_mode
}

run_test() {
    local test_name="$1"
    ((TESTS_RUN++))
    if "$test_name"; then
        ((TESTS_PASSED++))
        printf 'PASS: %s\n' "$test_name"
    else
        ((TESTS_FAILED++))
        printf 'FAIL: %s\n' "$test_name" >&2
    fi
}

main() {
    run_test test_generate_resume_hint_is_hard_rejected
    run_test test_print_resume_hint_does_not_write_state
    run_test test_local_failure_path_emits_no_restart_command
    run_test test_streamed_failure_path_emits_no_restart_command
    run_test test_all_preview_modes_normalize_read_only
    run_test test_explicit_no_autofix_is_preserved
    printf 'Resume/read-only contract: %d passed, %d failed\n' "$TESTS_PASSED" "$TESTS_FAILED"
    [[ "$TESTS_FAILED" -eq 0 ]]
}

main "$@"
