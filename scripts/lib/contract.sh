#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# ACFS Installer - Runtime Contract Validation
# Ensures required env vars and helper functions exist before
# invoking generated modules or orchestrator logic.
#
# NOTE: Do not enable strict mode here. This file is sourced
# by other scripts and must not leak set -euo pipefail.
# ============================================================

CONTRACT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure we have logging functions available
if [[ -z "${ACFS_BLUE:-}" ]]; then
    # shellcheck source=logging.sh
    source "$CONTRACT_SCRIPT_DIR/logging.sh" 2>/dev/null || true
fi

acfs_require_contract() {
    local context="${1:-generated}"
    local missing=()

    [[ -z "${TARGET_USER:-}" ]] && missing+=("TARGET_USER")
    [[ -z "${TARGET_HOME:-}" ]] && missing+=("TARGET_HOME")
    [[ -z "${MODE:-}" ]] && missing+=("MODE")

    # When running via curl|bash, SCRIPT_DIR is empty and we expect
    # a bootstrap directory to be prepared with libs, manifest, assets.
    if [[ -z "${SCRIPT_DIR:-}" ]]; then
        [[ -z "${ACFS_BOOTSTRAP_DIR:-}" ]] && missing+=("ACFS_BOOTSTRAP_DIR")
        [[ -z "${ACFS_LIB_DIR:-}" ]] && missing+=("ACFS_LIB_DIR")
        [[ -z "${ACFS_GENERATED_DIR:-}" ]] && missing+=("ACFS_GENERATED_DIR")
        [[ -z "${ACFS_ASSETS_DIR:-}" ]] && missing+=("ACFS_ASSETS_DIR")
        [[ -z "${ACFS_CHECKSUMS_YAML:-}" ]] && missing+=("ACFS_CHECKSUMS_YAML")
        [[ -z "${ACFS_MANIFEST_YAML:-}" ]] && missing+=("ACFS_MANIFEST_YAML")
    fi

    if ! declare -f log_detail >/dev/null 2>&1; then
        missing+=("log_detail function")
    fi
    if ! declare -f run_as_target >/dev/null 2>&1; then
        missing+=("run_as_target function")
    fi
    if ! declare -f run_as_target_shell >/dev/null 2>&1; then
        missing+=("run_as_target_shell function")
    fi
    if ! declare -f run_as_root_shell >/dev/null 2>&1; then
        missing+=("run_as_root_shell function")
    fi
    if ! declare -f run_as_current_shell >/dev/null 2>&1; then
        missing+=("run_as_current_shell function")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        if declare -f log_error >/dev/null 2>&1; then
            log_error "ACFS contract violation (${context})"
            if declare -f log_detail >/dev/null 2>&1; then
                log_detail "Missing: ${missing[*]}"
                log_detail "Fix: install.sh must source scripts/lib/*.sh, set required vars, and only then invoke generated module functions."
            else
                echo "    Missing: ${missing[*]}" >&2
                echo "    Fix: install.sh must source scripts/lib/*.sh, set required vars, and only then invoke generated module functions." >&2
            fi
        else
            echo "ERROR: ACFS contract violation (${context})" >&2
            echo "Missing: ${missing[*]}" >&2
            echo "Fix: install.sh must source scripts/lib/*.sh, set required vars, and only then invoke generated module functions." >&2
        fi
        return 1
    fi

    return 0
}

