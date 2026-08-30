#!/bin/bash -p
# shellcheck disable=SC1090,SC1091
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    builtin printf '%s\n' 'ERROR: install_stack.sh is a source-only library; run install.sh --only <module-id>' >&2
    exit 2
fi
# ============================================================
# AUTO-GENERATED FROM acfs.manifest.yaml - DO NOT EDIT
# Regenerate: bun run generate (from packages/manifest)
# ============================================================

set -euo pipefail

# Generated scripts can execute root-context manifest commands. Establish the
# same OS-owned command-search invariant as install.sh before even resolving
# this script's directory.
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

# Resolve the script itself before deriving any trusted sibling path. Bash
# preserves the lexical symlink invocation in BASH_SOURCE, so dirname alone
# would let an attacker-selected sibling lib directory become the trust root.
if [[ ! -x /usr/bin/readlink ]]     || ! ACFS_GENERATED_SCRIPT_PATH="$(/usr/bin/readlink -f -- "${BASH_SOURCE[0]}" 2>/dev/null)"     || [[ -z "$ACFS_GENERATED_SCRIPT_PATH" ]]     || [[ ! -f "$ACFS_GENERATED_SCRIPT_PATH" ]]; then
    printf '[ERROR] Unable to canonicalize generated installer path
' >&2
    return 1 2>/dev/null || exit 1
fi
ACFS_GENERATED_SCRIPT_DIR="${ACFS_GENERATED_SCRIPT_PATH%/*}"
[[ -n "$ACFS_GENERATED_SCRIPT_DIR" ]] || ACFS_GENERATED_SCRIPT_DIR="/"

# Ensure logging functions available
if [[ -f "$ACFS_GENERATED_SCRIPT_DIR/../lib/logging.sh" ]]; then
    source "$ACFS_GENERATED_SCRIPT_DIR/../lib/logging.sh"
else
    # Fallback logging functions if logging.sh not found
    # Progress/status output should go to stderr so stdout stays clean for piping.
    log_step() { echo "[*] $*" >&2; }
    log_section() { echo "" >&2; echo "=== $* ===" >&2; }
    log_success() { echo "[OK] $*" >&2; }
    log_error() { echo "[ERROR] $*" >&2; }
    log_warn() { echo "[WARN] $*" >&2; }
    log_info() { echo "    $*" >&2; }
fi

# Source install helpers (run_as_*_shell, selection helpers)
if [[ -f "$ACFS_GENERATED_SCRIPT_DIR/../lib/install_helpers.sh" ]]; then
    # This marker is process-minted control state, never caller configuration.
    # Discard any inherited value before deciding whether this script owns the
    # helper security boundary or is being sourced by install.sh.
    unset ACFS_FORCE_INSTALL_HELPERS_SECURITY_REDEFINE
    if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
        ACFS_FORCE_INSTALL_HELPERS_SECURITY_REDEFINE=1
    fi
    source "$ACFS_GENERATED_SCRIPT_DIR/../lib/install_helpers.sh"
    unset ACFS_FORCE_INSTALL_HELPERS_SECURITY_REDEFINE
fi

acfs_generated_system_binary_path() {
    local name="${1:-}"
    local candidate=""

    [[ -n "$name" ]] || return 1
    case "$name" in
        .|..)
            return 1
            ;;
        *[!A-Za-z0-9._+-]*)
            return 1
            ;;
    esac

    for candidate in \
        "/usr/bin/$name" \
        "/bin/$name" \
        "/usr/sbin/$name" \
        "/sbin/$name"
    do
        [[ -x "$candidate" ]] || continue
        printf '%s\n' "$candidate"
        return 0
    done

    return 1
}

acfs_generated_resolve_current_user() {
    local current_user=""
    local id_bin=""
    local whoami_bin=""

    id_bin="$(acfs_generated_system_binary_path id 2>/dev/null || true)"
    if [[ -n "$id_bin" ]]; then
        current_user="$("$id_bin" -un 2>/dev/null || true)"
    fi

    if [[ -z "$current_user" ]]; then
        whoami_bin="$(acfs_generated_system_binary_path whoami 2>/dev/null || true)"
        if [[ -n "$whoami_bin" ]]; then
            current_user="$("$whoami_bin" 2>/dev/null || true)"
        fi
    fi

    [[ -n "$current_user" ]] || return 1
    printf '%s\n' "$current_user"
}

acfs_generated_getent_passwd_entry() {
    local user="${1-}"
    local getent_bin=""
    local passwd_entry=""
    local passwd_line=""
    local printed_any=false

    getent_bin="$(acfs_generated_system_binary_path getent 2>/dev/null || true)"
    if [[ -z "$user" ]]; then
        if [[ -n "$getent_bin" ]]; then
            while IFS= read -r passwd_line; do
                printf '%s\n' "$passwd_line"
                printed_any=true
            done < <("$getent_bin" passwd 2>/dev/null || true)
            if [[ "$printed_any" == true ]]; then
                return 0
            fi
        fi

        [[ -r /etc/passwd ]] || return 1
        while IFS= read -r passwd_line; do
            printf '%s\n' "$passwd_line"
        done < /etc/passwd
        return 0
    fi

    if [[ -n "$getent_bin" ]]; then
        passwd_entry="$("$getent_bin" passwd "$user" 2>/dev/null || true)"
    fi

    if [[ -z "$passwd_entry" ]] && [[ -r /etc/passwd ]]; then
        while IFS= read -r passwd_line; do
            [[ "${passwd_line%%:*}" == "$user" ]] || continue
            passwd_entry="$passwd_line"
            break
        done < /etc/passwd
    fi

    [[ -n "$passwd_entry" ]] || return 1
    printf '%s\n' "$passwd_entry"
}

