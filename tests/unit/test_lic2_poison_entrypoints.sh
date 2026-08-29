#!/usr/bin/env bash
# Dynamic poison-pill coverage for finalized LIC1+LIC2 runtime exclusion.

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/acfs-lic2-poison.XXXXXX")" || exit 1
FIXTURE_ROOT="$TMP_ROOT/fixture"
POISON_MARKER="$FIXTURE_ROOT/poison-callback-fired"

passed=0
failed=0

pass() {
    passed=$((passed + 1))
    printf 'PASS: %s\n' "$1"
}

fail() {
    failed=$((failed + 1))
    printf 'FAIL: %s\n' "$1" >&2
    [[ -n "${2:-}" ]] && printf '  %s\n' "$2" >&2
}

extract_function() {
    local file="$1"
    local name="$2"
    local line=""
    local heredoc_delimiter=""
    local candidate_delimiter=""
    local found=false

    # A plain /^name() {$/,/^}$/ range is unsound for generated installers:
    # their install commands contain heredocs with column-zero shell functions
    # and closing braces.  Track heredoc bodies so those embedded braces cannot
    # truncate the extracted outer function and turn a parse error into a false
    # fail-closed result.
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$found" != "true" ]]; then
            [[ "$line" == "$name() {" ]] || continue
            found=true
        fi

        printf '%s\n' "$line"

        if [[ -n "$heredoc_delimiter" ]]; then
            if [[ "$line" == "$heredoc_delimiter" || "${line#"${line%%[!$'\t']*}"}" == "$heredoc_delimiter" ]]; then
                heredoc_delimiter=""
            fi
            continue
        fi

        candidate_delimiter="$(
            printf '%s\n' "$line" \
                | /usr/bin/sed -n "s/.*<<-*[	 ]*['\"]\{0,1\}\([A-Za-z_][A-Za-z0-9_]*\)['\"]\{0,1\}.*/\1/p"
        )"
        if [[ -n "$candidate_delimiter" ]]; then
            heredoc_delimiter="$candidate_delimiter"
            continue
        fi

        [[ "$line" == "}" ]] && return 0
    done < "$file"

    return 1
}

fixture_snapshot() {
    local path=""
    while IFS= read -r path; do
        if [[ -L "$path" ]]; then
            printf 'L|%s|%s\n' "${path#"$FIXTURE_ROOT"/}" "$(/usr/bin/readlink "$path")"
        elif [[ -f "$path" ]]; then
            printf 'F|%s|' "${path#"$FIXTURE_ROOT"/}"
            /usr/bin/shasum -a 256 "$path" | /usr/bin/awk '{print $1}'
        elif [[ -d "$path" ]]; then
            printf 'D|%s\n' "${path#"$FIXTURE_ROOT"/}"
        fi
    done < <(/usr/bin/find "$FIXTURE_ROOT" -print | LC_ALL=C /usr/bin/sort)
}

poison_callback() {
    builtin printf '%s\n' "$*" >> "$POISON_MARKER"
    return 97
}

define_downstream_poison() {
    local callback_name=""
    for callback_name in \
        command type stat readlink sha256sum shasum cat curl wget git jq tmux systemctl ss lsof ps pgrep kill sleep \
        mktemp mkdir mv ln rm chmod chown cp tar gzip \
        acfs_generated_ensure_selection should_run_module acfs_module_is_installed acfs_security_init \
        fetch_checksum get_checksum verify_checksum fetch_and_run fetch_and_run_with_runner \
        acfs_download_to_file acfs_stage_verified_installer acfs_fetch_url_content \
        binary_path binary_installed get_tool_version prepare_target_context augment_path_for_target_user \
        state_get_file state_init state_write_atomic state_load state_set_resume_hint state_mark_interrupted \
        progress_init progress_start progress_update progress_complete progress_count_modules \
        run_as_target run_as_target_shell run_as_root_shell run_as_current_shell run_as_target_runner \
        install_mcp_agent_mail install_beads_rust install_bv install_meta_skill install_skills \
        ensure_path detect_environment parse_args bootstrap_repo_archive fetch_commit_sha print_pinned_ref \
        acfs_normalize_verified_installer_cache_configuration \
        _initialize_bins _session_exists _port_is_listening _agent_mail_is_healthy \
        _native_agent_mail_unit_available _native_agent_mail_is_active _require_tmux \
        print_fix_summary end_autofix_session print_undo_summary report_success webhook_notify acfs_summary_emit \
        acfs_bootstrap_dir_is_owned_temp acfs_file_is_owned_temp acfs_release_install_lock acfs_log_close; do
        eval "$callback_name() { poison_callback '$callback_name'; }"
    done
}