# ============================================================
# Commissioning Core Admission Policy
# ============================================================
#
# The core coordination trio has a stricter contract than the general
# checksum-verified installer registry. Every install, update, direct stack,
# generated-module, doctor, and managed-service entry point must call this
# function before performing or accepting core state. A missing operation or
# byte-for-byte contract mismatch is a hard failure.
acfs_core_policy_enforce() {
    local module_id="${1:-}"
    local operation="${2:-}"
    local supplied_contract="${3:-}"
    local expected_contract=""
    local installer_sha256=""

    ACFS_CORE_POLICY_REASON=""

    case "$operation" in
        install|update|doctor|service) ;;
        *)
            ACFS_CORE_POLICY_REASON="unsupported core policy operation: ${operation:-<empty>}"
            return 1
            ;;
    esac

    case "$module_id" in
        stack.mcp_agent_mail)
            ACFS_CORE_POLICY_REASON="C4 commissioning HOLD: exact-source build inputs, authenticated guest-loopback service inputs, fail-closed state ownership, and qualified substrate package identities are not admitted"
            return 1
            ;;
        stack.beads_rust)
            expected_contract="source_commit=7eaf34b76927b4deadc913889f50fb06a8f803d7;installer_url=https://raw.githubusercontent.com/Dicklesworthstone/beads_rust/7eaf34b76927b4deadc913889f50fb06a8f803d7/install.sh;installer_sha256=b2b3ed0ae2712e53a72d48afd5a980a7c1d346bb6e6b9fb9e4f3b20566726c2f;version=v0.5.3;artifact_url=https://github.com/Dicklesworthstone/beads_rust/releases/download/v0.5.3/br-0.5.3-linux_aarch64.tar.gz;artifact_sha256=9781aec596be155dfff31c0ab4d140d076107422e0e703c5137b2d2edcff4bfb"
            if [[ "$supplied_contract" != "$expected_contract" ]]; then
                ACFS_CORE_POLICY_REASON="stack.beads_rust immutable admission contract mismatch"
                return 1
            fi
            if [[ "${KNOWN_INSTALLERS[br]:-}" != "https://raw.githubusercontent.com/Dicklesworthstone/beads_rust/7eaf34b76927b4deadc913889f50fb06a8f803d7/install.sh" ]]; then
                ACFS_CORE_POLICY_REASON="stack.beads_rust installer registry identity mismatch"
                return 1
            fi
            installer_sha256="$(get_checksum br 2>/dev/null || true)"
            if [[ -z "$installer_sha256" ]]; then
                installer_sha256="${ACFS_UPSTREAM_SHA256[br]:-}"
            fi
            if [[ "$installer_sha256" != "b2b3ed0ae2712e53a72d48afd5a980a7c1d346bb6e6b9fb9e4f3b20566726c2f" ]]; then
                ACFS_CORE_POLICY_REASON="stack.beads_rust installer checksum admission mismatch"
                return 1
            fi
            ;;
        stack.beads_viewer)
            expected_contract="source_commit=95a706caf57fc5fde846a453da5f28677d4a81b8;version=v0.22.0;artifact_url=https://github.com/Dicklesworthstone/beads_viewer/releases/download/v0.22.0/bv_linux_arm64.tar.gz;archive_sha256=23d451b87bb9dccfb94fab416b0243d107919d9d56458087475afda5a617aa89;binary_sha256=ee1dd03701a33d86e6496fb7021a96461e3c172e2a8be5b2ced554c7c378b320;selected_member=bv"
            if [[ "$supplied_contract" != "$expected_contract" ]]; then
                ACFS_CORE_POLICY_REASON="stack.beads_viewer immutable admission contract mismatch"
                return 1
            fi
            ;;
        *)
            ACFS_CORE_POLICY_REASON="unknown core policy module: ${module_id:-<empty>}"
            return 1
            ;;
    esac

    return 0
}

acfs_core_policy_reason() {
    printf '%s\n' "${ACFS_CORE_POLICY_REASON:-core admission policy unavailable}"
}

# Guard the generic verified-installer helpers as well as their named callers.
# This closes direct helper invocation as a bypass: Agent Mail remains held,
# br requires the exact pinned execution argv, and bv is available only through
# its single-member content-addressed generated implementation.
acfs_core_policy_enforce_installer_execution() {
    if [[ $# -lt 3 ]]; then
        ACFS_CORE_POLICY_REASON="core installer execution policy requires module, operation, and target home"
        return 1
    fi

    local module_id="${1:-}"
    local operation="${2:-}"
    local target_home="${3:-}"
    shift 3

    local br_contract="source_commit=7eaf34b76927b4deadc913889f50fb06a8f803d7;installer_url=https://raw.githubusercontent.com/Dicklesworthstone/beads_rust/7eaf34b76927b4deadc913889f50fb06a8f803d7/install.sh;installer_sha256=b2b3ed0ae2712e53a72d48afd5a980a7c1d346bb6e6b9fb9e4f3b20566726c2f;version=v0.5.3;artifact_url=https://github.com/Dicklesworthstone/beads_rust/releases/download/v0.5.3/br-0.5.3-linux_aarch64.tar.gz;artifact_sha256=9781aec596be155dfff31c0ab4d140d076107422e0e703c5137b2d2edcff4bfb"
    local -a expected_br_args=()
    local -a supplied_args=("$@")
    local index=0

    case "$module_id" in
        stack.mcp_agent_mail)
            acfs_core_policy_enforce "$module_id" "$operation" ""
            return $?
            ;;
        stack.beads_viewer)
            ACFS_CORE_POLICY_REASON="stack.beads_viewer direct installer execution is forbidden; use the content-addressed generated module"
            return 1
            ;;
        stack.beads_rust)
            if [[ -z "$target_home" || "$target_home" != /* || "$target_home" == "/" ]]; then
                ACFS_CORE_POLICY_REASON="stack.beads_rust requires an absolute non-root target home"
                return 1
            fi
            expected_br_args=(
                --version v0.5.3
                --dest "$target_home/.local/bin"
                --artifact-url "https://github.com/Dicklesworthstone/beads_rust/releases/download/v0.5.3/br-0.5.3-linux_aarch64.tar.gz"
                --checksum "9781aec596be155dfff31c0ab4d140d076107422e0e703c5137b2d2edcff4bfb"
            )
            if [[ $# -ne ${#expected_br_args[@]} ]]; then
                ACFS_CORE_POLICY_REASON="stack.beads_rust installer argv mismatch"
                return 1
            fi
            for index in "${!expected_br_args[@]}"; do
                if [[ "${supplied_args[$index]}" != "${expected_br_args[$index]}" ]]; then
                    ACFS_CORE_POLICY_REASON="stack.beads_rust installer argv mismatch"
                    return 1
                fi
            done
            acfs_core_policy_enforce "$module_id" "$operation" "$br_contract"
            return $?
            ;;
        *)
            ACFS_CORE_POLICY_REASON="unknown core installer module: ${module_id:-<empty>}"
            return 1
            ;;
    esac
}