acfs_generated_passwd_home_from_entry() {
    local passwd_entry="${1:-}"
    local passwd_home=""

    [[ -n "$passwd_entry" ]] || return 1
    IFS=: read -r _ _ _ _ _ passwd_home _ <<< "$passwd_entry"
    if [[ -n "$passwd_home" ]] && [[ "$passwd_home" == /* ]] && [[ "$passwd_home" != "/" ]]; then
        printf '%s\n' "${passwd_home%/}"
        return 0
    fi

    return 1
}

acfs_generated_target_user_exists() {
    local user="${1:-}"
    local id_bin=""

    [[ -n "$user" ]] || return 1
    id_bin="$(acfs_generated_system_binary_path id 2>/dev/null || true)"
    [[ -n "$id_bin" ]] || return 1
    "$id_bin" "$user" >/dev/null 2>&1
}

acfs_generated_default_home_for_new_user() {
    local user="${1:-}"

    [[ -n "$user" ]] || return 1
    [[ "$user" =~ ^[a-z_][a-z0-9._-]*$ ]] || return 1

    if [[ "$user" == "root" ]]; then
        printf '/root\n'
        return 0
    fi

    printf '/home/%s\n' "$user"
}

# When running a generated installer directly (not sourced by install.sh),
# set sane defaults and derive ACFS paths from the script location so
# contract validation passes and local assets are discoverable.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    # Match install.sh defaults
    if [[ -z "${TARGET_USER:-}" ]]; then
        if [[ $EUID -eq 0 ]] && [[ -z "${SUDO_USER:-}" ]]; then
            _ACFS_DETECTED_USER="ubuntu"
        else
            _ACFS_DETECTED_USER="${SUDO_USER:-}"
            if [[ -z "$_ACFS_DETECTED_USER" ]]; then
                _ACFS_DETECTED_USER="$(acfs_generated_resolve_current_user 2>/dev/null || true)"
            fi
            if [[ -z "$_ACFS_DETECTED_USER" ]]; then
                log_error "Unable to resolve the current user for TARGET_USER"
                exit 1
            fi
        fi
        TARGET_USER="$_ACFS_DETECTED_USER"
    fi
    unset _ACFS_DETECTED_USER

    if declare -f _acfs_validate_target_user >/dev/null 2>&1; then
        _acfs_validate_target_user "${TARGET_USER}" "TARGET_USER" || exit 1
    elif [[ -z "${TARGET_USER:-}" ]] || [[ ! "${TARGET_USER}" =~ ^[a-z_][a-z0-9._-]*$ ]]; then
        log_error "Invalid TARGET_USER '${TARGET_USER:-<empty>}' (expected: lowercase user name like 'ubuntu')"
        exit 1
    fi

    MODE="${MODE:-vibe}"

    _ACFS_EXPLICIT_TARGET_HOME="${TARGET_HOME:-}"
    if [[ -n "$_ACFS_EXPLICIT_TARGET_HOME" ]]; then
        _ACFS_EXPLICIT_TARGET_HOME="${_ACFS_EXPLICIT_TARGET_HOME%/}"
    fi
    _ACFS_RESOLVED_TARGET_HOME=""
    if declare -f _acfs_resolve_target_home >/dev/null 2>&1; then
        _ACFS_RESOLVED_TARGET_HOME="$(_acfs_resolve_target_home "${TARGET_USER}" "$_ACFS_EXPLICIT_TARGET_HOME" || true)"
    else
        if [[ "${TARGET_USER}" == "root" ]]; then
            _ACFS_RESOLVED_TARGET_HOME="/root"
        else
            _acfs_passwd_entry="$(acfs_generated_getent_passwd_entry "${TARGET_USER}" 2>/dev/null || true)"
            if [[ -n "$_acfs_passwd_entry" ]]; then
                _ACFS_RESOLVED_TARGET_HOME="$(acfs_generated_passwd_home_from_entry "$_acfs_passwd_entry" 2>/dev/null || true)"
            else
                _acfs_current_user="$(acfs_generated_resolve_current_user 2>/dev/null || true)"
                _acfs_current_home="${HOME:-}"
                if [[ -n "$_acfs_current_home" ]]; then
                    _acfs_current_home="${_acfs_current_home%/}"
                fi
                if [[ "${_acfs_current_user:-}" == "${TARGET_USER}" ]] && [[ -n "$_acfs_current_home" ]] && [[ "$_acfs_current_home" == /* ]] && [[ "$_acfs_current_home" != "/" ]] && { [[ -z "$_ACFS_EXPLICIT_TARGET_HOME" ]] || [[ "$_acfs_current_home" == "$_ACFS_EXPLICIT_TARGET_HOME" ]]; }; then
                    _ACFS_RESOLVED_TARGET_HOME="$_acfs_current_home"
                fi
                unset _acfs_current_user _acfs_current_home
            fi
            unset _acfs_passwd_entry
        fi
    fi
    if [[ -z "$_ACFS_RESOLVED_TARGET_HOME" ]] && [[ $EUID -eq 0 ]] && ! acfs_generated_target_user_exists "${TARGET_USER}"; then
        if [[ -n "$_ACFS_EXPLICIT_TARGET_HOME" ]] && [[ "$_ACFS_EXPLICIT_TARGET_HOME" == /* ]] && [[ "$_ACFS_EXPLICIT_TARGET_HOME" != "/" ]]; then
            _ACFS_RESOLVED_TARGET_HOME="$_ACFS_EXPLICIT_TARGET_HOME"
        else
            _ACFS_RESOLVED_TARGET_HOME="$(acfs_generated_default_home_for_new_user "${TARGET_USER}" 2>/dev/null || true)"
        fi
    fi
    if [[ -n "$_ACFS_RESOLVED_TARGET_HOME" ]]; then
        TARGET_HOME="${_ACFS_RESOLVED_TARGET_HOME%/}"
    fi
    unset _ACFS_EXPLICIT_TARGET_HOME _ACFS_RESOLVED_TARGET_HOME

    if [[ -z "${TARGET_HOME:-}" ]] || [[ "${TARGET_HOME}" == "/" ]] || [[ "${TARGET_HOME}" != /* ]]; then
        log_error "Invalid TARGET_HOME for '${TARGET_USER}': ${TARGET_HOME:-<empty>} (must be an absolute path and cannot be '/')"
        exit 1
    fi

    # Internal path/checksum authority is process-minted in direct mode. Never
    # accept caller-provided ACFS_* path overrides or CHECKSUMS_FILE here.
    unset ACFS_BOOTSTRAP_DIR ACFS_LIB_DIR ACFS_GENERATED_DIR ACFS_ASSETS_DIR
    unset ACFS_CHECKSUMS_YAML ACFS_MANIFEST_YAML CHECKSUMS_FILE
    unset ACFS_MANIFEST_INDEX_LOADED ACFS_GENERATED_SELECTION_READY
    if ! ACFS_BOOTSTRAP_DIR="$(/usr/bin/readlink -f -- "$ACFS_GENERATED_SCRIPT_DIR/../.." 2>/dev/null)"         || [[ -z "$ACFS_BOOTSTRAP_DIR" ]]         || [[ "$ACFS_BOOTSTRAP_DIR" == "/" ]]         || [[ ! -d "$ACFS_BOOTSTRAP_DIR" ]]; then
        log_error "Unable to derive generated installer repository root"
        exit 1
    fi

    ACFS_BIN_DIR="${ACFS_BIN_DIR:-$TARGET_HOME/.local/bin}"
    if [[ -z "${ACFS_BIN_DIR:-}" ]] || [[ "${ACFS_BIN_DIR}" == "/" ]] || [[ "${ACFS_BIN_DIR}" != /* ]]; then
        log_error "ACFS_BIN_DIR must be an absolute path and cannot be '/' (got: ${ACFS_BIN_DIR:-<empty>})"
        exit 1
    fi
    ACFS_LIB_DIR="$ACFS_BOOTSTRAP_DIR/scripts/lib"
    ACFS_GENERATED_DIR="$ACFS_BOOTSTRAP_DIR/scripts/generated"
    ACFS_ASSETS_DIR="$ACFS_BOOTSTRAP_DIR/acfs"
    ACFS_CHECKSUMS_YAML="$ACFS_BOOTSTRAP_DIR/checksums.yaml"
    ACFS_MANIFEST_YAML="$ACFS_BOOTSTRAP_DIR/acfs.manifest.yaml"

    export TARGET_USER TARGET_HOME MODE ACFS_BIN_DIR
    export ACFS_BOOTSTRAP_DIR ACFS_LIB_DIR ACFS_GENERATED_DIR ACFS_ASSETS_DIR ACFS_CHECKSUMS_YAML ACFS_MANIFEST_YAML

fi

acfs_generated_ensure_selection() {
    if [[ "${ACFS_MANIFEST_INDEX_LOADED:-false}" != "true" ]]; then
        local manifest_index="${ACFS_GENERATED_DIR:-$ACFS_GENERATED_SCRIPT_DIR}/manifest_index.sh"
        if [[ ! -f "$manifest_index" ]]; then
            log_error "Manifest index not found: $manifest_index"
            return 1
        fi
        source "$manifest_index"
        ACFS_MANIFEST_INDEX_LOADED=true
        export ACFS_MANIFEST_INDEX_LOADED
    fi

    if [[ "${ACFS_GENERATED_SELECTION_READY:-false}" != "true" ]]; then
        if ! declare -f acfs_resolve_selection >/dev/null 2>&1; then
            log_error "Install selection helper not loaded"
            return 1
        fi
        acfs_resolve_selection || return 1
        ACFS_GENERATED_SELECTION_READY=true
        export ACFS_GENERATED_SELECTION_READY
    fi

    return 0
}

acfs_generated_should_run_module() {
    local module_id="${1:-}"
    [[ -n "$module_id" ]] || return 1
    acfs_generated_ensure_selection || return 1
    should_run_module "$module_id"
}

# Source contract validation
if [[ -f "$ACFS_GENERATED_SCRIPT_DIR/../lib/contract.sh" ]]; then
    source "$ACFS_GENERATED_SCRIPT_DIR/../lib/contract.sh"
fi

# Optional security verification for upstream installer scripts.
# Scripts that need it should call: acfs_security_init
ACFS_SECURITY_READY=false
acfs_security_init() {
    if [[ "${ACFS_SECURITY_READY}" = "true" ]]; then
        return 0
    fi

    local security_lib="$ACFS_GENERATED_SCRIPT_DIR/../lib/security.sh"
    if [[ ! -f "$security_lib" ]]; then
        log_error "Security library not found: $security_lib"
        return 1
    fi

    # Use ACFS_CHECKSUMS_YAML if set by install.sh bootstrap (overrides security.sh default)
    if [[ -n "${ACFS_CHECKSUMS_YAML:-}" ]]; then
        export CHECKSUMS_FILE="${ACFS_CHECKSUMS_YAML}"
    fi

    # shellcheck source=../lib/security.sh
    # shellcheck disable=SC1091  # runtime relative source
    source "$security_lib"
    load_checksums || { log_error "Failed to load checksums.yaml"; return 1; }
    ACFS_SECURITY_READY=true
    return 0
}

# Category: stack
# Generated modules: 29

# Named tmux manager (agent cockpit)
acfs_generated_install_stack_ntm() {
    local module_id="stack.ntm"
    local canonical_contract="${ACFS_GENERATED_SCRIPT_DIR}/../lib/contract.sh"
    # Rebind the exact sibling contract at every generated entry. Imported
    # shell functions and environment state are never commissioning authority.
    if [[ ! -f "$canonical_contract" || -L "$canonical_contract" ]]; then
        log_error "stack.ntm: canonical runtime contract unavailable"
        return 1
    fi
    if ! builtin unset -f acfs_require_contract acfs_license_exclusion_profile_payload _acfs_license_profile_actual_sha256 acfs_license_policy_verify_profile acfs_license_policy_module_is_held acfs_license_policy_module_is_plain_mit_only acfs_license_policy_admit_entry acfs_license_clearance_requested acfs_license_clearance_verify acfs_license_clearance_active acfs_r1_runtime_profile_payload _acfs_r1_sha256_file _acfs_r1_profile_actual_sha256 _acfs_r1_runtime_root _acfs_r1_verify_bound_file acfs_r1_runtime_verify_profile acfs_r1_runtime_module_is_held acfs_r1_runtime_module_is_planned acfs_r1_runtime_admit_entry _acfs_r1_array_csv acfs_r1_runtime_prepare_selection acfs_r1_runtime_validate_plan acfs_core_policy_enforce acfs_core_policy_reason acfs_core_policy_contract _acfs_core_policy_target_home acfs_core_policy_expected_binary_path acfs_core_policy_expected_bv_versioned_path acfs_core_policy_expected_binary_sha256 _acfs_core_policy_sha256_file _acfs_core_policy_version_output acfs_core_policy_admit_binary acfs_core_policy_admit_repair_source acfs_core_policy_enforce_installer_execution 2>/dev/null; then
        log_error "stack.ntm: imported runtime policy function is not replaceable"
        return 1
    fi
    # shellcheck disable=SC1090  # exact generated sibling
    if ! builtin source "$canonical_contract"; then
        log_error "stack.ntm: canonical runtime contract could not be loaded"
        return 1
    fi
    if [[ "${ACFS_R1_RUNTIME_PROFILE_ID:-}" != "R1-held-module-exclusion-runtime-v1" ]] || ! builtin declare -F acfs_r1_runtime_admit_entry >/dev/null 2>&1; then
        log_error "stack.ntm: exact R1 runtime profile unavailable"
        return 1
    fi
    if ! acfs_r1_runtime_admit_entry direct "${module_id}"; then
        log_error "stack.ntm: ${ACFS_R1_POLICY_REASON:-R1 runtime admission rejected the module}"
        return 1
    fi
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping stack.ntm (not selected)"
        return 0
    fi
    log_step "Installing stack.ntm"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.ntm"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false
            local verified_installer_file=""
            local verified_installer_chmod_bin=""

                # Cleared per attempt so a stale reason from an earlier module can
                # never be misattributed to this one.
                ACFS_LAST_MODULE_FAILURE_REASON=""
            if acfs_security_init; then
                local known_installers_decl=""
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                known_installers_decl="$(declare -p KNOWN_INSTALLERS 2>/dev/null || true)"
                if [[ "$known_installers_decl" == declare\ -A* ]]; then
                    local tool="ntm"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.ntm: get_checksum failed for tool '$tool'"
                        ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if ! verified_installer_file="$(acfs_security_mktemp "/tmp/acfs-verified-installer.XXXXXX" 2>/dev/null)" || [[ -z "$verified_installer_file" ]]; then
                            log_error "stack.ntm: failed to create verified installer staging file"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                            verified_installer_file=""
                        elif ! verify_checksum "$url" "$expected_sha256" "$tool" > "$verified_installer_file"; then
                            log_error "stack.ntm: installer verification failed"
                            : "${ACFS_LAST_MODULE_FAILURE_REASON:=checksum}"
                        elif ! verified_installer_chmod_bin="$(acfs_generated_system_binary_path chmod 2>/dev/null)"; then
                            log_error "stack.ntm: trusted chmod not found for verified installer staging"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        elif ! "$verified_installer_chmod_bin" 0444 "$verified_installer_file"; then
                            log_error "stack.ntm: failed to make verified installer staging file read-only"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                        elif run_as_target_runner 'bash' "$verified_installer_file" '--no-shell'; then
                            install_success=true
                        else
                            log_error "stack.ntm: verified installer execution failed"
                            ACFS_LAST_MODULE_FAILURE_REASON="installer execution"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.ntm: KNOWN_INSTALLERS[$tool] not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.ntm: checksum for '$tool' not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                    fi
                else
                    log_error "stack.ntm: KNOWN_INSTALLERS array not available"
                    ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                fi
            else
                log_error "stack.ntm: acfs_security_init failed - check security.sh and checksums.yaml"
                ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
            fi
            if [[ -n "$verified_installer_file" ]]; then
                _acfs_remove_temp_files "$verified_installer_file"
                verified_installer_file=""
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.ntm"
                false
            fi
        }; then
            log_error "stack.ntm: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: ntm --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_NTM'
ntm --help
INSTALL_STACK_NTM
        then
            log_error "stack.ntm: verify failed: ntm --help"
            return 1
        fi
    fi

    log_success "stack.ntm installed"
}

# Like gmail for coding agents; MCP HTTP server + token; installs beads tools
acfs_generated_install_stack_mcp_agent_mail() {
    local module_id="stack.mcp_agent_mail"
    local canonical_contract="${ACFS_GENERATED_SCRIPT_DIR}/../lib/contract.sh"
    # Rebind the exact sibling contract at every generated entry. Imported
    # shell functions and environment state are never commissioning authority.
    if [[ ! -f "$canonical_contract" || -L "$canonical_contract" ]]; then
        log_error "stack.mcp_agent_mail: canonical runtime contract unavailable"
        return 1
    fi
    if ! builtin unset -f acfs_require_contract acfs_license_exclusion_profile_payload _acfs_license_profile_actual_sha256 acfs_license_policy_verify_profile acfs_license_policy_module_is_held acfs_license_policy_module_is_plain_mit_only acfs_license_policy_admit_entry acfs_license_clearance_requested acfs_license_clearance_verify acfs_license_clearance_active acfs_r1_runtime_profile_payload _acfs_r1_sha256_file _acfs_r1_profile_actual_sha256 _acfs_r1_runtime_root _acfs_r1_verify_bound_file acfs_r1_runtime_verify_profile acfs_r1_runtime_module_is_held acfs_r1_runtime_module_is_planned acfs_r1_runtime_admit_entry _acfs_r1_array_csv acfs_r1_runtime_prepare_selection acfs_r1_runtime_validate_plan acfs_core_policy_enforce acfs_core_policy_reason acfs_core_policy_contract _acfs_core_policy_target_home acfs_core_policy_expected_binary_path acfs_core_policy_expected_bv_versioned_path acfs_core_policy_expected_binary_sha256 _acfs_core_policy_sha256_file _acfs_core_policy_version_output acfs_core_policy_admit_binary acfs_core_policy_admit_repair_source acfs_core_policy_enforce_installer_execution 2>/dev/null; then
        log_error "stack.mcp_agent_mail: imported runtime policy function is not replaceable"
        return 1
    fi
    # shellcheck disable=SC1090  # exact generated sibling
    if ! builtin source "$canonical_contract"; then
        log_error "stack.mcp_agent_mail: canonical runtime contract could not be loaded"
        return 1
    fi
    if [[ "${ACFS_R1_RUNTIME_PROFILE_ID:-}" != "R1-held-module-exclusion-runtime-v1" ]] || ! builtin declare -F acfs_r1_runtime_admit_entry >/dev/null 2>&1; then
        log_error "stack.mcp_agent_mail: exact R1 runtime profile unavailable"
        return 1
    fi
    if ! acfs_r1_runtime_admit_entry direct "${module_id}"; then
        log_error "stack.mcp_agent_mail: ${ACFS_R1_POLICY_REASON:-R1 runtime admission rejected the module}"
        return 1
    fi
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping stack.mcp_agent_mail (not selected)"
        return 0
    fi
    log_step "Installing stack.mcp_agent_mail"

    # Core commissioning modules share one fail-closed admission policy.
    # Rebind after every mutable helper call so an ambient function cannot
    # shadow the final core decision. Agent Mail reaches this before security.
    builtin unset -f acfs_require_contract acfs_license_exclusion_profile_payload _acfs_license_profile_actual_sha256 acfs_license_policy_verify_profile acfs_license_policy_module_is_held acfs_license_policy_module_is_plain_mit_only acfs_license_policy_admit_entry acfs_license_clearance_requested acfs_license_clearance_verify acfs_license_clearance_active acfs_r1_runtime_profile_payload _acfs_r1_sha256_file _acfs_r1_profile_actual_sha256 _acfs_r1_runtime_root _acfs_r1_verify_bound_file acfs_r1_runtime_verify_profile acfs_r1_runtime_module_is_held acfs_r1_runtime_module_is_planned acfs_r1_runtime_admit_entry _acfs_r1_array_csv acfs_r1_runtime_prepare_selection acfs_r1_runtime_validate_plan acfs_core_policy_enforce acfs_core_policy_reason acfs_core_policy_contract _acfs_core_policy_target_home acfs_core_policy_expected_binary_path acfs_core_policy_expected_bv_versioned_path acfs_core_policy_expected_binary_sha256 _acfs_core_policy_sha256_file _acfs_core_policy_version_output acfs_core_policy_admit_binary acfs_core_policy_admit_repair_source acfs_core_policy_enforce_installer_execution 2>/dev/null || {
        log_error "stack.mcp_agent_mail: imported core policy function is not replaceable"
        return 1
    }
    # shellcheck disable=SC1090  # exact generated sibling
    if ! builtin source "$canonical_contract"; then
        log_error "stack.mcp_agent_mail: canonical runtime contract could not be rebound"
        return 1
    fi
    if ! builtin declare -F acfs_core_policy_enforce >/dev/null 2>&1; then
        log_error "stack.mcp_agent_mail: core admission policy unavailable"
        return 1
    fi
    if ! acfs_core_policy_enforce "stack.mcp_agent_mail" install ''; then
        log_error "stack.mcp_agent_mail: ${ACFS_CORE_POLICY_REASON:-core admission policy rejected the module}"
        return 1
    fi

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: pre-install check: false (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_MCP_AGENT_MAIL_PRE_INSTALL_CHECK'
false
INSTALL_STACK_MCP_AGENT_MAIL_PRE_INSTALL_CHECK
        then
            log_error "stack.mcp_agent_mail: C4 commissioning HOLD: published Agent Mail binaries are forbidden; exact-source build inputs and substrate package identities are not frozen"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.mcp_agent_mail"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false
            local verified_installer_file=""
            local verified_installer_chmod_bin=""

                # Cleared per attempt so a stale reason from an earlier module can
                # never be misattributed to this one.
                ACFS_LAST_MODULE_FAILURE_REASON=""
            if acfs_security_init; then
                local known_installers_decl=""
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                known_installers_decl="$(declare -p KNOWN_INSTALLERS 2>/dev/null || true)"
                if [[ "$known_installers_decl" == declare\ -A* ]]; then
                    local tool="mcp_agent_mail"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.mcp_agent_mail: get_checksum failed for tool '$tool'"
                        ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if ! verified_installer_file="$(acfs_security_mktemp "/tmp/acfs-verified-installer.XXXXXX" 2>/dev/null)" || [[ -z "$verified_installer_file" ]]; then
                            log_error "stack.mcp_agent_mail: failed to create verified installer staging file"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                            verified_installer_file=""
                        elif ! verify_checksum "$url" "$expected_sha256" "$tool" > "$verified_installer_file"; then
                            log_error "stack.mcp_agent_mail: installer verification failed"
                            : "${ACFS_LAST_MODULE_FAILURE_REASON:=checksum}"
                        elif ! verified_installer_chmod_bin="$(acfs_generated_system_binary_path chmod 2>/dev/null)"; then
                            log_error "stack.mcp_agent_mail: trusted chmod not found for verified installer staging"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        elif ! "$verified_installer_chmod_bin" 0444 "$verified_installer_file"; then
                            log_error "stack.mcp_agent_mail: failed to make verified installer staging file read-only"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                        elif run_as_target_runner 'env' 'AM_INSTALL_SKIP_MCP_SETUP=1' 'AM_INSTALL_SKIP_REMOTE_HTTP_READINESS=1' 'bash' "$verified_installer_file" '--version' 'v0.3.30' '--dest' "$TARGET_HOME"'/mcp_agent_mail' '--artifact-url' 'https://github.com/Dicklesworthstone/mcp_agent_mail_rust/releases/download/v0.3.30/mcp-agent-mail-aarch64-unknown-linux-gnu.tar.xz' '--checksum' '1ee708cfe0be9ef9bbb272e2358da79d0ae818ffdfce0b9446df5eb2337f5963' '--no-service' '--yes'; then
                            install_success=true
                        else
                            log_error "stack.mcp_agent_mail: verified installer execution failed"
                            ACFS_LAST_MODULE_FAILURE_REASON="installer execution"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.mcp_agent_mail: KNOWN_INSTALLERS[$tool] not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.mcp_agent_mail: checksum for '$tool' not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                    fi
                else
                    log_error "stack.mcp_agent_mail: KNOWN_INSTALLERS array not available"
                    ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                fi
            else
                log_error "stack.mcp_agent_mail: acfs_security_init failed - check security.sh and checksums.yaml"
                ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
            fi
            if [[ -n "$verified_installer_file" ]]; then
                _acfs_remove_temp_files "$verified_installer_file"
                verified_installer_file=""
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.mcp_agent_mail"
                false
            fi
        }; then
            log_error "stack.mcp_agent_mail: verified installer failed"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: if ! command -v am >/dev/null 2>&1; then (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_MCP_AGENT_MAIL'
if ! command -v am >/dev/null 2>&1; then
  echo "Agent Mail CLI missing after install" >&2
  exit 1
fi
storage_root="$HOME/.mcp_agent_mail_git_mailbox_repo"
unit_dir="$HOME/.config/systemd/user"
unit_file="$unit_dir/agent-mail.service"
am_bin="$(command -v am)"
db_url="sqlite:///${storage_root}/storage.sqlite3"

# Detect MCP base path: Rust am uses /mcp/, Python mcp_agent_mail uses /api/
if "$am_bin" --version 2>/dev/null | grep -q '^am '; then
    am_mcp_path="/mcp/"
else
    am_mcp_path="/api/"
fi

systemd_unit_reject_line_breaks() {
    local value="${1:-}"
    [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]]
}

systemd_unit_path_escape() {
    local value="${1:-}"
    local tab=$'\t'

    systemd_unit_reject_line_breaks "$value" || return 1
    value="${value//\\/\\\\}"
    value="${value//%/%%}"
    value="${value// /\\s}"
    value="${value//$tab/\\t}"
    printf '%s\n' "$value"
}

systemd_unit_quote() {
    local value="${1:-}"
    local escape_dollar="${2:-false}"

    systemd_unit_reject_line_breaks "$value" || return 1
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//%/%%}"
    if [[ "$escape_dollar" == "true" ]]; then
        value="${value//\$/\$\$}"
    fi
    printf '"%s"\n' "$value"
}

systemd_unit_exec_arg() {
    systemd_unit_quote "${1:-}" true
}

systemd_unit_exec_command() {
    systemd_unit_quote "${1:-}" false
}

systemd_unit_env_assignment() {
    local name="${1:-}"
    local value="${2:-}"

    [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 1
    systemd_unit_quote "${name}=${value}" false
}

mkdir -p "$storage_root" "$unit_dir"
storage_root_unit="$(systemd_unit_path_escape "$storage_root")" || exit 1
rust_log_env="$(systemd_unit_env_assignment RUST_LOG info)" || exit 1
storage_root_env="$(systemd_unit_env_assignment STORAGE_ROOT "$storage_root")" || exit 1
database_url_env="$(systemd_unit_env_assignment DATABASE_URL "$db_url")" || exit 1
http_allow_env="$(systemd_unit_env_assignment HTTP_ALLOW_LOCALHOST_UNAUTHENTICATED true)" || exit 1
am_bin_exec="$(systemd_unit_exec_command "$am_bin")" || exit 1
am_mcp_path_exec="$(systemd_unit_exec_arg "$am_mcp_path")" || exit 1
cat > "$unit_file" <<UNIT_EOF
[Unit]
Description=MCP Agent Mail Server
After=network.target

[Service]
Type=simple
WorkingDirectory=$storage_root_unit
Environment=$rust_log_env
Environment=$storage_root_env
Environment=$database_url_env
Environment=$http_allow_env
ExecStart=${am_bin_exec} serve-http --no-tui --host 127.0.0.1 --port 8765 --path ${am_mcp_path_exec}
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=default.target
UNIT_EOF

runtime_dir="/run/user/$(id -u)"
if [[ -d "$runtime_dir" ]]; then
  export XDG_RUNTIME_DIR="$runtime_dir"
  if [[ -S "$runtime_dir/bus" ]]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime_dir/bus"
  fi
fi

# Pre-check: determine if systemctl --user is usable.  On fresh VPS
# installs run from root, /run/user/<uid> may exist (created by
# install.sh Phase 1) but the D-Bus session bus may not be up yet.
_systemctl_user_ok=false
if command -v systemctl >/dev/null 2>&1; then
  if ! systemctl --user show-environment >/dev/null 2>&1; then
    # Try setting DBUS_SESSION_BUS_ADDRESS to trigger socket activation
    if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
      export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
    fi
    systemctl --user show-environment >/dev/null 2>&1 && _systemctl_user_ok=true
  else
    _systemctl_user_ok=true
  fi
fi

fallback_pid_file="$storage_root/agent-mail.pid"
fallback_log_file="$storage_root/agent-mail.log"

agent_mail_service_curl() {
  local curl_bin=""
  local candidate=""

  for candidate in /usr/bin/curl /bin/curl /usr/local/bin/curl /usr/local/sbin/curl /usr/sbin/curl /sbin/curl; do
    [[ -x "$candidate" ]] || continue
    curl_bin="$candidate"
    break
  done

  [[ -n "$curl_bin" ]] || return 127
  "$curl_bin" "$@"
}

agent_mail_readiness_ready() {
  local readiness_body=""
  local readiness_url=""

  for readiness_url in \
    http://127.0.0.1:8765/health/readiness \
    http://127.0.0.1:8765/health
  do
    readiness_body="$(agent_mail_service_curl -fsS --max-time 5 "$readiness_url" 2>/dev/null)" || continue
    if printf '%s\n' "$readiness_body" | grep -Eq '"status"[[:space:]]*:[[:space:]]*"ready"([[:space:]]*[,}])'; then
      return 0
    fi
  done

  return 1
}

stop_agent_mail_fallback() {
  local existing_pid=""
  local managed_pid=""
  local victim_args=""
  local victim_exe=""
  local am_real=""
  local owner_matches=false
  if [[ -f "$fallback_pid_file" ]]; then
    existing_pid="$(cat "$fallback_pid_file" 2>/dev/null || true)"
    if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
      managed_pid="$(systemctl --user show agent-mail.service -p MainPID --value 2>/dev/null || true)"
    fi
    if [[ "$managed_pid" =~ ^[1-9][0-9]*$ ]] && [[ "$existing_pid" == "$managed_pid" ]]; then
      echo "Agent Mail: PID $existing_pid belongs to agent-mail.service; leaving it to the supervisor" >&2
      rm -f "$fallback_pid_file"
      return 0
    fi
    if [[ "$existing_pid" =~ ^[1-9][0-9]*$ ]] && kill -0 "$existing_pid" 2>/dev/null; then
      victim_args="$(ps -p "$existing_pid" -o args= 2>/dev/null || true)"
      victim_exe="$(readlink -f "/proc/$existing_pid/exe" 2>/dev/null || true)"
      am_real="$(readlink -f "$am_bin" 2>/dev/null || printf '%s' "$am_bin")"
      if [[ ! "$victim_args" =~ (^|[[:space:]])serve-http([[:space:]]|$) ]] ||
         [[ ! "$victim_args" =~ (^|[[:space:]])--port(=|[[:space:]]+)8765([[:space:]]|$) ]]; then
        owner_matches=false
      elif [[ -n "$victim_exe" ]]; then
        [[ "$victim_exe" == "$am_real" ]] && owner_matches=true
      elif [[ "$victim_args" =~ (^|/)am([[:space:]]|$) ]]; then
        owner_matches=true
      fi
    fi
    if [[ "$owner_matches" == "true" ]]; then
      kill "$existing_pid" >/dev/null 2>&1 || true
      for _ in {1..10}; do
        if ! kill -0 "$existing_pid" 2>/dev/null; then
          break
        fi
        sleep 1
      done
      if kill -0 "$existing_pid" 2>/dev/null; then
        echo "Agent Mail: fallback PID $existing_pid did not stop after SIGTERM; refusing a hard kill" >&2
        return 1
      fi
    fi
    rm -f "$fallback_pid_file"
  fi
}

launch_agent_mail_fallback() {
  if agent_mail_service_curl -fsS --max-time 5 http://127.0.0.1:8765/health/liveness >/dev/null 2>&1 && \
     agent_mail_readiness_ready; then
    return 0
  fi

  if [[ -f "$fallback_pid_file" ]]; then
    stop_agent_mail_fallback || return 1
  fi

  nohup env \
    RUST_LOG=info \
    STORAGE_ROOT="$storage_root" \
    DATABASE_URL="$db_url" \
    HTTP_ALLOW_LOCALHOST_UNAUTHENTICATED=true \
    "$am_bin" serve-http --no-tui --host 127.0.0.1 --port 8765 --path "$am_mcp_path" \
    >>"$fallback_log_file" 2>&1 < /dev/null &
  echo $! > "$fallback_pid_file"
}

agent_mail_port_holder() {
  # Whatever is listening on 127.0.0.1:8765 right now (empty when nothing
  # is, or when no socket-inspection tool is available).
  if command -v ss >/dev/null 2>&1; then
    ss -H -ltnp 'sport = :8765' 2>/dev/null | head -n 3
  elif command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:8765 -sTCP:LISTEN 2>/dev/null | tail -n +2 | head -n 3
  fi
}

warn_if_agent_mail_port_taken() {
  local holder=""
  if agent_mail_service_curl -fsS --max-time 5 http://127.0.0.1:8765/health/liveness >/dev/null 2>&1; then
    return 0
  fi
  holder="$(agent_mail_port_holder)"
  [[ -n "$holder" ]] || return 0
  echo "Agent Mail: 127.0.0.1:8765 is already held by another process that is not Agent Mail:" >&2
  printf '  %s\n' "$holder" >&2
  echo "  Agent Mail cannot bind until that port is free. 'cm serve' (CASS Memory) defaults to the same port;" >&2
  echo "  run it as 'cm serve --port 8766' (or MCP_HTTP_PORT=8766) and re-run this step." >&2
}
warn_if_agent_mail_port_taken

if [[ "$_systemctl_user_ok" = "true" ]]; then
  stop_agent_mail_fallback || exit 1
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  systemctl --user enable agent-mail.service >/dev/null 2>&1 || exit 1
  systemctl --user restart agent-mail.service >/dev/null 2>&1 || exit 1
  active_waited=0
  active_max_wait=30
  until systemctl --user is-active --quiet agent-mail.service >/dev/null 2>&1; do
    if [[ "$active_waited" -ge "$active_max_wait" ]]; then
      break
    fi
    sleep 1
    active_waited=$((active_waited + 1))
  done
  systemctl --user is-active --quiet agent-mail.service >/dev/null 2>&1
else
  echo "Agent Mail: systemctl --user unavailable, using background fallback" >&2
  launch_agent_mail_fallback
fi
INSTALL_STACK_MCP_AGENT_MAIL
        then
            log_error "stack.mcp_agent_mail: install command failed: if ! command -v am >/dev/null 2>&1; then"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: until agent_mail_service_curl -fsS --max-time 10 http://127.0.0.1:8765/health/liveness >/dev/null 2>&1 && \\ (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_MCP_AGENT_MAIL'
# Wait for the managed Agent Mail service to become healthy.
agent_mail_service_curl() {
  local curl_bin=""
  local candidate=""

  for candidate in /usr/bin/curl /bin/curl /usr/local/bin/curl /usr/local/sbin/curl /usr/sbin/curl /sbin/curl; do
    [[ -x "$candidate" ]] || continue
    curl_bin="$candidate"
    break
  done

  [[ -n "$curl_bin" ]] || return 127
  "$curl_bin" "$@"
}

agent_mail_readiness_ready() {
  local readiness_body=""
  local readiness_url=""

  for readiness_url in \
    http://127.0.0.1:8765/health/readiness \
    http://127.0.0.1:8765/health
  do
    readiness_body="$(agent_mail_service_curl -fsS --max-time 10 "$readiness_url" 2>/dev/null)" || continue
    if printf '%s\n' "$readiness_body" | grep -Eq '"status"[[:space:]]*:[[:space:]]*"ready"([[:space:]]*[,}])'; then
      return 0
    fi
  done

  return 1
}

agent_mail_port_holder() {
  if command -v ss >/dev/null 2>&1; then
    ss -H -ltnp 'sport = :8765' 2>/dev/null | head -n 3
  elif command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:8765 -sTCP:LISTEN 2>/dev/null | tail -n +2 | head -n 3
  fi
}

waited=0
max_wait=240
until agent_mail_service_curl -fsS --max-time 10 http://127.0.0.1:8765/health/liveness >/dev/null 2>&1 && \
      agent_mail_readiness_ready; do
  if [[ "$waited" -ge "$max_wait" ]]; then
    echo "Agent Mail service did not become ready on 127.0.0.1:8765 after ${max_wait}s" >&2
    holder="$(agent_mail_port_holder)"
    if [[ -n "$holder" ]]; then
      echo "Something else is listening on 127.0.0.1:8765, so Agent Mail cannot bind:" >&2
      printf '  %s\n' "$holder" >&2
      echo "If this is 'cm serve' (CASS Memory), restart it with 'cm serve --port 8766' (or MCP_HTTP_PORT=8766)." >&2
    fi
    exit 1
  fi
  sleep 2
  waited=$((waited + 2))
done
INSTALL_STACK_MCP_AGENT_MAIL
        then
            log_error "stack.mcp_agent_mail: install command failed: until agent_mail_service_curl -fsS --max-time 10 http://127.0.0.1:8765/health/liveness >/dev/null 2>&1 && \\"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: command -v am (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_MCP_AGENT_MAIL'
command -v am
INSTALL_STACK_MCP_AGENT_MAIL
        then
            log_error "stack.mcp_agent_mail: verify failed: command -v am"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: if [[ -d \"\$runtime_dir\" ]]; then (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_MCP_AGENT_MAIL'
agent_mail_service_curl() {
  local curl_bin=""
  local candidate=""

  for candidate in /usr/bin/curl /bin/curl /usr/local/bin/curl /usr/local/sbin/curl /usr/sbin/curl /sbin/curl; do
    [[ -x "$candidate" ]] || continue
    curl_bin="$candidate"
    break
  done

  [[ -n "$curl_bin" ]] || return 127
  "$curl_bin" "$@"
}

agent_mail_readiness_ready() {
  local readiness_body=""
  local readiness_url=""

  for readiness_url in \
    http://127.0.0.1:8765/health/readiness \
    http://127.0.0.1:8765/health
  do
    readiness_body="$(agent_mail_service_curl -fsS --max-time 10 "$readiness_url" 2>/dev/null)" || continue
    if printf '%s\n' "$readiness_body" | grep -Eq '"status"[[:space:]]*:[[:space:]]*"ready"([[:space:]]*[,}])'; then
      return 0
    fi
  done

  return 1
}

runtime_dir="/run/user/$(id -u)"
if [[ -d "$runtime_dir" ]]; then
  export XDG_RUNTIME_DIR="$runtime_dir"
  export DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime_dir/bus"
fi
if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
  systemctl --user is-active --quiet agent-mail.service >/dev/null 2>&1 || exit 1
fi
agent_mail_service_curl -fsS --max-time 10 http://127.0.0.1:8765/health/liveness >/dev/null
agent_mail_readiness_ready
INSTALL_STACK_MCP_AGENT_MAIL
        then
            log_error "stack.mcp_agent_mail: verify failed: if [[ -d \"\$runtime_dir\" ]]; then"
            return 1
        fi
    fi

    log_success "stack.mcp_agent_mail installed"
}

# Local-first knowledge management with hybrid semantic search (ms)
acfs_generated_install_stack_meta_skill() {
    local module_id="stack.meta_skill"
    local canonical_contract="${ACFS_GENERATED_SCRIPT_DIR}/../lib/contract.sh"
    # Rebind the exact sibling contract at every generated entry. Imported
    # shell functions and environment state are never commissioning authority.
    if [[ ! -f "$canonical_contract" || -L "$canonical_contract" ]]; then
        log_error "stack.meta_skill: canonical runtime contract unavailable"
        return 1
    fi
    if ! builtin unset -f acfs_require_contract acfs_license_exclusion_profile_payload _acfs_license_profile_actual_sha256 acfs_license_policy_verify_profile acfs_license_policy_module_is_held acfs_license_policy_module_is_plain_mit_only acfs_license_policy_admit_entry acfs_license_clearance_requested acfs_license_clearance_verify acfs_license_clearance_active acfs_r1_runtime_profile_payload _acfs_r1_sha256_file _acfs_r1_profile_actual_sha256 _acfs_r1_runtime_root _acfs_r1_verify_bound_file acfs_r1_runtime_verify_profile acfs_r1_runtime_module_is_held acfs_r1_runtime_module_is_planned acfs_r1_runtime_admit_entry _acfs_r1_array_csv acfs_r1_runtime_prepare_selection acfs_r1_runtime_validate_plan acfs_core_policy_enforce acfs_core_policy_reason acfs_core_policy_contract _acfs_core_policy_target_home acfs_core_policy_expected_binary_path acfs_core_policy_expected_bv_versioned_path acfs_core_policy_expected_binary_sha256 _acfs_core_policy_sha256_file _acfs_core_policy_version_output acfs_core_policy_admit_binary acfs_core_policy_admit_repair_source acfs_core_policy_enforce_installer_execution 2>/dev/null; then
        log_error "stack.meta_skill: imported runtime policy function is not replaceable"
        return 1
    fi
    # shellcheck disable=SC1090  # exact generated sibling
    if ! builtin source "$canonical_contract"; then
        log_error "stack.meta_skill: canonical runtime contract could not be loaded"
        return 1
    fi
    if [[ "${ACFS_R1_RUNTIME_PROFILE_ID:-}" != "R1-held-module-exclusion-runtime-v1" ]] || ! builtin declare -F acfs_r1_runtime_admit_entry >/dev/null 2>&1; then
        log_error "stack.meta_skill: exact R1 runtime profile unavailable"
        return 1
    fi
    if ! acfs_r1_runtime_admit_entry direct "${module_id}"; then
        log_error "stack.meta_skill: ${ACFS_R1_POLICY_REASON:-R1 runtime admission rejected the module}"
        return 1
    fi
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping stack.meta_skill (not selected)"
        return 0
    fi
    log_step "Installing stack.meta_skill"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.meta_skill"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false
            local verified_installer_file=""
            local verified_installer_chmod_bin=""

            # Build the exact operator-approved source revision on every Linux host
            # with its committed dependency lock.
            if [[ "$(uname -s 2>/dev/null)" == "Linux" ]]; then
                local ms_source_repo="https://github.com/Dicklesworthstone/meta_skill.git"
                local ms_source_commit="2a4bc62a04c98d8812bfe68b77c862d87e1731e3"
                local ms_source_tree="956bd9e6426d120341d50a30722b41ddd7f688c7"
                local ms_cargo_lock_sha256="d7684ea8c8392092df67e2aee4fb9e74fae0359389572760235217838a5c3181"
                local ms_cargo_toml_sha256="9f0dc83afc2f236d4c4af16dbd16fc1639a9f0d00e07db23f949482c5eeeda4f"
                local ms_source_parent="$TARGET_HOME/.cache/acfs/source-builds"
                local ms_source_dir=""
                local ms_binary=""
                local ms_version=""
                local ms_git_bin=""
                local ms_mkdir_bin=""
                local ms_mktemp_bin=""
                local ms_rm_bin=""
                local ms_sha256sum_bin=""
                local ms_cargo_bin="$TARGET_HOME/.cargo/bin/cargo"

                ms_git_bin="$(acfs_generated_system_binary_path git 2>/dev/null || true)"
                ms_mkdir_bin="$(acfs_generated_system_binary_path mkdir 2>/dev/null || true)"
                ms_mktemp_bin="$(acfs_generated_system_binary_path mktemp 2>/dev/null || true)"
                ms_rm_bin="$(acfs_generated_system_binary_path rm 2>/dev/null || true)"
                ms_sha256sum_bin="$(acfs_generated_system_binary_path sha256sum 2>/dev/null || true)"

                if [[ -z "$ms_git_bin" || -z "$ms_mkdir_bin" || -z "$ms_mktemp_bin" || -z "$ms_rm_bin" || -z "$ms_sha256sum_bin" || ! -x "$ms_cargo_bin" ]]; then
                    log_error "stack.meta_skill: exact source build prerequisites are unavailable"
                    ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                elif [[ "$TARGET_HOME" != /* || "$TARGET_HOME" == "/" || -L "$TARGET_HOME" || -L "$TARGET_HOME/.cache" || -L "$TARGET_HOME/.cache/acfs" || -L "$ms_source_parent" ]]; then
                    log_error "stack.meta_skill: refusing source build through an invalid or symlinked target-home path"
                    ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                elif ! run_as_target "$ms_mkdir_bin" -p "$ms_source_parent"; then
                    log_error "stack.meta_skill: failed to prepare the confined source-build directory"
                    ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                elif [[ ! -d "$ms_source_parent" || -L "$ms_source_parent" ]]; then
                    log_error "stack.meta_skill: source-build directory is not a confined real directory"
                    ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                elif ! ms_source_dir="$(run_as_target "$ms_mktemp_bin" -d "$ms_source_parent/meta-skill.XXXXXX" 2>/dev/null)"; then
                    log_error "stack.meta_skill: failed to create the source-build staging directory"
                    ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                elif [[ "$ms_source_dir" != "$ms_source_parent"/meta-skill.* || ! -d "$ms_source_dir" || -L "$ms_source_dir" ]]; then
                    log_error "stack.meta_skill: source-build staging directory escaped its trusted template"
                    ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                elif (
                    set -euo pipefail
                    trap 'run_as_target "$ms_rm_bin" -rf -- "$ms_source_dir" >/dev/null 2>&1 || true' EXIT
                    run_as_target "$ms_git_bin" -c core.hooksPath=/dev/null clone --filter=blob:none --no-checkout "$ms_source_repo" "$ms_source_dir/src"
                    run_as_target "$ms_git_bin" -C "$ms_source_dir/src" -c core.hooksPath=/dev/null fetch --depth 1 origin "$ms_source_commit"
                    run_as_target "$ms_git_bin" -C "$ms_source_dir/src" -c core.hooksPath=/dev/null checkout --detach "$ms_source_commit"
                    [[ "$(run_as_target "$ms_git_bin" -C "$ms_source_dir/src" rev-parse HEAD)" == "$ms_source_commit" ]]
                    [[ "$(run_as_target "$ms_git_bin" -C "$ms_source_dir/src" rev-parse "HEAD^{tree}")" == "$ms_source_tree" ]]
                    [[ "$(run_as_target "$ms_sha256sum_bin" "$ms_source_dir/src/Cargo.lock" | awk 'NR == 1 { print $1 }')" == "$ms_cargo_lock_sha256" ]]
                    [[ "$(run_as_target "$ms_sha256sum_bin" "$ms_source_dir/src/Cargo.toml" | awk 'NR == 1 { print $1 }')" == "$ms_cargo_toml_sha256" ]]
                    [[ -z "$(run_as_target "$ms_git_bin" -C "$ms_source_dir/src" status --porcelain=v1 --untracked-files=all)" ]]
                    run_as_target env CARGO_NET_GIT_FETCH_WITH_CLI=true "$ms_cargo_bin" build --release --locked --bin ms --manifest-path "$ms_source_dir/src/Cargo.toml" --target-dir "$ms_source_dir/target"
                    ms_binary="$ms_source_dir/target/release/ms"
                    [[ -f "$ms_binary" && -x "$ms_binary" && ! -L "$ms_binary" ]]
                    ms_version="$(run_as_target "$ms_binary" --version 2>/dev/null)"
                    [[ "$ms_version" == "ms 0.2.2" ]]
                    acfs_install_executable_into_primary_bin "$ms_binary" ms
                ); then
                    install_success=true
                else
                    if [[ -n "$ms_source_dir" && "$ms_source_dir" == "$ms_source_parent"/meta-skill.* && -d "$ms_source_dir" && ! -L "$ms_source_dir" ]]; then
                        run_as_target "$ms_rm_bin" -rf -- "$ms_source_dir" >/dev/null 2>&1 || true
                    fi
                    log_error "stack.meta_skill: exact source build failed"
                    ACFS_LAST_MODULE_FAILURE_REASON="source build"
                fi
            else
                log_error "stack.meta_skill: exact source commissioning is supported only on Linux"
                ACFS_LAST_MODULE_FAILURE_REASON="unsupported platform"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.meta_skill"
                false
            fi
        }; then
            log_error "stack.meta_skill: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: test \"\$(ms --version 2>/dev/null)\" = \"ms 0.2.2\" (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_META_SKILL'
test "$(ms --version 2>/dev/null)" = "ms 0.2.2"
INSTALL_STACK_META_SKILL
        then
            log_error "stack.meta_skill: verify failed: test \"\$(ms --version 2>/dev/null)\" = \"ms 0.2.2\""
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify (optional): ms doctor (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_META_SKILL'
ms doctor
INSTALL_STACK_META_SKILL
        then
            log_warn "Optional verify failed: stack.meta_skill"
        fi
    fi

    log_success "stack.meta_skill installed"
}

# Automated iterative spec refinement with extended AI reasoning (apr)
acfs_generated_install_stack_automated_plan_reviser() {
    local module_id="stack.automated_plan_reviser"
    local canonical_contract="${ACFS_GENERATED_SCRIPT_DIR}/../lib/contract.sh"
    # Rebind the exact sibling contract at every generated entry. Imported
    # shell functions and environment state are never commissioning authority.
    if [[ ! -f "$canonical_contract" || -L "$canonical_contract" ]]; then
        log_error "stack.automated_plan_reviser: canonical runtime contract unavailable"
        return 1
    fi
    if ! builtin unset -f acfs_require_contract acfs_license_exclusion_profile_payload _acfs_license_profile_actual_sha256 acfs_license_policy_verify_profile acfs_license_policy_module_is_held acfs_license_policy_module_is_plain_mit_only acfs_license_policy_admit_entry acfs_license_clearance_requested acfs_license_clearance_verify acfs_license_clearance_active acfs_r1_runtime_profile_payload _acfs_r1_sha256_file _acfs_r1_profile_actual_sha256 _acfs_r1_runtime_root _acfs_r1_verify_bound_file acfs_r1_runtime_verify_profile acfs_r1_runtime_module_is_held acfs_r1_runtime_module_is_planned acfs_r1_runtime_admit_entry _acfs_r1_array_csv acfs_r1_runtime_prepare_selection acfs_r1_runtime_validate_plan acfs_core_policy_enforce acfs_core_policy_reason acfs_core_policy_contract _acfs_core_policy_target_home acfs_core_policy_expected_binary_path acfs_core_policy_expected_bv_versioned_path acfs_core_policy_expected_binary_sha256 _acfs_core_policy_sha256_file _acfs_core_policy_version_output acfs_core_policy_admit_binary acfs_core_policy_admit_repair_source acfs_core_policy_enforce_installer_execution 2>/dev/null; then
        log_error "stack.automated_plan_reviser: imported runtime policy function is not replaceable"
        return 1
    fi
    # shellcheck disable=SC1090  # exact generated sibling
    if ! builtin source "$canonical_contract"; then
        log_error "stack.automated_plan_reviser: canonical runtime contract could not be loaded"
        return 1
    fi
    if [[ "${ACFS_R1_RUNTIME_PROFILE_ID:-}" != "R1-held-module-exclusion-runtime-v1" ]] || ! builtin declare -F acfs_r1_runtime_admit_entry >/dev/null 2>&1; then
        log_error "stack.automated_plan_reviser: exact R1 runtime profile unavailable"
        return 1
    fi
    if ! acfs_r1_runtime_admit_entry direct "${module_id}"; then
        log_error "stack.automated_plan_reviser: ${ACFS_R1_POLICY_REASON:-R1 runtime admission rejected the module}"
        return 1
    fi
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping stack.automated_plan_reviser (not selected)"
        return 0
    fi
    log_step "Installing stack.automated_plan_reviser"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.automated_plan_reviser"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false
            local verified_installer_file=""
            local verified_installer_chmod_bin=""

                # Cleared per attempt so a stale reason from an earlier module can
                # never be misattributed to this one.
                ACFS_LAST_MODULE_FAILURE_REASON=""
            if acfs_security_init; then
                local known_installers_decl=""
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                known_installers_decl="$(declare -p KNOWN_INSTALLERS 2>/dev/null || true)"
                if [[ "$known_installers_decl" == declare\ -A* ]]; then
                    local tool="apr"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.automated_plan_reviser: get_checksum failed for tool '$tool'"
                        ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if ! verified_installer_file="$(acfs_security_mktemp "/tmp/acfs-verified-installer.XXXXXX" 2>/dev/null)" || [[ -z "$verified_installer_file" ]]; then
                            log_error "stack.automated_plan_reviser: failed to create verified installer staging file"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                            verified_installer_file=""
                        elif ! verify_checksum "$url" "$expected_sha256" "$tool" > "$verified_installer_file"; then
                            log_error "stack.automated_plan_reviser: installer verification failed"
                            : "${ACFS_LAST_MODULE_FAILURE_REASON:=checksum}"
                        elif ! verified_installer_chmod_bin="$(acfs_generated_system_binary_path chmod 2>/dev/null)"; then
                            log_error "stack.automated_plan_reviser: trusted chmod not found for verified installer staging"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        elif ! "$verified_installer_chmod_bin" 0444 "$verified_installer_file"; then
                            log_error "stack.automated_plan_reviser: failed to make verified installer staging file read-only"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                        elif run_as_target_runner 'bash' "$verified_installer_file"; then
                            install_success=true
                        else
                            log_error "stack.automated_plan_reviser: verified installer execution failed"
                            ACFS_LAST_MODULE_FAILURE_REASON="installer execution"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.automated_plan_reviser: KNOWN_INSTALLERS[$tool] not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.automated_plan_reviser: checksum for '$tool' not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                    fi
                else
                    log_error "stack.automated_plan_reviser: KNOWN_INSTALLERS array not available"
                    ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                fi
            else
                log_error "stack.automated_plan_reviser: acfs_security_init failed - check security.sh and checksums.yaml"
                ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
            fi
            if [[ -n "$verified_installer_file" ]]; then
                _acfs_remove_temp_files "$verified_installer_file"
                verified_installer_file=""
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.automated_plan_reviser"
                false
            fi
        }; then
            log_warn "stack.automated_plan_reviser: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.automated_plan_reviser" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.automated_plan_reviser"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: apr --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_AUTOMATED_PLAN_REVISER'
apr --help
INSTALL_STACK_AUTOMATED_PLAN_REVISER
        then
            log_warn "stack.automated_plan_reviser: verify failed: apr --help"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.automated_plan_reviser" "verify failed: apr --help"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.automated_plan_reviser"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify (optional): apr --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_AUTOMATED_PLAN_REVISER'
apr --version
INSTALL_STACK_AUTOMATED_PLAN_REVISER
        then
            log_warn "Optional verify failed: stack.automated_plan_reviser"
        fi
    fi

    log_success "stack.automated_plan_reviser installed"
}

# Curated battle-tested prompts for AI agents - browse and install as skills (jfp)
acfs_generated_install_stack_jeffreysprompts() {
    local module_id="stack.jeffreysprompts"
    local canonical_contract="${ACFS_GENERATED_SCRIPT_DIR}/../lib/contract.sh"
    # Rebind the exact sibling contract at every generated entry. Imported
    # shell functions and environment state are never commissioning authority.
    if [[ ! -f "$canonical_contract" || -L "$canonical_contract" ]]; then
        log_error "stack.jeffreysprompts: canonical runtime contract unavailable"
        return 1
    fi
    if ! builtin unset -f acfs_require_contract acfs_license_exclusion_profile_payload _acfs_license_profile_actual_sha256 acfs_license_policy_verify_profile acfs_license_policy_module_is_held acfs_license_policy_module_is_plain_mit_only acfs_license_policy_admit_entry acfs_license_clearance_requested acfs_license_clearance_verify acfs_license_clearance_active acfs_r1_runtime_profile_payload _acfs_r1_sha256_file _acfs_r1_profile_actual_sha256 _acfs_r1_runtime_root _acfs_r1_verify_bound_file acfs_r1_runtime_verify_profile acfs_r1_runtime_module_is_held acfs_r1_runtime_module_is_planned acfs_r1_runtime_admit_entry _acfs_r1_array_csv acfs_r1_runtime_prepare_selection acfs_r1_runtime_validate_plan acfs_core_policy_enforce acfs_core_policy_reason acfs_core_policy_contract _acfs_core_policy_target_home acfs_core_policy_expected_binary_path acfs_core_policy_expected_bv_versioned_path acfs_core_policy_expected_binary_sha256 _acfs_core_policy_sha256_file _acfs_core_policy_version_output acfs_core_policy_admit_binary acfs_core_policy_admit_repair_source acfs_core_policy_enforce_installer_execution 2>/dev/null; then
        log_error "stack.jeffreysprompts: imported runtime policy function is not replaceable"
        return 1
    fi
    # shellcheck disable=SC1090  # exact generated sibling
    if ! builtin source "$canonical_contract"; then
        log_error "stack.jeffreysprompts: canonical runtime contract could not be loaded"
        return 1
    fi
    if [[ "${ACFS_R1_RUNTIME_PROFILE_ID:-}" != "R1-held-module-exclusion-runtime-v1" ]] || ! builtin declare -F acfs_r1_runtime_admit_entry >/dev/null 2>&1; then
        log_error "stack.jeffreysprompts: exact R1 runtime profile unavailable"
        return 1
    fi
    if ! acfs_r1_runtime_admit_entry direct "${module_id}"; then
        log_error "stack.jeffreysprompts: ${ACFS_R1_POLICY_REASON:-R1 runtime admission rejected the module}"
        return 1
    fi
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping stack.jeffreysprompts (not selected)"
        return 0
    fi
    log_step "Installing stack.jeffreysprompts"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.jeffreysprompts"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false
            local verified_installer_file=""
            local verified_installer_chmod_bin=""

            # JeffreysPrompts has no immutable executable installer at the approved
            # revision. Build its exact Rust workspace revision on every Linux host.
            if [[ "$(uname -s 2>/dev/null)" == "Linux" ]]; then
                local jfp_source_repo="https://github.com/Dicklesworthstone/jeffreysprompts.com.git"
                local jfp_source_commit="2cec2d5257ef0da32a856b51673f243b6c72a3e2"
                local jfp_source_tree="79fc4e85f86a6e1e809e212004a4cc848e1d19ee"
                local jfp_cargo_lock_sha256="d17941a5a85c4f4eda4f4cb070125ebf6b1af7e403846e6b35915c6d95f25c9d"
                local jfp_cargo_toml_sha256="c902d565b250385fe4619cad99a5d68f923355c6833735d730f5a5979254378f"
                local jfp_source_parent="$TARGET_HOME/.cache/acfs/source-builds"
                local jfp_source_dir=""
                local jfp_binary=""
                local jfp_version=""
                local jfp_git_bin=""
                local jfp_mkdir_bin=""
                local jfp_mktemp_bin=""
                local jfp_rm_bin=""
                local jfp_sha256sum_bin=""
                local jfp_cargo_bin="$TARGET_HOME/.cargo/bin/cargo"

                jfp_git_bin="$(acfs_generated_system_binary_path git 2>/dev/null || true)"
                jfp_mkdir_bin="$(acfs_generated_system_binary_path mkdir 2>/dev/null || true)"
                jfp_mktemp_bin="$(acfs_generated_system_binary_path mktemp 2>/dev/null || true)"
                jfp_rm_bin="$(acfs_generated_system_binary_path rm 2>/dev/null || true)"
                jfp_sha256sum_bin="$(acfs_generated_system_binary_path sha256sum 2>/dev/null || true)"

                if [[ -z "$jfp_git_bin" || -z "$jfp_mkdir_bin" || -z "$jfp_mktemp_bin" || -z "$jfp_rm_bin" || -z "$jfp_sha256sum_bin" || ! -x "$jfp_cargo_bin" ]]; then
                    log_error "stack.jeffreysprompts: exact source build prerequisites are unavailable"
                    ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                elif [[ "$TARGET_HOME" != /* || "$TARGET_HOME" == "/" || -L "$TARGET_HOME" || -L "$TARGET_HOME/.cache" || -L "$TARGET_HOME/.cache/acfs" || -L "$jfp_source_parent" ]]; then
                    log_error "stack.jeffreysprompts: refusing source build through an invalid or symlinked target-home path"
                    ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                elif ! run_as_target "$jfp_mkdir_bin" -p "$jfp_source_parent"; then
                    log_error "stack.jeffreysprompts: failed to prepare the confined source-build directory"
                    ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                elif [[ ! -d "$jfp_source_parent" || -L "$jfp_source_parent" ]]; then
                    log_error "stack.jeffreysprompts: source-build directory is not a confined real directory"
                    ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                elif ! jfp_source_dir="$(run_as_target "$jfp_mktemp_bin" -d "$jfp_source_parent/jfp.XXXXXX" 2>/dev/null)"; then
                    log_error "stack.jeffreysprompts: failed to create the source-build staging directory"
                    ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                elif [[ "$jfp_source_dir" != "$jfp_source_parent"/jfp.* || ! -d "$jfp_source_dir" || -L "$jfp_source_dir" ]]; then
                    log_error "stack.jeffreysprompts: source-build staging directory escaped its trusted template"
                    ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                elif (
                    set -euo pipefail
                    trap 'run_as_target "$jfp_rm_bin" -rf -- "$jfp_source_dir" >/dev/null 2>&1 || true' EXIT
                    run_as_target "$jfp_git_bin" -c core.hooksPath=/dev/null clone --filter=blob:none --no-checkout "$jfp_source_repo" "$jfp_source_dir/src"
                    run_as_target "$jfp_git_bin" -C "$jfp_source_dir/src" -c core.hooksPath=/dev/null fetch --depth 1 origin "$jfp_source_commit"
                    run_as_target "$jfp_git_bin" -C "$jfp_source_dir/src" -c core.hooksPath=/dev/null checkout --detach "$jfp_source_commit"
                    [[ "$(run_as_target "$jfp_git_bin" -C "$jfp_source_dir/src" rev-parse HEAD)" == "$jfp_source_commit" ]]
                    [[ "$(run_as_target "$jfp_git_bin" -C "$jfp_source_dir/src" rev-parse "HEAD^{tree}")" == "$jfp_source_tree" ]]
                    [[ "$(run_as_target "$jfp_sha256sum_bin" "$jfp_source_dir/src/Cargo.lock" | awk 'NR == 1 { print $1 }')" == "$jfp_cargo_lock_sha256" ]]
                    [[ "$(run_as_target "$jfp_sha256sum_bin" "$jfp_source_dir/src/Cargo.toml" | awk 'NR == 1 { print $1 }')" == "$jfp_cargo_toml_sha256" ]]
                    [[ -z "$(run_as_target "$jfp_git_bin" -C "$jfp_source_dir/src" status --porcelain=v1 --untracked-files=all)" ]]
                    run_as_target env CARGO_NET_GIT_FETCH_WITH_CLI=true "$jfp_cargo_bin" build --release --locked --bin jfp --manifest-path "$jfp_source_dir/src/Cargo.toml" --target-dir "$jfp_source_dir/target"
                    jfp_binary="$jfp_source_dir/target/release/jfp"
                    [[ -f "$jfp_binary" && -x "$jfp_binary" && ! -L "$jfp_binary" ]]
                    jfp_version="$(run_as_target "$jfp_binary" --version 2>/dev/null)"
                    [[ "$jfp_version" == "jfp 0.1.0" ]]
                    acfs_install_executable_into_primary_bin "$jfp_binary" jfp
                ); then
                    install_success=true
                else
                    if [[ -n "$jfp_source_dir" && "$jfp_source_dir" == "$jfp_source_parent"/jfp.* && -d "$jfp_source_dir" && ! -L "$jfp_source_dir" ]]; then
                        run_as_target "$jfp_rm_bin" -rf -- "$jfp_source_dir" >/dev/null 2>&1 || true
                    fi
                    log_error "stack.jeffreysprompts: exact source build failed"
                    ACFS_LAST_MODULE_FAILURE_REASON="source build"
                fi
            else
                log_error "stack.jeffreysprompts: exact source commissioning is supported only on Linux"
                ACFS_LAST_MODULE_FAILURE_REASON="unsupported platform"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.jeffreysprompts"
                false
            fi
        }; then
            log_warn "stack.jeffreysprompts: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.jeffreysprompts" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.jeffreysprompts"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: test \"\$(jfp --version 2>/dev/null)\" = \"jfp 0.1.0\" (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_JEFFREYSPROMPTS'
test "$(jfp --version 2>/dev/null)" = "jfp 0.1.0"
INSTALL_STACK_JEFFREYSPROMPTS
        then
            log_warn "stack.jeffreysprompts: verify failed: test \"\$(jfp --version 2>/dev/null)\" = \"jfp 0.1.0\""
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.jeffreysprompts" "verify failed: test \"\$(jfp --version 2>/dev/null)\" = \"jfp 0.1.0\""
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.jeffreysprompts"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify (optional): jfp doctor (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_JEFFREYSPROMPTS'
jfp doctor
INSTALL_STACK_JEFFREYSPROMPTS
        then
            log_warn "Optional verify failed: stack.jeffreysprompts"
        fi
    fi

    log_success "stack.jeffreysprompts installed"
}

# Find and terminate stuck/zombie processes with intelligent scoring (pt)
acfs_generated_install_stack_process_triage() {
    local module_id="stack.process_triage"
    local canonical_contract="${ACFS_GENERATED_SCRIPT_DIR}/../lib/contract.sh"
    # Rebind the exact sibling contract at every generated entry. Imported
    # shell functions and environment state are never commissioning authority.
    if [[ ! -f "$canonical_contract" || -L "$canonical_contract" ]]; then
        log_error "stack.process_triage: canonical runtime contract unavailable"
        return 1
    fi
    if ! builtin unset -f acfs_require_contract acfs_license_exclusion_profile_payload _acfs_license_profile_actual_sha256 acfs_license_policy_verify_profile acfs_license_policy_module_is_held acfs_license_policy_module_is_plain_mit_only acfs_license_policy_admit_entry acfs_license_clearance_requested acfs_license_clearance_verify acfs_license_clearance_active acfs_r1_runtime_profile_payload _acfs_r1_sha256_file _acfs_r1_profile_actual_sha256 _acfs_r1_runtime_root _acfs_r1_verify_bound_file acfs_r1_runtime_verify_profile acfs_r1_runtime_module_is_held acfs_r1_runtime_module_is_planned acfs_r1_runtime_admit_entry _acfs_r1_array_csv acfs_r1_runtime_prepare_selection acfs_r1_runtime_validate_plan acfs_core_policy_enforce acfs_core_policy_reason acfs_core_policy_contract _acfs_core_policy_target_home acfs_core_policy_expected_binary_path acfs_core_policy_expected_bv_versioned_path acfs_core_policy_expected_binary_sha256 _acfs_core_policy_sha256_file _acfs_core_policy_version_output acfs_core_policy_admit_binary acfs_core_policy_admit_repair_source acfs_core_policy_enforce_installer_execution 2>/dev/null; then
        log_error "stack.process_triage: imported runtime policy function is not replaceable"
        return 1
    fi
    # shellcheck disable=SC1090  # exact generated sibling
    if ! builtin source "$canonical_contract"; then
        log_error "stack.process_triage: canonical runtime contract could not be loaded"
        return 1
    fi
    if [[ "${ACFS_R1_RUNTIME_PROFILE_ID:-}" != "R1-held-module-exclusion-runtime-v1" ]] || ! builtin declare -F acfs_r1_runtime_admit_entry >/dev/null 2>&1; then
        log_error "stack.process_triage: exact R1 runtime profile unavailable"
        return 1
    fi
    if ! acfs_r1_runtime_admit_entry direct "${module_id}"; then
        log_error "stack.process_triage: ${ACFS_R1_POLICY_REASON:-R1 runtime admission rejected the module}"
        return 1
    fi
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping stack.process_triage (not selected)"
        return 0
    fi
    log_step "Installing stack.process_triage"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.process_triage"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false
            local verified_installer_file=""
            local verified_installer_chmod_bin=""

                # Cleared per attempt so a stale reason from an earlier module can
                # never be misattributed to this one.
                ACFS_LAST_MODULE_FAILURE_REASON=""
            if acfs_security_init; then
                local known_installers_decl=""
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                known_installers_decl="$(declare -p KNOWN_INSTALLERS 2>/dev/null || true)"
                if [[ "$known_installers_decl" == declare\ -A* ]]; then
                    local tool="pt"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.process_triage: get_checksum failed for tool '$tool'"
                        ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if ! verified_installer_file="$(acfs_security_mktemp "/tmp/acfs-verified-installer.XXXXXX" 2>/dev/null)" || [[ -z "$verified_installer_file" ]]; then
                            log_error "stack.process_triage: failed to create verified installer staging file"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                            verified_installer_file=""
                        elif ! verify_checksum "$url" "$expected_sha256" "$tool" > "$verified_installer_file"; then
                            log_error "stack.process_triage: installer verification failed"
                            : "${ACFS_LAST_MODULE_FAILURE_REASON:=checksum}"
                        elif ! verified_installer_chmod_bin="$(acfs_generated_system_binary_path chmod 2>/dev/null)"; then
                            log_error "stack.process_triage: trusted chmod not found for verified installer staging"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        elif ! "$verified_installer_chmod_bin" 0444 "$verified_installer_file"; then
                            log_error "stack.process_triage: failed to make verified installer staging file read-only"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                        elif run_as_target_runner 'bash' "$verified_installer_file"; then
                            install_success=true
                        else
                            log_error "stack.process_triage: verified installer execution failed"
                            ACFS_LAST_MODULE_FAILURE_REASON="installer execution"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.process_triage: KNOWN_INSTALLERS[$tool] not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.process_triage: checksum for '$tool' not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                    fi
                else
                    log_error "stack.process_triage: KNOWN_INSTALLERS array not available"
                    ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                fi
            else
                log_error "stack.process_triage: acfs_security_init failed - check security.sh and checksums.yaml"
                ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
            fi
            if [[ -n "$verified_installer_file" ]]; then
                _acfs_remove_temp_files "$verified_installer_file"
                verified_installer_file=""
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.process_triage"
                false
            fi
        }; then
            log_warn "stack.process_triage: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.process_triage" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.process_triage"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: pt --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_PROCESS_TRIAGE'
pt --help
INSTALL_STACK_PROCESS_TRIAGE
        then
            log_warn "stack.process_triage: verify failed: pt --help"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.process_triage" "verify failed: pt --help"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.process_triage"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify (optional): pt --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_PROCESS_TRIAGE'
pt --version
INSTALL_STACK_PROCESS_TRIAGE
        then
            log_warn "Optional verify failed: stack.process_triage"
        fi
    fi

    log_success "stack.process_triage installed"
}

# UBS bug scanning (easy-mode)
acfs_generated_install_stack_ultimate_bug_scanner() {
    local module_id="stack.ultimate_bug_scanner"
    local canonical_contract="${ACFS_GENERATED_SCRIPT_DIR}/../lib/contract.sh"
    # Rebind the exact sibling contract at every generated entry. Imported
    # shell functions and environment state are never commissioning authority.
    if [[ ! -f "$canonical_contract" || -L "$canonical_contract" ]]; then
        log_error "stack.ultimate_bug_scanner: canonical runtime contract unavailable"
        return 1
    fi
    if ! builtin unset -f acfs_require_contract acfs_license_exclusion_profile_payload _acfs_license_profile_actual_sha256 acfs_license_policy_verify_profile acfs_license_policy_module_is_held acfs_license_policy_module_is_plain_mit_only acfs_license_policy_admit_entry acfs_license_clearance_requested acfs_license_clearance_verify acfs_license_clearance_active acfs_r1_runtime_profile_payload _acfs_r1_sha256_file _acfs_r1_profile_actual_sha256 _acfs_r1_runtime_root _acfs_r1_verify_bound_file acfs_r1_runtime_verify_profile acfs_r1_runtime_module_is_held acfs_r1_runtime_module_is_planned acfs_r1_runtime_admit_entry _acfs_r1_array_csv acfs_r1_runtime_prepare_selection acfs_r1_runtime_validate_plan acfs_core_policy_enforce acfs_core_policy_reason acfs_core_policy_contract _acfs_core_policy_target_home acfs_core_policy_expected_binary_path acfs_core_policy_expected_bv_versioned_path acfs_core_policy_expected_binary_sha256 _acfs_core_policy_sha256_file _acfs_core_policy_version_output acfs_core_policy_admit_binary acfs_core_policy_admit_repair_source acfs_core_policy_enforce_installer_execution 2>/dev/null; then
        log_error "stack.ultimate_bug_scanner: imported runtime policy function is not replaceable"
        return 1
    fi
    # shellcheck disable=SC1090  # exact generated sibling
    if ! builtin source "$canonical_contract"; then
        log_error "stack.ultimate_bug_scanner: canonical runtime contract could not be loaded"
        return 1
    fi
    if [[ "${ACFS_R1_RUNTIME_PROFILE_ID:-}" != "R1-held-module-exclusion-runtime-v1" ]] || ! builtin declare -F acfs_r1_runtime_admit_entry >/dev/null 2>&1; then
        log_error "stack.ultimate_bug_scanner: exact R1 runtime profile unavailable"
        return 1
    fi
    if ! acfs_r1_runtime_admit_entry direct "${module_id}"; then
        log_error "stack.ultimate_bug_scanner: ${ACFS_R1_POLICY_REASON:-R1 runtime admission rejected the module}"
        return 1
    fi
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping stack.ultimate_bug_scanner (not selected)"
        return 0
    fi
    log_step "Installing stack.ultimate_bug_scanner"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.ultimate_bug_scanner"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false
            local verified_installer_file=""
            local verified_installer_chmod_bin=""

                # Cleared per attempt so a stale reason from an earlier module can
                # never be misattributed to this one.
                ACFS_LAST_MODULE_FAILURE_REASON=""
            if acfs_security_init; then
                local known_installers_decl=""
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                known_installers_decl="$(declare -p KNOWN_INSTALLERS 2>/dev/null || true)"
                if [[ "$known_installers_decl" == declare\ -A* ]]; then
                    local tool="ubs"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.ultimate_bug_scanner: get_checksum failed for tool '$tool'"
                        ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if ! verified_installer_file="$(acfs_security_mktemp "/tmp/acfs-verified-installer.XXXXXX" 2>/dev/null)" || [[ -z "$verified_installer_file" ]]; then
                            log_error "stack.ultimate_bug_scanner: failed to create verified installer staging file"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                            verified_installer_file=""
                        elif ! verify_checksum "$url" "$expected_sha256" "$tool" > "$verified_installer_file"; then
                            log_error "stack.ultimate_bug_scanner: installer verification failed"
                            : "${ACFS_LAST_MODULE_FAILURE_REASON:=checksum}"
                        elif ! verified_installer_chmod_bin="$(acfs_generated_system_binary_path chmod 2>/dev/null)"; then
                            log_error "stack.ultimate_bug_scanner: trusted chmod not found for verified installer staging"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        elif ! "$verified_installer_chmod_bin" 0444 "$verified_installer_file"; then
                            log_error "stack.ultimate_bug_scanner: failed to make verified installer staging file read-only"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                        elif run_as_target_runner 'bash' "$verified_installer_file" '--easy-mode'; then
                            install_success=true
                        else
                            log_error "stack.ultimate_bug_scanner: verified installer execution failed"
                            ACFS_LAST_MODULE_FAILURE_REASON="installer execution"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.ultimate_bug_scanner: KNOWN_INSTALLERS[$tool] not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.ultimate_bug_scanner: checksum for '$tool' not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                    fi
                else
                    log_error "stack.ultimate_bug_scanner: KNOWN_INSTALLERS array not available"
                    ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                fi
            else
                log_error "stack.ultimate_bug_scanner: acfs_security_init failed - check security.sh and checksums.yaml"
                ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
            fi
            if [[ -n "$verified_installer_file" ]]; then
                _acfs_remove_temp_files "$verified_installer_file"
                verified_installer_file=""
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.ultimate_bug_scanner"
                false
            fi
        }; then
            log_error "stack.ultimate_bug_scanner: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: ubs --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_ULTIMATE_BUG_SCANNER'
ubs --help
INSTALL_STACK_ULTIMATE_BUG_SCANNER
        then
            log_error "stack.ultimate_bug_scanner: verify failed: ubs --help"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify (optional): cd /tmp && ubs doctor (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_ULTIMATE_BUG_SCANNER'
cd /tmp && ubs doctor
INSTALL_STACK_ULTIMATE_BUG_SCANNER
        then
            log_warn "Optional verify failed: stack.ultimate_bug_scanner"
        fi
    fi

    log_success "stack.ultimate_bug_scanner installed"
}

# beads_rust (br) - Rust issue tracker with graph-aware dependencies
acfs_generated_install_stack_beads_rust() {
    local module_id="stack.beads_rust"
    local canonical_contract="${ACFS_GENERATED_SCRIPT_DIR}/../lib/contract.sh"
    # Rebind the exact sibling contract at every generated entry. Imported
    # shell functions and environment state are never commissioning authority.
    if [[ ! -f "$canonical_contract" || -L "$canonical_contract" ]]; then
        log_error "stack.beads_rust: canonical runtime contract unavailable"
        return 1
    fi
    if ! builtin unset -f acfs_require_contract acfs_license_exclusion_profile_payload _acfs_license_profile_actual_sha256 acfs_license_policy_verify_profile acfs_license_policy_module_is_held acfs_license_policy_module_is_plain_mit_only acfs_license_policy_admit_entry acfs_license_clearance_requested acfs_license_clearance_verify acfs_license_clearance_active acfs_r1_runtime_profile_payload _acfs_r1_sha256_file _acfs_r1_profile_actual_sha256 _acfs_r1_runtime_root _acfs_r1_verify_bound_file acfs_r1_runtime_verify_profile acfs_r1_runtime_module_is_held acfs_r1_runtime_module_is_planned acfs_r1_runtime_admit_entry _acfs_r1_array_csv acfs_r1_runtime_prepare_selection acfs_r1_runtime_validate_plan acfs_core_policy_enforce acfs_core_policy_reason acfs_core_policy_contract _acfs_core_policy_target_home acfs_core_policy_expected_binary_path acfs_core_policy_expected_bv_versioned_path acfs_core_policy_expected_binary_sha256 _acfs_core_policy_sha256_file _acfs_core_policy_version_output acfs_core_policy_admit_binary acfs_core_policy_admit_repair_source acfs_core_policy_enforce_installer_execution 2>/dev/null; then
        log_error "stack.beads_rust: imported runtime policy function is not replaceable"
        return 1
    fi
    # shellcheck disable=SC1090  # exact generated sibling
    if ! builtin source "$canonical_contract"; then
        log_error "stack.beads_rust: canonical runtime contract could not be loaded"
        return 1
    fi
    if [[ "${ACFS_R1_RUNTIME_PROFILE_ID:-}" != "R1-held-module-exclusion-runtime-v1" ]] || ! builtin declare -F acfs_r1_runtime_admit_entry >/dev/null 2>&1; then
        log_error "stack.beads_rust: exact R1 runtime profile unavailable"
        return 1
    fi
    if ! acfs_r1_runtime_admit_entry direct "${module_id}"; then
        log_error "stack.beads_rust: ${ACFS_R1_POLICY_REASON:-R1 runtime admission rejected the module}"
        return 1
    fi
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping stack.beads_rust (not selected)"
        return 0
    fi
    log_step "Installing stack.beads_rust"

    # Core commissioning modules share one fail-closed admission policy.
    if ! acfs_security_init; then
        log_error "stack.beads_rust: security policy unavailable"
        return 1
    fi
    # Rebind after every mutable helper call so an ambient function cannot
    # shadow the final core decision. Agent Mail reaches this before security.
    builtin unset -f acfs_require_contract acfs_license_exclusion_profile_payload _acfs_license_profile_actual_sha256 acfs_license_policy_verify_profile acfs_license_policy_module_is_held acfs_license_policy_module_is_plain_mit_only acfs_license_policy_admit_entry acfs_license_clearance_requested acfs_license_clearance_verify acfs_license_clearance_active acfs_r1_runtime_profile_payload _acfs_r1_sha256_file _acfs_r1_profile_actual_sha256 _acfs_r1_runtime_root _acfs_r1_verify_bound_file acfs_r1_runtime_verify_profile acfs_r1_runtime_module_is_held acfs_r1_runtime_module_is_planned acfs_r1_runtime_admit_entry _acfs_r1_array_csv acfs_r1_runtime_prepare_selection acfs_r1_runtime_validate_plan acfs_core_policy_enforce acfs_core_policy_reason acfs_core_policy_contract _acfs_core_policy_target_home acfs_core_policy_expected_binary_path acfs_core_policy_expected_bv_versioned_path acfs_core_policy_expected_binary_sha256 _acfs_core_policy_sha256_file _acfs_core_policy_version_output acfs_core_policy_admit_binary acfs_core_policy_admit_repair_source acfs_core_policy_enforce_installer_execution 2>/dev/null || {
        log_error "stack.beads_rust: imported core policy function is not replaceable"
        return 1
    }
    # shellcheck disable=SC1090  # exact generated sibling
    if ! builtin source "$canonical_contract"; then
        log_error "stack.beads_rust: canonical runtime contract could not be rebound"
        return 1
    fi
    if ! builtin declare -F acfs_core_policy_enforce >/dev/null 2>&1; then
        log_error "stack.beads_rust: core admission policy unavailable"
        return 1
    fi
    if ! acfs_core_policy_enforce "stack.beads_rust" install 'source_commit=7eaf34b76927b4deadc913889f50fb06a8f803d7;installer_url=https://raw.githubusercontent.com/Dicklesworthstone/beads_rust/7eaf34b76927b4deadc913889f50fb06a8f803d7/install.sh;installer_sha256=b2b3ed0ae2712e53a72d48afd5a980a7c1d346bb6e6b9fb9e4f3b20566726c2f;version=v0.5.3;artifact_url=https://github.com/Dicklesworthstone/beads_rust/releases/download/v0.5.3/br-0.5.3-linux_aarch64.tar.gz;artifact_sha256=9781aec596be155dfff31c0ab4d140d076107422e0e703c5137b2d2edcff4bfb;binary_sha256=f7d105e685da6c49dd87b0335d11d5fe2aa8765033a78cfbfb00dee7a4b1e123'; then
        log_error "stack.beads_rust: ${ACFS_CORE_POLICY_REASON:-core admission policy rejected the module}"
        return 1
    fi

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.beads_rust"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false
            local verified_installer_file=""
            local verified_installer_chmod_bin=""

                # Cleared per attempt so a stale reason from an earlier module can
                # never be misattributed to this one.
                ACFS_LAST_MODULE_FAILURE_REASON=""
            if acfs_security_init; then
                local known_installers_decl=""
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                known_installers_decl="$(declare -p KNOWN_INSTALLERS 2>/dev/null || true)"
                if [[ "$known_installers_decl" == declare\ -A* ]]; then
                    local tool="br"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.beads_rust: get_checksum failed for tool '$tool'"
                        ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if ! verified_installer_file="$(acfs_security_mktemp "/tmp/acfs-verified-installer.XXXXXX" 2>/dev/null)" || [[ -z "$verified_installer_file" ]]; then
                            log_error "stack.beads_rust: failed to create verified installer staging file"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                            verified_installer_file=""
                        elif ! verify_checksum "$url" "$expected_sha256" "$tool" > "$verified_installer_file"; then
                            log_error "stack.beads_rust: installer verification failed"
                            : "${ACFS_LAST_MODULE_FAILURE_REASON:=checksum}"
                        elif ! verified_installer_chmod_bin="$(acfs_generated_system_binary_path chmod 2>/dev/null)"; then
                            log_error "stack.beads_rust: trusted chmod not found for verified installer staging"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        elif ! "$verified_installer_chmod_bin" 0444 "$verified_installer_file"; then
                            log_error "stack.beads_rust: failed to make verified installer staging file read-only"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                        elif run_as_target_runner 'bash' "$verified_installer_file" '--version' 'v0.5.3' '--dest' "$TARGET_HOME"'/.local/bin' '--artifact-url' 'https://github.com/Dicklesworthstone/beads_rust/releases/download/v0.5.3/br-0.5.3-linux_aarch64.tar.gz' '--checksum' '9781aec596be155dfff31c0ab4d140d076107422e0e703c5137b2d2edcff4bfb'; then
                            install_success=true
                        else
                            log_error "stack.beads_rust: verified installer execution failed"
                            ACFS_LAST_MODULE_FAILURE_REASON="installer execution"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.beads_rust: KNOWN_INSTALLERS[$tool] not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.beads_rust: checksum for '$tool' not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                    fi
                else
                    log_error "stack.beads_rust: KNOWN_INSTALLERS array not available"
                    ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                fi
            else
                log_error "stack.beads_rust: acfs_security_init failed - check security.sh and checksums.yaml"
                ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
            fi
            if [[ -n "$verified_installer_file" ]]; then
                _acfs_remove_temp_files "$verified_installer_file"
                verified_installer_file=""
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.beads_rust"
                false
            fi
        }; then
            log_error "stack.beads_rust: verified installer failed"
            return 1
        fi
    fi

    # A version string is not an installed-state or post-install identity.
    if ! declare -f acfs_core_policy_admit_binary >/dev/null 2>&1 \
        || ! acfs_core_policy_admit_binary "stack.beads_rust" install 'source_commit=7eaf34b76927b4deadc913889f50fb06a8f803d7;installer_url=https://raw.githubusercontent.com/Dicklesworthstone/beads_rust/7eaf34b76927b4deadc913889f50fb06a8f803d7/install.sh;installer_sha256=b2b3ed0ae2712e53a72d48afd5a980a7c1d346bb6e6b9fb9e4f3b20566726c2f;version=v0.5.3;artifact_url=https://github.com/Dicklesworthstone/beads_rust/releases/download/v0.5.3/br-0.5.3-linux_aarch64.tar.gz;artifact_sha256=9781aec596be155dfff31c0ab4d140d076107422e0e703c5137b2d2edcff4bfb;binary_sha256=f7d105e685da6c49dd87b0335d11d5fe2aa8765033a78cfbfb00dee7a4b1e123' "$TARGET_HOME/.local/bin/br"; then
        log_error "stack.beads_rust: ${ACFS_CORE_POLICY_REASON:-exact binary identity rejected}"
        return 1
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: \"\$TARGET_HOME/.local/bin/br\" --version | grep -Eq '(^|[[:space:]])v?0[.]5[.]3([[:space:]]|\$)' (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_BEADS_RUST'
"$TARGET_HOME/.local/bin/br" --version | grep -Eq '(^|[[:space:]])v?0[.]5[.]3([[:space:]]|$)'
INSTALL_STACK_BEADS_RUST
        then
            log_error "stack.beads_rust: verify failed: \"\$TARGET_HOME/.local/bin/br\" --version | grep -Eq '(^|[[:space:]])v?0[.]5[.]3([[:space:]]|\$)'"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify (optional): \"\$TARGET_HOME/.local/bin/br\" list --json 2>/dev/null (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_BEADS_RUST'
"$TARGET_HOME/.local/bin/br" list --json 2>/dev/null
INSTALL_STACK_BEADS_RUST
        then
            log_warn "Optional verify failed: stack.beads_rust"
        fi
    fi

    log_success "stack.beads_rust installed"
}

# bv TUI for Beads tasks
acfs_generated_install_stack_beads_viewer() {
    local module_id="stack.beads_viewer"
    local canonical_contract="${ACFS_GENERATED_SCRIPT_DIR}/../lib/contract.sh"
    # Rebind the exact sibling contract at every generated entry. Imported
    # shell functions and environment state are never commissioning authority.
    if [[ ! -f "$canonical_contract" || -L "$canonical_contract" ]]; then
        log_error "stack.beads_viewer: canonical runtime contract unavailable"
        return 1
    fi
    if ! builtin unset -f acfs_require_contract acfs_license_exclusion_profile_payload _acfs_license_profile_actual_sha256 acfs_license_policy_verify_profile acfs_license_policy_module_is_held acfs_license_policy_module_is_plain_mit_only acfs_license_policy_admit_entry acfs_license_clearance_requested acfs_license_clearance_verify acfs_license_clearance_active acfs_r1_runtime_profile_payload _acfs_r1_sha256_file _acfs_r1_profile_actual_sha256 _acfs_r1_runtime_root _acfs_r1_verify_bound_file acfs_r1_runtime_verify_profile acfs_r1_runtime_module_is_held acfs_r1_runtime_module_is_planned acfs_r1_runtime_admit_entry _acfs_r1_array_csv acfs_r1_runtime_prepare_selection acfs_r1_runtime_validate_plan acfs_core_policy_enforce acfs_core_policy_reason acfs_core_policy_contract _acfs_core_policy_target_home acfs_core_policy_expected_binary_path acfs_core_policy_expected_bv_versioned_path acfs_core_policy_expected_binary_sha256 _acfs_core_policy_sha256_file _acfs_core_policy_version_output acfs_core_policy_admit_binary acfs_core_policy_admit_repair_source acfs_core_policy_enforce_installer_execution 2>/dev/null; then
        log_error "stack.beads_viewer: imported runtime policy function is not replaceable"
        return 1
    fi
    # shellcheck disable=SC1090  # exact generated sibling
    if ! builtin source "$canonical_contract"; then
        log_error "stack.beads_viewer: canonical runtime contract could not be loaded"
        return 1
    fi
    if [[ "${ACFS_R1_RUNTIME_PROFILE_ID:-}" != "R1-held-module-exclusion-runtime-v1" ]] || ! builtin declare -F acfs_r1_runtime_admit_entry >/dev/null 2>&1; then
        log_error "stack.beads_viewer: exact R1 runtime profile unavailable"
        return 1
    fi
    if ! acfs_r1_runtime_admit_entry direct "${module_id}"; then
        log_error "stack.beads_viewer: ${ACFS_R1_POLICY_REASON:-R1 runtime admission rejected the module}"
        return 1
    fi
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping stack.beads_viewer (not selected)"
        return 0
    fi
    log_step "Installing stack.beads_viewer"

    # Core commissioning modules share one fail-closed admission policy.
    if ! acfs_security_init; then
        log_error "stack.beads_viewer: security policy unavailable"
        return 1
    fi
    # Rebind after every mutable helper call so an ambient function cannot
    # shadow the final core decision. Agent Mail reaches this before security.
    builtin unset -f acfs_require_contract acfs_license_exclusion_profile_payload _acfs_license_profile_actual_sha256 acfs_license_policy_verify_profile acfs_license_policy_module_is_held acfs_license_policy_module_is_plain_mit_only acfs_license_policy_admit_entry acfs_license_clearance_requested acfs_license_clearance_verify acfs_license_clearance_active acfs_r1_runtime_profile_payload _acfs_r1_sha256_file _acfs_r1_profile_actual_sha256 _acfs_r1_runtime_root _acfs_r1_verify_bound_file acfs_r1_runtime_verify_profile acfs_r1_runtime_module_is_held acfs_r1_runtime_module_is_planned acfs_r1_runtime_admit_entry _acfs_r1_array_csv acfs_r1_runtime_prepare_selection acfs_r1_runtime_validate_plan acfs_core_policy_enforce acfs_core_policy_reason acfs_core_policy_contract _acfs_core_policy_target_home acfs_core_policy_expected_binary_path acfs_core_policy_expected_bv_versioned_path acfs_core_policy_expected_binary_sha256 _acfs_core_policy_sha256_file _acfs_core_policy_version_output acfs_core_policy_admit_binary acfs_core_policy_admit_repair_source acfs_core_policy_enforce_installer_execution 2>/dev/null || {
        log_error "stack.beads_viewer: imported core policy function is not replaceable"
        return 1
    }
    # shellcheck disable=SC1090  # exact generated sibling
    if ! builtin source "$canonical_contract"; then
        log_error "stack.beads_viewer: canonical runtime contract could not be rebound"
        return 1
    fi
    if ! builtin declare -F acfs_core_policy_enforce >/dev/null 2>&1; then
        log_error "stack.beads_viewer: core admission policy unavailable"
        return 1
    fi
    if ! acfs_core_policy_enforce "stack.beads_viewer" install 'source_commit=95a706caf57fc5fde846a453da5f28677d4a81b8;version=v0.22.0;artifact_url=https://github.com/Dicklesworthstone/beads_viewer/releases/download/v0.22.0/bv_linux_arm64.tar.gz;archive_sha256=23d451b87bb9dccfb94fab416b0243d107919d9d56458087475afda5a617aa89;binary_sha256=ee1dd03701a33d86e6496fb7021a96461e3c172e2a8be5b2ced554c7c378b320;selected_member=bv'; then
        log_error "stack.beads_viewer: ${ACFS_CORE_POLICY_REASON:-core admission policy rejected the module}"
        return 1
    fi

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: install content-addressed bv v0.22.0 for Linux ARM64 (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_BEADS_VIEWER'
# acfs-summary: install content-addressed bv v0.22.0 for Linux ARM64
set -euo pipefail
umask 077

bv_url="https://github.com/Dicklesworthstone/beads_viewer/releases/download/v0.22.0/bv_linux_arm64.tar.gz"
bv_archive_sha256="23d451b87bb9dccfb94fab416b0243d107919d9d56458087475afda5a617aa89"
bv_binary_sha256="ee1dd03701a33d86e6496fb7021a96461e3c172e2a8be5b2ced554c7c378b320"
bv_archive=""
bv_binary=""
bv_stage=""
bv_link_stage_dir=""
bv_link_stage=""

cleanup_bv_pinned_install() {
  if [[ -n "$bv_archive" ]]; then
    /usr/bin/rm -f -- "$bv_archive"
  fi
  if [[ -n "$bv_binary" ]]; then
    /usr/bin/rm -f -- "$bv_binary"
  fi
  if [[ -n "$bv_stage" ]]; then
    /usr/bin/rm -f -- "$bv_stage"
  fi
  if [[ -n "$bv_link_stage" ]]; then
    /usr/bin/rm -f -- "$bv_link_stage"
  fi
  if [[ -n "$bv_link_stage_dir" ]]; then
    /usr/bin/rmdir -- "$bv_link_stage_dir" 2>/dev/null || true
  fi
}

for required_binary in /usr/bin/curl /usr/bin/tar /usr/bin/sha256sum /usr/bin/awk /usr/bin/install /usr/bin/ln /usr/bin/mkdir /usr/bin/mktemp /usr/bin/mv /usr/bin/readlink /usr/bin/rm /usr/bin/rmdir /usr/bin/uname; do
  if [[ ! -x "$required_binary" ]]; then
    echo "Required trusted binary is unavailable: $required_binary" >&2
    exit 1
  fi
done

if [[ "$(/usr/bin/uname -s)" != "Linux" ]] \
  || { [[ "$(/usr/bin/uname -m)" != "aarch64" ]] && [[ "$(/usr/bin/uname -m)" != "arm64" ]]; }; then
  echo "bv v0.22.0 candidate supports only Linux ARM64" >&2
  exit 1
fi

bv_archive="$(/usr/bin/mktemp "/tmp/acfs-bv-v0.22.0.XXXXXX.tar.gz")"
bv_binary="$(/usr/bin/mktemp "/tmp/acfs-bv-v0.22.0.XXXXXX.bin")"
trap cleanup_bv_pinned_install EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

/usr/bin/curl -q --fail --location --silent --show-error \
  --proto '=https' --proto-redir '=https' --tlsv1.2 \
  --retry 3 --connect-timeout 15 --max-time 300 \
  --user-agent 'OpenAI File Downloader, XaiImageApiFetch/1.0' \
  --output "$bv_archive" "$bv_url"

bv_actual_archive_sha256="$(/usr/bin/sha256sum "$bv_archive" | /usr/bin/awk '{print $1}')"
if [[ "$bv_actual_archive_sha256" != "$bv_archive_sha256" ]]; then
  echo "bv v0.22.0 archive checksum mismatch" >&2
  exit 1
fi

# Scope the archive contract to the one exact member ACFS selects.
# Other archive members, if any, are never extracted or trusted.
bv_member_count="$(/usr/bin/tar -tzf "$bv_archive" | /usr/bin/awk '$0 == "bv" { count += 1 } END { print count + 0 }')"
bv_member_listing="$(/usr/bin/tar -tvzf "$bv_archive" -- bv)"
bv_member_listing_count="$(printf '%s\n' "$bv_member_listing" | /usr/bin/awk 'NF { count += 1 } END { print count + 0 }')"
if [[ "$bv_member_count" != "1" ]] \
  || [[ "$bv_member_listing_count" != "1" ]] \
  || [[ "$bv_member_listing" != -* ]]; then
  echo "bv v0.22.0 archive does not contain exactly one selected regular member named bv" >&2
  exit 1
fi

/usr/bin/tar -xOzf "$bv_archive" -- bv > "$bv_binary"
bv_actual_binary_sha256="$(/usr/bin/sha256sum "$bv_binary" | /usr/bin/awk '{print $1}')"
if [[ "$bv_actual_binary_sha256" != "$bv_binary_sha256" ]]; then
  echo "bv v0.22.0 binary checksum mismatch" >&2
  exit 1
fi

bv_version_dir="$HOME/.local/lib/acfs/bv/v0.22.0"
bv_versioned_target="$bv_version_dir/bv"
bv_public_dir="$HOME/.local/bin"
bv_public_target="$bv_public_dir/bv"

for bv_target_dir in \
  "$HOME/.local" \
  "$HOME/.local/lib" \
  "$HOME/.local/lib/acfs" \
  "$HOME/.local/lib/acfs/bv" \
  "$bv_version_dir" \
  "$bv_public_dir"
do
  if [[ -L "$bv_target_dir" ]]; then
    echo "Refusing bv install through a symlinked target directory: $bv_target_dir" >&2
    exit 1
  fi
done
/usr/bin/mkdir -p "$bv_version_dir" "$bv_public_dir"

if [[ -L "$bv_versioned_target" ]] || { [[ -e "$bv_versioned_target" ]] && [[ ! -f "$bv_versioned_target" ]]; }; then
  echo "Refusing to replace unsafe versioned bv target: $bv_versioned_target" >&2
  exit 1
fi
if [[ -L "$bv_public_target" ]] || { [[ -e "$bv_public_target" ]] && [[ ! -f "$bv_public_target" ]]; }; then
  echo "Refusing to replace unsafe public bv target: $bv_public_target" >&2
  exit 1
fi

bv_stage="$(/usr/bin/mktemp "$bv_version_dir/.bv-v0.22.0.XXXXXX")"
/usr/bin/install -m 0755 "$bv_binary" "$bv_stage"
bv_actual_binary_sha256="$(/usr/bin/sha256sum "$bv_stage" | /usr/bin/awk '{print $1}')"
if [[ "$bv_actual_binary_sha256" != "$bv_binary_sha256" ]]; then
  echo "Staged bv v0.22.0 binary checksum mismatch" >&2
  exit 1
fi
/usr/bin/mv -f -- "$bv_stage" "$bv_versioned_target"
bv_stage=""

bv_actual_binary_sha256="$(/usr/bin/sha256sum "$bv_versioned_target" | /usr/bin/awk '{print $1}')"
if [[ "$bv_actual_binary_sha256" != "$bv_binary_sha256" ]]; then
  echo "Installed versioned bv v0.22.0 binary checksum mismatch" >&2
  exit 1
fi

bv_link_stage_dir="$(/usr/bin/mktemp -d "$bv_public_dir/.bv-link-stage.XXXXXX")"
bv_link_stage="$bv_link_stage_dir/bv"
/usr/bin/ln -s "$bv_versioned_target" "$bv_link_stage"
/usr/bin/mv -f -- "$bv_link_stage" "$bv_public_target"
bv_link_stage=""
/usr/bin/rmdir -- "$bv_link_stage_dir"
bv_link_stage_dir=""

if [[ "$(/usr/bin/readlink "$bv_public_target")" != "$bv_versioned_target" ]]; then
  echo "Public bv command does not reference the admitted versioned binary" >&2
  exit 1
fi
bv_actual_binary_sha256="$(/usr/bin/sha256sum "$bv_public_target" | /usr/bin/awk '{print $1}')"
if [[ "$bv_actual_binary_sha256" != "$bv_binary_sha256" ]]; then
  echo "Public bv command checksum mismatch" >&2
  exit 1
fi
INSTALL_STACK_BEADS_VIEWER
        then
            log_error "stack.beads_viewer: install command failed: install content-addressed bv v0.22.0 for Linux ARM64"
            return 1
        fi
    fi

    # A version string is not an installed-state or post-install identity.
    if ! declare -f acfs_core_policy_admit_binary >/dev/null 2>&1 \
        || ! acfs_core_policy_admit_binary "stack.beads_viewer" install 'source_commit=95a706caf57fc5fde846a453da5f28677d4a81b8;version=v0.22.0;artifact_url=https://github.com/Dicklesworthstone/beads_viewer/releases/download/v0.22.0/bv_linux_arm64.tar.gz;archive_sha256=23d451b87bb9dccfb94fab416b0243d107919d9d56458087475afda5a617aa89;binary_sha256=ee1dd03701a33d86e6496fb7021a96461e3c172e2a8be5b2ced554c7c378b320;selected_member=bv' "$TARGET_HOME/.local/bin/bv"; then
        log_error "stack.beads_viewer: ${ACFS_CORE_POLICY_REASON:-exact binary identity rejected}"
        return 1
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: \"\$TARGET_HOME/.local/bin/bv\" --version | grep -Eq '(^|[[:space:]])v?0[.]22[.]0([[:space:]]|\$)' (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_BEADS_VIEWER'
"$TARGET_HOME/.local/bin/bv" --version | grep -Eq '(^|[[:space:]])v?0[.]22[.]0([[:space:]]|$)'
INSTALL_STACK_BEADS_VIEWER
        then
            log_error "stack.beads_viewer: verify failed: \"\$TARGET_HOME/.local/bin/bv\" --version | grep -Eq '(^|[[:space:]])v?0[.]22[.]0([[:space:]]|\$)'"
            return 1
        fi
    fi

    log_success "stack.beads_viewer installed"
}

# Unified search across agent session history
acfs_generated_install_stack_cass() {
    local module_id="stack.cass"
    local canonical_contract="${ACFS_GENERATED_SCRIPT_DIR}/../lib/contract.sh"
    # Rebind the exact sibling contract at every generated entry. Imported
    # shell functions and environment state are never commissioning authority.
    if [[ ! -f "$canonical_contract" || -L "$canonical_contract" ]]; then
        log_error "stack.cass: canonical runtime contract unavailable"
        return 1
    fi
    if ! builtin unset -f acfs_require_contract acfs_license_exclusion_profile_payload _acfs_license_profile_actual_sha256 acfs_license_policy_verify_profile acfs_license_policy_module_is_held acfs_license_policy_module_is_plain_mit_only acfs_license_policy_admit_entry acfs_license_clearance_requested acfs_license_clearance_verify acfs_license_clearance_active acfs_r1_runtime_profile_payload _acfs_r1_sha256_file _acfs_r1_profile_actual_sha256 _acfs_r1_runtime_root _acfs_r1_verify_bound_file acfs_r1_runtime_verify_profile acfs_r1_runtime_module_is_held acfs_r1_runtime_module_is_planned acfs_r1_runtime_admit_entry _acfs_r1_array_csv acfs_r1_runtime_prepare_selection acfs_r1_runtime_validate_plan acfs_core_policy_enforce acfs_core_policy_reason acfs_core_policy_contract _acfs_core_policy_target_home acfs_core_policy_expected_binary_path acfs_core_policy_expected_bv_versioned_path acfs_core_policy_expected_binary_sha256 _acfs_core_policy_sha256_file _acfs_core_policy_version_output acfs_core_policy_admit_binary acfs_core_policy_admit_repair_source acfs_core_policy_enforce_installer_execution 2>/dev/null; then
        log_error "stack.cass: imported runtime policy function is not replaceable"
        return 1
    fi
    # shellcheck disable=SC1090  # exact generated sibling
    if ! builtin source "$canonical_contract"; then
        log_error "stack.cass: canonical runtime contract could not be loaded"
        return 1
    fi
    if [[ "${ACFS_R1_RUNTIME_PROFILE_ID:-}" != "R1-held-module-exclusion-runtime-v1" ]] || ! builtin declare -F acfs_r1_runtime_admit_entry >/dev/null 2>&1; then
        log_error "stack.cass: exact R1 runtime profile unavailable"
        return 1
    fi
    if ! acfs_r1_runtime_admit_entry direct "${module_id}"; then
        log_error "stack.cass: ${ACFS_R1_POLICY_REASON:-R1 runtime admission rejected the module}"
        return 1
    fi
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping stack.cass (not selected)"
        return 0
    fi
    log_step "Installing stack.cass"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.cass"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false
            local verified_installer_file=""
            local verified_installer_chmod_bin=""
            local verified_installer_env_ready=true

            local verified_installer_tmpdir_template="$TARGET_HOME"'/.cache/acfs/installer-tmp/cass.XXXXXX'
            local verified_installer_tmpdir_parent="${verified_installer_tmpdir_template%/*}"
            local verified_installer_tmpdir_prefix="${verified_installer_tmpdir_template%XXXXXX}"
            local verified_installer_tmpdir=""
            local verified_installer_tmpdir_suffix=""
            local verified_installer_mkdir_bin=""
            local verified_installer_mktemp_bin=""
            if [[ "$verified_installer_tmpdir_template" != *XXXXXX* ]]; then
                log_error "stack.cass: installer TMPDIR template must contain XXXXXX: $verified_installer_tmpdir_template"
                verified_installer_env_ready=false
            elif ! verified_installer_mkdir_bin="$(acfs_generated_system_binary_path mkdir 2>/dev/null)"; then
                log_error "stack.cass: trusted mkdir not found for installer TMPDIR"
                verified_installer_env_ready=false
            elif ! verified_installer_mktemp_bin="$(acfs_generated_system_binary_path mktemp 2>/dev/null)"; then
                log_error "stack.cass: trusted mktemp not found for installer TMPDIR"
                verified_installer_env_ready=false
            elif [[ "$verified_installer_tmpdir_parent" != "$TARGET_HOME/.cache/acfs/installer-tmp" ]]; then
                log_error "stack.cass: installer TMPDIR parent escaped the approved target-home path"
                verified_installer_env_ready=false
            elif [[ -L "$TARGET_HOME" || -L "$TARGET_HOME/.cache" || -L "$TARGET_HOME/.cache/acfs" || -L "$verified_installer_tmpdir_parent" ]]; then
                log_error "stack.cass: refusing installer TMPDIR through a symlinked target-home path"
                verified_installer_env_ready=false
            elif ! run_as_target "$verified_installer_mkdir_bin" -p "$verified_installer_tmpdir_parent"; then
                log_error "stack.cass: failed to prepare installer TMPDIR parent: $verified_installer_tmpdir_parent"
                verified_installer_env_ready=false
            elif [[ ! -d "$verified_installer_tmpdir_parent" || -L "$TARGET_HOME" || -L "$TARGET_HOME/.cache" || -L "$TARGET_HOME/.cache/acfs" || -L "$verified_installer_tmpdir_parent" ]]; then
                log_error "stack.cass: installer TMPDIR parent is not a confined real directory"
                verified_installer_env_ready=false
            elif ! verified_installer_tmpdir="$(run_as_target "$verified_installer_mktemp_bin" -d "$verified_installer_tmpdir_template" 2>/dev/null)"; then
                log_error "stack.cass: failed to create installer TMPDIR from template: $verified_installer_tmpdir_template"
                verified_installer_env_ready=false
            elif [[ -z "$verified_installer_tmpdir" ]]; then
                log_error "stack.cass: installer TMPDIR creation returned an empty path"
                verified_installer_env_ready=false
            else
                verified_installer_tmpdir_suffix="${verified_installer_tmpdir#"$verified_installer_tmpdir_prefix"}"
                if [[ "$verified_installer_tmpdir" != "$verified_installer_tmpdir_prefix"* || -z "$verified_installer_tmpdir_suffix" || "$verified_installer_tmpdir_suffix" == *[!A-Za-z0-9]* || ! -d "$verified_installer_tmpdir" || -L "$verified_installer_tmpdir" || -L "$verified_installer_tmpdir_parent" ]]; then
                    log_error "stack.cass: installer TMPDIR escaped its trusted template: $verified_installer_tmpdir"
                    verified_installer_env_ready=false
                fi
            fi

                # Cleared per attempt so a stale reason from an earlier module can
                # never be misattributed to this one.
                ACFS_LAST_MODULE_FAILURE_REASON=""
            if [[ "$verified_installer_env_ready" = "true" ]] && acfs_security_init; then
                local known_installers_decl=""
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                known_installers_decl="$(declare -p KNOWN_INSTALLERS 2>/dev/null || true)"
                if [[ "$known_installers_decl" == declare\ -A* ]]; then
                    local tool="cass"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.cass: get_checksum failed for tool '$tool'"
                        ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if ! verified_installer_file="$(acfs_security_mktemp "/tmp/acfs-verified-installer.XXXXXX" 2>/dev/null)" || [[ -z "$verified_installer_file" ]]; then
                            log_error "stack.cass: failed to create verified installer staging file"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                            verified_installer_file=""
                        elif ! verify_checksum "$url" "$expected_sha256" "$tool" > "$verified_installer_file"; then
                            log_error "stack.cass: installer verification failed"
                            : "${ACFS_LAST_MODULE_FAILURE_REASON:=checksum}"
                        elif ! verified_installer_chmod_bin="$(acfs_generated_system_binary_path chmod 2>/dev/null)"; then
                            log_error "stack.cass: trusted chmod not found for verified installer staging"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        elif ! "$verified_installer_chmod_bin" 0444 "$verified_installer_file"; then
                            log_error "stack.cass: failed to make verified installer staging file read-only"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                        elif run_as_target_runner 'env' "TMPDIR=$verified_installer_tmpdir" 'bash' "$verified_installer_file" '--easy-mode' '--verify'; then
                            install_success=true
                        else
                            log_error "stack.cass: verified installer execution failed"
                            ACFS_LAST_MODULE_FAILURE_REASON="installer execution"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.cass: KNOWN_INSTALLERS[$tool] not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.cass: checksum for '$tool' not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                    fi
                else
                    log_error "stack.cass: KNOWN_INSTALLERS array not available"
                    ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                fi
            else
                if [[ "$verified_installer_env_ready" != "true" ]]; then
                    log_error "stack.cass: verified installer environment setup failed"
                    ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                else
                    log_error "stack.cass: acfs_security_init failed - check security.sh and checksums.yaml"
                    ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                fi
            fi
            if [[ -n "$verified_installer_file" ]]; then
                _acfs_remove_temp_files "$verified_installer_file"
                verified_installer_file=""
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.cass"
                false
            fi
        }; then
            log_error "stack.cass: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: cass --help || cass --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_CASS'
cass --help || cass --version
INSTALL_STACK_CASS
        then
            log_error "stack.cass: verify failed: cass --help || cass --version"
            return 1
        fi
    fi

    log_success "stack.cass installed"
}

# Procedural memory for agents (cass-memory)
acfs_generated_install_stack_cm() {
    local module_id="stack.cm"
    local canonical_contract="${ACFS_GENERATED_SCRIPT_DIR}/../lib/contract.sh"
    # Rebind the exact sibling contract at every generated entry. Imported
    # shell functions and environment state are never commissioning authority.
    if [[ ! -f "$canonical_contract" || -L "$canonical_contract" ]]; then
        log_error "stack.cm: canonical runtime contract unavailable"
        return 1
    fi
    if ! builtin unset -f acfs_require_contract acfs_license_exclusion_profile_payload _acfs_license_profile_actual_sha256 acfs_license_policy_verify_profile acfs_license_policy_module_is_held acfs_license_policy_module_is_plain_mit_only acfs_license_policy_admit_entry acfs_license_clearance_requested acfs_license_clearance_verify acfs_license_clearance_active acfs_r1_runtime_profile_payload _acfs_r1_sha256_file _acfs_r1_profile_actual_sha256 _acfs_r1_runtime_root _acfs_r1_verify_bound_file acfs_r1_runtime_verify_profile acfs_r1_runtime_module_is_held acfs_r1_runtime_module_is_planned acfs_r1_runtime_admit_entry _acfs_r1_array_csv acfs_r1_runtime_prepare_selection acfs_r1_runtime_validate_plan acfs_core_policy_enforce acfs_core_policy_reason acfs_core_policy_contract _acfs_core_policy_target_home acfs_core_policy_expected_binary_path acfs_core_policy_expected_bv_versioned_path acfs_core_policy_expected_binary_sha256 _acfs_core_policy_sha256_file _acfs_core_policy_version_output acfs_core_policy_admit_binary acfs_core_policy_admit_repair_source acfs_core_policy_enforce_installer_execution 2>/dev/null; then
        log_error "stack.cm: imported runtime policy function is not replaceable"
        return 1
    fi
    # shellcheck disable=SC1090  # exact generated sibling
    if ! builtin source "$canonical_contract"; then
        log_error "stack.cm: canonical runtime contract could not be loaded"
        return 1
    fi
    if [[ "${ACFS_R1_RUNTIME_PROFILE_ID:-}" != "R1-held-module-exclusion-runtime-v1" ]] || ! builtin declare -F acfs_r1_runtime_admit_entry >/dev/null 2>&1; then
        log_error "stack.cm: exact R1 runtime profile unavailable"
        return 1
    fi
    if ! acfs_r1_runtime_admit_entry direct "${module_id}"; then
        log_error "stack.cm: ${ACFS_R1_POLICY_REASON:-R1 runtime admission rejected the module}"
        return 1
    fi
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping stack.cm (not selected)"
        return 0
    fi
    log_step "Installing stack.cm"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.cm"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false
            local verified_installer_file=""
            local verified_installer_chmod_bin=""

                # Cleared per attempt so a stale reason from an earlier module can
                # never be misattributed to this one.
                ACFS_LAST_MODULE_FAILURE_REASON=""
            if acfs_security_init; then
                local known_installers_decl=""
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                known_installers_decl="$(declare -p KNOWN_INSTALLERS 2>/dev/null || true)"
                if [[ "$known_installers_decl" == declare\ -A* ]]; then
                    local tool="cm"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.cm: get_checksum failed for tool '$tool'"
                        ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if ! verified_installer_file="$(acfs_security_mktemp "/tmp/acfs-verified-installer.XXXXXX" 2>/dev/null)" || [[ -z "$verified_installer_file" ]]; then
                            log_error "stack.cm: failed to create verified installer staging file"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                            verified_installer_file=""
                        elif ! verify_checksum "$url" "$expected_sha256" "$tool" > "$verified_installer_file"; then
                            log_error "stack.cm: installer verification failed"
                            : "${ACFS_LAST_MODULE_FAILURE_REASON:=checksum}"
                        elif ! verified_installer_chmod_bin="$(acfs_generated_system_binary_path chmod 2>/dev/null)"; then
                            log_error "stack.cm: trusted chmod not found for verified installer staging"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        elif ! "$verified_installer_chmod_bin" 0444 "$verified_installer_file"; then
                            log_error "stack.cm: failed to make verified installer staging file read-only"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                        elif run_as_target_runner 'bash' "$verified_installer_file" '--easy-mode' '--verify'; then
                            install_success=true
                        else
                            log_error "stack.cm: verified installer execution failed"
                            ACFS_LAST_MODULE_FAILURE_REASON="installer execution"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.cm: KNOWN_INSTALLERS[$tool] not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.cm: checksum for '$tool' not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                    fi
                else
                    log_error "stack.cm: KNOWN_INSTALLERS array not available"
                    ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                fi
            else
                log_error "stack.cm: acfs_security_init failed - check security.sh and checksums.yaml"
                ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
            fi
            if [[ -n "$verified_installer_file" ]]; then
                _acfs_remove_temp_files "$verified_installer_file"
                verified_installer_file=""
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.cm"
                false
            fi
        }; then
            log_error "stack.cm: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: cm --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_CM'
cm --version
INSTALL_STACK_CM
        then
            log_error "stack.cm: verify failed: cm --version"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify (optional): timeout 30 cm doctor --json (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_CM'
timeout 30 cm doctor --json
INSTALL_STACK_CM
        then
            log_warn "Optional verify failed: stack.cm"
        fi
    fi

    log_success "stack.cm installed"
}

# Instant auth switching for agent CLIs
acfs_generated_install_stack_caam() {
    local module_id="stack.caam"
    local canonical_contract="${ACFS_GENERATED_SCRIPT_DIR}/../lib/contract.sh"
    # Rebind the exact sibling contract at every generated entry. Imported
    # shell functions and environment state are never commissioning authority.
    if [[ ! -f "$canonical_contract" || -L "$canonical_contract" ]]; then
        log_error "stack.caam: canonical runtime contract unavailable"
        return 1
    fi
    if ! builtin unset -f acfs_require_contract acfs_license_exclusion_profile_payload _acfs_license_profile_actual_sha256 acfs_license_policy_verify_profile acfs_license_policy_module_is_held acfs_license_policy_module_is_plain_mit_only acfs_license_policy_admit_entry acfs_license_clearance_requested acfs_license_clearance_verify acfs_license_clearance_active acfs_r1_runtime_profile_payload _acfs_r1_sha256_file _acfs_r1_profile_actual_sha256 _acfs_r1_runtime_root _acfs_r1_verify_bound_file acfs_r1_runtime_verify_profile acfs_r1_runtime_module_is_held acfs_r1_runtime_module_is_planned acfs_r1_runtime_admit_entry _acfs_r1_array_csv acfs_r1_runtime_prepare_selection acfs_r1_runtime_validate_plan acfs_core_policy_enforce acfs_core_policy_reason acfs_core_policy_contract _acfs_core_policy_target_home acfs_core_policy_expected_binary_path acfs_core_policy_expected_bv_versioned_path acfs_core_policy_expected_binary_sha256 _acfs_core_policy_sha256_file _acfs_core_policy_version_output acfs_core_policy_admit_binary acfs_core_policy_admit_repair_source acfs_core_policy_enforce_installer_execution 2>/dev/null; then
        log_error "stack.caam: imported runtime policy function is not replaceable"
        return 1
    fi
    # shellcheck disable=SC1090  # exact generated sibling
    if ! builtin source "$canonical_contract"; then
        log_error "stack.caam: canonical runtime contract could not be loaded"
        return 1
    fi
    if [[ "${ACFS_R1_RUNTIME_PROFILE_ID:-}" != "R1-held-module-exclusion-runtime-v1" ]] || ! builtin declare -F acfs_r1_runtime_admit_entry >/dev/null 2>&1; then
        log_error "stack.caam: exact R1 runtime profile unavailable"
        return 1
    fi
    if ! acfs_r1_runtime_admit_entry direct "${module_id}"; then
        log_error "stack.caam: ${ACFS_R1_POLICY_REASON:-R1 runtime admission rejected the module}"
        return 1
    fi
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping stack.caam (not selected)"
        return 0
    fi
    log_step "Installing stack.caam"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.caam"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false
            local verified_installer_file=""
            local verified_installer_chmod_bin=""

                # Cleared per attempt so a stale reason from an earlier module can
                # never be misattributed to this one.
                ACFS_LAST_MODULE_FAILURE_REASON=""
            if acfs_security_init; then
                local known_installers_decl=""
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                known_installers_decl="$(declare -p KNOWN_INSTALLERS 2>/dev/null || true)"
                if [[ "$known_installers_decl" == declare\ -A* ]]; then
                    local tool="caam"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.caam: get_checksum failed for tool '$tool'"
                        ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if ! verified_installer_file="$(acfs_security_mktemp "/tmp/acfs-verified-installer.XXXXXX" 2>/dev/null)" || [[ -z "$verified_installer_file" ]]; then
                            log_error "stack.caam: failed to create verified installer staging file"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                            verified_installer_file=""
                        elif ! verify_checksum "$url" "$expected_sha256" "$tool" > "$verified_installer_file"; then
                            log_error "stack.caam: installer verification failed"
                            : "${ACFS_LAST_MODULE_FAILURE_REASON:=checksum}"
                        elif ! verified_installer_chmod_bin="$(acfs_generated_system_binary_path chmod 2>/dev/null)"; then
                            log_error "stack.caam: trusted chmod not found for verified installer staging"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        elif ! "$verified_installer_chmod_bin" 0444 "$verified_installer_file"; then
                            log_error "stack.caam: failed to make verified installer staging file read-only"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                        elif run_as_target_runner 'env' 'NONINTERACTIVE=1' 'bash' "$verified_installer_file"; then
                            install_success=true
                        else
                            log_error "stack.caam: verified installer execution failed"
                            ACFS_LAST_MODULE_FAILURE_REASON="installer execution"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.caam: KNOWN_INSTALLERS[$tool] not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.caam: checksum for '$tool' not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                    fi
                else
                    log_error "stack.caam: KNOWN_INSTALLERS array not available"
                    ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                fi
            else
                log_error "stack.caam: acfs_security_init failed - check security.sh and checksums.yaml"
                ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
            fi
            if [[ -n "$verified_installer_file" ]]; then
                _acfs_remove_temp_files "$verified_installer_file"
                verified_installer_file=""
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.caam"
                false
            fi
        }; then
            log_error "stack.caam: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: caam status || caam --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_CAAM'
caam status || caam --help
INSTALL_STACK_CAAM
        then
            log_error "stack.caam: verify failed: caam status || caam --help"
            return 1
        fi
    fi

    log_success "stack.caam installed"
}

# Two-person rule for dangerous commands (optional guardrails)
acfs_generated_install_stack_slb() {
    local module_id="stack.slb"
    local canonical_contract="${ACFS_GENERATED_SCRIPT_DIR}/../lib/contract.sh"
    # Rebind the exact sibling contract at every generated entry. Imported
    # shell functions and environment state are never commissioning authority.
    if [[ ! -f "$canonical_contract" || -L "$canonical_contract" ]]; then
        log_error "stack.slb: canonical runtime contract unavailable"
        return 1
    fi
    if ! builtin unset -f acfs_require_contract acfs_license_exclusion_profile_payload _acfs_license_profile_actual_sha256 acfs_license_policy_verify_profile acfs_license_policy_module_is_held acfs_license_policy_module_is_plain_mit_only acfs_license_policy_admit_entry acfs_license_clearance_requested acfs_license_clearance_verify acfs_license_clearance_active acfs_r1_runtime_profile_payload _acfs_r1_sha256_file _acfs_r1_profile_actual_sha256 _acfs_r1_runtime_root _acfs_r1_verify_bound_file acfs_r1_runtime_verify_profile acfs_r1_runtime_module_is_held acfs_r1_runtime_module_is_planned acfs_r1_runtime_admit_entry _acfs_r1_array_csv acfs_r1_runtime_prepare_selection acfs_r1_runtime_validate_plan acfs_core_policy_enforce acfs_core_policy_reason acfs_core_policy_contract _acfs_core_policy_target_home acfs_core_policy_expected_binary_path acfs_core_policy_expected_bv_versioned_path acfs_core_policy_expected_binary_sha256 _acfs_core_policy_sha256_file _acfs_core_policy_version_output acfs_core_policy_admit_binary acfs_core_policy_admit_repair_source acfs_core_policy_enforce_installer_execution 2>/dev/null; then
        log_error "stack.slb: imported runtime policy function is not replaceable"
        return 1
    fi
    # shellcheck disable=SC1090  # exact generated sibling
    if ! builtin source "$canonical_contract"; then
        log_error "stack.slb: canonical runtime contract could not be loaded"
        return 1
    fi
    if [[ "${ACFS_R1_RUNTIME_PROFILE_ID:-}" != "R1-held-module-exclusion-runtime-v1" ]] || ! builtin declare -F acfs_r1_runtime_admit_entry >/dev/null 2>&1; then
        log_error "stack.slb: exact R1 runtime profile unavailable"
        return 1
    fi
    if ! acfs_r1_runtime_admit_entry direct "${module_id}"; then
        log_error "stack.slb: ${ACFS_R1_POLICY_REASON:-R1 runtime admission rejected the module}"
        return 1
    fi
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping stack.slb (not selected)"
        return 0
    fi
    log_step "Installing stack.slb"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.slb"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false
            local verified_installer_file=""
            local verified_installer_chmod_bin=""

                # Cleared per attempt so a stale reason from an earlier module can
                # never be misattributed to this one.
                ACFS_LAST_MODULE_FAILURE_REASON=""
            if acfs_security_init; then
                local known_installers_decl=""
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                known_installers_decl="$(declare -p KNOWN_INSTALLERS 2>/dev/null || true)"
                if [[ "$known_installers_decl" == declare\ -A* ]]; then
                    local tool="slb"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.slb: get_checksum failed for tool '$tool'"
                        ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if ! verified_installer_file="$(acfs_security_mktemp "/tmp/acfs-verified-installer.XXXXXX" 2>/dev/null)" || [[ -z "$verified_installer_file" ]]; then
                            log_error "stack.slb: failed to create verified installer staging file"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                            verified_installer_file=""
                        elif ! verify_checksum "$url" "$expected_sha256" "$tool" > "$verified_installer_file"; then
                            log_error "stack.slb: installer verification failed"
                            : "${ACFS_LAST_MODULE_FAILURE_REASON:=checksum}"
                        elif ! verified_installer_chmod_bin="$(acfs_generated_system_binary_path chmod 2>/dev/null)"; then
                            log_error "stack.slb: trusted chmod not found for verified installer staging"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        elif ! "$verified_installer_chmod_bin" 0444 "$verified_installer_file"; then
                            log_error "stack.slb: failed to make verified installer staging file read-only"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                        elif run_as_target_runner 'env' 'INSTALL_DIR='"$TARGET_HOME"'/.local/bin' 'bash' "$verified_installer_file"; then
                            install_success=true
                        else
                            log_error "stack.slb: verified installer execution failed"
                            ACFS_LAST_MODULE_FAILURE_REASON="installer execution"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.slb: KNOWN_INSTALLERS[$tool] not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.slb: checksum for '$tool' not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                    fi
                else
                    log_error "stack.slb: KNOWN_INSTALLERS array not available"
                    ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                fi
            else
                log_error "stack.slb: acfs_security_init failed - check security.sh and checksums.yaml"
                ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
            fi
            if [[ -n "$verified_installer_file" ]]; then
                _acfs_remove_temp_files "$verified_installer_file"
                verified_installer_file=""
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.slb"
                false
            fi
        }; then
            log_warn "stack.slb: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.slb" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.slb"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: export PATH=\"\$HOME/go/bin:\$PATH\" && slb >/dev/null 2>&1 || slb --help >/dev/null 2>&1 (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_SLB'
export PATH="$HOME/go/bin:$PATH" && slb >/dev/null 2>&1 || slb --help >/dev/null 2>&1
INSTALL_STACK_SLB
        then
            log_warn "stack.slb: verify failed: export PATH=\"\$HOME/go/bin:\$PATH\" && slb >/dev/null 2>&1 || slb --help >/dev/null 2>&1"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.slb" "verify failed: export PATH=\"\$HOME/go/bin:\$PATH\" && slb >/dev/null 2>&1 || slb --help >/dev/null 2>&1"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.slb"
            fi
            return 0
        fi
    fi

    log_success "stack.slb installed"
}

# Destructive Command Guard - Claude Code hook blocking dangerous git/fs commands
acfs_generated_install_stack_dcg() {
    local module_id="stack.dcg"
    local canonical_contract="${ACFS_GENERATED_SCRIPT_DIR}/../lib/contract.sh"
    # Rebind the exact sibling contract at every generated entry. Imported
    # shell functions and environment state are never commissioning authority.
    if [[ ! -f "$canonical_contract" || -L "$canonical_contract" ]]; then
        log_error "stack.dcg: canonical runtime contract unavailable"
        return 1
    fi
    if ! builtin unset -f acfs_require_contract acfs_license_exclusion_profile_payload _acfs_license_profile_actual_sha256 acfs_license_policy_verify_profile acfs_license_policy_module_is_held acfs_license_policy_module_is_plain_mit_only acfs_license_policy_admit_entry acfs_license_clearance_requested acfs_license_clearance_verify acfs_license_clearance_active acfs_r1_runtime_profile_payload _acfs_r1_sha256_file _acfs_r1_profile_actual_sha256 _acfs_r1_runtime_root _acfs_r1_verify_bound_file acfs_r1_runtime_verify_profile acfs_r1_runtime_module_is_held acfs_r1_runtime_module_is_planned acfs_r1_runtime_admit_entry _acfs_r1_array_csv acfs_r1_runtime_prepare_selection acfs_r1_runtime_validate_plan acfs_core_policy_enforce acfs_core_policy_reason acfs_core_policy_contract _acfs_core_policy_target_home acfs_core_policy_expected_binary_path acfs_core_policy_expected_bv_versioned_path acfs_core_policy_expected_binary_sha256 _acfs_core_policy_sha256_file _acfs_core_policy_version_output acfs_core_policy_admit_binary acfs_core_policy_admit_repair_source acfs_core_policy_enforce_installer_execution 2>/dev/null; then
        log_error "stack.dcg: imported runtime policy function is not replaceable"
        return 1
    fi
    # shellcheck disable=SC1090  # exact generated sibling
    if ! builtin source "$canonical_contract"; then
        log_error "stack.dcg: canonical runtime contract could not be loaded"
        return 1
    fi
    if [[ "${ACFS_R1_RUNTIME_PROFILE_ID:-}" != "R1-held-module-exclusion-runtime-v1" ]] || ! builtin declare -F acfs_r1_runtime_admit_entry >/dev/null 2>&1; then
        log_error "stack.dcg: exact R1 runtime profile unavailable"
        return 1
    fi
    if ! acfs_r1_runtime_admit_entry direct "${module_id}"; then
        log_error "stack.dcg: ${ACFS_R1_POLICY_REASON:-R1 runtime admission rejected the module}"
        return 1
    fi
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping stack.dcg (not selected)"
        return 0
    fi
    log_step "Installing stack.dcg"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.dcg"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false
            local verified_installer_file=""
            local verified_installer_chmod_bin=""

                # Cleared per attempt so a stale reason from an earlier module can
                # never be misattributed to this one.
                ACFS_LAST_MODULE_FAILURE_REASON=""
            if acfs_security_init; then
                local known_installers_decl=""
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                known_installers_decl="$(declare -p KNOWN_INSTALLERS 2>/dev/null || true)"
                if [[ "$known_installers_decl" == declare\ -A* ]]; then
                    local tool="dcg"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.dcg: get_checksum failed for tool '$tool'"
                        ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if ! verified_installer_file="$(acfs_security_mktemp "/tmp/acfs-verified-installer.XXXXXX" 2>/dev/null)" || [[ -z "$verified_installer_file" ]]; then
                            log_error "stack.dcg: failed to create verified installer staging file"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                            verified_installer_file=""
                        elif ! verify_checksum "$url" "$expected_sha256" "$tool" > "$verified_installer_file"; then
                            log_error "stack.dcg: installer verification failed"
                            : "${ACFS_LAST_MODULE_FAILURE_REASON:=checksum}"
                        elif ! verified_installer_chmod_bin="$(acfs_generated_system_binary_path chmod 2>/dev/null)"; then
                            log_error "stack.dcg: trusted chmod not found for verified installer staging"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        elif ! "$verified_installer_chmod_bin" 0444 "$verified_installer_file"; then
                            log_error "stack.dcg: failed to make verified installer staging file read-only"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                        elif run_as_target_runner 'bash' "$verified_installer_file" '--easy-mode'; then
                            install_success=true
                        else
                            log_error "stack.dcg: verified installer execution failed"
                            ACFS_LAST_MODULE_FAILURE_REASON="installer execution"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.dcg: KNOWN_INSTALLERS[$tool] not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.dcg: checksum for '$tool' not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                    fi
                else
                    log_error "stack.dcg: KNOWN_INSTALLERS array not available"
                    ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                fi
            else
                log_error "stack.dcg: acfs_security_init failed - check security.sh and checksums.yaml"
                ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
            fi
            if [[ -n "$verified_installer_file" ]]; then
                _acfs_remove_temp_files "$verified_installer_file"
                verified_installer_file=""
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.dcg"
                false
            fi
        }; then
            log_error "stack.dcg: verified installer failed"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: if command -v claude >/dev/null 2>&1; then (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_DCG'
if command -v claude >/dev/null 2>&1; then
  dcg install --force
fi
INSTALL_STACK_DCG
        then
            log_error "stack.dcg: install command failed: if command -v claude >/dev/null 2>&1; then"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: dcg --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_DCG'
dcg --version
INSTALL_STACK_DCG
        then
            log_error "stack.dcg: verify failed: dcg --version"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: claude_settings_has_command_hook \"\$settings\" \"\$dcg_command_pattern\" || (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_DCG'
claude_settings_has_command_hook() {
  local settings_file="${1:-}"
  local command_pattern="${2:-}"
  local jq_bin=""

  [[ -n "$settings_file" && -n "$command_pattern" ]] || return 1
  [[ -f "$settings_file" ]] || return 1
  for jq_bin in /usr/bin/jq /bin/jq /usr/local/bin/jq /usr/local/sbin/jq /usr/sbin/jq /sbin/jq; do
    [[ -x "$jq_bin" ]] && break
  done
  [[ -x "$jq_bin" ]] || return 1

  "$jq_bin" -e --arg pattern "$command_pattern" '
    def command_hook_matches:
      type == "object"
      and ((.type? // "command") == "command")
      and ((.command? // "") | strings | test($pattern));
    def event_entry_matches:
      if type == "object" and (.hooks? | type) == "array" then
        any(.hooks[]?; command_hook_matches)
      else
        command_hook_matches
      end;
    def hook_event_entries:
      if (.hooks? | type) == "object" then
        .hooks | to_entries[]? | .value | arrays | .[]?
      elif (.hooks? | type) == "array" then
        .hooks[]?
      else
        empty
      end;
    any(hook_event_entries; event_entry_matches)
  ' "$settings_file" >/dev/null 2>&1
}

settings="$HOME/.claude/settings.json"
alt_settings="$HOME/.config/claude/settings.json"
dcg_command_pattern='(^|[[:space:]/])dcg([[:space:]]|$)'

claude_settings_has_command_hook "$settings" "$dcg_command_pattern" ||
  claude_settings_has_command_hook "$alt_settings" "$dcg_command_pattern"
INSTALL_STACK_DCG
        then
            log_error "stack.dcg: verify failed: claude_settings_has_command_hook \"\$settings\" \"\$dcg_command_pattern\" ||"
            return 1
        fi
    fi

    log_success "stack.dcg installed"
}

# Repo Updater - multi-repo sync + AI-driven commit automation
acfs_generated_install_stack_ru() {
    local module_id="stack.ru"
    local canonical_contract="${ACFS_GENERATED_SCRIPT_DIR}/../lib/contract.sh"
    # Rebind the exact sibling contract at every generated entry. Imported
    # shell functions and environment state are never commissioning authority.
    if [[ ! -f "$canonical_contract" || -L "$canonical_contract" ]]; then
        log_error "stack.ru: canonical runtime contract unavailable"
        return 1
    fi
    if ! builtin unset -f acfs_require_contract acfs_license_exclusion_profile_payload _acfs_license_profile_actual_sha256 acfs_license_policy_verify_profile acfs_license_policy_module_is_held acfs_license_policy_module_is_plain_mit_only acfs_license_policy_admit_entry acfs_license_clearance_requested acfs_license_clearance_verify acfs_license_clearance_active acfs_r1_runtime_profile_payload _acfs_r1_sha256_file _acfs_r1_profile_actual_sha256 _acfs_r1_runtime_root _acfs_r1_verify_bound_file acfs_r1_runtime_verify_profile acfs_r1_runtime_module_is_held acfs_r1_runtime_module_is_planned acfs_r1_runtime_admit_entry _acfs_r1_array_csv acfs_r1_runtime_prepare_selection acfs_r1_runtime_validate_plan acfs_core_policy_enforce acfs_core_policy_reason acfs_core_policy_contract _acfs_core_policy_target_home acfs_core_policy_expected_binary_path acfs_core_policy_expected_bv_versioned_path acfs_core_policy_expected_binary_sha256 _acfs_core_policy_sha256_file _acfs_core_policy_version_output acfs_core_policy_admit_binary acfs_core_policy_admit_repair_source acfs_core_policy_enforce_installer_execution 2>/dev/null; then
        log_error "stack.ru: imported runtime policy function is not replaceable"
        return 1
    fi
    # shellcheck disable=SC1090  # exact generated sibling
    if ! builtin source "$canonical_contract"; then
        log_error "stack.ru: canonical runtime contract could not be loaded"
        return 1
    fi
    if [[ "${ACFS_R1_RUNTIME_PROFILE_ID:-}" != "R1-held-module-exclusion-runtime-v1" ]] || ! builtin declare -F acfs_r1_runtime_admit_entry >/dev/null 2>&1; then
        log_error "stack.ru: exact R1 runtime profile unavailable"
        return 1
    fi
    if ! acfs_r1_runtime_admit_entry direct "${module_id}"; then
        log_error "stack.ru: ${ACFS_R1_POLICY_REASON:-R1 runtime admission rejected the module}"
        return 1
    fi
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping stack.ru (not selected)"
        return 0
    fi
    log_step "Installing stack.ru"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.ru"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false
            local verified_installer_file=""
            local verified_installer_chmod_bin=""

                # Cleared per attempt so a stale reason from an earlier module can
                # never be misattributed to this one.
                ACFS_LAST_MODULE_FAILURE_REASON=""
            if acfs_security_init; then
                local known_installers_decl=""
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                known_installers_decl="$(declare -p KNOWN_INSTALLERS 2>/dev/null || true)"
                if [[ "$known_installers_decl" == declare\ -A* ]]; then
                    local tool="ru"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.ru: get_checksum failed for tool '$tool'"
                        ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if ! verified_installer_file="$(acfs_security_mktemp "/tmp/acfs-verified-installer.XXXXXX" 2>/dev/null)" || [[ -z "$verified_installer_file" ]]; then
                            log_error "stack.ru: failed to create verified installer staging file"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                            verified_installer_file=""
                        elif ! verify_checksum "$url" "$expected_sha256" "$tool" > "$verified_installer_file"; then
                            log_error "stack.ru: installer verification failed"
                            : "${ACFS_LAST_MODULE_FAILURE_REASON:=checksum}"
                        elif ! verified_installer_chmod_bin="$(acfs_generated_system_binary_path chmod 2>/dev/null)"; then
                            log_error "stack.ru: trusted chmod not found for verified installer staging"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        elif ! "$verified_installer_chmod_bin" 0444 "$verified_installer_file"; then
                            log_error "stack.ru: failed to make verified installer staging file read-only"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                        elif run_as_target_runner 'env' 'RU_NON_INTERACTIVE=1' 'bash' "$verified_installer_file"; then
                            install_success=true
                        else
                            log_error "stack.ru: verified installer execution failed"
                            ACFS_LAST_MODULE_FAILURE_REASON="installer execution"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.ru: KNOWN_INSTALLERS[$tool] not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.ru: checksum for '$tool' not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                    fi
                else
                    log_error "stack.ru: KNOWN_INSTALLERS array not available"
                    ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                fi
            else
                log_error "stack.ru: acfs_security_init failed - check security.sh and checksums.yaml"
                ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
            fi
            if [[ -n "$verified_installer_file" ]]; then
                _acfs_remove_temp_files "$verified_installer_file"
                verified_installer_file=""
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.ru"
                false
            fi
        }; then
            log_error "stack.ru: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: ru --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_RU'
ru --version
INSTALL_STACK_RU
        then
            log_error "stack.ru: verify failed: ru --version"
            return 1
        fi
    fi

    log_success "stack.ru installed"
}

# Brenner Bot - research session manager with hypothesis tracking
acfs_generated_install_stack_brenner_bot() {
    local module_id="stack.brenner_bot"
    local canonical_contract="${ACFS_GENERATED_SCRIPT_DIR}/../lib/contract.sh"
    # Rebind the exact sibling contract at every generated entry. Imported
    # shell functions and environment state are never commissioning authority.
    if [[ ! -f "$canonical_contract" || -L "$canonical_contract" ]]; then
        log_error "stack.brenner_bot: canonical runtime contract unavailable"
        return 1
    fi
    if ! builtin unset -f acfs_require_contract acfs_license_exclusion_profile_payload _acfs_license_profile_actual_sha256 acfs_license_policy_verify_profile acfs_license_policy_module_is_held acfs_license_policy_module_is_plain_mit_only acfs_license_policy_admit_entry acfs_license_clearance_requested acfs_license_clearance_verify acfs_license_clearance_active acfs_r1_runtime_profile_payload _acfs_r1_sha256_file _acfs_r1_profile_actual_sha256 _acfs_r1_runtime_root _acfs_r1_verify_bound_file acfs_r1_runtime_verify_profile acfs_r1_runtime_module_is_held acfs_r1_runtime_module_is_planned acfs_r1_runtime_admit_entry _acfs_r1_array_csv acfs_r1_runtime_prepare_selection acfs_r1_runtime_validate_plan acfs_core_policy_enforce acfs_core_policy_reason acfs_core_policy_contract _acfs_core_policy_target_home acfs_core_policy_expected_binary_path acfs_core_policy_expected_bv_versioned_path acfs_core_policy_expected_binary_sha256 _acfs_core_policy_sha256_file _acfs_core_policy_version_output acfs_core_policy_admit_binary acfs_core_policy_admit_repair_source acfs_core_policy_enforce_installer_execution 2>/dev/null; then
        log_error "stack.brenner_bot: imported runtime policy function is not replaceable"
        return 1
    fi
    # shellcheck disable=SC1090  # exact generated sibling
    if ! builtin source "$canonical_contract"; then
        log_error "stack.brenner_bot: canonical runtime contract could not be loaded"
        return 1
    fi
    if [[ "${ACFS_R1_RUNTIME_PROFILE_ID:-}" != "R1-held-module-exclusion-runtime-v1" ]] || ! builtin declare -F acfs_r1_runtime_admit_entry >/dev/null 2>&1; then
        log_error "stack.brenner_bot: exact R1 runtime profile unavailable"
        return 1
    fi
    if ! acfs_r1_runtime_admit_entry direct "${module_id}"; then
        log_error "stack.brenner_bot: ${ACFS_R1_POLICY_REASON:-R1 runtime admission rejected the module}"
        return 1
    fi
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping stack.brenner_bot (not selected)"
        return 0
    fi
    log_step "Installing stack.brenner_bot"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.brenner_bot"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false
            local verified_installer_file=""
            local verified_installer_chmod_bin=""

                # Cleared per attempt so a stale reason from an earlier module can
                # never be misattributed to this one.
                ACFS_LAST_MODULE_FAILURE_REASON=""
            if acfs_security_init; then
                local known_installers_decl=""
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                known_installers_decl="$(declare -p KNOWN_INSTALLERS 2>/dev/null || true)"
                if [[ "$known_installers_decl" == declare\ -A* ]]; then
                    local tool="brenner_bot"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.brenner_bot: get_checksum failed for tool '$tool'"
                        ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if ! verified_installer_file="$(acfs_security_mktemp "/tmp/acfs-verified-installer.XXXXXX" 2>/dev/null)" || [[ -z "$verified_installer_file" ]]; then
                            log_error "stack.brenner_bot: failed to create verified installer staging file"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                            verified_installer_file=""
                        elif ! verify_checksum "$url" "$expected_sha256" "$tool" > "$verified_installer_file"; then
                            log_error "stack.brenner_bot: installer verification failed"
                            : "${ACFS_LAST_MODULE_FAILURE_REASON:=checksum}"
                        elif ! verified_installer_chmod_bin="$(acfs_generated_system_binary_path chmod 2>/dev/null)"; then
                            log_error "stack.brenner_bot: trusted chmod not found for verified installer staging"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        elif ! "$verified_installer_chmod_bin" 0444 "$verified_installer_file"; then
                            log_error "stack.brenner_bot: failed to make verified installer staging file read-only"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                        elif run_as_target_runner 'bash' "$verified_installer_file" '--skip-cass'; then
                            install_success=true
                        else
                            log_error "stack.brenner_bot: verified installer execution failed"
                            ACFS_LAST_MODULE_FAILURE_REASON="installer execution"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.brenner_bot: KNOWN_INSTALLERS[$tool] not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.brenner_bot: checksum for '$tool' not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                    fi
                else
                    log_error "stack.brenner_bot: KNOWN_INSTALLERS array not available"
                    ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                fi
            else
                log_error "stack.brenner_bot: acfs_security_init failed - check security.sh and checksums.yaml"
                ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
            fi
            if [[ -n "$verified_installer_file" ]]; then
                _acfs_remove_temp_files "$verified_installer_file"
                verified_installer_file=""
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.brenner_bot"
                false
            fi
        }; then
            log_warn "stack.brenner_bot: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.brenner_bot" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.brenner_bot"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: brenner --version || brenner --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_BRENNER_BOT'
brenner --version || brenner --help
INSTALL_STACK_BRENNER_BOT
        then
            log_warn "stack.brenner_bot: verify failed: brenner --version || brenner --help"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.brenner_bot" "verify failed: brenner --version || brenner --help"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.brenner_bot"
            fi
            return 0
        fi
    fi

    log_success "stack.brenner_bot installed"
}

# Remote Compilation Helper - transparent build offloading for AI coding agents
acfs_generated_install_stack_rch() {
    local module_id="stack.rch"
    local canonical_contract="${ACFS_GENERATED_SCRIPT_DIR}/../lib/contract.sh"
    # Rebind the exact sibling contract at every generated entry. Imported
    # shell functions and environment state are never commissioning authority.
    if [[ ! -f "$canonical_contract" || -L "$canonical_contract" ]]; then
        log_error "stack.rch: canonical runtime contract unavailable"
        return 1
    fi
    if ! builtin unset -f acfs_require_contract acfs_license_exclusion_profile_payload _acfs_license_profile_actual_sha256 acfs_license_policy_verify_profile acfs_license_policy_module_is_held acfs_license_policy_module_is_plain_mit_only acfs_license_policy_admit_entry acfs_license_clearance_requested acfs_license_clearance_verify acfs_license_clearance_active acfs_r1_runtime_profile_payload _acfs_r1_sha256_file _acfs_r1_profile_actual_sha256 _acfs_r1_runtime_root _acfs_r1_verify_bound_file acfs_r1_runtime_verify_profile acfs_r1_runtime_module_is_held acfs_r1_runtime_module_is_planned acfs_r1_runtime_admit_entry _acfs_r1_array_csv acfs_r1_runtime_prepare_selection acfs_r1_runtime_validate_plan acfs_core_policy_enforce acfs_core_policy_reason acfs_core_policy_contract _acfs_core_policy_target_home acfs_core_policy_expected_binary_path acfs_core_policy_expected_bv_versioned_path acfs_core_policy_expected_binary_sha256 _acfs_core_policy_sha256_file _acfs_core_policy_version_output acfs_core_policy_admit_binary acfs_core_policy_admit_repair_source acfs_core_policy_enforce_installer_execution 2>/dev/null; then
        log_error "stack.rch: imported runtime policy function is not replaceable"
        return 1
    fi
    # shellcheck disable=SC1090  # exact generated sibling
    if ! builtin source "$canonical_contract"; then
        log_error "stack.rch: canonical runtime contract could not be loaded"
        return 1
    fi
    if [[ "${ACFS_R1_RUNTIME_PROFILE_ID:-}" != "R1-held-module-exclusion-runtime-v1" ]] || ! builtin declare -F acfs_r1_runtime_admit_entry >/dev/null 2>&1; then
        log_error "stack.rch: exact R1 runtime profile unavailable"
        return 1
    fi
    if ! acfs_r1_runtime_admit_entry direct "${module_id}"; then
        log_error "stack.rch: ${ACFS_R1_POLICY_REASON:-R1 runtime admission rejected the module}"
        return 1
    fi
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping stack.rch (not selected)"
        return 0
    fi
    log_step "Installing stack.rch"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.rch"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false
            local verified_installer_file=""
            local verified_installer_chmod_bin=""

            # RCH release discovery and installer source fallback are mutable.
            # Build the exact approved source with its two canonical profiles.
            if [[ "$(uname -s 2>/dev/null)" == "Linux" ]]; then
                local rch_source_repo="https://github.com/Dicklesworthstone/remote_compilation_helper.git"
                local rch_source_commit="0a982fdee2ca5ce26791dd17b83285916a7b97f6"
                local rch_source_tree="368cc8c1426f6f7b30c505ffbc6ca9769a5d06d7"
                local rch_cargo_lock_sha256="c115964866335f4194dd83350f0a800f5af507a99e23943eef31812d79536e4a"
                local rch_cargo_toml_sha256="17112f2d581bf2916e515dda40fb048d983bb3154285a226fe6a09bef3e8ffc3"
                local rch_toolchain="nightly-2026-06-06"
                local rch_source_parent="$TARGET_HOME/.cache/acfs/source-builds"
                local rch_source_dir=""
                local rch_target=""
                local rch_binary=""
                local rchd_binary=""
                local rch_wkr_binary=""
                local rch_version=""
                local rchd_version=""
                local rch_wkr_version=""
                local rch_git_bin=""
                local rch_mkdir_bin=""
                local rch_mktemp_bin=""
                local rch_rm_bin=""
                local rch_sha256sum_bin=""
                local rch_cargo_bin="$TARGET_HOME/.cargo/bin/cargo"
                local rch_rustup_bin="$TARGET_HOME/.cargo/bin/rustup"

                case "$(uname -m 2>/dev/null || true)" in
                    x86_64|amd64) rch_target="x86_64-unknown-linux-gnu" ;;
                    aarch64|arm64) rch_target="aarch64-unknown-linux-gnu" ;;
                esac
                rch_git_bin="$(acfs_generated_system_binary_path git 2>/dev/null || true)"
                rch_mkdir_bin="$(acfs_generated_system_binary_path mkdir 2>/dev/null || true)"
                rch_mktemp_bin="$(acfs_generated_system_binary_path mktemp 2>/dev/null || true)"
                rch_rm_bin="$(acfs_generated_system_binary_path rm 2>/dev/null || true)"
                rch_sha256sum_bin="$(acfs_generated_system_binary_path sha256sum 2>/dev/null || true)"

                if [[ -z "$rch_target" || -z "$rch_git_bin" || -z "$rch_mkdir_bin" || -z "$rch_mktemp_bin" || -z "$rch_rm_bin" || -z "$rch_sha256sum_bin" || ! -x "$rch_cargo_bin" || ! -x "$rch_rustup_bin" ]]; then
                    log_error "stack.rch: exact source build prerequisites are unavailable"
                    ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                elif [[ "$TARGET_HOME" != /* || "$TARGET_HOME" == "/" || -L "$TARGET_HOME" || -L "$TARGET_HOME/.cache" || -L "$TARGET_HOME/.cache/acfs" || -L "$rch_source_parent" ]]; then
                    log_error "stack.rch: refusing source build through an invalid or symlinked target-home path"
                    ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                elif ! run_as_target "$rch_mkdir_bin" -p "$rch_source_parent"; then
                    log_error "stack.rch: failed to prepare the confined source-build directory"
                    ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                elif [[ ! -d "$rch_source_parent" || -L "$rch_source_parent" ]]; then
                    log_error "stack.rch: source-build directory is not a confined real directory"
                    ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                elif ! rch_source_dir="$(run_as_target "$rch_mktemp_bin" -d "$rch_source_parent/rch.XXXXXX" 2>/dev/null)"; then
                    log_error "stack.rch: failed to create the source-build staging directory"
                    ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                elif [[ "$rch_source_dir" != "$rch_source_parent"/rch.* || ! -d "$rch_source_dir" || -L "$rch_source_dir" ]]; then
                    log_error "stack.rch: source-build staging directory escaped its trusted template"
                    ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                elif (
                    set -euo pipefail
                    trap 'run_as_target "$rch_rm_bin" -rf -- "$rch_source_dir" >/dev/null 2>&1 || true' EXIT
                    run_as_target "$rch_git_bin" -c core.hooksPath=/dev/null clone --filter=blob:none --no-checkout "$rch_source_repo" "$rch_source_dir/src"
                    run_as_target "$rch_git_bin" -C "$rch_source_dir/src" -c core.hooksPath=/dev/null fetch --depth 1 origin "$rch_source_commit"
                    run_as_target "$rch_git_bin" -C "$rch_source_dir/src" -c core.hooksPath=/dev/null checkout --detach "$rch_source_commit"
                    [[ "$(run_as_target "$rch_git_bin" -C "$rch_source_dir/src" rev-parse HEAD)" == "$rch_source_commit" ]]
                    [[ "$(run_as_target "$rch_git_bin" -C "$rch_source_dir/src" rev-parse "HEAD^{tree}")" == "$rch_source_tree" ]]
                    [[ "$(run_as_target "$rch_sha256sum_bin" "$rch_source_dir/src/Cargo.lock" | awk 'NR == 1 { print $1 }')" == "$rch_cargo_lock_sha256" ]]
                    [[ "$(run_as_target "$rch_sha256sum_bin" "$rch_source_dir/src/Cargo.toml" | awk 'NR == 1 { print $1 }')" == "$rch_cargo_toml_sha256" ]]
                    [[ -z "$(run_as_target "$rch_git_bin" -C "$rch_source_dir/src" status --porcelain=v1 --untracked-files=all)" ]]
                    run_as_target "$rch_rustup_bin" toolchain install "$rch_toolchain" --profile minimal --no-self-update
                    run_as_target env RCH_GIT_COMMIT="$rch_source_commit" CARGO_BUILD_JOBS=1 RUSTFLAGS= CARGO_NET_GIT_FETCH_WITH_CLI=true "$rch_cargo_bin" +"$rch_toolchain" build --locked --jobs 1 --target "$rch_target" --profile wrapper-release --package rch --bin rch --manifest-path "$rch_source_dir/src/Cargo.toml" --target-dir "$rch_source_dir/target"
                    run_as_target env RCH_GIT_COMMIT="$rch_source_commit" CARGO_BUILD_JOBS=1 RUSTFLAGS= CARGO_NET_GIT_FETCH_WITH_CLI=true "$rch_cargo_bin" +"$rch_toolchain" build --locked --jobs 1 --target "$rch_target" --profile daemon-release --package rchd --package rch-wkr --manifest-path "$rch_source_dir/src/Cargo.toml" --target-dir "$rch_source_dir/target"
                    rch_binary="$rch_source_dir/target/$rch_target/wrapper-release/rch"
                    rchd_binary="$rch_source_dir/target/$rch_target/daemon-release/rchd"
                    rch_wkr_binary="$rch_source_dir/target/$rch_target/daemon-release/rch-wkr"
                    [[ -f "$rch_binary" && -x "$rch_binary" && ! -L "$rch_binary" ]]
                    [[ -f "$rchd_binary" && -x "$rchd_binary" && ! -L "$rchd_binary" ]]
                    [[ -f "$rch_wkr_binary" && -x "$rch_wkr_binary" && ! -L "$rch_wkr_binary" ]]
                    rch_version="$(run_as_target "$rch_binary" --version 2>/dev/null)"
                    rchd_version="$(run_as_target "$rchd_binary" --version 2>/dev/null)"
                    rch_wkr_version="$(run_as_target "$rch_wkr_binary" --version 2>/dev/null)"
                    [[ "$rch_version" == "rch 1.0.60 (commit 0a982fdee2ca)" ]]
                    [[ "$rchd_version" == "rchd 1.0.60 (commit 0a982fdee2ca)" ]]
                    [[ "$rch_wkr_version" == "rch-wkr 1.0.60 (commit 0a982fdee2ca)" ]]
                    acfs_install_executable_into_primary_bin "$rch_binary" rch
                    acfs_install_executable_into_primary_bin "$rchd_binary" rchd
                    acfs_install_executable_into_primary_bin "$rch_wkr_binary" rch-wkr
                ); then
                    install_success=true
                else
                    if [[ -n "$rch_source_dir" && "$rch_source_dir" == "$rch_source_parent"/rch.* && -d "$rch_source_dir" && ! -L "$rch_source_dir" ]]; then
                        run_as_target "$rch_rm_bin" -rf -- "$rch_source_dir" >/dev/null 2>&1 || true
                    fi
                    log_error "stack.rch: exact source build failed"
                    ACFS_LAST_MODULE_FAILURE_REASON="source build"
                fi
            else
                log_error "stack.rch: exact source commissioning is supported only on Linux"
                ACFS_LAST_MODULE_FAILURE_REASON="unsupported platform"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.rch"
                false
            fi
        }; then
            log_warn "stack.rch: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.rch" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.rch"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: test \"\$(rch --version 2>/dev/null)\" = \"rch 1.0.60 (commit 0a982fdee2ca)\" (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_RCH'
test "$(rch --version 2>/dev/null)" = "rch 1.0.60 (commit 0a982fdee2ca)"
INSTALL_STACK_RCH
        then
            log_warn "stack.rch: verify failed: test \"\$(rch --version 2>/dev/null)\" = \"rch 1.0.60 (commit 0a982fdee2ca)\""
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.rch" "verify failed: test \"\$(rch --version 2>/dev/null)\" = \"rch 1.0.60 (commit 0a982fdee2ca)\""
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.rch"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: test \"\$(rchd --version 2>/dev/null)\" = \"rchd 1.0.60 (commit 0a982fdee2ca)\" (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_RCH'
test "$(rchd --version 2>/dev/null)" = "rchd 1.0.60 (commit 0a982fdee2ca)"
INSTALL_STACK_RCH
        then
            log_warn "stack.rch: verify failed: test \"\$(rchd --version 2>/dev/null)\" = \"rchd 1.0.60 (commit 0a982fdee2ca)\""
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.rch" "verify failed: test \"\$(rchd --version 2>/dev/null)\" = \"rchd 1.0.60 (commit 0a982fdee2ca)\""
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.rch"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: test \"\$(rch-wkr --version 2>/dev/null)\" = \"rch-wkr 1.0.60 (commit 0a982fdee2ca)\" (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_RCH'
test "$(rch-wkr --version 2>/dev/null)" = "rch-wkr 1.0.60 (commit 0a982fdee2ca)"
INSTALL_STACK_RCH
        then
            log_warn "stack.rch: verify failed: test \"\$(rch-wkr --version 2>/dev/null)\" = \"rch-wkr 1.0.60 (commit 0a982fdee2ca)\""
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.rch" "verify failed: test \"\$(rch-wkr --version 2>/dev/null)\" = \"rch-wkr 1.0.60 (commit 0a982fdee2ca)\""
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.rch"
            fi
            return 0
        fi
    fi

    log_success "stack.rch installed"
}

# WezTerm Automata (wa) - terminal automation and orchestration for AI agents
acfs_generated_install_stack_wezterm_automata() {
    local module_id="stack.wezterm_automata"
    local canonical_contract="${ACFS_GENERATED_SCRIPT_DIR}/../lib/contract.sh"
    # Rebind the exact sibling contract at every generated entry. Imported
    # shell functions and environment state are never commissioning authority.
    if [[ ! -f "$canonical_contract" || -L "$canonical_contract" ]]; then
        log_error "stack.wezterm_automata: canonical runtime contract unavailable"
        return 1
    fi
    if ! builtin unset -f acfs_require_contract acfs_license_exclusion_profile_payload _acfs_license_profile_actual_sha256 acfs_license_policy_verify_profile acfs_license_policy_module_is_held acfs_license_policy_module_is_plain_mit_only acfs_license_policy_admit_entry acfs_license_clearance_requested acfs_license_clearance_verify acfs_license_clearance_active acfs_r1_runtime_profile_payload _acfs_r1_sha256_file _acfs_r1_profile_actual_sha256 _acfs_r1_runtime_root _acfs_r1_verify_bound_file acfs_r1_runtime_verify_profile acfs_r1_runtime_module_is_held acfs_r1_runtime_module_is_planned acfs_r1_runtime_admit_entry _acfs_r1_array_csv acfs_r1_runtime_prepare_selection acfs_r1_runtime_validate_plan acfs_core_policy_enforce acfs_core_policy_reason acfs_core_policy_contract _acfs_core_policy_target_home acfs_core_policy_expected_binary_path acfs_core_policy_expected_bv_versioned_path acfs_core_policy_expected_binary_sha256 _acfs_core_policy_sha256_file _acfs_core_policy_version_output acfs_core_policy_admit_binary acfs_core_policy_admit_repair_source acfs_core_policy_enforce_installer_execution 2>/dev/null; then
        log_error "stack.wezterm_automata: imported runtime policy function is not replaceable"
        return 1
    fi
    # shellcheck disable=SC1090  # exact generated sibling
    if ! builtin source "$canonical_contract"; then
        log_error "stack.wezterm_automata: canonical runtime contract could not be loaded"
        return 1
    fi
    if [[ "${ACFS_R1_RUNTIME_PROFILE_ID:-}" != "R1-held-module-exclusion-runtime-v1" ]] || ! builtin declare -F acfs_r1_runtime_admit_entry >/dev/null 2>&1; then
        log_error "stack.wezterm_automata: exact R1 runtime profile unavailable"
        return 1
    fi
    if ! acfs_r1_runtime_admit_entry direct "${module_id}"; then
        log_error "stack.wezterm_automata: ${ACFS_R1_POLICY_REASON:-R1 runtime admission rejected the module}"
        return 1
    fi
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping stack.wezterm_automata (not selected)"
        return 0
    fi
    log_step "Installing stack.wezterm_automata"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: trap 'rm -rf \"\$WA_TMP\"' EXIT (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_WEZTERM_AUTOMATA'
WA_TMP="$(mktemp -d "${TMPDIR:-/tmp}/wa_build.XXXXXX")"
trap 'rm -rf "$WA_TMP"' EXIT
cd "$WA_TMP"
git clone --depth 1 https://github.com/Dicklesworthstone/wezterm_automata.git .
cargo build --release -p wa
cp target/release/wa ~/.cargo/bin/
rm -rf "$WA_TMP"
INSTALL_STACK_WEZTERM_AUTOMATA
        then
            log_warn "stack.wezterm_automata: install command failed: trap 'rm -rf \"\$WA_TMP\"' EXIT"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.wezterm_automata" "install command failed: trap 'rm -rf \"\$WA_TMP\"' EXIT"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.wezterm_automata"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: wa --version || wa --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_WEZTERM_AUTOMATA'
wa --version || wa --help
INSTALL_STACK_WEZTERM_AUTOMATA
        then
            log_warn "stack.wezterm_automata: verify failed: wa --version || wa --help"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.wezterm_automata" "verify failed: wa --version || wa --help"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.wezterm_automata"
            fi
            return 0
        fi
    fi

    log_success "stack.wezterm_automata installed"
}

# System Resource Protection Script - ananicy-cpp rules + TUI monitor for responsive dev workstations
acfs_generated_install_stack_srps() {
    local module_id="stack.srps"
    local canonical_contract="${ACFS_GENERATED_SCRIPT_DIR}/../lib/contract.sh"
    # Rebind the exact sibling contract at every generated entry. Imported
    # shell functions and environment state are never commissioning authority.
    if [[ ! -f "$canonical_contract" || -L "$canonical_contract" ]]; then
        log_error "stack.srps: canonical runtime contract unavailable"
        return 1
    fi
    if ! builtin unset -f acfs_require_contract acfs_license_exclusion_profile_payload _acfs_license_profile_actual_sha256 acfs_license_policy_verify_profile acfs_license_policy_module_is_held acfs_license_policy_module_is_plain_mit_only acfs_license_policy_admit_entry acfs_license_clearance_requested acfs_license_clearance_verify acfs_license_clearance_active acfs_r1_runtime_profile_payload _acfs_r1_sha256_file _acfs_r1_profile_actual_sha256 _acfs_r1_runtime_root _acfs_r1_verify_bound_file acfs_r1_runtime_verify_profile acfs_r1_runtime_module_is_held acfs_r1_runtime_module_is_planned acfs_r1_runtime_admit_entry _acfs_r1_array_csv acfs_r1_runtime_prepare_selection acfs_r1_runtime_validate_plan acfs_core_policy_enforce acfs_core_policy_reason acfs_core_policy_contract _acfs_core_policy_target_home acfs_core_policy_expected_binary_path acfs_core_policy_expected_bv_versioned_path acfs_core_policy_expected_binary_sha256 _acfs_core_policy_sha256_file _acfs_core_policy_version_output acfs_core_policy_admit_binary acfs_core_policy_admit_repair_source acfs_core_policy_enforce_installer_execution 2>/dev/null; then
        log_error "stack.srps: imported runtime policy function is not replaceable"
        return 1
    fi
    # shellcheck disable=SC1090  # exact generated sibling
    if ! builtin source "$canonical_contract"; then
        log_error "stack.srps: canonical runtime contract could not be loaded"
        return 1
    fi
    if [[ "${ACFS_R1_RUNTIME_PROFILE_ID:-}" != "R1-held-module-exclusion-runtime-v1" ]] || ! builtin declare -F acfs_r1_runtime_admit_entry >/dev/null 2>&1; then
        log_error "stack.srps: exact R1 runtime profile unavailable"
        return 1
    fi
    if ! acfs_r1_runtime_admit_entry direct "${module_id}"; then
        log_error "stack.srps: ${ACFS_R1_POLICY_REASON:-R1 runtime admission rejected the module}"
        return 1
    fi
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping stack.srps (not selected)"
        return 0
    fi
    log_step "Installing stack.srps"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.srps"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false
            local verified_installer_file=""
            local verified_installer_chmod_bin=""

                # Cleared per attempt so a stale reason from an earlier module can
                # never be misattributed to this one.
                ACFS_LAST_MODULE_FAILURE_REASON=""
            if acfs_security_init; then
                local known_installers_decl=""
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                known_installers_decl="$(declare -p KNOWN_INSTALLERS 2>/dev/null || true)"
                if [[ "$known_installers_decl" == declare\ -A* ]]; then
                    local tool="srps"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.srps: get_checksum failed for tool '$tool'"
                        ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if ! verified_installer_file="$(acfs_security_mktemp "/tmp/acfs-verified-installer.XXXXXX" 2>/dev/null)" || [[ -z "$verified_installer_file" ]]; then
                            log_error "stack.srps: failed to create verified installer staging file"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                            verified_installer_file=""
                        elif ! verify_checksum "$url" "$expected_sha256" "$tool" > "$verified_installer_file"; then
                            log_error "stack.srps: installer verification failed"
                            : "${ACFS_LAST_MODULE_FAILURE_REASON:=checksum}"
                        elif ! verified_installer_chmod_bin="$(acfs_generated_system_binary_path chmod 2>/dev/null)"; then
                            log_error "stack.srps: trusted chmod not found for verified installer staging"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        elif ! "$verified_installer_chmod_bin" 0444 "$verified_installer_file"; then
                            log_error "stack.srps: failed to make verified installer staging file read-only"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                        elif run_as_target_runner 'env' 'PATH=/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/sbin:/usr/local/bin' 'bash' "$verified_installer_file" '--install'; then
                            install_success=true
                        else
                            log_error "stack.srps: verified installer execution failed"
                            ACFS_LAST_MODULE_FAILURE_REASON="installer execution"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.srps: KNOWN_INSTALLERS[$tool] not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.srps: checksum for '$tool' not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                    fi
                else
                    log_error "stack.srps: KNOWN_INSTALLERS array not available"
                    ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                fi
            else
                log_error "stack.srps: acfs_security_init failed - check security.sh and checksums.yaml"
                ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
            fi
            if [[ -n "$verified_installer_file" ]]; then
                _acfs_remove_temp_files "$verified_installer_file"
                verified_installer_file=""
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.srps"
                false
            fi
        }; then
            log_warn "stack.srps: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.srps" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.srps"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: test -x /usr/local/bin/sysmoni (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_SRPS'
test -x /usr/local/bin/sysmoni
INSTALL_STACK_SRPS
        then
            log_warn "stack.srps: verify failed: test -x /usr/local/bin/sysmoni"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.srps" "verify failed: test -x /usr/local/bin/sysmoni"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.srps"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: systemctl is-active ananicy-cpp (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_SRPS'
systemctl is-active ananicy-cpp
INSTALL_STACK_SRPS
        then
            log_warn "stack.srps: verify failed: systemctl is-active ananicy-cpp"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.srps" "verify failed: systemctl is-active ananicy-cpp"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.srps"
            fi
            return 0
        fi
    fi

    log_success "stack.srps installed"
}

# Two-tier hybrid local search — lexical (BM25) + semantic retrieval with progressive delivery (fsfs)
acfs_generated_install_stack_frankensearch() {
    local module_id="stack.frankensearch"
    local canonical_contract="${ACFS_GENERATED_SCRIPT_DIR}/../lib/contract.sh"
    # Rebind the exact sibling contract at every generated entry. Imported
    # shell functions and environment state are never commissioning authority.
    if [[ ! -f "$canonical_contract" || -L "$canonical_contract" ]]; then
        log_error "stack.frankensearch: canonical runtime contract unavailable"
        return 1
    fi
    if ! builtin unset -f acfs_require_contract acfs_license_exclusion_profile_payload _acfs_license_profile_actual_sha256 acfs_license_policy_verify_profile acfs_license_policy_module_is_held acfs_license_policy_module_is_plain_mit_only acfs_license_policy_admit_entry acfs_license_clearance_requested acfs_license_clearance_verify acfs_license_clearance_active acfs_r1_runtime_profile_payload _acfs_r1_sha256_file _acfs_r1_profile_actual_sha256 _acfs_r1_runtime_root _acfs_r1_verify_bound_file acfs_r1_runtime_verify_profile acfs_r1_runtime_module_is_held acfs_r1_runtime_module_is_planned acfs_r1_runtime_admit_entry _acfs_r1_array_csv acfs_r1_runtime_prepare_selection acfs_r1_runtime_validate_plan acfs_core_policy_enforce acfs_core_policy_reason acfs_core_policy_contract _acfs_core_policy_target_home acfs_core_policy_expected_binary_path acfs_core_policy_expected_bv_versioned_path acfs_core_policy_expected_binary_sha256 _acfs_core_policy_sha256_file _acfs_core_policy_version_output acfs_core_policy_admit_binary acfs_core_policy_admit_repair_source acfs_core_policy_enforce_installer_execution 2>/dev/null; then
        log_error "stack.frankensearch: imported runtime policy function is not replaceable"
        return 1
    fi
    # shellcheck disable=SC1090  # exact generated sibling
    if ! builtin source "$canonical_contract"; then
        log_error "stack.frankensearch: canonical runtime contract could not be loaded"
        return 1
    fi
    if [[ "${ACFS_R1_RUNTIME_PROFILE_ID:-}" != "R1-held-module-exclusion-runtime-v1" ]] || ! builtin declare -F acfs_r1_runtime_admit_entry >/dev/null 2>&1; then
        log_error "stack.frankensearch: exact R1 runtime profile unavailable"
        return 1
    fi
    if ! acfs_r1_runtime_admit_entry direct "${module_id}"; then
        log_error "stack.frankensearch: ${ACFS_R1_POLICY_REASON:-R1 runtime admission rejected the module}"
        return 1
    fi
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping stack.frankensearch (not selected)"
        return 0
    fi
    log_step "Installing stack.frankensearch"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.frankensearch"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false
            local verified_installer_file=""
            local verified_installer_chmod_bin=""

            # Cleared per attempt so a stale reason from an earlier module can
            # never be misattributed to this one.
            ACFS_LAST_MODULE_FAILURE_REASON=""
            if acfs_security_init; then
                local known_installers_decl=""
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                known_installers_decl="$(declare -p KNOWN_INSTALLERS 2>/dev/null || true)"
                if [[ "$known_installers_decl" == declare\ -A* ]]; then
                    local tool="fsfs"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.frankensearch: get_checksum failed for tool '$tool'"
                        ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        local -a fsfs_installer_args=('--easy-mode')
                        local fsfs_arch=""
                        local fsfs_target=""
                        local fsfs_version=""
                        local fsfs_version_bare=""
                        local fsfs_artifact_url=""
                        local fsfs_checksum=""
                        local fsfs_candidate=""
                        local -a fsfs_candidates=()
                        local fsfs_can_run=true

                        if [[ "$(uname -s 2>/dev/null)" == "Linux" ]]; then
                            fsfs_arch="$(uname -m 2>/dev/null || true)"
                            case "$fsfs_arch" in
                                x86_64|amd64) fsfs_target="x86_64-unknown-linux-musl" ;;
                                aarch64|arm64) fsfs_target="aarch64-unknown-linux-musl" ;;
                                *) fsfs_target="" ;;
                            esac

                            if [[ -z "$fsfs_target" ]]; then
                                fsfs_can_run=false
                                log_warn "stack.frankensearch: FrankenSearch Linux binary artifact unavailable for this architecture; skipping source-build fallback"
                            else
                                if [[ -n "${ACFS_FSFS_VERSION:-}" ]]; then
                                    fsfs_candidates+=("$ACFS_FSFS_VERSION")
                                else
                                    while IFS= read -r fsfs_candidate; do
                                        [[ -n "$fsfs_candidate" ]] || continue
                                        case " ${fsfs_candidates[*]} " in
                                            *" $fsfs_candidate "*) ;;
                                            *) fsfs_candidates+=("$fsfs_candidate") ;;
                                        esac
                                    done < <(acfs_curl --connect-timeout 30 --max-time 60 -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/Dicklesworthstone/frankensearch/releases?per_page=10" 2>/dev/null | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' || true)

                                    fsfs_candidate="$(acfs_curl --connect-timeout 30 --max-time 60 -o /dev/null -w '%{url_effective}' "https://github.com/Dicklesworthstone/frankensearch/releases/latest" 2>/dev/null | sed -E 's|.*/tag/||' || true)"
                                    if [[ "$fsfs_candidate" =~ ^v[0-9][A-Za-z0-9._-]*$ ]]; then
                                        case " ${fsfs_candidates[*]} " in
                                            *" $fsfs_candidate "*) ;;
                                            *) fsfs_candidates+=("$fsfs_candidate") ;;
                                        esac
                                    fi
                                fi

                                if [[ ${#fsfs_candidates[@]} -eq 0 ]]; then
                                    fsfs_can_run=false
                                    log_warn "stack.frankensearch: unable to resolve FrankenSearch release; skipping source-build fallback"
                                else
                                    for fsfs_version in "${fsfs_candidates[@]}"; do
                                        [[ "$fsfs_version" =~ ^v[0-9][A-Za-z0-9._-]*$ ]] || continue
                                        fsfs_version_bare="${fsfs_version#v}"
                                        fsfs_artifact_url="https://github.com/Dicklesworthstone/frankensearch/releases/download/${fsfs_version}/fsfs-lite-${fsfs_version_bare}-${fsfs_target}.tar.xz"
                                        fsfs_checksum="$(acfs_curl --connect-timeout 30 --max-time 60 "${fsfs_artifact_url}.sha256" 2>/dev/null | awk 'NR == 1 { print $1 }' || true)"
                                        if [[ "$fsfs_checksum" =~ ^[0-9A-Fa-f]{64}$ ]]; then
                                            fsfs_installer_args+=(
                                                --version "$fsfs_version"
                                                --artifact-url "$fsfs_artifact_url"
                                                --checksum "${fsfs_checksum,,}"
                                            )
                                            log_info "stack.frankensearch: using FrankenSearch Linux lite artifact $fsfs_artifact_url"
                                            break
                                        fi
                                        log_warn "stack.frankensearch: FrankenSearch lite artifact checksum unavailable for $fsfs_version"
                                    done
                                    if [[ ! "$fsfs_checksum" =~ ^[0-9A-Fa-f]{64}$ ]]; then
                                        fsfs_can_run=false
                                        log_warn "stack.frankensearch: unable to resolve a FrankenSearch lite artifact with a checksum; skipping source-build fallback"
                                    fi
                                fi
                            fi
                        fi

                        if [[ "$fsfs_can_run" == "true" ]]; then
                            if ! verified_installer_file="$(acfs_security_mktemp "/tmp/acfs-verified-installer.XXXXXX" 2>/dev/null)" || [[ -z "$verified_installer_file" ]]; then
                                log_error "stack.frankensearch: failed to create verified installer staging file"
                                ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                                verified_installer_file=""
                            elif ! verify_checksum "$url" "$expected_sha256" "$tool" > "$verified_installer_file"; then
                                log_error "stack.frankensearch: installer verification failed"
                                : "${ACFS_LAST_MODULE_FAILURE_REASON:=checksum}"
                            elif ! verified_installer_chmod_bin="$(acfs_generated_system_binary_path chmod 2>/dev/null)"; then
                                log_error "stack.frankensearch: trusted chmod not found for verified installer staging"
                                ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                            elif ! "$verified_installer_chmod_bin" 0444 "$verified_installer_file"; then
                                log_error "stack.frankensearch: failed to make verified installer staging file read-only"
                                ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                            elif run_as_target_runner 'bash' "$verified_installer_file" "${fsfs_installer_args[@]}"; then
                                install_success=true
                            else
                                log_error "stack.frankensearch: verified installer execution failed"
                                ACFS_LAST_MODULE_FAILURE_REASON="installer execution"
                            fi
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.frankensearch: KNOWN_INSTALLERS[$tool] not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.frankensearch: checksum for '$tool' not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                    fi
                else
                    log_error "stack.frankensearch: KNOWN_INSTALLERS array not available"
                    ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                fi
            else
                log_error "stack.frankensearch: acfs_security_init failed - check security.sh and checksums.yaml"
                ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
            fi
            if [[ -n "$verified_installer_file" ]]; then
                _acfs_remove_temp_files "$verified_installer_file"
                verified_installer_file=""
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.frankensearch"
                false
            fi
        }; then
            log_warn "stack.frankensearch: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.frankensearch" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.frankensearch"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: fsfs version || fsfs --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_FRANKENSEARCH'
fsfs version || fsfs --help
INSTALL_STACK_FRANKENSEARCH
        then
            log_warn "stack.frankensearch: verify failed: fsfs version || fsfs --help"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.frankensearch" "verify failed: fsfs version || fsfs --help"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.frankensearch"
            fi
            return 0
        fi
    fi

    log_success "stack.frankensearch installed"
}

# Cross-platform disk-pressure defense for AI coding workloads (sbh)
acfs_generated_install_stack_storage_ballast_helper() {
    local module_id="stack.storage_ballast_helper"
    local canonical_contract="${ACFS_GENERATED_SCRIPT_DIR}/../lib/contract.sh"
    # Rebind the exact sibling contract at every generated entry. Imported
    # shell functions and environment state are never commissioning authority.
    if [[ ! -f "$canonical_contract" || -L "$canonical_contract" ]]; then
        log_error "stack.storage_ballast_helper: canonical runtime contract unavailable"
        return 1
    fi
    if ! builtin unset -f acfs_require_contract acfs_license_exclusion_profile_payload _acfs_license_profile_actual_sha256 acfs_license_policy_verify_profile acfs_license_policy_module_is_held acfs_license_policy_module_is_plain_mit_only acfs_license_policy_admit_entry acfs_license_clearance_requested acfs_license_clearance_verify acfs_license_clearance_active acfs_r1_runtime_profile_payload _acfs_r1_sha256_file _acfs_r1_profile_actual_sha256 _acfs_r1_runtime_root _acfs_r1_verify_bound_file acfs_r1_runtime_verify_profile acfs_r1_runtime_module_is_held acfs_r1_runtime_module_is_planned acfs_r1_runtime_admit_entry _acfs_r1_array_csv acfs_r1_runtime_prepare_selection acfs_r1_runtime_validate_plan acfs_core_policy_enforce acfs_core_policy_reason acfs_core_policy_contract _acfs_core_policy_target_home acfs_core_policy_expected_binary_path acfs_core_policy_expected_bv_versioned_path acfs_core_policy_expected_binary_sha256 _acfs_core_policy_sha256_file _acfs_core_policy_version_output acfs_core_policy_admit_binary acfs_core_policy_admit_repair_source acfs_core_policy_enforce_installer_execution 2>/dev/null; then
        log_error "stack.storage_ballast_helper: imported runtime policy function is not replaceable"
        return 1
    fi
    # shellcheck disable=SC1090  # exact generated sibling
    if ! builtin source "$canonical_contract"; then
        log_error "stack.storage_ballast_helper: canonical runtime contract could not be loaded"
        return 1
    fi
    if [[ "${ACFS_R1_RUNTIME_PROFILE_ID:-}" != "R1-held-module-exclusion-runtime-v1" ]] || ! builtin declare -F acfs_r1_runtime_admit_entry >/dev/null 2>&1; then
        log_error "stack.storage_ballast_helper: exact R1 runtime profile unavailable"
        return 1
    fi
    if ! acfs_r1_runtime_admit_entry direct "${module_id}"; then
        log_error "stack.storage_ballast_helper: ${ACFS_R1_POLICY_REASON:-R1 runtime admission rejected the module}"
        return 1
    fi
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping stack.storage_ballast_helper (not selected)"
        return 0
    fi
    log_step "Installing stack.storage_ballast_helper"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.storage_ballast_helper"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false
            local verified_installer_file=""
            local verified_installer_chmod_bin=""

                # Cleared per attempt so a stale reason from an earlier module can
                # never be misattributed to this one.
                ACFS_LAST_MODULE_FAILURE_REASON=""
            if acfs_security_init; then
                local known_installers_decl=""
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                known_installers_decl="$(declare -p KNOWN_INSTALLERS 2>/dev/null || true)"
                if [[ "$known_installers_decl" == declare\ -A* ]]; then
                    local tool="sbh"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.storage_ballast_helper: get_checksum failed for tool '$tool'"
                        ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if ! verified_installer_file="$(acfs_security_mktemp "/tmp/acfs-verified-installer.XXXXXX" 2>/dev/null)" || [[ -z "$verified_installer_file" ]]; then
                            log_error "stack.storage_ballast_helper: failed to create verified installer staging file"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                            verified_installer_file=""
                        elif ! verify_checksum "$url" "$expected_sha256" "$tool" > "$verified_installer_file"; then
                            log_error "stack.storage_ballast_helper: installer verification failed"
                            : "${ACFS_LAST_MODULE_FAILURE_REASON:=checksum}"
                        elif ! verified_installer_chmod_bin="$(acfs_generated_system_binary_path chmod 2>/dev/null)"; then
                            log_error "stack.storage_ballast_helper: trusted chmod not found for verified installer staging"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        elif ! "$verified_installer_chmod_bin" 0444 "$verified_installer_file"; then
                            log_error "stack.storage_ballast_helper: failed to make verified installer staging file read-only"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                        elif run_as_target_runner 'bash' "$verified_installer_file"; then
                            install_success=true
                        else
                            log_error "stack.storage_ballast_helper: verified installer execution failed"
                            ACFS_LAST_MODULE_FAILURE_REASON="installer execution"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.storage_ballast_helper: KNOWN_INSTALLERS[$tool] not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.storage_ballast_helper: checksum for '$tool' not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                    fi
                else
                    log_error "stack.storage_ballast_helper: KNOWN_INSTALLERS array not available"
                    ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                fi
            else
                log_error "stack.storage_ballast_helper: acfs_security_init failed - check security.sh and checksums.yaml"
                ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
            fi
            if [[ -n "$verified_installer_file" ]]; then
                _acfs_remove_temp_files "$verified_installer_file"
                verified_installer_file=""
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.storage_ballast_helper"
                false
            fi
        }; then
            log_warn "stack.storage_ballast_helper: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.storage_ballast_helper" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.storage_ballast_helper"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: command -v sbh (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_STORAGE_BALLAST_HELPER'
command -v sbh
INSTALL_STACK_STORAGE_BALLAST_HELPER
        then
            log_warn "stack.storage_ballast_helper: verify failed: command -v sbh"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.storage_ballast_helper" "verify failed: command -v sbh"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.storage_ballast_helper"
            fi
            return 0
        fi
    fi

    log_success "stack.storage_ballast_helper installed"
}

# Cross-provider AI coding session resumption — convert and resume sessions across providers (casr)
acfs_generated_install_stack_cross_agent_session_resumer() {
    local module_id="stack.cross_agent_session_resumer"
    local canonical_contract="${ACFS_GENERATED_SCRIPT_DIR}/../lib/contract.sh"
    # Rebind the exact sibling contract at every generated entry. Imported
    # shell functions and environment state are never commissioning authority.
    if [[ ! -f "$canonical_contract" || -L "$canonical_contract" ]]; then
        log_error "stack.cross_agent_session_resumer: canonical runtime contract unavailable"
        return 1
    fi
    if ! builtin unset -f acfs_require_contract acfs_license_exclusion_profile_payload _acfs_license_profile_actual_sha256 acfs_license_policy_verify_profile acfs_license_policy_module_is_held acfs_license_policy_module_is_plain_mit_only acfs_license_policy_admit_entry acfs_license_clearance_requested acfs_license_clearance_verify acfs_license_clearance_active acfs_r1_runtime_profile_payload _acfs_r1_sha256_file _acfs_r1_profile_actual_sha256 _acfs_r1_runtime_root _acfs_r1_verify_bound_file acfs_r1_runtime_verify_profile acfs_r1_runtime_module_is_held acfs_r1_runtime_module_is_planned acfs_r1_runtime_admit_entry _acfs_r1_array_csv acfs_r1_runtime_prepare_selection acfs_r1_runtime_validate_plan acfs_core_policy_enforce acfs_core_policy_reason acfs_core_policy_contract _acfs_core_policy_target_home acfs_core_policy_expected_binary_path acfs_core_policy_expected_bv_versioned_path acfs_core_policy_expected_binary_sha256 _acfs_core_policy_sha256_file _acfs_core_policy_version_output acfs_core_policy_admit_binary acfs_core_policy_admit_repair_source acfs_core_policy_enforce_installer_execution 2>/dev/null; then
        log_error "stack.cross_agent_session_resumer: imported runtime policy function is not replaceable"
        return 1
    fi
    # shellcheck disable=SC1090  # exact generated sibling
    if ! builtin source "$canonical_contract"; then
        log_error "stack.cross_agent_session_resumer: canonical runtime contract could not be loaded"
        return 1
    fi
    if [[ "${ACFS_R1_RUNTIME_PROFILE_ID:-}" != "R1-held-module-exclusion-runtime-v1" ]] || ! builtin declare -F acfs_r1_runtime_admit_entry >/dev/null 2>&1; then
        log_error "stack.cross_agent_session_resumer: exact R1 runtime profile unavailable"
        return 1
    fi
    if ! acfs_r1_runtime_admit_entry direct "${module_id}"; then
        log_error "stack.cross_agent_session_resumer: ${ACFS_R1_POLICY_REASON:-R1 runtime admission rejected the module}"
        return 1
    fi
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping stack.cross_agent_session_resumer (not selected)"
        return 0
    fi
    log_step "Installing stack.cross_agent_session_resumer"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.cross_agent_session_resumer"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false
            local verified_installer_file=""
            local verified_installer_chmod_bin=""

                # Cleared per attempt so a stale reason from an earlier module can
                # never be misattributed to this one.
                ACFS_LAST_MODULE_FAILURE_REASON=""
            if acfs_security_init; then
                local known_installers_decl=""
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                known_installers_decl="$(declare -p KNOWN_INSTALLERS 2>/dev/null || true)"
                if [[ "$known_installers_decl" == declare\ -A* ]]; then
                    local tool="casr"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.cross_agent_session_resumer: get_checksum failed for tool '$tool'"
                        ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if ! verified_installer_file="$(acfs_security_mktemp "/tmp/acfs-verified-installer.XXXXXX" 2>/dev/null)" || [[ -z "$verified_installer_file" ]]; then
                            log_error "stack.cross_agent_session_resumer: failed to create verified installer staging file"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                            verified_installer_file=""
                        elif ! verify_checksum "$url" "$expected_sha256" "$tool" > "$verified_installer_file"; then
                            log_error "stack.cross_agent_session_resumer: installer verification failed"
                            : "${ACFS_LAST_MODULE_FAILURE_REASON:=checksum}"
                        elif ! verified_installer_chmod_bin="$(acfs_generated_system_binary_path chmod 2>/dev/null)"; then
                            log_error "stack.cross_agent_session_resumer: trusted chmod not found for verified installer staging"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        elif ! "$verified_installer_chmod_bin" 0444 "$verified_installer_file"; then
                            log_error "stack.cross_agent_session_resumer: failed to make verified installer staging file read-only"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                        elif run_as_target_runner 'bash' "$verified_installer_file"; then
                            install_success=true
                        else
                            log_error "stack.cross_agent_session_resumer: verified installer execution failed"
                            ACFS_LAST_MODULE_FAILURE_REASON="installer execution"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.cross_agent_session_resumer: KNOWN_INSTALLERS[$tool] not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.cross_agent_session_resumer: checksum for '$tool' not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                    fi
                else
                    log_error "stack.cross_agent_session_resumer: KNOWN_INSTALLERS array not available"
                    ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                fi
            else
                log_error "stack.cross_agent_session_resumer: acfs_security_init failed - check security.sh and checksums.yaml"
                ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
            fi
            if [[ -n "$verified_installer_file" ]]; then
                _acfs_remove_temp_files "$verified_installer_file"
                verified_installer_file=""
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.cross_agent_session_resumer"
                false
            fi
        }; then
            log_warn "stack.cross_agent_session_resumer: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.cross_agent_session_resumer" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.cross_agent_session_resumer"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: casr providers || casr --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_CROSS_AGENT_SESSION_RESUMER'
casr providers || casr --help
INSTALL_STACK_CROSS_AGENT_SESSION_RESUMER
        then
            log_warn "stack.cross_agent_session_resumer: verify failed: casr providers || casr --help"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.cross_agent_session_resumer" "verify failed: casr providers || casr --help"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.cross_agent_session_resumer"
            fi
            return 0
        fi
    fi

    log_success "stack.cross_agent_session_resumer installed"
}

