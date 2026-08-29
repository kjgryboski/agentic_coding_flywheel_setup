#!/bin/bash -p
# shellcheck disable=SC1090,SC1091
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    builtin printf '%s\n' 'ERROR: install_w2_partial_safe.sh is a source-only library; run install.sh --only <module-id>' >&2
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

# Category: base
# Generated modules: 7

# Base packages + sane defaults
acfs_generated_install_base_system() {
    local module_id="base.system"
    local canonical_contract="${ACFS_GENERATED_SCRIPT_DIR}/../lib/contract.sh"
    # Rebind the exact sibling contract at every generated entry. Imported
    # shell functions and environment state are never commissioning authority.
    if [[ ! -f "$canonical_contract" || -L "$canonical_contract" ]]; then
        log_error "base.system: canonical runtime contract unavailable"
        return 1
    fi
    if ! builtin unset -f acfs_require_contract acfs_license_exclusion_profile_payload _acfs_license_profile_actual_sha256 acfs_license_policy_verify_profile acfs_license_policy_module_is_held acfs_license_policy_module_is_plain_mit_only acfs_license_policy_admit_entry acfs_r1_runtime_profile_payload _acfs_r1_sha256_file _acfs_r1_profile_actual_sha256 _acfs_r1_runtime_root _acfs_r1_verify_bound_file acfs_r1_runtime_verify_profile acfs_r1_runtime_module_is_held acfs_r1_runtime_module_is_planned acfs_r1_runtime_admit_entry _acfs_r1_array_csv acfs_r1_runtime_prepare_selection acfs_r1_runtime_validate_plan acfs_core_policy_enforce acfs_core_policy_reason acfs_core_policy_contract _acfs_core_policy_target_home acfs_core_policy_expected_binary_path acfs_core_policy_expected_bv_versioned_path acfs_core_policy_expected_binary_sha256 _acfs_core_policy_sha256_file _acfs_core_policy_version_output acfs_core_policy_admit_binary acfs_core_policy_admit_repair_source acfs_core_policy_enforce_installer_execution 2>/dev/null; then
        log_error "base.system: imported runtime policy function is not replaceable"
        return 1
    fi
    # shellcheck disable=SC1090  # exact generated sibling
    if ! builtin source "$canonical_contract"; then
        log_error "base.system: canonical runtime contract could not be loaded"
        return 1
    fi
    if [[ "${ACFS_R1_RUNTIME_PROFILE_ID:-}" != "R1-held-module-exclusion-runtime-v1" ]] || ! builtin declare -F acfs_r1_runtime_admit_entry >/dev/null 2>&1; then
        log_error "base.system: exact R1 runtime profile unavailable"
        return 1
    fi
    if ! acfs_r1_runtime_admit_entry direct "${module_id}"; then
        log_error "base.system: ${ACFS_R1_POLICY_REASON:-R1 runtime admission rejected the module}"
        return 1
    fi
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping base.system (not selected)"
        return 0
    fi
    log_step "Installing base.system"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: apt-get -o DPkg::Lock::Timeout=120 update -y (root)"
    else
        if ! run_as_root_shell <<'INSTALL_BASE_SYSTEM'
apt-get -o DPkg::Lock::Timeout=120 update -y
INSTALL_BASE_SYSTEM
        then
            log_error "base.system: install command failed: apt-get -o DPkg::Lock::Timeout=120 update -y"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: apt-get -o DPkg::Lock::Timeout=120 install -y curl git ca-certificates unzip tar xz-utils jq build-essential gnupg lsb-release (root)"
    else
        if ! run_as_root_shell <<'INSTALL_BASE_SYSTEM'
apt-get -o DPkg::Lock::Timeout=120 install -y curl git ca-certificates unzip tar xz-utils jq build-essential gnupg lsb-release
INSTALL_BASE_SYSTEM
        then
            log_error "base.system: install command failed: apt-get -o DPkg::Lock::Timeout=120 install -y curl git ca-certificates unzip tar xz-utils jq build-essential gnupg lsb-release"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: curl --version (root)"
    else
        if ! run_as_root_shell <<'INSTALL_BASE_SYSTEM'
curl --version
INSTALL_BASE_SYSTEM
        then
            log_error "base.system: verify failed: curl --version"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: git --version (root)"
    else
        if ! run_as_root_shell <<'INSTALL_BASE_SYSTEM'
git --version
INSTALL_BASE_SYSTEM
        then
            log_error "base.system: verify failed: git --version"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: jq --version (root)"
    else
        if ! run_as_root_shell <<'INSTALL_BASE_SYSTEM'
jq --version
INSTALL_BASE_SYSTEM
        then
            log_error "base.system: verify failed: jq --version"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: gpg --version (root)"
    else
        if ! run_as_root_shell <<'INSTALL_BASE_SYSTEM'
gpg --version
INSTALL_BASE_SYSTEM
        then
            log_error "base.system: verify failed: gpg --version"
            return 1
        fi
    fi

    log_success "base.system installed"
}