define_policy_poison() {
    local policy_name=""
    for policy_name in \
        acfs_license_exclusion_profile_payload _acfs_license_profile_actual_sha256 \
        acfs_license_policy_verify_profile acfs_license_policy_module_is_held \
        acfs_license_policy_module_is_plain_mit_only acfs_license_policy_admit_entry \
        acfs_r1_runtime_profile_payload _acfs_r1_sha256_file _acfs_r1_profile_actual_sha256 \
        _acfs_r1_runtime_root _acfs_r1_verify_bound_file acfs_r1_runtime_verify_profile \
        acfs_r1_runtime_module_is_held acfs_r1_runtime_module_is_planned \
        acfs_r1_runtime_admit_entry _acfs_r1_array_csv acfs_r1_runtime_prepare_selection \
        acfs_r1_runtime_validate_plan acfs_core_policy_enforce acfs_core_policy_reason \
        acfs_core_policy_contract _acfs_core_policy_target_home \
        acfs_core_policy_expected_binary_path acfs_core_policy_expected_bv_versioned_path \
        acfs_core_policy_expected_binary_sha256 _acfs_core_policy_sha256_file \
        _acfs_core_policy_version_output acfs_core_policy_admit_binary \
        acfs_core_policy_admit_repair_source acfs_core_policy_enforce_installer_execution; do
        eval "$policy_name() { poison_callback 'policy:$policy_name'; return 0; }"
    done
}

mkdir -p \
    "$FIXTURE_ROOT/bin" \
    "$FIXTURE_ROOT/home/.local/bin" \
    "$FIXTURE_ROOT/home/.local/lib/acfs/bv/v0.22.0" \
    "$FIXTURE_ROOT/state"
for sentinel_name in manifest index checksums state progress config log receipt; do
    printf '%s sentinel\n' "$sentinel_name" > "$FIXTURE_ROOT/state/$sentinel_name"
done
printf '#!/bin/sh\nprintf "binary invoked\\n" >> "$ACFS_POISON_MARKER"\nexit 97\n' > "$FIXTURE_ROOT/bin/poison"
chmod 0755 "$FIXTURE_ROOT/bin/poison"
for poison_name in br bv am cass cm ntm curl git jq tmux systemctl ss lsof; do
    ln -s poison "$FIXTURE_ROOT/bin/$poison_name"
done
printf '#!/bin/sh\nexit 0\n' > "$FIXTURE_ROOT/home/.local/lib/acfs/bv/v0.22.0/bv"
chmod 0755 "$FIXTURE_ROOT/home/.local/lib/acfs/bv/v0.22.0/bv"
ln -s "$FIXTURE_ROOT/bin/poison" "$FIXTURE_ROOT/home/.local/bin/br"
ln -s "$FIXTURE_ROOT/bin/poison" "$FIXTURE_ROOT/home/.local/bin/bv"

export ACFS_POISON_MARKER="$POISON_MARKER"
export PATH="$FIXTURE_ROOT/bin:/usr/bin:/bin"
export HOME="$FIXTURE_ROOT/home"

fixture_before="$(fixture_snapshot)"