# Fallback release infrastructure — local builds via act when GitHub Actions is throttled (dsr)
acfs_generated_install_stack_doodlestein_self_releaser() {
    local module_id="stack.doodlestein_self_releaser"
    local canonical_contract="${ACFS_GENERATED_SCRIPT_DIR}/../lib/contract.sh"
    # Rebind the exact sibling contract at every generated entry. Imported
    # shell functions and environment state are never commissioning authority.
    if [[ ! -f "$canonical_contract" || -L "$canonical_contract" ]]; then
        log_error "stack.doodlestein_self_releaser: canonical runtime contract unavailable"
        return 1
    fi
    if ! builtin unset -f acfs_require_contract acfs_license_exclusion_profile_payload _acfs_license_profile_actual_sha256 acfs_license_policy_verify_profile acfs_license_policy_module_is_held acfs_license_policy_module_is_plain_mit_only acfs_license_policy_admit_entry acfs_license_clearance_requested acfs_license_clearance_verify acfs_license_clearance_active acfs_r1_runtime_profile_payload _acfs_r1_sha256_file _acfs_r1_profile_actual_sha256 _acfs_r1_runtime_root _acfs_r1_verify_bound_file acfs_r1_runtime_verify_profile acfs_r1_runtime_module_is_held acfs_r1_runtime_module_is_planned acfs_r1_runtime_admit_entry _acfs_r1_array_csv acfs_r1_runtime_prepare_selection acfs_r1_runtime_validate_plan acfs_core_policy_enforce acfs_core_policy_reason acfs_core_policy_contract _acfs_core_policy_target_home acfs_core_policy_expected_binary_path acfs_core_policy_expected_bv_versioned_path acfs_core_policy_expected_binary_sha256 _acfs_core_policy_sha256_file _acfs_core_policy_version_output acfs_core_policy_admit_binary acfs_core_policy_admit_repair_source acfs_core_policy_enforce_installer_execution 2>/dev/null; then
        log_error "stack.doodlestein_self_releaser: imported runtime policy function is not replaceable"
        return 1
    fi
    # shellcheck disable=SC1090  # exact generated sibling
    if ! builtin source "$canonical_contract"; then
        log_error "stack.doodlestein_self_releaser: canonical runtime contract could not be loaded"
        return 1
    fi
    if [[ "${ACFS_R1_RUNTIME_PROFILE_ID:-}" != "R1-held-module-exclusion-runtime-v1" ]] || ! builtin declare -F acfs_r1_runtime_admit_entry >/dev/null 2>&1; then
        log_error "stack.doodlestein_self_releaser: exact R1 runtime profile unavailable"
        return 1
    fi
    if ! acfs_r1_runtime_admit_entry direct "${module_id}"; then
        log_error "stack.doodlestein_self_releaser: ${ACFS_R1_POLICY_REASON:-R1 runtime admission rejected the module}"
        return 1
    fi
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping stack.doodlestein_self_releaser (not selected)"
        return 0
    fi
    log_step "Installing stack.doodlestein_self_releaser"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.doodlestein_self_releaser"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false
            local verified_installer_file=""
            local verified_installer_chmod_bin=""

                # Cleared per attempt so a stale reason from an earlier module can
                # never be misattributed to this one.
                ACFS_LAST_MODULE_FAILURE_REASON=""
            if acfs_security_init; then
                local known_installers_decl=""
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                known_installers_decl="$(declare -p KNOWN_INSTALLERS 2>/dev/null || true)"
                if [[ "$known_installers_decl" == declare\ -A* ]]; then
                    local tool="dsr"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.doodlestein_self_releaser: get_checksum failed for tool '$tool'"
                        ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if ! verified_installer_file="$(acfs_security_mktemp "/tmp/acfs-verified-installer.XXXXXX" 2>/dev/null)" || [[ -z "$verified_installer_file" ]]; then
                            log_error "stack.doodlestein_self_releaser: failed to create verified installer staging file"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                            verified_installer_file=""
                        elif ! verify_checksum "$url" "$expected_sha256" "$tool" > "$verified_installer_file"; then
                            log_error "stack.doodlestein_self_releaser: installer verification failed"
                            : "${ACFS_LAST_MODULE_FAILURE_REASON:=checksum}"
                        elif ! verified_installer_chmod_bin="$(acfs_generated_system_binary_path chmod 2>/dev/null)"; then
                            log_error "stack.doodlestein_self_releaser: trusted chmod not found for verified installer staging"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        elif ! "$verified_installer_chmod_bin" 0444 "$verified_installer_file"; then
                            log_error "stack.doodlestein_self_releaser: failed to make verified installer staging file read-only"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                        elif run_as_target_runner 'bash' "$verified_installer_file" '--easy-mode'; then
                            install_success=true
                        else
                            log_error "stack.doodlestein_self_releaser: verified installer execution failed"
                            ACFS_LAST_MODULE_FAILURE_REASON="installer execution"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.doodlestein_self_releaser: KNOWN_INSTALLERS[$tool] not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.doodlestein_self_releaser: checksum for '$tool' not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                    fi
                else
                    log_error "stack.doodlestein_self_releaser: KNOWN_INSTALLERS array not available"
                    ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                fi
            else
                log_error "stack.doodlestein_self_releaser: acfs_security_init failed - check security.sh and checksums.yaml"
                ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
            fi
            if [[ -n "$verified_installer_file" ]]; then
                _acfs_remove_temp_files "$verified_installer_file"
                verified_installer_file=""
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.doodlestein_self_releaser"
                false
            fi
        }; then
            log_warn "stack.doodlestein_self_releaser: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.doodlestein_self_releaser" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.doodlestein_self_releaser"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: dsr --version || dsr --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_DOODLESTEIN_SELF_RELEASER'