# Create workspace and ACFS directories
acfs_generated_install_base_filesystem() {
    local module_id="base.filesystem"
    local canonical_contract="${ACFS_GENERATED_SCRIPT_DIR}/../lib/contract.sh"
    # Rebind the exact sibling contract at every generated entry. Imported
    # shell functions and environment state are never commissioning authority.
    if [[ ! -f "$canonical_contract" || -L "$canonical_contract" ]]; then
        log_error "base.filesystem: canonical runtime contract unavailable"
        return 1
    fi
    if ! builtin unset -f acfs_require_contract acfs_license_exclusion_profile_payload _acfs_license_profile_actual_sha256 acfs_license_policy_verify_profile acfs_license_policy_module_is_held acfs_license_policy_module_is_plain_mit_only acfs_license_policy_admit_entry acfs_r1_runtime_profile_payload _acfs_r1_sha256_file _acfs_r1_profile_actual_sha256 _acfs_r1_runtime_root _acfs_r1_verify_bound_file acfs_r1_runtime_verify_profile acfs_r1_runtime_module_is_held acfs_r1_runtime_module_is_planned acfs_r1_runtime_admit_entry _acfs_r1_array_csv acfs_r1_runtime_prepare_selection acfs_r1_runtime_validate_plan acfs_core_policy_enforce acfs_core_policy_reason acfs_core_policy_contract _acfs_core_policy_target_home acfs_core_policy_expected_binary_path acfs_core_policy_expected_bv_versioned_path acfs_core_policy_expected_binary_sha256 _acfs_core_policy_sha256_file _acfs_core_policy_version_output acfs_core_policy_admit_binary acfs_core_policy_admit_repair_source acfs_core_policy_enforce_installer_execution 2>/dev/null; then
        log_error "base.filesystem: imported runtime policy function is not replaceable"
        return 1
    fi
    # shellcheck disable=SC1090  # exact generated sibling
    if ! builtin source "$canonical_contract"; then
        log_error "base.filesystem: canonical runtime contract could not be loaded"
        return 1
    fi
    if [[ "${ACFS_R1_RUNTIME_PROFILE_ID:-}" != "R1-held-module-exclusion-runtime-v1" ]] || ! builtin declare -F acfs_r1_runtime_admit_entry >/dev/null 2>&1; then
        log_error "base.filesystem: exact R1 runtime profile unavailable"
        return 1
    fi
    if ! acfs_r1_runtime_admit_entry direct "${module_id}"; then
        log_error "base.filesystem: ${ACFS_R1_POLICY_REASON:-R1 runtime admission rejected the module}"
        return 1
    fi
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping base.filesystem (not selected)"
        return 0
    fi
    log_step "Installing base.filesystem"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: for p in /data /data/projects /data/cache; do (root)"
    else
        if ! run_as_root_shell <<'INSTALL_BASE_FILESYSTEM'
# Hardening: refuse to operate on symlinked workspace paths.
# Prevents symlink tricks like /data -> / or /data/projects -> /etc.
for p in /data /data/projects /data/cache; do
  if [[ -e "$p" && -L "$p" ]]; then
    echo "ERROR: Refusing to use symlinked path: $p" >&2
    exit 1
  fi
done

mkdir -p /data/projects /data/cache
chown -h "${TARGET_USER:-ubuntu}:${TARGET_USER:-ubuntu}" /data /data/projects /data/cache
INSTALL_BASE_FILESYSTEM
        then
            log_error "base.filesystem: install command failed: for p in /data /data/projects /data/cache; do"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: if [[ -n \"\$explicit_target_home\" ]]; then (root)"
    else
        if ! run_as_root_shell <<'INSTALL_BASE_FILESYSTEM'
# Generated helper functions used by this child shell.
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

target_home=""
explicit_target_home="${TARGET_HOME:-}"
if [[ -n "$explicit_target_home" ]]; then
  explicit_target_home="${explicit_target_home%/}"
fi
if [[ "${TARGET_USER:-ubuntu}" == "root" ]]; then
  target_home="/root"
else
  _acfs_passwd_entry="$(acfs_generated_getent_passwd_entry "${TARGET_USER:-ubuntu}" 2>/dev/null || true)"
  if [[ -n "$_acfs_passwd_entry" ]]; then
    target_home="$(acfs_generated_passwd_home_from_entry "$_acfs_passwd_entry" 2>/dev/null || true)"
  else
    current_user="$(acfs_generated_resolve_current_user 2>/dev/null || true)"
    current_home="${HOME:-}"
    if [[ -n "$current_home" ]]; then
      current_home="${current_home%/}"
    fi
    if [[ -n "$current_user" ]] && [[ "$current_user" == "${TARGET_USER:-ubuntu}" ]] && [[ -n "$current_home" ]] && [[ "$current_home" == /* ]] && [[ "$current_home" != "/" ]] && { [[ -z "$explicit_target_home" ]] || [[ "$current_home" == "$explicit_target_home" ]]; }; then
      target_home="$current_home"
    fi
    unset current_user current_home
  fi
  unset _acfs_passwd_entry
fi
unset explicit_target_home
if [[ -z "$target_home" ]]; then
  echo "ERROR: Unable to resolve TARGET_HOME for '${TARGET_USER:-ubuntu}'; export TARGET_HOME explicitly" >&2
  exit 1
fi
if [[ -z "$target_home" || "$target_home" == "/" || "$target_home" != /* ]]; then
  echo "ERROR: Invalid TARGET_HOME: '${target_home:-<empty>}'" >&2
  exit 1
fi
if [[ -e "$target_home/.acfs" && -L "$target_home/.acfs" ]]; then
  echo "ERROR: Refusing to use symlinked ACFS dir: $target_home/.acfs" >&2
  exit 1
fi

mkdir -p "$target_home/.acfs"
chown -hR "${TARGET_USER:-ubuntu}:${TARGET_USER:-ubuntu}" "$target_home/.acfs"

# Save the workspace AGENTS.md template into ACFS-owned storage.
# ACFS may freely refresh this canonical copy on every install/update.
ACFS_RAW="${ACFS_RAW:-https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/${ACFS_REF:-main}}"
CURL_ARGS=(-q -fsSL)
if curl -q --help all 2>/dev/null | grep -q -- '--proto'; then
  CURL_ARGS=(-q --proto '=https' --proto-redir '=https' -fsSL)
fi
mkdir -p "$target_home/.acfs/docs"
curl "${CURL_ARGS[@]}" -o "$target_home/.acfs/docs/AGENTS.workspace.md" "${ACFS_RAW}/acfs/AGENTS.md" || true
chown -R "${TARGET_USER:-ubuntu}:${TARGET_USER:-ubuntu}" "$target_home/.acfs/docs" 2>/dev/null || true

# Seed /data/projects/AGENTS.md ONLY when absent. An existing file
# may contain user-authored rules and is never overwritten; use
# `acfs agents install` for explicit, non-overwriting deployment.
if [[ -f "$target_home/.acfs/docs/AGENTS.workspace.md" && ! -e /data/projects/AGENTS.md ]]; then
  cp "$target_home/.acfs/docs/AGENTS.workspace.md" /data/projects/AGENTS.md
  chown "${TARGET_USER:-ubuntu}:${TARGET_USER:-ubuntu}" /data/projects/AGENTS.md 2>/dev/null || true
fi
INSTALL_BASE_FILESYSTEM
        then
            log_error "base.filesystem: install command failed: if [[ -n \"\$explicit_target_home\" ]]; then"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: test -d /data/projects (root)"
    else
        if ! run_as_root_shell <<'INSTALL_BASE_FILESYSTEM'
test -d /data/projects
INSTALL_BASE_FILESYSTEM
        then
            log_error "base.filesystem: verify failed: test -d /data/projects"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: if [[ -n \"\$explicit_target_home\" ]]; then (root)"
    else
        if ! run_as_root_shell <<'INSTALL_BASE_FILESYSTEM'
# Generated helper functions used by this child shell.
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

# Resolve TARGET_HOME using generated helper functions. Doctor
# injects these helpers for manifest checks that reference
# acfs_generated_* functions, so this stays consistent with
# installer target-home resolution and avoids inherited HOME leaks.
explicit_target_home="${TARGET_HOME:-}"
if [[ -n "$explicit_target_home" ]]; then
  explicit_target_home="${explicit_target_home%/}"
fi
target_home=""
if [[ "${TARGET_USER:-ubuntu}" == "root" ]]; then
  target_home="/root"
else
  _acfs_passwd_entry="$(acfs_generated_getent_passwd_entry "${TARGET_USER:-ubuntu}" 2>/dev/null || true)"
  if [[ -n "$_acfs_passwd_entry" ]]; then
    target_home="$(acfs_generated_passwd_home_from_entry "$_acfs_passwd_entry" 2>/dev/null || true)"
  else
    current_user="$(acfs_generated_resolve_current_user 2>/dev/null || true)"
    current_home="${HOME:-}"
    if [[ -n "$current_home" ]]; then
      current_home="${current_home%/}"
    fi
    if [[ -n "$current_user" ]] && [[ "$current_user" == "${TARGET_USER:-ubuntu}" ]] && [[ -n "$current_home" ]] && [[ "$current_home" == /* ]] && [[ "$current_home" != "/" ]] && { [[ -z "$explicit_target_home" ]] || [[ "$current_home" == "$explicit_target_home" ]]; }; then
      target_home="$current_home"
    fi
    unset current_user current_home
  fi
  unset _acfs_passwd_entry
fi
unset explicit_target_home
if [[ -z "$target_home" ]] || [[ "$target_home" == "/" ]] || [[ "$target_home" != /* ]]; then
  echo "ERROR: Unable to resolve TARGET_HOME for '${TARGET_USER:-ubuntu}'; export TARGET_HOME explicitly (got: '${target_home:-<empty>}')" >&2
  exit 1
fi
test -d "$target_home/.acfs"
test -f "$target_home/.acfs/docs/AGENTS.workspace.md"
INSTALL_BASE_FILESYSTEM
        then
            log_error "base.filesystem: verify failed: if [[ -n \"\$explicit_target_home\" ]]; then"
            return 1
        fi
    fi

    log_success "base.filesystem installed"
}

# Modern CLI tools referenced by the zshrc intent
acfs_generated_install_cli_modern() {
    local module_id="cli.modern"
    local canonical_contract="${ACFS_GENERATED_SCRIPT_DIR}/../lib/contract.sh"
    # Rebind the exact sibling contract at every generated entry. Imported
    # shell functions and environment state are never commissioning authority.
    if [[ ! -f "$canonical_contract" || -L "$canonical_contract" ]]; then
        log_error "cli.modern: canonical runtime contract unavailable"
        return 1
    fi
    if ! builtin unset -f acfs_require_contract acfs_license_exclusion_profile_payload _acfs_license_profile_actual_sha256 acfs_license_policy_verify_profile acfs_license_policy_module_is_held acfs_license_policy_module_is_plain_mit_only acfs_license_policy_admit_entry acfs_r1_runtime_profile_payload _acfs_r1_sha256_file _acfs_r1_profile_actual_sha256 _acfs_r1_runtime_root _acfs_r1_verify_bound_file acfs_r1_runtime_verify_profile acfs_r1_runtime_module_is_held acfs_r1_runtime_module_is_planned acfs_r1_runtime_admit_entry _acfs_r1_array_csv acfs_r1_runtime_prepare_selection acfs_r1_runtime_validate_plan acfs_core_policy_enforce acfs_core_policy_reason acfs_core_policy_contract _acfs_core_policy_target_home acfs_core_policy_expected_binary_path acfs_core_policy_expected_bv_versioned_path acfs_core_policy_expected_binary_sha256 _acfs_core_policy_sha256_file _acfs_core_policy_version_output acfs_core_policy_admit_binary acfs_core_policy_admit_repair_source acfs_core_policy_enforce_installer_execution 2>/dev/null; then
        log_error "cli.modern: imported runtime policy function is not replaceable"
        return 1
    fi
    # shellcheck disable=SC1090  # exact generated sibling
    if ! builtin source "$canonical_contract"; then
        log_error "cli.modern: canonical runtime contract could not be loaded"
        return 1
    fi
    if [[ "${ACFS_R1_RUNTIME_PROFILE_ID:-}" != "R1-held-module-exclusion-runtime-v1" ]] || ! builtin declare -F acfs_r1_runtime_admit_entry >/dev/null 2>&1; then
        log_error "cli.modern: exact R1 runtime profile unavailable"
        return 1
    fi
    if ! acfs_r1_runtime_admit_entry direct "${module_id}"; then
        log_error "cli.modern: ${ACFS_R1_POLICY_REASON:-R1 runtime admission rejected the module}"
        return 1
    fi
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping cli.modern (not selected)"
        return 0
    fi
    log_step "Installing cli.modern"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: apt-get -o DPkg::Lock::Timeout=120 install -y ripgrep tmux fzf direnv jq gh git-lfs lsof dnsutils netcat-openbsd strace rsync (root)"
    else
        if ! run_as_root_shell <<'INSTALL_CLI_MODERN'
apt-get -o DPkg::Lock::Timeout=120 install -y ripgrep tmux fzf direnv jq gh git-lfs lsof dnsutils netcat-openbsd strace rsync
INSTALL_CLI_MODERN
        then
            log_error "cli.modern: install command failed: apt-get -o DPkg::Lock::Timeout=120 install -y ripgrep tmux fzf direnv jq gh git-lfs lsof dnsutils netcat-openbsd strace rsync"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: apt-get -o DPkg::Lock::Timeout=120 install -y lsd || true (root)"
    else
        if ! run_as_root_shell <<'INSTALL_CLI_MODERN'
apt-get -o DPkg::Lock::Timeout=120 install -y lsd || true
INSTALL_CLI_MODERN
        then
            log_error "cli.modern: install command failed: apt-get -o DPkg::Lock::Timeout=120 install -y lsd || true"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: apt-get -o DPkg::Lock::Timeout=120 install -y eza || true (root)"
    else
        if ! run_as_root_shell <<'INSTALL_CLI_MODERN'
apt-get -o DPkg::Lock::Timeout=120 install -y eza || true
INSTALL_CLI_MODERN
        then
            log_error "cli.modern: install command failed: apt-get -o DPkg::Lock::Timeout=120 install -y eza || true"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: apt-get -o DPkg::Lock::Timeout=120 install -y bat || apt-get -o DPkg::Lock::Timeout=120 install -y batcat || true (root)"
    else
        if ! run_as_root_shell <<'INSTALL_CLI_MODERN'
apt-get -o DPkg::Lock::Timeout=120 install -y bat || apt-get -o DPkg::Lock::Timeout=120 install -y batcat || true
INSTALL_CLI_MODERN
        then
            log_error "cli.modern: install command failed: apt-get -o DPkg::Lock::Timeout=120 install -y bat || apt-get -o DPkg::Lock::Timeout=120 install -y batcat || true"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: apt-get -o DPkg::Lock::Timeout=120 install -y fd-find || true (root)"
    else
        if ! run_as_root_shell <<'INSTALL_CLI_MODERN'
apt-get -o DPkg::Lock::Timeout=120 install -y fd-find || true
INSTALL_CLI_MODERN
        then
            log_error "cli.modern: install command failed: apt-get -o DPkg::Lock::Timeout=120 install -y fd-find || true"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: apt-get -o DPkg::Lock::Timeout=120 install -y btop || true (root)"
    else
        if ! run_as_root_shell <<'INSTALL_CLI_MODERN'
apt-get -o DPkg::Lock::Timeout=120 install -y btop || true
INSTALL_CLI_MODERN
        then
            log_error "cli.modern: install command failed: apt-get -o DPkg::Lock::Timeout=120 install -y btop || true"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: apt-get -o DPkg::Lock::Timeout=120 install -y dust || true (root)"
    else
        if ! run_as_root_shell <<'INSTALL_CLI_MODERN'
apt-get -o DPkg::Lock::Timeout=120 install -y dust || true
INSTALL_CLI_MODERN
        then
            log_error "cli.modern: install command failed: apt-get -o DPkg::Lock::Timeout=120 install -y dust || true"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: apt-get -o DPkg::Lock::Timeout=120 install -y neovim || true (root)"
    else
        if ! run_as_root_shell <<'INSTALL_CLI_MODERN'
apt-get -o DPkg::Lock::Timeout=120 install -y neovim || true
INSTALL_CLI_MODERN
        then
            log_error "cli.modern: install command failed: apt-get -o DPkg::Lock::Timeout=120 install -y neovim || true"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: apt-get -o DPkg::Lock::Timeout=120 install -y docker.io docker-compose-plugin || true (root)"
    else
        if ! run_as_root_shell <<'INSTALL_CLI_MODERN'
apt-get -o DPkg::Lock::Timeout=120 install -y docker.io docker-compose-plugin || true
INSTALL_CLI_MODERN
        then
            log_error "cli.modern: install command failed: apt-get -o DPkg::Lock::Timeout=120 install -y docker.io docker-compose-plugin || true"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: rg --version (root)"
    else
        if ! run_as_root_shell <<'INSTALL_CLI_MODERN'
rg --version
INSTALL_CLI_MODERN
        then
            log_error "cli.modern: verify failed: rg --version"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: tmux -V (root)"
    else
        if ! run_as_root_shell <<'INSTALL_CLI_MODERN'
tmux -V
INSTALL_CLI_MODERN
        then
            log_error "cli.modern: verify failed: tmux -V"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: fzf --version (root)"
    else
        if ! run_as_root_shell <<'INSTALL_CLI_MODERN'
fzf --version
INSTALL_CLI_MODERN
        then
            log_error "cli.modern: verify failed: fzf --version"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: gh --version (root)"
    else
        if ! run_as_root_shell <<'INSTALL_CLI_MODERN'
gh --version
INSTALL_CLI_MODERN
        then
            log_error "cli.modern: verify failed: gh --version"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: git-lfs version (root)"
    else
        if ! run_as_root_shell <<'INSTALL_CLI_MODERN'
git-lfs version
INSTALL_CLI_MODERN
        then
            log_error "cli.modern: verify failed: git-lfs version"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: rsync --version (root)"
    else
        if ! run_as_root_shell <<'INSTALL_CLI_MODERN'
rsync --version
INSTALL_CLI_MODERN
        then
            log_error "cli.modern: verify failed: rsync --version"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: strace --version (root)"
    else
        if ! run_as_root_shell <<'INSTALL_CLI_MODERN'
strace --version
INSTALL_CLI_MODERN
        then
            log_error "cli.modern: verify failed: strace --version"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: command -v lsof (root)"
    else
        if ! run_as_root_shell <<'INSTALL_CLI_MODERN'
command -v lsof
INSTALL_CLI_MODERN
        then
            log_error "cli.modern: verify failed: command -v lsof"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: command -v dig (root)"
    else
        if ! run_as_root_shell <<'INSTALL_CLI_MODERN'
command -v dig
INSTALL_CLI_MODERN
        then
            log_error "cli.modern: verify failed: command -v dig"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: command -v nc (root)"
    else
        if ! run_as_root_shell <<'INSTALL_CLI_MODERN'
command -v nc
INSTALL_CLI_MODERN
        then
            log_error "cli.modern: verify failed: command -v nc"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify (optional): command -v lsd || command -v eza (root)"
    else
        if ! run_as_root_shell <<'INSTALL_CLI_MODERN'
command -v lsd || command -v eza
INSTALL_CLI_MODERN
        then
            log_warn "Optional verify failed: cli.modern"
        fi
    fi

    log_success "cli.modern installed"
}

# Bun runtime for JS tooling and global CLIs
acfs_generated_install_lang_bun() {
    local module_id="lang.bun"
    local canonical_contract="${ACFS_GENERATED_SCRIPT_DIR}/../lib/contract.sh"
    # Rebind the exact sibling contract at every generated entry. Imported
    # shell functions and environment state are never commissioning authority.
    if [[ ! -f "$canonical_contract" || -L "$canonical_contract" ]]; then
        log_error "lang.bun: canonical runtime contract unavailable"
        return 1
    fi
    if ! builtin unset -f acfs_require_contract acfs_license_exclusion_profile_payload _acfs_license_profile_actual_sha256 acfs_license_policy_verify_profile acfs_license_policy_module_is_held acfs_license_policy_module_is_plain_mit_only acfs_license_policy_admit_entry acfs_r1_runtime_profile_payload _acfs_r1_sha256_file _acfs_r1_profile_actual_sha256 _acfs_r1_runtime_root _acfs_r1_verify_bound_file acfs_r1_runtime_verify_profile acfs_r1_runtime_module_is_held acfs_r1_runtime_module_is_planned acfs_r1_runtime_admit_entry _acfs_r1_array_csv acfs_r1_runtime_prepare_selection acfs_r1_runtime_validate_plan acfs_core_policy_enforce acfs_core_policy_reason acfs_core_policy_contract _acfs_core_policy_target_home acfs_core_policy_expected_binary_path acfs_core_policy_expected_bv_versioned_path acfs_core_policy_expected_binary_sha256 _acfs_core_policy_sha256_file _acfs_core_policy_version_output acfs_core_policy_admit_binary acfs_core_policy_admit_repair_source acfs_core_policy_enforce_installer_execution 2>/dev/null; then
        log_error "lang.bun: imported runtime policy function is not replaceable"
        return 1
    fi
    # shellcheck disable=SC1090  # exact generated sibling
    if ! builtin source "$canonical_contract"; then
        log_error "lang.bun: canonical runtime contract could not be loaded"
        return 1
    fi
    if [[ "${ACFS_R1_RUNTIME_PROFILE_ID:-}" != "R1-held-module-exclusion-runtime-v1" ]] || ! builtin declare -F acfs_r1_runtime_admit_entry >/dev/null 2>&1; then
        log_error "lang.bun: exact R1 runtime profile unavailable"
        return 1
    fi
    if ! acfs_r1_runtime_admit_entry direct "${module_id}"; then
        log_error "lang.bun: ${ACFS_R1_POLICY_REASON:-R1 runtime admission rejected the module}"
        return 1
    fi
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping lang.bun (not selected)"
        return 0
    fi
    log_step "Installing lang.bun"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: lang.bun"
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
                    local tool="bun"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "lang.bun: get_checksum failed for tool '$tool'"
                        ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if ! verified_installer_file="$(acfs_security_mktemp "/tmp/acfs-verified-installer.XXXXXX" 2>/dev/null)" || [[ -z "$verified_installer_file" ]]; then
                            log_error "lang.bun: failed to create verified installer staging file"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                            verified_installer_file=""
                        elif ! verify_checksum "$url" "$expected_sha256" "$tool" > "$verified_installer_file"; then
                            log_error "lang.bun: installer verification failed"
                            : "${ACFS_LAST_MODULE_FAILURE_REASON:=checksum}"
                        elif ! verified_installer_chmod_bin="$(acfs_generated_system_binary_path chmod 2>/dev/null)"; then
                            log_error "lang.bun: trusted chmod not found for verified installer staging"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        elif ! "$verified_installer_chmod_bin" 0444 "$verified_installer_file"; then
                            log_error "lang.bun: failed to make verified installer staging file read-only"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                        elif run_as_target_runner 'bash' "$verified_installer_file"; then
                            install_success=true
                        else
                            log_error "lang.bun: verified installer execution failed"
                            ACFS_LAST_MODULE_FAILURE_REASON="installer execution"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "lang.bun: KNOWN_INSTALLERS[$tool] not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "lang.bun: checksum for '$tool' not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                    fi
                else
                    log_error "lang.bun: KNOWN_INSTALLERS array not available"
                    ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                fi
            else
                log_error "lang.bun: acfs_security_init failed - check security.sh and checksums.yaml"
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
                log_error "Verified install failed for lang.bun"
                false
            fi
        }; then
            log_error "lang.bun: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: ~/.bun/bin/bun --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_LANG_BUN'
~/.bun/bin/bun --version
INSTALL_LANG_BUN
        then
            log_error "lang.bun: verify failed: ~/.bun/bin/bun --version"
            return 1
        fi
    fi

    log_success "lang.bun installed"
}

# uv Python tooling (fast venvs)
acfs_generated_install_lang_uv() {
    local module_id="lang.uv"
    local canonical_contract="${ACFS_GENERATED_SCRIPT_DIR}/../lib/contract.sh"
    # Rebind the exact sibling contract at every generated entry. Imported
    # shell functions and environment state are never commissioning authority.
    if [[ ! -f "$canonical_contract" || -L "$canonical_contract" ]]; then
        log_error "lang.uv: canonical runtime contract unavailable"
        return 1
    fi
    if ! builtin unset -f acfs_require_contract acfs_license_exclusion_profile_payload _acfs_license_profile_actual_sha256 acfs_license_policy_verify_profile acfs_license_policy_module_is_held acfs_license_policy_module_is_plain_mit_only acfs_license_policy_admit_entry acfs_r1_runtime_profile_payload _acfs_r1_sha256_file _acfs_r1_profile_actual_sha256 _acfs_r1_runtime_root _acfs_r1_verify_bound_file acfs_r1_runtime_verify_profile acfs_r1_runtime_module_is_held acfs_r1_runtime_module_is_planned acfs_r1_runtime_admit_entry _acfs_r1_array_csv acfs_r1_runtime_prepare_selection acfs_r1_runtime_validate_plan acfs_core_policy_enforce acfs_core_policy_reason acfs_core_policy_contract _acfs_core_policy_target_home acfs_core_policy_expected_binary_path acfs_core_policy_expected_bv_versioned_path acfs_core_policy_expected_binary_sha256 _acfs_core_policy_sha256_file _acfs_core_policy_version_output acfs_core_policy_admit_binary acfs_core_policy_admit_repair_source acfs_core_policy_enforce_installer_execution 2>/dev/null; then
        log_error "lang.uv: imported runtime policy function is not replaceable"
        return 1
    fi
    # shellcheck disable=SC1090  # exact generated sibling
    if ! builtin source "$canonical_contract"; then
        log_error "lang.uv: canonical runtime contract could not be loaded"
        return 1
    fi
    if [[ "${ACFS_R1_RUNTIME_PROFILE_ID:-}" != "R1-held-module-exclusion-runtime-v1" ]] || ! builtin declare -F acfs_r1_runtime_admit_entry >/dev/null 2>&1; then
        log_error "lang.uv: exact R1 runtime profile unavailable"
        return 1
    fi
    if ! acfs_r1_runtime_admit_entry direct "${module_id}"; then
        log_error "lang.uv: ${ACFS_R1_POLICY_REASON:-R1 runtime admission rejected the module}"
        return 1
    fi
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping lang.uv (not selected)"
        return 0
    fi
    log_step "Installing lang.uv"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: lang.uv"
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
                    local tool="uv"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "lang.uv: get_checksum failed for tool '$tool'"
                        ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if ! verified_installer_file="$(acfs_security_mktemp "/tmp/acfs-verified-installer.XXXXXX" 2>/dev/null)" || [[ -z "$verified_installer_file" ]]; then
                            log_error "lang.uv: failed to create verified installer staging file"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                            verified_installer_file=""
                        elif ! verify_checksum "$url" "$expected_sha256" "$tool" > "$verified_installer_file"; then
                            log_error "lang.uv: installer verification failed"
                            : "${ACFS_LAST_MODULE_FAILURE_REASON:=checksum}"
                        elif ! verified_installer_chmod_bin="$(acfs_generated_system_binary_path chmod 2>/dev/null)"; then
                            log_error "lang.uv: trusted chmod not found for verified installer staging"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        elif ! "$verified_installer_chmod_bin" 0444 "$verified_installer_file"; then
                            log_error "lang.uv: failed to make verified installer staging file read-only"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                        elif run_as_target_runner 'sh' "$verified_installer_file"; then
                            install_success=true
                        else
                            log_error "lang.uv: verified installer execution failed"
                            ACFS_LAST_MODULE_FAILURE_REASON="installer execution"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "lang.uv: KNOWN_INSTALLERS[$tool] not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "lang.uv: checksum for '$tool' not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                    fi
                else
                    log_error "lang.uv: KNOWN_INSTALLERS array not available"
                    ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                fi
            else
                log_error "lang.uv: acfs_security_init failed - check security.sh and checksums.yaml"
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
                log_error "Verified install failed for lang.uv"
                false
            fi
        }; then
            log_error "lang.uv: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: command -v uv >/dev/null 2>&1 && uv --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_LANG_UV'
command -v uv >/dev/null 2>&1 && uv --version
INSTALL_LANG_UV
        then
            log_error "lang.uv: verify failed: command -v uv >/dev/null 2>&1 && uv --version"
            return 1
        fi
    fi

    log_success "lang.uv installed"
}

# Rust nightly + cargo
acfs_generated_install_lang_rust() {
    local module_id="lang.rust"
    local canonical_contract="${ACFS_GENERATED_SCRIPT_DIR}/../lib/contract.sh"
    # Rebind the exact sibling contract at every generated entry. Imported
    # shell functions and environment state are never commissioning authority.
    if [[ ! -f "$canonical_contract" || -L "$canonical_contract" ]]; then
        log_error "lang.rust: canonical runtime contract unavailable"
        return 1
    fi
    if ! builtin unset -f acfs_require_contract acfs_license_exclusion_profile_payload _acfs_license_profile_actual_sha256 acfs_license_policy_verify_profile acfs_license_policy_module_is_held acfs_license_policy_module_is_plain_mit_only acfs_license_policy_admit_entry acfs_r1_runtime_profile_payload _acfs_r1_sha256_file _acfs_r1_profile_actual_sha256 _acfs_r1_runtime_root _acfs_r1_verify_bound_file acfs_r1_runtime_verify_profile acfs_r1_runtime_module_is_held acfs_r1_runtime_module_is_planned acfs_r1_runtime_admit_entry _acfs_r1_array_csv acfs_r1_runtime_prepare_selection acfs_r1_runtime_validate_plan acfs_core_policy_enforce acfs_core_policy_reason acfs_core_policy_contract _acfs_core_policy_target_home acfs_core_policy_expected_binary_path acfs_core_policy_expected_bv_versioned_path acfs_core_policy_expected_binary_sha256 _acfs_core_policy_sha256_file _acfs_core_policy_version_output acfs_core_policy_admit_binary acfs_core_policy_admit_repair_source acfs_core_policy_enforce_installer_execution 2>/dev/null; then
        log_error "lang.rust: imported runtime policy function is not replaceable"
        return 1
    fi
    # shellcheck disable=SC1090  # exact generated sibling
    if ! builtin source "$canonical_contract"; then
        log_error "lang.rust: canonical runtime contract could not be loaded"
        return 1
    fi
    if [[ "${ACFS_R1_RUNTIME_PROFILE_ID:-}" != "R1-held-module-exclusion-runtime-v1" ]] || ! builtin declare -F acfs_r1_runtime_admit_entry >/dev/null 2>&1; then
        log_error "lang.rust: exact R1 runtime profile unavailable"
        return 1
    fi
    if ! acfs_r1_runtime_admit_entry direct "${module_id}"; then
        log_error "lang.rust: ${ACFS_R1_POLICY_REASON:-R1 runtime admission rejected the module}"
        return 1
    fi
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping lang.rust (not selected)"
        return 0
    fi
    log_step "Installing lang.rust"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: lang.rust"
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
                    local tool="rust"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "lang.rust: get_checksum failed for tool '$tool'"
                        ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if ! verified_installer_file="$(acfs_security_mktemp "/tmp/acfs-verified-installer.XXXXXX" 2>/dev/null)" || [[ -z "$verified_installer_file" ]]; then
                            log_error "lang.rust: failed to create verified installer staging file"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                            verified_installer_file=""
                        elif ! verify_checksum "$url" "$expected_sha256" "$tool" > "$verified_installer_file"; then
                            log_error "lang.rust: installer verification failed"
                            : "${ACFS_LAST_MODULE_FAILURE_REASON:=checksum}"
                        elif ! verified_installer_chmod_bin="$(acfs_generated_system_binary_path chmod 2>/dev/null)"; then
                            log_error "lang.rust: trusted chmod not found for verified installer staging"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        elif ! "$verified_installer_chmod_bin" 0444 "$verified_installer_file"; then
                            log_error "lang.rust: failed to make verified installer staging file read-only"
                            ACFS_LAST_MODULE_FAILURE_REASON="environment setup"
                        elif run_as_target_runner 'sh' "$verified_installer_file" '-y' '--default-toolchain' 'nightly'; then
                            install_success=true
                        else
                            log_error "lang.rust: verified installer execution failed"
                            ACFS_LAST_MODULE_FAILURE_REASON="installer execution"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "lang.rust: KNOWN_INSTALLERS[$tool] not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "lang.rust: checksum for '$tool' not found"
                            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                        fi
                    fi
                else
                    log_error "lang.rust: KNOWN_INSTALLERS array not available"
                    ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"
                fi
            else
                log_error "lang.rust: acfs_security_init failed - check security.sh and checksums.yaml"
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
                log_error "Verified install failed for lang.rust"
                false
            fi
        }; then
            log_error "lang.rust: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: ~/.cargo/bin/cargo --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_LANG_RUST'
~/.cargo/bin/cargo --version
INSTALL_LANG_RUST
        then
            log_error "lang.rust: verify failed: ~/.cargo/bin/cargo --version"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: ~/.cargo/bin/rustup show | grep -q nightly (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_LANG_RUST'
~/.cargo/bin/rustup show | grep -q nightly
INSTALL_LANG_RUST
        then
            log_error "lang.rust: verify failed: ~/.cargo/bin/rustup show | grep -q nightly"
            return 1
        fi
    fi

    log_success "lang.rust installed"
}

# Go toolchain
acfs_generated_install_lang_go() {
    local module_id="lang.go"
    local canonical_contract="${ACFS_GENERATED_SCRIPT_DIR}/../lib/contract.sh"
    # Rebind the exact sibling contract at every generated entry. Imported
    # shell functions and environment state are never commissioning authority.
    if [[ ! -f "$canonical_contract" || -L "$canonical_contract" ]]; then
        log_error "lang.go: canonical runtime contract unavailable"
        return 1
    fi
    if ! builtin unset -f acfs_require_contract acfs_license_exclusion_profile_payload _acfs_license_profile_actual_sha256 acfs_license_policy_verify_profile acfs_license_policy_module_is_held acfs_license_policy_module_is_plain_mit_only acfs_license_policy_admit_entry acfs_r1_runtime_profile_payload _acfs_r1_sha256_file _acfs_r1_profile_actual_sha256 _acfs_r1_runtime_root _acfs_r1_verify_bound_file acfs_r1_runtime_verify_profile acfs_r1_runtime_module_is_held acfs_r1_runtime_module_is_planned acfs_r1_runtime_admit_entry _acfs_r1_array_csv acfs_r1_runtime_prepare_selection acfs_r1_runtime_validate_plan acfs_core_policy_enforce acfs_core_policy_reason acfs_core_policy_contract _acfs_core_policy_target_home acfs_core_policy_expected_binary_path acfs_core_policy_expected_bv_versioned_path acfs_core_policy_expected_binary_sha256 _acfs_core_policy_sha256_file _acfs_core_policy_version_output acfs_core_policy_admit_binary acfs_core_policy_admit_repair_source acfs_core_policy_enforce_installer_execution 2>/dev/null; then
        log_error "lang.go: imported runtime policy function is not replaceable"
        return 1
    fi
    # shellcheck disable=SC1090  # exact generated sibling
    if ! builtin source "$canonical_contract"; then
        log_error "lang.go: canonical runtime contract could not be loaded"
        return 1
    fi
    if [[ "${ACFS_R1_RUNTIME_PROFILE_ID:-}" != "R1-held-module-exclusion-runtime-v1" ]] || ! builtin declare -F acfs_r1_runtime_admit_entry >/dev/null 2>&1; then
        log_error "lang.go: exact R1 runtime profile unavailable"
        return 1
    fi
    if ! acfs_r1_runtime_admit_entry direct "${module_id}"; then
        log_error "lang.go: ${ACFS_R1_POLICY_REASON:-R1 runtime admission rejected the module}"
        return 1
    fi
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping lang.go (not selected)"
        return 0
    fi
    log_step "Installing lang.go"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: apt-get -o DPkg::Lock::Timeout=120 install -y golang-go (root)"
    else
        if ! run_as_root_shell <<'INSTALL_LANG_GO'
apt-get -o DPkg::Lock::Timeout=120 install -y golang-go
INSTALL_LANG_GO
        then
            log_error "lang.go: install command failed: apt-get -o DPkg::Lock::Timeout=120 install -y golang-go"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: go version (root)"
    else
        if ! run_as_root_shell <<'INSTALL_LANG_GO'
go version
INSTALL_LANG_GO
        then
            log_error "lang.go: verify failed: go version"
            return 1
        fi
    fi

    log_success "lang.go installed"
}

# Orchestrator-owned modules omitted from this library: users.ubuntu

# Category scripts are source-only libraries.