# Every generated held-module function must replace ambient authority and stop
# before contract consumers, selection, installed predicates, installers, or
# verification callbacks.
ACFS_BLUE=test
# shellcheck source=../../scripts/lib/contract.sh
source "$REPO_ROOT/scripts/lib/contract.sh"
IFS=',' read -r -a held_modules <<< "$ACFS_LICENSE_HELD_CSV"
generated_failures=()
for module_id in "${held_modules[@]}"; do
    function_name="acfs_generated_install_${module_id//./_}"
    function_body="$(extract_function "$REPO_ROOT/scripts/generated/install_stack.sh" "$function_name")"
    if [[ -z "$function_body" ]]; then
        generated_failures+=("$module_id:missing")
        continue
    fi
    if ! (
        define_downstream_poison
        define_policy_poison
        eval "$function_body"
        log_error() { :; }
        log_info() { poison_callback log_info; }
        log_step() { poison_callback log_step; }
        ACFS_GENERATED_SCRIPT_DIR="$REPO_ROOT/scripts/generated"
        ACFS_R1_RUNTIME_PROFILE_ID="poisoned-profile"
        "$function_name" >/dev/null 2>&1
        exit $?
    ); then
        :
    else
        generated_failures+=("$module_id:admitted")
    fi
    [[ ! -e "$POISON_MARKER" ]] || generated_failures+=("$module_id:poison-fired")