dsr --version || dsr --help
INSTALL_STACK_DOODLESTEIN_SELF_RELEASER
        then
            log_warn "stack.doodlestein_self_releaser: verify failed: dsr --version || dsr --help"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.doodlestein_self_releaser" "verify failed: dsr --version || dsr --help"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.doodlestein_self_releaser"
            fi
            return 0
        fi
    fi

    log_success "stack.doodlestein_self_releaser installed"
}

# Smart backup tool for AI coding agent configuration folders (asb)
acfs_generated_install_stack_agent_settings_backup() {
    local module_id="stack.agent_settings_backup"
    local canonical_contract="${ACFS_GENERATED_SCRIPT_DIR}/../lib/contract.sh"
    # Rebind the exact sibling contract at every generated entry. Imported
    # shell functions and environment state are never commissioning authority.
    if [[ ! -f "$canonical_contract" || -L "$canonical_contract" ]]; then
        log_error "stack.agent_settings_backup: canonical runtime contract unavailable"
        return 1
    fi
    if ! builtin unset -f acfs_require_contract acfs_license_exclusion_profile_payload _acfs_license_profile_actual_sha256 acfs_license_policy_verify_profile acfs_license_policy_module_is_held acfs_license_policy_module_is_plain_mit_only acfs_license_policy_admit_entry acfs_license_clearance_requested acfs_license_clearance_verify acfs_license_clearance_active acfs_r1_runtime_profile_payload _acfs_r1_sha256_file _acfs_r1_profile_actual_sha256 _acfs_r1_runtime_root _acfs_r1_verify_bound_file acfs_r1_runtime_verify_profile acfs_r1_runtime_module_is_held acfs_r1_runtime_module_is_planned acfs_r1_runtime_admit_entry _acfs_r1_array_csv acfs_r1_runtime_prepare_selection acfs_r1_runtime_validate_plan acfs_core_policy_enforce acfs_core_policy_reason acfs_core_policy_contract _acfs_core_policy_target_home acfs_core_policy_expected_binary_path acfs_core_policy_expected_bv_versioned_path acfs_core_policy_expected_binary_sha256 _acfs_core_policy_sha256_file _acfs_core_policy_version_output acfs_core_policy_admit_binary acfs_core_policy_admit_repair_source acfs_core_policy_enforce_installer_execution 2>/dev/null; then
        log_error "stack.agent_settings_backup: imported runtime policy function is not replaceable"
        return 1
    fi
    # shellcheck disable=SC1090  # exact generated sibling
    if ! builtin source "$canonical_contract"; then
        log_error "stack.agent_settings_backup: canonical runtime contract could not be loaded"
        return 1
    fi
    if [[ "${ACFS_R1_RUNTIME_PROFILE_ID:-}" != "R1-held-module-exclusion-runtime-v1" ]] || ! builtin declare -F acfs_r1_runtime_admit_entry >/dev/null 2>&1; then
        log_error "stack.agent_settings_backup: exact R1 runtime profile unavailable"
        return 1
    fi
    if ! acfs_r1_runtime_admit_entry direct "${module_id}"; then
        log_error "stack.agent_settings_backup: ${ACFS_R1_POLICY_REASON:-R1 runtime admission rejected the module}"
        return 1
    fi
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping stack.agent_settings_backup (not selected)"
        return 0
    fi
    log_step "Installing stack.agent_settings_backup"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.agent_settings_backup"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false
            local verified_installer_file=""
            local verified_installer_chmod_bin=""

                # Cleared per attempt so a stale reason from an earlier module can
                # never be misattributed to this one.
                ACFS_LAST_MODULE_FAILURE_REASON=""
            if acfs_security_init; then
                local known_installers_decl=""
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                known_installers_decl="$(declare -p KNOWN_INSTALLERS 2>/dev/null || true)"
                if [[ "$known_installers_decl" == declare\ -A* ]]; then
                    local tool="asb"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.agent_settings_backup: get_checksum failed for tool '$tool'"
                        ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if ! verified_installer_file="$(acfs_security_mktemp "/tmp/acfs-verified-installer.XXXXXX" 2>/dev/null)" || [[ -z "$verified_installer_file" ]]; then
                            log_error "stack.agent_settings_backup: failed to create verified installer staging file"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                            verified_installer_file=""
                        elif ! verify_checksum "$url" "$expected_sha256" "$tool" > "$verified_installer_file"; then
                            log_error "stack.agent_settings_backup: installer verification failed"
                            : "${ACFS_LAST_MODULE_FAILURE_REASON:=checksum}"
                        elif ! verified_installer_chmod_bin="$(acfs_generated_system_binary_path chmod 2>/dev/null)"; then
                            log_error "stack.agent_settings_backup: trusted chmod not found for verified installer staging"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        elif ! "$verified_installer_chmod_bin" 0444 "$verified_installer_file"; then
                            log_error "stack.agent_settings_backup: failed to make verified installer staging file read-only"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                        elif run_as_target_runner 'bash' "$verified_installer_file"; then
                            install_success=true
                        else
                            log_error "stack.agent_settings_backup: verified installer execution failed"
                            ACFS_LAST_MODULE_FAILURE_REASON="installer execution"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.agent_settings_backup: KNOWN_INSTALLERS[$tool] not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.agent_settings_backup: checksum for '$tool' not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                    fi
                else
                    log_error "stack.agent_settings_backup: KNOWN_INSTALLERS array not available"
                    ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                fi
            else
                log_error "stack.agent_settings_backup: acfs_security_init failed - check security.sh and checksums.yaml"
                ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
            fi
            if [[ -n "$verified_installer_file" ]]; then
                _acfs_remove_temp_files "$verified_installer_file"
                verified_installer_file=""
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.agent_settings_backup"
                false
            fi
        }; then
            log_warn "stack.agent_settings_backup: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.agent_settings_backup" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.agent_settings_backup"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: if [[ -d \"\$backup_root\" ]]; then (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_AGENT_SETTINGS_BACKUP'
