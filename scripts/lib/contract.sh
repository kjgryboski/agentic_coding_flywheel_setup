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
            expected_contract="source_commit=7eaf34b76927b4deadc913889f50fb06a8f803d7;installer_url=https://raw.githubusercontent.com/Dicklesworthstone/beads_rust/7eaf34b76927b4deadc913889f50fb06a8f803d7/install.sh;installer_sha256=b2b3ed0ae2712e53a72d48afd5a980a7c1d346bb6e6b9fb9e4f3b20566726c2f;version=v0.5.3;artifact_url=https://github.com/Dicklesworthstone/beads_rust/releases/download/v0.5.3/br-0.5.3-linux_aarch64.tar.gz;artifact_sha256=9781aec596be155dfff31c0ab4d140d076107422e0e703c5137b2d2edcff4bfb;binary_sha256=f7d105e685da6c49dd87b0335d11d5fe2aa8765033a78cfbfb00dee7a4b1e123"
            if [[ "$supplied_contract" != "$expected_contract" ]]; then
                ACFS_CORE_POLICY_REASON="stack.beads_rust immutable admission contract mismatch"
                return 1
            fi
            # Doctor has no mutation authority and verifies the installed
            # binary below. Mutating routes must additionally prove that the
            # loaded installer registry still names the pinned source bytes.
            if [[ "$operation" != "doctor" ]]; then
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

acfs_core_policy_expected_binary_sha256() {
    case "${1:-}" in
        stack.beads_rust)
            printf '%s\n' "f7d105e685da6c49dd87b0335d11d5fe2aa8765033a78cfbfb00dee7a4b1e123"
            ;;
        stack.beads_viewer)
            printf '%s\n' "ee1dd03701a33d86e6496fb7021a96461e3c172e2a8be5b2ced554c7c378b320"
            ;;
        *)
            return 1
            ;;
    esac
}

_acfs_core_policy_sha256_file() {
    local binary_path="${1:-}"
    local output=""
    local actual_sha256=""

    [[ -n "$binary_path" ]] || return 1
    if [[ -x /usr/bin/sha256sum ]]; then
        output="$(/usr/bin/sha256sum "$binary_path" 2>/dev/null)" || return 1
    elif [[ -x /usr/bin/shasum ]]; then
        output="$(/usr/bin/shasum -a 256 "$binary_path" 2>/dev/null)" || return 1
    else
        return 1
    fi

    read -r actual_sha256 _ <<< "$output"
    [[ "$actual_sha256" =~ ^[0-9a-f]{64}$ ]] || return 1
    printf '%s\n' "$actual_sha256"
}

_acfs_core_policy_version_output() {
    local binary_path="${1:-}"

    [[ -n "$binary_path" ]] || return 1
    if [[ -x /usr/bin/timeout ]]; then
        /usr/bin/timeout 5 "$binary_path" --version 2>&1
    else
        "$binary_path" --version 2>&1
    fi
}

# Admit an installed core binary only after the caller's immutable source
# contract, its exact bytes, and its pinned version all agree. The digest is
# checked before executing the binary, so an arbitrary PATH entry cannot run
# merely because doctor or an installer wants to inspect its version.
acfs_core_policy_admit_binary() {
    local module_id="${1:-}"
    local operation="${2:-}"
    local supplied_contract="${3:-}"
    local binary_path="${4:-}"
    local expected_sha256=""
    local actual_sha256=""
    local version_output=""
    local version_pattern=""

    acfs_core_policy_enforce "$module_id" "$operation" "$supplied_contract" || return $?

    if [[ -z "$binary_path" || "$binary_path" != /* || ! -f "$binary_path" || ! -x "$binary_path" ]]; then
        ACFS_CORE_POLICY_REASON="$module_id admitted binary is unavailable or unsafe"
        return 1
    fi

    expected_sha256="$(acfs_core_policy_expected_binary_sha256 "$module_id" 2>/dev/null || true)"
    if [[ -z "$expected_sha256" ]]; then
        ACFS_CORE_POLICY_REASON="$module_id has no pinned binary digest"
        return 1
    fi

    actual_sha256="$(_acfs_core_policy_sha256_file "$binary_path" 2>/dev/null || true)"
    if [[ "$actual_sha256" != "$expected_sha256" ]]; then
        ACFS_CORE_POLICY_REASON="$module_id installed binary digest mismatch"
        return 1
    fi

    case "$module_id" in
        stack.beads_rust)
            version_pattern='(^|[[:space:]])v?0[.]5[.]3([[:space:]]|$)'
            ;;
        stack.beads_viewer)
            version_pattern='(^|[[:space:]])v?0[.]22[.]0([[:space:]]|$)'
            ;;
        *)
            ACFS_CORE_POLICY_REASON="$module_id has no pinned binary version"
            return 1
            ;;
    esac

    version_output="$(_acfs_core_policy_version_output "$binary_path" 2>/dev/null || true)"
    if [[ ! "$version_output" =~ $version_pattern ]]; then
        ACFS_CORE_POLICY_REASON="$module_id installed binary version mismatch"
        return 1
    fi

    ACFS_CORE_POLICY_REASON=""
    return 0
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

    local br_contract="source_commit=7eaf34b76927b4deadc913889f50fb06a8f803d7;installer_url=https://raw.githubusercontent.com/Dicklesworthstone/beads_rust/7eaf34b76927b4deadc913889f50fb06a8f803d7/install.sh;installer_sha256=b2b3ed0ae2712e53a72d48afd5a980a7c1d346bb6e6b9fb9e4f3b20566726c2f;version=v0.5.3;artifact_url=https://github.com/Dicklesworthstone/beads_rust/releases/download/v0.5.3/br-0.5.3-linux_aarch64.tar.gz;artifact_sha256=9781aec596be155dfff31c0ab4d140d076107422e0e703c5137b2d2edcff4bfb;binary_sha256=f7d105e685da6c49dd87b0335d11d5fe2aa8765033a78cfbfb00dee7a4b1e123"
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