done
if [[ ${#held_modules[@]} -eq 27 && ${#generated_failures[@]} -eq 0 ]]; then
    pass "all 27 generated direct module functions reject poisoned ambient authority before callbacks"
else
    fail "all 27 generated direct module functions reject poisoned ambient authority before callbacks" \
        "held=${#held_modules[@]} failures=${generated_failures[*]}"
fi

# The local installer main, every moduleless lifecycle classification, direct
# profile resolution, and EXIT cleanup must all reject before parsing or any
# state/log/receipt/temp callback.
early_gate_def="$(extract_function "$REPO_ROOT/install.sh" acfs_enforce_early_license_exclusion)"
main_def="$(extract_function "$REPO_ROOT/install.sh" main)"
cleanup_def="$(extract_function "$REPO_ROOT/install.sh" cleanup)"
installer_entry_failures=()
if ! (
    define_downstream_poison
    define_policy_poison
    eval "$early_gate_def"
    eval "$main_def"
    eval "$cleanup_def"
    SCRIPT_DIR="$REPO_ROOT"
    ACFS_BLUE=test
    for args in \
        "" \
        "--profile stack-only" \
        "--resume" \
        "--dry-run" \
        "--print" \
        "--list-modules" \
        "--print-plan" \
        "--only stack.mcp_agent_mail"; do
        # shellcheck disable=SC2086
        if main $args >/dev/null 2>&1; then
            exit 1
        fi
        [[ "${ACFS_R1_POLICY_REASON:-}" == *"LIC1+LIC2 HOLD"* ]] || exit 1
    done
    for lifecycle in default filtered resume finalize failure-cleanup plan print list configuration helper; do
        define_policy_poison
        if acfs_enforce_early_license_exclusion "$lifecycle" >/dev/null 2>&1; then
            exit 1
        fi
        [[ "${ACFS_R1_POLICY_REASON:-}" == *"LIC1+LIC2 HOLD"* ]] || exit 1
    done
    define_policy_poison
    false
    cleanup >/dev/null 2>&1
    [[ $? -ne 0 && ! -e "$POISON_MARKER" ]]
); then
    installer_entry_failures+=("installer-entry")
fi
if [[ ${#installer_entry_failures[@]} -eq 0 && ! -e "$POISON_MARKER" ]]; then
    pass "default/profile/resume/finalize/failure-cleanup paths reject before parsing or mutation"
else
    fail "default/profile/resume/finalize/failure-cleanup paths reject before parsing or mutation" \
        "failures=${installer_entry_failures[*]}"
fi

# Direct installer and checksum helpers are extracted exactly, then invoked
# with poison paths and callbacks.  Their first real dependency must be the
# canonical policy rebind.
install_helper_names=(
    acfs_fetch_url_content
    acfs_fetch_fresh_checksums_via_api
    acfs_parse_checksums_content
    acfs_required_upstream_tools
    acfs_validate_upstream_checksums
    acfs_load_upstream_checksums
    acfs_run_verified_upstream_script_as_target_with_env
    acfs_run_verified_upstream_script_as_target
    binary_path
    binary_installed
    _smoke_target_path
    _smoke_run_as_target
    acfs_smoke_install_fix_command
    run_smoke_test
)
direct_install_failures=()
for function_name in "${install_helper_names[@]}"; do
    function_body="$(extract_function "$REPO_ROOT/install.sh" "$function_name")"
    if [[ -z "$function_body" ]] || ! (
        define_downstream_poison
        define_policy_poison
        eval "$early_gate_def"
        eval "$function_body"
        SCRIPT_DIR="$REPO_ROOT"
        ACFS_BLUE=test
        "$function_name" poison://held "$FIXTURE_ROOT/state/manifest" held extra >/dev/null 2>&1
        exit $?
    ); then
        :
    else
        direct_install_failures+=("$function_name:admitted")
    fi
    [[ ! -e "$POISON_MARKER" ]] || direct_install_failures+=("$function_name:poison-fired")
done
if [[ ${#direct_install_failures[@]} -eq 0 ]]; then
    pass "install fetch/checksum/network/smoke/direct helpers reject before poison"
else
    fail "install fetch/checksum/network/smoke/direct helpers reject before poison" \
        "failures=${direct_install_failures[*]}"
fi

security_rebind_def="$(extract_function "$REPO_ROOT/scripts/lib/security.sh" _acfs_security_rebind_canonical_contract)"
security_admit_def="$(extract_function "$REPO_ROOT/scripts/lib/security.sh" _acfs_security_admit_module_operation)"
security_helper_names=(
    acfs_download_to_file
    acfs_installer_cache_snapshot_regular_file
    acfs_installer_cache_verify_bound_file
    acfs_offline_pack_locate
    acfs_offline_pack_validate_manifest
    acfs_offline_pack_verify_artifact
    fetch_checksum
    verify_checksum
    acfs_stage_verified_installer
    fetch_and_run_with_runner
    fetch_and_run
    fetch_and_run_with_recovery
    print_upstream_urls
    print_current_checksums
    acfs_load_checksums_strict
    load_checksums
    get_checksum
    acfs_fetch_fresh_checksums_to_file
    handle_all_checksum_mismatches
    check_installer_checksum
    verify_all_installers
    verify_all_installers_json
)
security_failures=()
for function_name in "${security_helper_names[@]}"; do
    function_body="$(extract_function "$REPO_ROOT/scripts/lib/security.sh" "$function_name")"
    if [[ -z "$function_body" ]] || ! (
        define_downstream_poison
        define_policy_poison
        eval "$security_rebind_def"
        eval "$security_admit_def"
        eval "$function_body"
        SECURITY_SCRIPT_DIR="$REPO_ROOT/scripts/lib"
        ACFS_BLUE=test
        log_error() { :; }
        "$function_name" poison://held "$FIXTURE_ROOT/state/checksums" held extra >/dev/null 2>&1
        exit $?
    ); then
        :
    else
        security_failures+=("$function_name:admitted")
    fi
    [[ ! -e "$POISON_MARKER" ]] || security_failures+=("$function_name:poison-fired")
done
if [[ ${#security_failures[@]} -eq 0 ]]; then
    pass "security cache/staging/fetch/checksum/list helpers reject before poison"
else
    fail "security cache/staging/fetch/checksum/list helpers reject before poison" \
        "failures=${security_failures[*]}"
fi

# Direct metadata, selection, progress, state, and export/config helpers use
# their own canonical rebinders.  Exercise representative public helpers from
# every library with poisoned backing arrays and callbacks.
helper_failures=()
if ! (
    define_downstream_poison
    define_policy_poison
    eval "$(extract_function "$REPO_ROOT/scripts/lib/install_helpers.sh" _acfs_install_helpers_rebind_canonical_contract)"
    eval "$(extract_function "$REPO_ROOT/scripts/lib/install_helpers.sh" _acfs_install_helpers_admit)"
    eval "$(extract_function "$REPO_ROOT/scripts/lib/install_helpers.sh" source_manifest_index)"
    eval "$(extract_function "$REPO_ROOT/scripts/lib/install_helpers.sh" acfs_module_is_installed)"
    eval "$(extract_function "$REPO_ROOT/scripts/lib/install_helpers.sh" acfs_run_generated_category_phase)"
    INSTALL_HELPERS_DIR="$REPO_ROOT/scripts/lib"
    ACFS_GENERATED_DIR="$FIXTURE_ROOT/state"
    source_manifest_index >/dev/null 2>&1 && exit 1
    acfs_module_is_installed stack.beads_rust >/dev/null 2>&1 && exit 1
    acfs_run_generated_category_phase stack >/dev/null 2>&1 && exit 1
    [[ ! -e "$POISON_MARKER" ]]
); then
    helper_failures+=("install-helpers")
fi
if ! (
    define_downstream_poison
    define_policy_poison
    eval "$(extract_function "$REPO_ROOT/scripts/lib/progress.sh" _progress_admit_module_metadata)"
    eval "$(extract_function "$REPO_ROOT/scripts/lib/progress.sh" progress_count_modules)"
    _ACFS_PROGRESS_SCRIPT_DIR="$REPO_ROOT/scripts/lib"
    progress_count_modules >/dev/null 2>&1
    exit $?
); then
    :
else
    helper_failures+=("progress")
fi
if ! (
    define_downstream_poison
    define_policy_poison
    eval "$(extract_function "$REPO_ROOT/scripts/lib/state.sh" _state_license_admit)"
    eval "$(extract_function "$REPO_ROOT/scripts/lib/state.sh" state_init)"
    eval "$(extract_function "$REPO_ROOT/scripts/lib/state.sh" state_write_atomic)"
    eval "$(extract_function "$REPO_ROOT/scripts/lib/state.sh" state_load)"
    eval "$(extract_function "$REPO_ROOT/scripts/lib/state.sh" state_selection_includes_phase)"
    _ACFS_STATE_SCRIPT_DIR="$REPO_ROOT/scripts/lib"
    state_init >/dev/null 2>&1 && exit 1
    state_write_atomic "$FIXTURE_ROOT/state/state" poison >/dev/null 2>&1 && exit 1
    state_load >/dev/null 2>&1 && exit 1
    state_selection_includes_phase 9 >/dev/null 2>&1 && exit 1
    [[ ! -e "$POISON_MARKER" ]]
); then
    helper_failures+=("state")
fi
if ! (
    define_downstream_poison
    define_policy_poison
    eval "$(extract_function "$REPO_ROOT/scripts/lib/export-config.sh" export_config_license_admit)"
    eval "$(extract_function "$REPO_ROOT/scripts/lib/export-config.sh" get_tool_version)"
    eval "$(extract_function "$REPO_ROOT/scripts/lib/export-config.sh" get_modules)"
    eval "$(extract_function "$REPO_ROOT/scripts/lib/export-config.sh" export_config_main)"
    _EXPORT_SCRIPT_DIR="$REPO_ROOT/scripts/lib"
    log_error() { :; }
    get_tool_version br >/dev/null 2>&1 && exit 1
    get_modules >/dev/null 2>&1 && exit 1
    export_config_main >/dev/null 2>&1 && exit 1
    [[ ! -e "$POISON_MARKER" ]]
); then
    helper_failures+=("export-config")
fi
if [[ ${#helper_failures[@]} -eq 0 && ! -e "$POISON_MARKER" ]]; then
    pass "manifest/installed/progress/state/config direct helpers reject before poison"
else
    fail "manifest/installed/progress/state/config direct helpers reject before poison" \
        "failures=${helper_failures[*]}"
fi

# Update repair is now evidence only of refusal under LIC2.  It must not call a
# mocked admission success path or alter the canonical/public symlink fixture.
repair_def="$(extract_function "$REPO_ROOT/scripts/lib/update.sh" _update_r1_repair_bv_canonical_link)"
update_rebind_def="$(extract_function "$REPO_ROOT/scripts/lib/update.sh" _update_rebind_canonical_contract)"
repair_link_before="$(/usr/bin/readlink "$FIXTURE_ROOT/home/.local/bin/bv")"
if (
    define_downstream_poison
    define_policy_poison
    eval "$update_rebind_def"
    eval "$repair_def"
    SCRIPT_DIR="$REPO_ROOT/scripts/lib"
    DRY_RUN=false
    _update_r1_repair_bv_canonical_link "$FIXTURE_ROOT/home" >/dev/null 2>&1
); then
    fail "held bv repair rejects before path lookup or symlink mutation" "repair returned success"
elif [[ ! -e "$POISON_MARKER" \
    && "$(/usr/bin/readlink "$FIXTURE_ROOT/home/.local/bin/bv")" == "$repair_link_before" ]]; then
    pass "held bv repair rejects before path lookup or symlink mutation"
else
    fail "held bv repair rejects before path lookup or symlink mutation"
fi

# Aggregate update/doctor/fix/stack and service boundaries must stop before
# child dispatch, probes, fix summaries, sessions, sockets, or processes.
lifecycle_failures=()
if ! (
    define_downstream_poison
    define_policy_poison
    eval "$update_rebind_def"
    eval "$(extract_function "$REPO_ROOT/scripts/lib/update.sh" main)"
    SCRIPT_DIR="$REPO_ROOT/scripts/lib"
    main --stack >/dev/null 2>&1
    exit $?
); then :; else lifecycle_failures+=("update"); fi
if ! (
    define_downstream_poison
    define_policy_poison
    eval "$(extract_function "$REPO_ROOT/scripts/lib/doctor.sh" _acfs_doctor_rebind_canonical_contract)"
    eval "$(extract_function "$REPO_ROOT/scripts/lib/doctor.sh" main)"
    SCRIPT_DIR="$REPO_ROOT/scripts/lib"
    main doctor --deep >/dev/null 2>&1
    exit $?
); then :; else lifecycle_failures+=("doctor"); fi
if ! (
    define_downstream_poison
    define_policy_poison
    eval "$(extract_function "$REPO_ROOT/scripts/lib/doctor_fix.sh" _doctor_fix_rebind_canonical_contract)"
    eval "$(extract_function "$REPO_ROOT/scripts/lib/doctor_fix.sh" run_doctor_fix)"
    eval "$(extract_function "$REPO_ROOT/scripts/lib/doctor_fix.sh" finalize_doctor_fix)"
    SCRIPT_DIR="$REPO_ROOT/scripts/lib"
    run_doctor_fix --only stack >/dev/null 2>&1 && exit 1
    finalize_doctor_fix >/dev/null 2>&1 && exit 1
    [[ ! -e "$POISON_MARKER" ]]
); then lifecycle_failures+=("doctor-fix"); fi
if ! (
    define_downstream_poison
    define_policy_poison
    eval "$(extract_function "$REPO_ROOT/scripts/lib/stack.sh" _stack_rebind_canonical_contract)"
    eval "$(extract_function "$REPO_ROOT/scripts/lib/stack.sh" install_all_stack)"
    STACK_SCRIPT_DIR="$REPO_ROOT/scripts/lib"
    log_error() { :; }
    log_step() { poison_callback log_step; }
    log_success() { poison_callback log_success; }
    install_all_stack >/dev/null 2>&1
    exit $?
); then :; else lifecycle_failures+=("stack"); fi
service_output="$(
    (
        define_downstream_poison
        define_policy_poison
        ACFS_BLUE=test
        source "$REPO_ROOT/scripts/lib/acfs-services.sh"
    ) 2>&1
)"
service_rc=$?
if [[ $service_rc -eq 0 || "$service_output" != *"no future independently accepted exact C5 capsule identity exists"* ]]; then
    lifecycle_failures+=("service")
fi
if [[ ${#lifecycle_failures[@]} -eq 0 && ! -e "$POISON_MARKER" ]]; then
    pass "update/doctor/fix/stack/service boundaries reject before child or external callbacks"
else
    fail "update/doctor/fix/stack/service boundaries reject before child or external callbacks" \
        "failures=${lifecycle_failures[*]}"
fi

fixture_after="$(fixture_snapshot)"
if [[ ! -e "$POISON_MARKER" && "$fixture_before" == "$fixture_after" ]]; then
    pass "poison fixture tree remains byte-for-byte unchanged"
else
    fail "poison fixture tree remains byte-for-byte unchanged" \
        "fixture=$FIXTURE_ROOT poison=$([[ -e "$POISON_MARKER" ]] && printf yes || printf no)"
fi

printf '\nLIC2 poison entrypoints: %d passed, %d failed\n' "$passed" "$failed"
printf 'Fixture retained for independent inspection: %s\n' "$FIXTURE_ROOT"
[[ $failed -eq 0 ]]