backup_root="${ASB_BACKUP_ROOT:-$HOME/.agent_settings_backups}"
existing_backup_repo=""

if [[ -d "$backup_root" ]]; then
  existing_backup_repo="$(find "$backup_root" -mindepth 2 -maxdepth 2 -name .git -print -quit 2>/dev/null || true)"
fi

if [[ -n "$existing_backup_repo" ]]; then
  echo "ASB backup history already exists at $backup_root" >&2
else
  if asb backup; then
    echo "ASB initial backup created at $backup_root" >&2
  else
    echo "WARN: ASB initial backup failed; continuing without a seeded backup repo" >&2
  fi
fi

cron_status="$(asb schedule --status --cron 2>&1 || true)"
systemd_status="$(asb schedule --status --systemd 2>&1 || true)"
cron_missing=false
systemd_missing=false

if printf '%s' "$cron_status" | grep -q "No cron schedule found"; then
  cron_missing=true
fi
if printf '%s' "$systemd_status" | grep -q "Systemd timer is not enabled"; then
  systemd_missing=true
fi

if [[ "$cron_missing" == "true" && "$systemd_missing" == "true" ]]; then
  if asb schedule --cron --interval daily >/dev/null 2>&1; then
    echo "ASB scheduled backups enabled via cron (daily)." >&2
  else
    echo "WARN: ASB scheduled backup setup failed; continuing without automation" >&2
  fi
fi

echo "ASB backup root: $backup_root" >&2
INSTALL_STACK_AGENT_SETTINGS_BACKUP
        then
            log_warn "stack.agent_settings_backup: install command failed: if [[ -d \"\$backup_root\" ]]; then"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.agent_settings_backup" "install command failed: if [[ -d \"\$backup_root\" ]]; then"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.agent_settings_backup"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: asb version || asb help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_AGENT_SETTINGS_BACKUP'
asb version || asb help
INSTALL_STACK_AGENT_SETTINGS_BACKUP
        then
            log_warn "stack.agent_settings_backup: verify failed: asb version || asb help"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.agent_settings_backup" "verify failed: asb version || asb help"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.agent_settings_backup"
            fi
            return 0
        fi
    fi

    log_success "stack.agent_settings_backup installed"
}

# Post-compaction reminder hook for Claude Code that forces an AGENTS.md re-read
acfs_generated_install_stack_pcr() {
    local module_id="stack.pcr"
    local canonical_contract="${ACFS_GENERATED_SCRIPT_DIR}/../lib/contract.sh"
    # Rebind the exact sibling contract at every generated entry. Imported
    # shell functions and environment state are never commissioning authority.
    if [[ ! -f "$canonical_contract" || -L "$canonical_contract" ]]; then
        log_error "stack.pcr: canonical runtime contract unavailable"
        return 1
    fi
    if ! builtin unset -f acfs_require_contract acfs_license_exclusion_profile_payload _acfs_license_profile_actual_sha256 acfs_license_policy_verify_profile acfs_license_policy_module_is_held acfs_license_policy_module_is_plain_mit_only acfs_license_policy_admit_entry acfs_license_clearance_requested acfs_license_clearance_verify acfs_license_clearance_active acfs_r1_runtime_profile_payload _acfs_r1_sha256_file _acfs_r1_profile_actual_sha256 _acfs_r1_runtime_root _acfs_r1_verify_bound_file acfs_r1_runtime_verify_profile acfs_r1_runtime_module_is_held acfs_r1_runtime_module_is_planned acfs_r1_runtime_admit_entry _acfs_r1_array_csv acfs_r1_runtime_prepare_selection acfs_r1_runtime_validate_plan acfs_core_policy_enforce acfs_core_policy_reason acfs_core_policy_contract _acfs_core_policy_target_home acfs_core_policy_expected_binary_path acfs_core_policy_expected_bv_versioned_path acfs_core_policy_expected_binary_sha256 _acfs_core_policy_sha256_file _acfs_core_policy_version_output acfs_core_policy_admit_binary acfs_core_policy_admit_repair_source acfs_core_policy_enforce_installer_execution 2>/dev/null; then
        log_error "stack.pcr: imported runtime policy function is not replaceable"
        return 1
    fi
    # shellcheck disable=SC1090  # exact generated sibling
    if ! builtin source "$canonical_contract"; then
        log_error "stack.pcr: canonical runtime contract could not be loaded"
        return 1
    fi
    if [[ "${ACFS_R1_RUNTIME_PROFILE_ID:-}" != "R1-held-module-exclusion-runtime-v1" ]] || ! builtin declare -F acfs_r1_runtime_admit_entry >/dev/null 2>&1; then
        log_error "stack.pcr: exact R1 runtime profile unavailable"
        return 1
    fi
    if ! acfs_r1_runtime_admit_entry direct "${module_id}"; then
        log_error "stack.pcr: ${ACFS_R1_POLICY_REASON:-R1 runtime admission rejected the module}"
        return 1
    fi
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping stack.pcr (not selected)"
        return 0
    fi
    log_step "Installing stack.pcr"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: pre-install check: command -v claude >/dev/null 2>&1 (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_PCR_PRE_INSTALL_CHECK'
command -v claude >/dev/null 2>&1
INSTALL_STACK_PCR_PRE_INSTALL_CHECK
        then
            log_warn "stack.pcr: Skipping PCR - Claude Code not found"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.pcr" "Skipping PCR - Claude Code not found"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.pcr"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.pcr"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false
            local verified_installer_file=""
            local verified_installer_chmod_bin=""

                # Cleared per attempt so a stale reason from an earlier module can
                # never be misattributed to this one.
                ACFS_LAST_MODULE_FAILURE_REASON=""
            if acfs_security_init; then
                local known_installers_decl=""
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                known_installers_decl="$(declare -p KNOWN_INSTALLERS 2>/dev/null || true)"
                if [[ "$known_installers_decl" == declare\ -A* ]]; then
                    local tool="pcr"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.pcr: get_checksum failed for tool '$tool'"
                        ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if ! verified_installer_file="$(acfs_security_mktemp "/tmp/acfs-verified-installer.XXXXXX" 2>/dev/null)" || [[ -z "$verified_installer_file" ]]; then
                            log_error "stack.pcr: failed to create verified installer staging file"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                            verified_installer_file=""
                        elif ! verify_checksum "$url" "$expected_sha256" "$tool" > "$verified_installer_file"; then
                            log_error "stack.pcr: installer verification failed"
                            : "${ACFS_LAST_MODULE_FAILURE_REASON:=checksum}"
                        elif ! verified_installer_chmod_bin="$(acfs_generated_system_binary_path chmod 2>/dev/null)"; then
                            log_error "stack.pcr: trusted chmod not found for verified installer staging"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        elif ! "$verified_installer_chmod_bin" 0444 "$verified_installer_file"; then
                            log_error "stack.pcr: failed to make verified installer staging file read-only"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                        elif run_as_target_runner 'bash' "$verified_installer_file" '--yes'; then
                            install_success=true
                        else
                            log_error "stack.pcr: verified installer execution failed"
                            ACFS_LAST_MODULE_FAILURE_REASON="installer execution"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.pcr: KNOWN_INSTALLERS[$tool] not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.pcr: checksum for '$tool' not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                    fi
                else
                    log_error "stack.pcr: KNOWN_INSTALLERS array not available"
                    ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                fi
            else
                log_error "stack.pcr: acfs_security_init failed - check security.sh and checksums.yaml"
                ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
            fi
            if [[ -n "$verified_installer_file" ]]; then
                _acfs_remove_temp_files "$verified_installer_file"
                verified_installer_file=""
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.pcr"
                false
            fi
        }; then
            log_warn "stack.pcr: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.pcr" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.pcr"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: test -x \"\$hook_script\" || exit 1 (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_PCR'
claude_settings_has_command_hook() {
  local settings_file="${1:-}"
  local command_pattern="${2:-}"
  local jq_bin=""

  [[ -n "$settings_file" && -n "$command_pattern" ]] || return 1
  [[ -f "$settings_file" ]] || return 1
  for jq_bin in /usr/bin/jq /bin/jq /usr/local/bin/jq /usr/local/sbin/jq /usr/sbin/jq /sbin/jq; do
    [[ -x "$jq_bin" ]] && break
  done
  [[ -x "$jq_bin" ]] || return 1

  "$jq_bin" -e --arg pattern "$command_pattern" '
    def command_hook_matches:
      type == "object"
      and ((.type? // "command") == "command")
      and ((.command? // "") | strings | test($pattern));
    def event_entry_matches:
      if type == "object" and (.hooks? | type) == "array" then
        any(.hooks[]?; command_hook_matches)
      else
        command_hook_matches
      end;
    def hook_event_entries:
      if (.hooks? | type) == "object" then
        .hooks | to_entries[]? | .value | arrays | .[]?
      elif (.hooks? | type) == "array" then
        .hooks[]?
      else
        empty
      end;
    any(hook_event_entries; event_entry_matches)
  ' "$settings_file" >/dev/null 2>&1
}

target_home="${TARGET_HOME:-$HOME}"
hook_script="$target_home/.local/bin/claude-post-compact-reminder"
settings="$target_home/.claude/settings.json"
alt_settings="$target_home/.config/claude/settings.json"
pcr_command_pattern='(^|[[:space:]/])claude-post-compact-reminder([[:space:]]|$)'

test -x "$hook_script" || exit 1

claude_settings_has_command_hook "$settings" "$pcr_command_pattern" ||
  claude_settings_has_command_hook "$alt_settings" "$pcr_command_pattern"
INSTALL_STACK_PCR
        then
            log_warn "stack.pcr: verify failed: test -x \"\$hook_script\" || exit 1"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.pcr" "verify failed: test -x \"\$hook_script\" || exit 1"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.pcr"
            fi
            return 0
        fi
    fi

    log_success "stack.pcr installed"
}

# Durable, local-first, explainable memory for coding agents (ee)
acfs_generated_install_stack_eidetic_engine_cli() {
    local module_id="stack.eidetic_engine_cli"
    local canonical_contract="${ACFS_GENERATED_SCRIPT_DIR}/../lib/contract.sh"
    # Rebind the exact sibling contract at every generated entry. Imported
    # shell functions and environment state are never commissioning authority.
    if [[ ! -f "$canonical_contract" || -L "$canonical_contract" ]]; then
        log_error "stack.eidetic_engine_cli: canonical runtime contract unavailable"
        return 1
    fi
    if ! builtin unset -f acfs_require_contract acfs_license_exclusion_profile_payload _acfs_license_profile_actual_sha256 acfs_license_policy_verify_profile acfs_license_policy_module_is_held acfs_license_policy_module_is_plain_mit_only acfs_license_policy_admit_entry acfs_license_clearance_requested acfs_license_clearance_verify acfs_license_clearance_active acfs_r1_runtime_profile_payload _acfs_r1_sha256_file _acfs_r1_profile_actual_sha256 _acfs_r1_runtime_root _acfs_r1_verify_bound_file acfs_r1_runtime_verify_profile acfs_r1_runtime_module_is_held acfs_r1_runtime_module_is_planned acfs_r1_runtime_admit_entry _acfs_r1_array_csv acfs_r1_runtime_prepare_selection acfs_r1_runtime_validate_plan acfs_core_policy_enforce acfs_core_policy_reason acfs_core_policy_contract _acfs_core_policy_target_home acfs_core_policy_expected_binary_path acfs_core_policy_expected_bv_versioned_path acfs_core_policy_expected_binary_sha256 _acfs_core_policy_sha256_file _acfs_core_policy_version_output acfs_core_policy_admit_binary acfs_core_policy_admit_repair_source acfs_core_policy_enforce_installer_execution 2>/dev/null; then
        log_error "stack.eidetic_engine_cli: imported runtime policy function is not replaceable"
        return 1
    fi
    # shellcheck disable=SC1090  # exact generated sibling
    if ! builtin source "$canonical_contract"; then
        log_error "stack.eidetic_engine_cli: canonical runtime contract could not be loaded"
        return 1
    fi
    if [[ "${ACFS_R1_RUNTIME_PROFILE_ID:-}" != "R1-held-module-exclusion-runtime-v1" ]] || ! builtin declare -F acfs_r1_runtime_admit_entry >/dev/null 2>&1; then
        log_error "stack.eidetic_engine_cli: exact R1 runtime profile unavailable"
        return 1
    fi
    if ! acfs_r1_runtime_admit_entry direct "${module_id}"; then
        log_error "stack.eidetic_engine_cli: ${ACFS_R1_POLICY_REASON:-R1 runtime admission rejected the module}"
        return 1
    fi
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping stack.eidetic_engine_cli (not selected)"
        return 0
    fi
    log_step "Installing stack.eidetic_engine_cli"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.eidetic_engine_cli"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false
            local verified_installer_file=""
            local verified_installer_chmod_bin=""

            # Build the approved source and its locked siblings on every Linux host.
            if [[ "$(uname -s 2>/dev/null)" == "Linux" ]]; then
                local ee_source_repo="https://github.com/Dicklesworthstone/eidetic_engine_cli.git"
                local ee_source_commit="0fc6801c91edc0764cf405b049024a25c3199e09"
                local ee_source_tree="179ac1bb86320f3874b34cec1cbcca2b85c7eadf"
                local ee_cargo_lock_sha256="d4a9012264d98026a6e2fd85a04b2ff3c85e636ebdcfb970f310a9f0421004cc"
                local ee_cargo_toml_sha256="2ae5549883ab45efca3f7eadd62130f24a4ff29f1c6216475dfa615646006598"
                local ee_stack_lock_sha256="9b649eff8925fd22d980e7bbddd7ff479ff6318c14f141fe9a8343b7a4db2738"
                local ee_checkout_sha256="a0f5041e4c13ba6faeb23df1e25ce3dc693c96dd9b2667d9d351e82e0dccde3c"
                local ee_source_parent="$TARGET_HOME/.cache/acfs/source-builds"
                local ee_source_dir=""
                local ee_binary=""
                local ee_version=""
                local ee_git_bin=""
                local ee_mkdir_bin=""
                local ee_mktemp_bin=""
                local ee_rm_bin=""
                local ee_sha256sum_bin=""
                local ee_cargo_bin="$TARGET_HOME/.cargo/bin/cargo"

                ee_git_bin="$(acfs_generated_system_binary_path git 2>/dev/null || true)"
                ee_mkdir_bin="$(acfs_generated_system_binary_path mkdir 2>/dev/null || true)"
                ee_mktemp_bin="$(acfs_generated_system_binary_path mktemp 2>/dev/null || true)"
                ee_rm_bin="$(acfs_generated_system_binary_path rm 2>/dev/null || true)"
                ee_sha256sum_bin="$(acfs_generated_system_binary_path sha256sum 2>/dev/null || true)"

                if [[ -z "$ee_git_bin" || -z "$ee_mkdir_bin" || -z "$ee_mktemp_bin" || -z "$ee_rm_bin" || -z "$ee_sha256sum_bin" || ! -x "$ee_cargo_bin" ]]; then
                    log_error "stack.eidetic_engine_cli: exact source build prerequisites are unavailable"
                    ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                elif [[ "$TARGET_HOME" != /* || "$TARGET_HOME" == "/" || -L "$TARGET_HOME" || -L "$TARGET_HOME/.cache" || -L "$TARGET_HOME/.cache/acfs" || -L "$ee_source_parent" ]]; then
                    log_error "stack.eidetic_engine_cli: refusing source build through an invalid or symlinked target-home path"
                    ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                elif ! run_as_target "$ee_mkdir_bin" -p "$ee_source_parent"; then
                    log_error "stack.eidetic_engine_cli: failed to prepare the confined source-build directory"
                    ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                elif [[ ! -d "$ee_source_parent" || -L "$ee_source_parent" ]]; then
                    log_error "stack.eidetic_engine_cli: source-build directory is not a confined real directory"
                    ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                elif ! ee_source_dir="$(run_as_target "$ee_mktemp_bin" -d "$ee_source_parent/eidetic-engine.XXXXXX" 2>/dev/null)"; then
                    log_error "stack.eidetic_engine_cli: failed to create the source-build staging directory"
                    ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                elif [[ "$ee_source_dir" != "$ee_source_parent"/eidetic-engine.* || ! -d "$ee_source_dir" || -L "$ee_source_dir" ]]; then
                    log_error "stack.eidetic_engine_cli: source-build staging directory escaped its trusted template"
                    ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                elif (
                    set -euo pipefail
                    trap 'run_as_target "$ee_rm_bin" -rf -- "$ee_source_dir" >/dev/null 2>&1 || true' EXIT
                    run_as_target "$ee_git_bin" -c core.hooksPath=/dev/null clone --filter=blob:none --no-checkout "$ee_source_repo" "$ee_source_dir/eidetic_engine_cli"
                    run_as_target "$ee_git_bin" -C "$ee_source_dir/eidetic_engine_cli" -c core.hooksPath=/dev/null fetch --depth 1 origin "$ee_source_commit"
                    run_as_target "$ee_git_bin" -C "$ee_source_dir/eidetic_engine_cli" -c core.hooksPath=/dev/null checkout --detach "$ee_source_commit"
                    [[ "$(run_as_target "$ee_git_bin" -C "$ee_source_dir/eidetic_engine_cli" rev-parse HEAD)" == "$ee_source_commit" ]]
                    [[ "$(run_as_target "$ee_git_bin" -C "$ee_source_dir/eidetic_engine_cli" rev-parse "HEAD^{tree}")" == "$ee_source_tree" ]]
                    [[ "$(run_as_target "$ee_sha256sum_bin" "$ee_source_dir/eidetic_engine_cli/Cargo.lock" | awk 'NR == 1 { print $1 }')" == "$ee_cargo_lock_sha256" ]]
                    [[ "$(run_as_target "$ee_sha256sum_bin" "$ee_source_dir/eidetic_engine_cli/Cargo.toml" | awk 'NR == 1 { print $1 }')" == "$ee_cargo_toml_sha256" ]]
                    [[ "$(run_as_target "$ee_sha256sum_bin" "$ee_source_dir/eidetic_engine_cli/franken-stack.lock" | awk 'NR == 1 { print $1 }')" == "$ee_stack_lock_sha256" ]]
                    [[ "$(run_as_target "$ee_sha256sum_bin" "$ee_source_dir/eidetic_engine_cli/scripts/checkout-franken-stack.sh" | awk 'NR == 1 { print $1 }')" == "$ee_checkout_sha256" ]]
                    [[ -z "$(run_as_target "$ee_git_bin" -C "$ee_source_dir/eidetic_engine_cli" status --porcelain=v1 --untracked-files=all)" ]]
                    run_as_target env PATH="$TARGET_HOME/.cargo/bin:/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" bash "$ee_source_dir/eidetic_engine_cli/scripts/checkout-franken-stack.sh" "$ee_source_dir"
                    run_as_target env CARGO_BUILD_JOBS=1 RUSTFLAGS= CARGO_NET_GIT_FETCH_WITH_CLI=true "$ee_cargo_bin" build --jobs 1 --release --locked --bin ee --manifest-path "$ee_source_dir/eidetic_engine_cli/Cargo.toml" --target-dir "$ee_source_dir/target"
                    ee_binary="$ee_source_dir/target/release/ee"
                    [[ -f "$ee_binary" && -x "$ee_binary" && ! -L "$ee_binary" ]]
                    ee_version="$(run_as_target "$ee_binary" --version 2>/dev/null)"
                    [[ "$ee_version" == "ee 0.14.2" ]]
                    acfs_install_executable_into_primary_bin "$ee_binary" ee
                ); then
                    install_success=true
                else
                    if [[ -n "$ee_source_dir" && "$ee_source_dir" == "$ee_source_parent"/eidetic-engine.* && -d "$ee_source_dir" && ! -L "$ee_source_dir" ]]; then
                        run_as_target "$ee_rm_bin" -rf -- "$ee_source_dir" >/dev/null 2>&1 || true
                    fi
                    log_error "stack.eidetic_engine_cli: exact source build failed"
                    ACFS_LAST_MODULE_FAILURE_REASON="source build"
                fi
            else
                log_error "stack.eidetic_engine_cli: exact source commissioning is supported only on Linux"
                ACFS_LAST_MODULE_FAILURE_REASON="unsupported platform"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.eidetic_engine_cli"
                false
            fi
        }; then
            log_warn "stack.eidetic_engine_cli: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.eidetic_engine_cli" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.eidetic_engine_cli"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: test \"\$(ee --version 2>/dev/null)\" = \"ee 0.14.2\" (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_EIDETIC_ENGINE_CLI'
test "$(ee --version 2>/dev/null)" = "ee 0.14.2"
INSTALL_STACK_EIDETIC_ENGINE_CLI
        then
            log_warn "stack.eidetic_engine_cli: verify failed: test \"\$(ee --version 2>/dev/null)\" = \"ee 0.14.2\""
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.eidetic_engine_cli" "verify failed: test \"\$(ee --version 2>/dev/null)\" = \"ee 0.14.2\""
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.eidetic_engine_cli"
            fi
            return 0
        fi
    fi

    log_success "stack.eidetic_engine_cli installed"
}

# Pure-Rust Markdown engine rendering self-contained HTML and tagged PDF (fmd)
acfs_generated_install_stack_franken_markdown() {
    local module_id="stack.franken_markdown"
    local canonical_contract="${ACFS_GENERATED_SCRIPT_DIR}/../lib/contract.sh"
    # Rebind the exact sibling contract at every generated entry. Imported
    # shell functions and environment state are never commissioning authority.
    if [[ ! -f "$canonical_contract" || -L "$canonical_contract" ]]; then
        log_error "stack.franken_markdown: canonical runtime contract unavailable"
        return 1
    fi
    if ! builtin unset -f acfs_require_contract acfs_license_exclusion_profile_payload _acfs_license_profile_actual_sha256 acfs_license_policy_verify_profile acfs_license_policy_module_is_held acfs_license_policy_module_is_plain_mit_only acfs_license_policy_admit_entry acfs_license_clearance_requested acfs_license_clearance_verify acfs_license_clearance_active acfs_r1_runtime_profile_payload _acfs_r1_sha256_file _acfs_r1_profile_actual_sha256 _acfs_r1_runtime_root _acfs_r1_verify_bound_file acfs_r1_runtime_verify_profile acfs_r1_runtime_module_is_held acfs_r1_runtime_module_is_planned acfs_r1_runtime_admit_entry _acfs_r1_array_csv acfs_r1_runtime_prepare_selection acfs_r1_runtime_validate_plan acfs_core_policy_enforce acfs_core_policy_reason acfs_core_policy_contract _acfs_core_policy_target_home acfs_core_policy_expected_binary_path acfs_core_policy_expected_bv_versioned_path acfs_core_policy_expected_binary_sha256 _acfs_core_policy_sha256_file _acfs_core_policy_version_output acfs_core_policy_admit_binary acfs_core_policy_admit_repair_source acfs_core_policy_enforce_installer_execution 2>/dev/null; then
        log_error "stack.franken_markdown: imported runtime policy function is not replaceable"
        return 1
    fi
    # shellcheck disable=SC1090  # exact generated sibling
    if ! builtin source "$canonical_contract"; then
        log_error "stack.franken_markdown: canonical runtime contract could not be loaded"
        return 1
    fi
    if [[ "${ACFS_R1_RUNTIME_PROFILE_ID:-}" != "R1-held-module-exclusion-runtime-v1" ]] || ! builtin declare -F acfs_r1_runtime_admit_entry >/dev/null 2>&1; then
        log_error "stack.franken_markdown: exact R1 runtime profile unavailable"
        return 1
    fi
    if ! acfs_r1_runtime_admit_entry direct "${module_id}"; then
        log_error "stack.franken_markdown: ${ACFS_R1_POLICY_REASON:-R1 runtime admission rejected the module}"
        return 1
    fi
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping stack.franken_markdown (not selected)"
        return 0
    fi
    log_step "Installing stack.franken_markdown"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.franken_markdown"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false
            local verified_installer_file=""
            local verified_installer_chmod_bin=""

            # Franken Markdown release discovery and installer source fallback are
            # mutable. Build the exact approved source with its committed lock.
            if [[ "$(uname -s 2>/dev/null)" == "Linux" ]]; then
                local fmd_source_repo="https://github.com/Dicklesworthstone/franken_markdown.git"
                local fmd_source_commit="5637bad86e3c0deacab6411a734715015b143a12"
                local fmd_source_tree="f2d92693543fb542596f4aa00a402e832938caf1"
                local fmd_cargo_lock_sha256="3114ddb930a116a042e62d36f3a906f341414f6791383360c179c6337cb54ff0"
                local fmd_cargo_toml_sha256="8cd3d68fcc88ede03ef1179d93fad1828d517b61469b3ef3c89aed237dcddabd"
                local fmd_toolchain="nightly-2026-08-25"
                local fmd_source_parent="$TARGET_HOME/.cache/acfs/source-builds"
                local fmd_source_dir=""
                local fmd_target=""
                local fmd_binary=""
                local fmd_version=""
                local fmd_git_bin=""
                local fmd_mkdir_bin=""
                local fmd_mktemp_bin=""
                local fmd_rm_bin=""
                local fmd_sha256sum_bin=""
                local fmd_cargo_bin="$TARGET_HOME/.cargo/bin/cargo"
                local fmd_rustup_bin="$TARGET_HOME/.cargo/bin/rustup"

                case "$(uname -m 2>/dev/null || true)" in
                    x86_64|amd64) fmd_target="x86_64-unknown-linux-gnu" ;;
                    aarch64|arm64) fmd_target="aarch64-unknown-linux-gnu" ;;
                esac
                fmd_git_bin="$(acfs_generated_system_binary_path git 2>/dev/null || true)"
                fmd_mkdir_bin="$(acfs_generated_system_binary_path mkdir 2>/dev/null || true)"
                fmd_mktemp_bin="$(acfs_generated_system_binary_path mktemp 2>/dev/null || true)"
                fmd_rm_bin="$(acfs_generated_system_binary_path rm 2>/dev/null || true)"
                fmd_sha256sum_bin="$(acfs_generated_system_binary_path sha256sum 2>/dev/null || true)"

                if [[ -z "$fmd_target" || -z "$fmd_git_bin" || -z "$fmd_mkdir_bin" || -z "$fmd_mktemp_bin" || -z "$fmd_rm_bin" || -z "$fmd_sha256sum_bin" || ! -x "$fmd_cargo_bin" || ! -x "$fmd_rustup_bin" ]]; then
                    log_error "stack.franken_markdown: exact source build prerequisites are unavailable"
                    ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                elif [[ "$TARGET_HOME" != /* || "$TARGET_HOME" == "/" || -L "$TARGET_HOME" || -L "$TARGET_HOME/.cache" || -L "$TARGET_HOME/.cache/acfs" || -L "$fmd_source_parent" ]]; then
                    log_error "stack.franken_markdown: refusing source build through an invalid or symlinked target-home path"
                    ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                elif ! run_as_target "$fmd_mkdir_bin" -p "$fmd_source_parent"; then
                    log_error "stack.franken_markdown: failed to prepare the confined source-build directory"
                    ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                elif [[ ! -d "$fmd_source_parent" || -L "$fmd_source_parent" ]]; then
                    log_error "stack.franken_markdown: source-build directory is not a confined real directory"
                    ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                elif ! fmd_source_dir="$(run_as_target "$fmd_mktemp_bin" -d "$fmd_source_parent/fmd.XXXXXX" 2>/dev/null)"; then
                    log_error "stack.franken_markdown: failed to create the source-build staging directory"
                    ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                elif [[ "$fmd_source_dir" != "$fmd_source_parent"/fmd.* || ! -d "$fmd_source_dir" || -L "$fmd_source_dir" ]]; then
                    log_error "stack.franken_markdown: source-build staging directory escaped its trusted template"
                    ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                elif (
                    set -euo pipefail
                    trap 'run_as_target "$fmd_rm_bin" -rf -- "$fmd_source_dir" >/dev/null 2>&1 || true' EXIT
                    run_as_target "$fmd_git_bin" -c core.hooksPath=/dev/null clone --filter=blob:none --no-checkout "$fmd_source_repo" "$fmd_source_dir/src"
                    run_as_target "$fmd_git_bin" -C "$fmd_source_dir/src" -c core.hooksPath=/dev/null fetch --depth 1 origin "$fmd_source_commit"
                    run_as_target "$fmd_git_bin" -C "$fmd_source_dir/src" -c core.hooksPath=/dev/null checkout --detach "$fmd_source_commit"
                    [[ "$(run_as_target "$fmd_git_bin" -C "$fmd_source_dir/src" rev-parse HEAD)" == "$fmd_source_commit" ]]
                    [[ "$(run_as_target "$fmd_git_bin" -C "$fmd_source_dir/src" rev-parse "HEAD^{tree}")" == "$fmd_source_tree" ]]
                    [[ "$(run_as_target "$fmd_sha256sum_bin" "$fmd_source_dir/src/Cargo.lock" | awk 'NR == 1 { print $1 }')" == "$fmd_cargo_lock_sha256" ]]
                    [[ "$(run_as_target "$fmd_sha256sum_bin" "$fmd_source_dir/src/Cargo.toml" | awk 'NR == 1 { print $1 }')" == "$fmd_cargo_toml_sha256" ]]
                    [[ -z "$(run_as_target "$fmd_git_bin" -C "$fmd_source_dir/src" status --porcelain=v1 --untracked-files=all)" ]]
                    run_as_target "$fmd_rustup_bin" toolchain install "$fmd_toolchain" --profile minimal --no-self-update
                    run_as_target env CARGO_BUILD_JOBS=1 RUSTFLAGS= CARGO_NET_GIT_FETCH_WITH_CLI=true "$fmd_cargo_bin" +"$fmd_toolchain" build --locked --jobs 1 --target "$fmd_target" --release --package franken_markdown --bin fmd --manifest-path "$fmd_source_dir/src/Cargo.toml" --target-dir "$fmd_source_dir/target"
                    fmd_binary="$fmd_source_dir/target/$fmd_target/release/fmd"
                    [[ -f "$fmd_binary" && -x "$fmd_binary" && ! -L "$fmd_binary" ]]
                    fmd_version="$(run_as_target "$fmd_binary" --version 2>/dev/null)"
                    [[ "$fmd_version" == "fmd 0.4.2" ]]
                    acfs_install_executable_into_primary_bin "$fmd_binary" fmd
                ); then
                    install_success=true
                else
                    if [[ -n "$fmd_source_dir" && "$fmd_source_dir" == "$fmd_source_parent"/fmd.* && -d "$fmd_source_dir" && ! -L "$fmd_source_dir" ]]; then
                        run_as_target "$fmd_rm_bin" -rf -- "$fmd_source_dir" >/dev/null 2>&1 || true
                    fi
                    log_error "stack.franken_markdown: exact source build failed"
                    ACFS_LAST_MODULE_FAILURE_REASON="source build"
                fi
            else
                log_error "stack.franken_markdown: exact source commissioning is supported only on Linux"
                ACFS_LAST_MODULE_FAILURE_REASON="unsupported platform"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.franken_markdown"
                false
            fi
        }; then
            log_warn "stack.franken_markdown: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.franken_markdown" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.franken_markdown"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: test \"\$(fmd --version 2>/dev/null)\" = \"fmd 0.4.2\" (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_FRANKEN_MARKDOWN'
test "$(fmd --version 2>/dev/null)" = "fmd 0.4.2"
INSTALL_STACK_FRANKEN_MARKDOWN
        then
            log_warn "stack.franken_markdown: verify failed: test \"\$(fmd --version 2>/dev/null)\" = \"fmd 0.4.2\""
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.franken_markdown" "verify failed: test \"\$(fmd --version 2>/dev/null)\" = \"fmd 0.4.2\""
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.franken_markdown"
            fi
            return 0
        fi
    fi

    log_success "stack.franken_markdown installed"
}

# Native single-binary Rust port of the Pi coding agent (pi)
acfs_generated_install_stack_pi_agent_rust() {
    local module_id="stack.pi_agent_rust"
    local canonical_contract="${ACFS_GENERATED_SCRIPT_DIR}/../lib/contract.sh"
    # Rebind the exact sibling contract at every generated entry. Imported
    # shell functions and environment state are never commissioning authority.
    if [[ ! -f "$canonical_contract" || -L "$canonical_contract" ]]; then
        log_error "stack.pi_agent_rust: canonical runtime contract unavailable"
        return 1
    fi
    if ! builtin unset -f acfs_require_contract acfs_license_exclusion_profile_payload _acfs_license_profile_actual_sha256 acfs_license_policy_verify_profile acfs_license_policy_module_is_held acfs_license_policy_module_is_plain_mit_only acfs_license_policy_admit_entry acfs_license_clearance_requested acfs_license_clearance_verify acfs_license_clearance_active acfs_r1_runtime_profile_payload _acfs_r1_sha256_file _acfs_r1_profile_actual_sha256 _acfs_r1_runtime_root _acfs_r1_verify_bound_file acfs_r1_runtime_verify_profile acfs_r1_runtime_module_is_held acfs_r1_runtime_module_is_planned acfs_r1_runtime_admit_entry _acfs_r1_array_csv acfs_r1_runtime_prepare_selection acfs_r1_runtime_validate_plan acfs_core_policy_enforce acfs_core_policy_reason acfs_core_policy_contract _acfs_core_policy_target_home acfs_core_policy_expected_binary_path acfs_core_policy_expected_bv_versioned_path acfs_core_policy_expected_binary_sha256 _acfs_core_policy_sha256_file _acfs_core_policy_version_output acfs_core_policy_admit_binary acfs_core_policy_admit_repair_source acfs_core_policy_enforce_installer_execution 2>/dev/null; then
        log_error "stack.pi_agent_rust: imported runtime policy function is not replaceable"
        return 1
    fi
    # shellcheck disable=SC1090  # exact generated sibling
    if ! builtin source "$canonical_contract"; then
        log_error "stack.pi_agent_rust: canonical runtime contract could not be loaded"
        return 1
    fi
    if [[ "${ACFS_R1_RUNTIME_PROFILE_ID:-}" != "R1-held-module-exclusion-runtime-v1" ]] || ! builtin declare -F acfs_r1_runtime_admit_entry >/dev/null 2>&1; then
        log_error "stack.pi_agent_rust: exact R1 runtime profile unavailable"
        return 1
    fi
    if ! acfs_r1_runtime_admit_entry direct "${module_id}"; then
        log_error "stack.pi_agent_rust: ${ACFS_R1_POLICY_REASON:-R1 runtime admission rejected the module}"
        return 1
    fi
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping stack.pi_agent_rust (not selected)"
        return 0
    fi
    log_step "Installing stack.pi_agent_rust"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.pi_agent_rust"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false
            local verified_installer_file=""
            local verified_installer_chmod_bin=""

                # Cleared per attempt so a stale reason from an earlier module can
                # never be misattributed to this one.
                ACFS_LAST_MODULE_FAILURE_REASON=""
            if acfs_security_init; then
                local known_installers_decl=""
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                known_installers_decl="$(declare -p KNOWN_INSTALLERS 2>/dev/null || true)"
                if [[ "$known_installers_decl" == declare\ -A* ]]; then
                    local tool="pi"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.pi_agent_rust: get_checksum failed for tool '$tool'"
                        ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if ! verified_installer_file="$(acfs_security_mktemp "/tmp/acfs-verified-installer.XXXXXX" 2>/dev/null)" || [[ -z "$verified_installer_file" ]]; then
                            log_error "stack.pi_agent_rust: failed to create verified installer staging file"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                            verified_installer_file=""
                        elif ! verify_checksum "$url" "$expected_sha256" "$tool" > "$verified_installer_file"; then
                            log_error "stack.pi_agent_rust: installer verification failed"
                            : "${ACFS_LAST_MODULE_FAILURE_REASON:=checksum}"
                        elif ! verified_installer_chmod_bin="$(acfs_generated_system_binary_path chmod 2>/dev/null)"; then
                            log_error "stack.pi_agent_rust: trusted chmod not found for verified installer staging"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        elif ! "$verified_installer_chmod_bin" 0444 "$verified_installer_file"; then
                            log_error "stack.pi_agent_rust: failed to make verified installer staging file read-only"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                        elif run_as_target_runner 'bash' "$verified_installer_file" '--yes' '--easy-mode'; then
                            install_success=true
                        else
                            log_error "stack.pi_agent_rust: verified installer execution failed"
                            ACFS_LAST_MODULE_FAILURE_REASON="installer execution"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.pi_agent_rust: KNOWN_INSTALLERS[$tool] not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.pi_agent_rust: checksum for '$tool' not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                    fi
                else
                    log_error "stack.pi_agent_rust: KNOWN_INSTALLERS array not available"
                    ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                fi
            else
                log_error "stack.pi_agent_rust: acfs_security_init failed - check security.sh and checksums.yaml"
                ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
            fi
            if [[ -n "$verified_installer_file" ]]; then
                _acfs_remove_temp_files "$verified_installer_file"
                verified_installer_file=""
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.pi_agent_rust"
                false
            fi
        }; then
            log_warn "stack.pi_agent_rust: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.pi_agent_rust" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.pi_agent_rust"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: pi --version || pi --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_PI_AGENT_RUST'
pi --version || pi --help
INSTALL_STACK_PI_AGENT_RUST
        then
            log_warn "stack.pi_agent_rust: verify failed: pi --version || pi --help"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.pi_agent_rust" "verify failed: pi --version || pi --help"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.pi_agent_rust"
            fi
            return 0
        fi
    fi

    log_success "stack.pi_agent_rust installed"
}

# Recover crashed coding-agent sessions after a hard power cut (pfr)
acfs_generated_install_stack_power_failure_resumer() {
    local module_id="stack.power_failure_resumer"
    local canonical_contract="${ACFS_GENERATED_SCRIPT_DIR}/../lib/contract.sh"
    # Rebind the exact sibling contract at every generated entry. Imported
    # shell functions and environment state are never commissioning authority.
    if [[ ! -f "$canonical_contract" || -L "$canonical_contract" ]]; then
        log_error "stack.power_failure_resumer: canonical runtime contract unavailable"
        return 1
    fi
    if ! builtin unset -f acfs_require_contract acfs_license_exclusion_profile_payload _acfs_license_profile_actual_sha256 acfs_license_policy_verify_profile acfs_license_policy_module_is_held acfs_license_policy_module_is_plain_mit_only acfs_license_policy_admit_entry acfs_license_clearance_requested acfs_license_clearance_verify acfs_license_clearance_active acfs_r1_runtime_profile_payload _acfs_r1_sha256_file _acfs_r1_profile_actual_sha256 _acfs_r1_runtime_root _acfs_r1_verify_bound_file acfs_r1_runtime_verify_profile acfs_r1_runtime_module_is_held acfs_r1_runtime_module_is_planned acfs_r1_runtime_admit_entry _acfs_r1_array_csv acfs_r1_runtime_prepare_selection acfs_r1_runtime_validate_plan acfs_core_policy_enforce acfs_core_policy_reason acfs_core_policy_contract _acfs_core_policy_target_home acfs_core_policy_expected_binary_path acfs_core_policy_expected_bv_versioned_path acfs_core_policy_expected_binary_sha256 _acfs_core_policy_sha256_file _acfs_core_policy_version_output acfs_core_policy_admit_binary acfs_core_policy_admit_repair_source acfs_core_policy_enforce_installer_execution 2>/dev/null; then
        log_error "stack.power_failure_resumer: imported runtime policy function is not replaceable"
        return 1
    fi
    # shellcheck disable=SC1090  # exact generated sibling
    if ! builtin source "$canonical_contract"; then
        log_error "stack.power_failure_resumer: canonical runtime contract could not be loaded"
        return 1
    fi
    if [[ "${ACFS_R1_RUNTIME_PROFILE_ID:-}" != "R1-held-module-exclusion-runtime-v1" ]] || ! builtin declare -F acfs_r1_runtime_admit_entry >/dev/null 2>&1; then
        log_error "stack.power_failure_resumer: exact R1 runtime profile unavailable"
        return 1
    fi
    if ! acfs_r1_runtime_admit_entry direct "${module_id}"; then
        log_error "stack.power_failure_resumer: ${ACFS_R1_POLICY_REASON:-R1 runtime admission rejected the module}"
        return 1
    fi
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping stack.power_failure_resumer (not selected)"
        return 0
    fi
    log_step "Installing stack.power_failure_resumer"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.power_failure_resumer"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false
            local verified_installer_file=""
            local verified_installer_chmod_bin=""

                # Cleared per attempt so a stale reason from an earlier module can
                # never be misattributed to this one.
                ACFS_LAST_MODULE_FAILURE_REASON=""
            if acfs_security_init; then
                local known_installers_decl=""
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                known_installers_decl="$(declare -p KNOWN_INSTALLERS 2>/dev/null || true)"
                if [[ "$known_installers_decl" == declare\ -A* ]]; then
                    local tool="pfr"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.power_failure_resumer: get_checksum failed for tool '$tool'"
                        ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if ! verified_installer_file="$(acfs_security_mktemp "/tmp/acfs-verified-installer.XXXXXX" 2>/dev/null)" || [[ -z "$verified_installer_file" ]]; then
                            log_error "stack.power_failure_resumer: failed to create verified installer staging file"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                            verified_installer_file=""
                        elif ! verify_checksum "$url" "$expected_sha256" "$tool" > "$verified_installer_file"; then
                            log_error "stack.power_failure_resumer: installer verification failed"
                            : "${ACFS_LAST_MODULE_FAILURE_REASON:=checksum}"
                        elif ! verified_installer_chmod_bin="$(acfs_generated_system_binary_path chmod 2>/dev/null)"; then
                            log_error "stack.power_failure_resumer: trusted chmod not found for verified installer staging"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        elif ! "$verified_installer_chmod_bin" 0444 "$verified_installer_file"; then
                            log_error "stack.power_failure_resumer: failed to make verified installer staging file read-only"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                        elif run_as_target_runner 'bash' "$verified_installer_file" '--easy-mode' '--install-skill'; then
                            install_success=true
                        else
                            log_error "stack.power_failure_resumer: verified installer execution failed"
                            ACFS_LAST_MODULE_FAILURE_REASON="installer execution"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.power_failure_resumer: KNOWN_INSTALLERS[$tool] not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.power_failure_resumer: checksum for '$tool' not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                    fi
                else
                    log_error "stack.power_failure_resumer: KNOWN_INSTALLERS array not available"
                    ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                fi
            else
                log_error "stack.power_failure_resumer: acfs_security_init failed - check security.sh and checksums.yaml"
                ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
            fi
            if [[ -n "$verified_installer_file" ]]; then
                _acfs_remove_temp_files "$verified_installer_file"
                verified_installer_file=""
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.power_failure_resumer"
                false
            fi
        }; then
            log_warn "stack.power_failure_resumer: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.power_failure_resumer" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.power_failure_resumer"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: command -v pfr (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_POWER_FAILURE_RESUMER'
command -v pfr
INSTALL_STACK_POWER_FAILURE_RESUMER
        then
            log_warn "stack.power_failure_resumer: verify failed: command -v pfr"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.power_failure_resumer" "verify failed: command -v pfr"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.power_failure_resumer"
            fi
            return 0
        fi
    fi

    log_success "stack.power_failure_resumer installed"
}

# Category scripts are source-only libraries.
