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
# R1 is the content-addressed runtime selection envelope for the exact U5V2
# remediation base.  These literals are deliberately reset on every source so
# caller-supplied environment values cannot turn a HOLD or an out-of-plan
# module into runtime authority.
ACFS_R1_RUNTIME_PROFILE_ID="R1-held-module-exclusion-runtime-v1"
ACFS_R1_RUNTIME_PROFILE_SHA256="3dd1bf41b051765c36cc75c210a6482d624fc85448cfba02841300eff8ce2bdc"
ACFS_R1_SOURCE_JSON_SHA256="33bca439667099cc56b98539aa825658a5f2f72f5d9dbd28d9212ab9cf3a427c"
ACFS_R1_SOURCE_MD_SHA256="7141b4fa4c5362a44f7f0f61bdec7a7eef9b4bfbc6f8c3f408bb4ab8d18ca37b"
ACFS_R1_U5V2_VERIFIER_SHA256="e70a27302ec46439f51797b4945ae54aae81ce9e4d49daa7bbc3e971cfc24445"
ACFS_R1_U5_BASE_COMMIT="890bd2e235c3f29a94029b6d4b3c4308abb6f027"
ACFS_R1_U5_BASE_TREE="8e1da65b3345a25fdac54eec3959932a70bab5fd"
ACFS_R1_MANIFEST_SHA256="61fed87a0aa299fc6e6c657afb23845ec46137392393d0113e8d11b50b7dda65"
ACFS_R1_GENERATOR_SHA256="db0fa865c687630ec9b6290db9039ad457c5a8f0bc64f604af5c46a95ac0ea6f"
ACFS_R1_MANIFEST_INDEX_SHA256="6329351b2b546ee5ee5ac3b00535972664a246bcc907175a4d7f45d2f377beae"
ACFS_R1_INSTALL_SH_SHA256="3a47aefccdc35e92afe39c50c22071f29b25bfa3c4bb41d9f2147f752797c764"
ACFS_R1_SECURITY_SHA256="047fae70c75de78e903654f7a59e94f7ef510c26d4dbf0face1ade7696cd89be"
ACFS_R1_CHECKSUMS_SHA256="36bbd2eba33e6ef70871f8c321623ba6d0b46720569c23b7ea5f1e91c9d0e83c"
ACFS_R1_INSTALL_HELPERS_SHA256="707e771ceebc84c8a2bbe043059fb1ed361bb10fffc8ce3314ccba949839f07f"
ACFS_R1_PROGRESS_SHA256="c75a9d6ff3c4be155b892344e135ed12b99ca444a1e6dca61d491f200d3719a7"
ACFS_R1_MODULE_SELECTOR_SHA256="b524b6179e6eed45852d876043e17ff5563bbfb32b22401752ff9d11079c61b0"
ACFS_R1_EXPORT_CONFIG_SHA256="0cfa29731605ca45377a6e10fdd8e261bc16aff7de8219af67542c35a017e787"
ACFS_R1_STATE_SHA256="76409a938231e88a3232d65ccbca095f1b505bee893eaa463b33b851df6a0813"
ACFS_R1_STACK_SHA256="4350275e6776d76a496cd9ee8ddb3e10449e2836c6dece032503e17e7d674e58"
ACFS_R1_UPDATE_SHA256="4774a90d8911b5c18e6aafb5e33114314c85188aeaa22e6777b2a20e6a054043"
ACFS_R1_DOCTOR_SHA256="ffdacc227261ea77b1798dc7b4a97aeb2ccfc2875acf6b764350131c7b74994a"
ACFS_R1_DOCTOR_FIX_SHA256="5abc547533c4074630c973cac403a393497954a30952f24d755d52f456882b22"
ACFS_R1_SERVICES_SHA256="eba54b8c1b54974fccc56a969e702c5e8f9f928a334692736ff53ddf1ebd68f5"
ACFS_R1_GENERATED_BASE_SHA256="a7d9e2d5f2aa028cfb83f1c470c0e3eb95447f4f80dd5eab0201c9c47ae12391"
ACFS_R1_GENERATED_USERS_SHA256="b90a4abab9dd9414ccfcac98ef4c09c57dc96950294a469bd58e984b4a68826c"
ACFS_R1_GENERATED_FILESYSTEM_SHA256="f9b22dfc41c435be31f863fc7ad37f9ebaf6e795dac5b87d4be78eca28fc51ab"
ACFS_R1_GENERATED_CLI_SHA256="1871b26476c88926c107c047d83cb90eb0cb2a0c3ab0bafbe632b6989e6247b6"
ACFS_R1_GENERATED_LANG_SHA256="6976f5724294934aa320da4ac50323d69d22349184f5ec60a632df5fca8605c1"
ACFS_R1_GENERATED_STACK_SHA256="ac6c6138410d71f94ebd8231707d7994b182c01d241678341fb952c64cce6320"
ACFS_R1_GENERATED_DOCTOR_SHA256="5e3389aac6674ad652b58e54ee9f5147ac4fe885ec34271777ee6411d597be1e"
ACFS_W2_GENERATED_PARTIAL_SAFE_SHA256="88a375113e99108f6567bd210ac38cb5f0d268de109890da36d5056c1b4942b3"
ACFS_R1_SEED_CSV="users.ubuntu,base.filesystem,cli.modern,stack.mcp_agent_mail,stack.beads_rust,stack.beads_viewer"
ACFS_R1_PLAN_CSV="base.system,users.ubuntu,base.filesystem,cli.modern,lang.bun,lang.uv,lang.rust,lang.go,stack.mcp_agent_mail,stack.beads_rust,stack.beads_viewer"
ACFS_R1_HELD_CSV="stack.caam,stack.slb,stack.srps,stack.storage_ballast_helper,stack.cross_agent_session_resumer,stack.doodlestein_self_releaser,stack.agent_settings_backup,stack.pcr,stack.franken_markdown,stack.power_failure_resumer"
ACFS_R1_POLICY_REASON=""

# LIC1 + LIC2 are a separate, content-addressed exclusion authority.  This
# profile deliberately contains only packet identity and the classified guide
# module coordinates.  It does not read, source, inspect, or execute any held
# repository.  PFR's plain-MIT license classification is non-authorizing: its
# pre-existing qualification HOLD remains in ACFS_R1_HELD_CSV above.
ACFS_LICENSE_EXCLUSION_PROFILE_ID="LICX-core-guide-license-exclusion-v1"
ACFS_LICENSE_EXCLUSION_PROFILE_SHA256="f7e9575697b7e6d18f5059c92430a01fb0bbd43b944c3b1073be4804badbe513"
ACFS_LICENSE_LIC1_SHA256="9bfd85c340c6223482e07b96c668600e0db9a18b8a4f25e45f77f0129af63300"
ACFS_LICENSE_LIC2_SHA256="89b56c5a62cea238a9e9d3b6ff88a2923a88bafd45c982a523dba5c7de5b51ee"
ACFS_LICENSE_HELD_COUNT="27"
ACFS_LICENSE_PLAIN_MIT_ONLY_COUNT="1"
ACFS_LICENSE_UNRESOLVED_COUNT="0"
ACFS_LICENSE_HELD_CSV="stack.beads_rust,stack.agent_settings_backup,stack.caam,stack.cross_agent_session_resumer,stack.pcr,stack.automated_plan_reviser,stack.brenner_bot,stack.eidetic_engine_cli,stack.frankensearch,stack.jeffreysprompts,stack.meta_skill,stack.pi_agent_rust,stack.process_triage,stack.rch,stack.ru,stack.doodlestein_self_releaser,stack.franken_markdown,stack.slb,stack.srps,stack.storage_ballast_helper,stack.mcp_agent_mail,stack.beads_viewer,stack.ultimate_bug_scanner,stack.dcg,stack.cass,stack.cm,stack.ntm"
ACFS_LICENSE_PLAIN_MIT_ONLY_CSV="stack.power_failure_resumer"
ACFS_LICENSE_R1_PLAN_HELD_CSV="stack.mcp_agent_mail,stack.beads_rust,stack.beads_viewer"
ACFS_LICENSE_POLICY_REASON=""

# W2 adds a separate, explicit commissioning authority without changing the
# U6/R1 default HOLD.  The caller must name the exact immutable allowlist file;
# no Boolean flag, environment-only assertion, or inferred license status can
# activate this path.
ACFS_W2_PARTIAL_SAFE_ALLOWLIST_SHA256="736ce053c42c91b4219cc13dde7a604c33158e1369f3d4d91031672da80f3633"
ACFS_W2_PARTIAL_SAFE_SEED_CSV="users.ubuntu,base.filesystem,cli.modern,lang.bun,lang.uv,lang.rust,lang.go"
ACFS_W2_PARTIAL_SAFE_PLAN_CSV="base.system,users.ubuntu,base.filesystem,cli.modern,lang.bun,lang.uv,lang.rust,lang.go"
ACFS_W2_PARTIAL_SAFE_POLICY_REASON=""

acfs_w2_partial_safe_requested() {
    [[ -n "${ACFS_PARTIAL_SAFE_ALLOWLIST_FILE:-}" ]]
}

acfs_w2_partial_safe_verify_allowlist() {
    local allowlist="${ACFS_PARTIAL_SAFE_ALLOWLIST_FILE:-}"
    local canonical=""
    local actual_sha256=""
    local mode=""
    local links=""
    local owner=""

    ACFS_W2_PARTIAL_SAFE_POLICY_REASON=""
    if [[ -z "$allowlist" || "$allowlist" != /* || ! -f "$allowlist" || -L "$allowlist" ]]; then
        ACFS_W2_PARTIAL_SAFE_POLICY_REASON="W2 PARTIAL_SAFE allowlist is missing, non-absolute, nonregular, or a symlink"
        return 1
    fi
    canonical="$(cd "$(dirname "$allowlist")" 2>/dev/null && printf '%s/%s\n' "$PWD" "$(basename "$allowlist")")"
    if [[ -z "$canonical" || "$canonical" != "$allowlist" ]]; then
        ACFS_W2_PARTIAL_SAFE_POLICY_REASON="W2 PARTIAL_SAFE allowlist path is not canonical"
        return 1
    fi
    if [[ "$(uname -s 2>/dev/null)" == "Darwin" ]]; then
        mode="$(/usr/bin/stat -f '%Lp' "$allowlist" 2>/dev/null || true)"
        links="$(/usr/bin/stat -f '%l' "$allowlist" 2>/dev/null || true)"
        owner="$(/usr/bin/stat -f '%u' "$allowlist" 2>/dev/null || true)"
    else
        mode="$(/usr/bin/stat -c '%a' "$allowlist" 2>/dev/null || true)"
        links="$(/usr/bin/stat -c '%h' "$allowlist" 2>/dev/null || true)"
        owner="$(/usr/bin/stat -c '%u' "$allowlist" 2>/dev/null || true)"
    fi
    if [[ ! "$mode" =~ ^[0-7]{3,4}$ ]] || (( (8#$mode & 8#222) != 0 )); then
        ACFS_W2_PARTIAL_SAFE_POLICY_REASON="W2 PARTIAL_SAFE allowlist must have no write bits"
        return 1
    fi
    if [[ "$links" != "1" || "$owner" != "$EUID" ]]; then
        ACFS_W2_PARTIAL_SAFE_POLICY_REASON="W2 PARTIAL_SAFE allowlist must be single-link and owned by the commissioning identity"
        return 1
    fi
    actual_sha256="$(_acfs_r1_sha256_file "$allowlist" 2>/dev/null || true)"
    if [[ "$actual_sha256" != "$ACFS_W2_PARTIAL_SAFE_ALLOWLIST_SHA256" ]]; then
        ACFS_W2_PARTIAL_SAFE_POLICY_REASON="W2 PARTIAL_SAFE allowlist digest mismatch"
        return 1
    fi
    return 0
}

acfs_w2_partial_safe_active() {
    acfs_w2_partial_safe_requested || return 1
    acfs_w2_partial_safe_verify_allowlist
}

acfs_license_exclusion_profile_payload() {
    /bin/cat <<'ACFS_LICENSE_EXCLUSION_PROFILE'
schema_version=1
profile_id=LICX-core-guide-license-exclusion-v1
lic1_sha256=9bfd85c340c6223482e07b96c668600e0db9a18b8a4f25e45f77f0129af63300
lic2_sha256=89b56c5a62cea238a9e9d3b6ff88a2923a88bafd45c982a523dba5c7de5b51ee
held_count=27
plain_mit_license_only_count=1
unresolved_count=0
r1_plan_held_modules=stack.mcp_agent_mail,stack.beads_rust,stack.beads_viewer
prior_qualifications=historical_hold_evidence_not_authorization
held_release_condition=express_written_permission
runtime_authorization=none
row=stack.beads_rust|Dicklesworthstone/beads_rust|7eaf34b76927b4deadc913889f50fb06a8f803d7|held_lic1
row=stack.agent_settings_backup|Dicklesworthstone/agent_settings_backup_script|7a060386c06d50b7f4c1440fd1da15b2ee447bc4|held_lic1
row=stack.caam|Dicklesworthstone/coding_agent_account_manager|afb72f80755a877c2e0037154e80771ad69fec91|held_lic1
row=stack.cross_agent_session_resumer|Dicklesworthstone/cross_agent_session_resumer|37af44abc16a38c76990b25b163fe42e0d7fffd1|held_lic1
row=stack.pcr|Dicklesworthstone/post_compact_reminder|c1f4811323dbf826fbf646dd85640b664fe6666b|held_lic1
row=stack.automated_plan_reviser|Dicklesworthstone/automated_plan_reviser_pro|8357f66c0f2b5a6274cca489a57f0e3e1c042235|held_lic1
row=stack.brenner_bot|Dicklesworthstone/brenner_bot|34a59a89846d14d7504523041eff960d2d80e434|held_lic1
row=stack.eidetic_engine_cli|Dicklesworthstone/eidetic_engine_cli|0fc6801c91edc0764cf405b049024a25c3199e09|held_lic1
row=stack.frankensearch|Dicklesworthstone/frankensearch|22859f74056c31fd3a713bacecd4a1f22f0cf82d|held_lic1
row=stack.jeffreysprompts|Dicklesworthstone/jeffreysprompts.com|2cec2d5257ef0da32a856b51673f243b6c72a3e2|held_lic1
row=stack.meta_skill|Dicklesworthstone/meta_skill|2a4bc62a04c98d8812bfe68b77c862d87e1731e3|held_lic1
row=stack.pi_agent_rust|Dicklesworthstone/pi_agent_rust|e23c4622f8bc4038a5e061ee3640a0e9206ec5cc|held_lic1
row=stack.process_triage|Dicklesworthstone/process_triage|7f455d51e5857c245a72cdea29a1ad84b1d942ad|held_lic1
row=stack.rch|Dicklesworthstone/remote_compilation_helper|0a982fdee2ca5ce26791dd17b83285916a7b97f6|held_lic1
row=stack.ru|Dicklesworthstone/repo_updater|72d8c6da4008a08480d7ef2e66fc165969248400|held_lic1
row=stack.doodlestein_self_releaser|Dicklesworthstone/doodlestein_self_releaser|e10233a5dfb49b014ecb54b204af4cb553d58741|held_lic1
row=stack.franken_markdown|Dicklesworthstone/franken_markdown|5637bad86e3c0deacab6411a734715015b143a12|held_lic1
row=stack.slb|Dicklesworthstone/slb|707af1db44ed3070c0ff93db75f7720a53335320|held_lic1
row=stack.srps|Dicklesworthstone/system_resource_protection_script|49288dd0dc37481b6f0a0a782d7c78ac123f201c|held_lic1
row=stack.storage_ballast_helper|Dicklesworthstone/storage_ballast_helper|587c332962883d1fff40a183c2d0fb0ef615cfe6|held_lic1
row=stack.mcp_agent_mail|Dicklesworthstone/mcp_agent_mail|7bce6f031bc29331d7e5aa09a9f67c75c2ab5430|held_lic2
row=stack.beads_viewer|Dicklesworthstone/beads_viewer|95a706caf57fc5fde846a453da5f28677d4a81b8|held_lic2
row=stack.ultimate_bug_scanner|Dicklesworthstone/ultimate_bug_scanner|0af10c926d6fbb14a1f589326d75c03f610207f0|held_lic2
row=stack.dcg|Dicklesworthstone/destructive_command_guard|d1ada2d0136c64146726bdc13b7147b6023c3bad|held_lic2
row=stack.cass|Dicklesworthstone/coding_agent_session_search|aa2023301a0253cb045eef77335dde16b53f41cf|held_lic2
row=stack.cm|Dicklesworthstone/cass_memory_system|c173d50f29c2d0494312bf7930dbf22b8a26d860|held_lic2
row=stack.ntm|Dicklesworthstone/ntm|415d479de50f6349d744a3f8d3f7a1b5d7d92a9b|held_lic2
row=stack.power_failure_resumer|Dicklesworthstone/power_failure_resumer|6557be08fc3b9298892ae448dc4b68ea2b874703|plain_mit_license_only_non_authorizing
ACFS_LICENSE_EXCLUSION_PROFILE
}

acfs_r1_runtime_profile_payload() {
    /bin/cat <<'ACFS_R1_RUNTIME_PROFILE'
schema_version=1
profile_id=R1-held-module-exclusion-runtime-v1
source_json_sha256=33bca439667099cc56b98539aa825658a5f2f72f5d9dbd28d9212ab9cf3a427c
source_markdown_sha256=7141b4fa4c5362a44f7f0f61bdec7a7eef9b4bfbc6f8c3f408bb4ab8d18ca37b
u5v2_verifier_sha256=e70a27302ec46439f51797b4945ae54aae81ce9e4d49daa7bbc3e971cfc24445
u5_base_commit=890bd2e235c3f29a94029b6d4b3c4308abb6f027
u5_base_tree=8e1da65b3345a25fdac54eec3959932a70bab5fd
manifest_sha256=61fed87a0aa299fc6e6c657afb23845ec46137392393d0113e8d11b50b7dda65
generator_sha256=db0fa865c687630ec9b6290db9039ad457c5a8f0bc64f604af5c46a95ac0ea6f
manifest_index_sha256=6329351b2b546ee5ee5ac3b00535972664a246bcc907175a4d7f45d2f377beae
install_sh_sha256=3a47aefccdc35e92afe39c50c22071f29b25bfa3c4bb41d9f2147f752797c764
security_sha256=047fae70c75de78e903654f7a59e94f7ef510c26d4dbf0face1ade7696cd89be
checksums_sha256=36bbd2eba33e6ef70871f8c321623ba6d0b46720569c23b7ea5f1e91c9d0e83c
install_helpers_sha256=707e771ceebc84c8a2bbe043059fb1ed361bb10fffc8ce3314ccba949839f07f
progress_sha256=c75a9d6ff3c4be155b892344e135ed12b99ca444a1e6dca61d491f200d3719a7
module_selector_sha256=b524b6179e6eed45852d876043e17ff5563bbfb32b22401752ff9d11079c61b0
export_config_sha256=0cfa29731605ca45377a6e10fdd8e261bc16aff7de8219af67542c35a017e787
state_sha256=76409a938231e88a3232d65ccbca095f1b505bee893eaa463b33b851df6a0813
stack_sha256=4350275e6776d76a496cd9ee8ddb3e10449e2836c6dece032503e17e7d674e58
update_sha256=4774a90d8911b5c18e6aafb5e33114314c85188aeaa22e6777b2a20e6a054043
doctor_sha256=ffdacc227261ea77b1798dc7b4a97aeb2ccfc2875acf6b764350131c7b74994a
doctor_fix_sha256=5abc547533c4074630c973cac403a393497954a30952f24d755d52f456882b22
services_sha256=eba54b8c1b54974fccc56a969e702c5e8f9f928a334692736ff53ddf1ebd68f5
generated_base_sha256=a7d9e2d5f2aa028cfb83f1c470c0e3eb95447f4f80dd5eab0201c9c47ae12391
generated_users_sha256=b90a4abab9dd9414ccfcac98ef4c09c57dc96950294a469bd58e984b4a68826c
generated_filesystem_sha256=f9b22dfc41c435be31f863fc7ad37f9ebaf6e795dac5b87d4be78eca28fc51ab
generated_cli_sha256=1871b26476c88926c107c047d83cb90eb0cb2a0c3ab0bafbe632b6989e6247b6
generated_lang_sha256=6976f5724294934aa320da4ac50323d69d22349184f5ec60a632df5fca8605c1
generated_stack_sha256=ac6c6138410d71f94ebd8231707d7994b182c01d241678341fb952c64cce6320
generated_doctor_sha256=5e3389aac6674ad652b58e54ee9f5147ac4fe885ec34271777ee6411d597be1e
w2_generated_partial_safe_sha256=88a375113e99108f6567bd210ac38cb5f0d268de109890da36d5056c1b4942b3
license_exclusion_profile_id=LICX-core-guide-license-exclusion-v1
license_exclusion_profile_sha256=f7e9575697b7e6d18f5059c92430a01fb0bbd43b944c3b1073be4804badbe513
lic1_sha256=9bfd85c340c6223482e07b96c668600e0db9a18b8a4f25e45f77f0129af63300
lic2_sha256=89b56c5a62cea238a9e9d3b6ff88a2923a88bafd45c982a523dba5c7de5b51ee
license_held_modules=stack.beads_rust,stack.agent_settings_backup,stack.caam,stack.cross_agent_session_resumer,stack.pcr,stack.automated_plan_reviser,stack.brenner_bot,stack.eidetic_engine_cli,stack.frankensearch,stack.jeffreysprompts,stack.meta_skill,stack.pi_agent_rust,stack.process_triage,stack.rch,stack.ru,stack.doodlestein_self_releaser,stack.franken_markdown,stack.slb,stack.srps,stack.storage_ballast_helper,stack.mcp_agent_mail,stack.beads_viewer,stack.ultimate_bug_scanner,stack.dcg,stack.cass,stack.cm,stack.ntm
license_plain_mit_only=stack.power_failure_resumer
license_r1_plan_held=stack.mcp_agent_mail,stack.beads_rust,stack.beads_viewer
explicit_seeds=users.ubuntu,base.filesystem,cli.modern,stack.mcp_agent_mail,stack.beads_rust,stack.beads_viewer
resolved_plan=base.system,users.ubuntu,base.filesystem,cli.modern,lang.bun,lang.uv,lang.rust,lang.go,stack.mcp_agent_mail,stack.beads_rust,stack.beads_viewer
held_modules=stack.caam,stack.slb,stack.srps,stack.storage_ballast_helper,stack.cross_agent_session_resumer,stack.doodlestein_self_releaser,stack.agent_settings_backup,stack.pcr,stack.franken_markdown,stack.power_failure_resumer
generated_dispatch=required
dependency_closure=required
out_of_plan_lifecycle=deny
agent_mail_c5_capsule=required_but_absent
ACFS_R1_RUNTIME_PROFILE
}

_acfs_r1_sha256_file() {
    local file_path="${1:-}"
    local output=""
    local actual_sha256=""

    [[ -n "$file_path" && -f "$file_path" && ! -L "$file_path" ]] || return 1
    if [[ -x /usr/bin/sha256sum ]]; then
        output="$(/usr/bin/sha256sum "$file_path" 2>/dev/null)" || return 1
    elif [[ -x /usr/bin/shasum ]]; then
        output="$(/usr/bin/shasum -a 256 "$file_path" 2>/dev/null)" || return 1
    else
        return 1
    fi
    read -r actual_sha256 _ <<< "$output"
    [[ "$actual_sha256" =~ ^[0-9a-f]{64}$ ]] || return 1
    printf '%s\n' "$actual_sha256"
}

_acfs_r1_profile_actual_sha256() {
    local output=""
    local actual_sha256=""

    if [[ -x /usr/bin/sha256sum ]]; then
        output="$(acfs_r1_runtime_profile_payload | /usr/bin/sha256sum 2>/dev/null)" || return 1
    elif [[ -x /usr/bin/shasum ]]; then
        output="$(acfs_r1_runtime_profile_payload | /usr/bin/shasum -a 256 2>/dev/null)" || return 1
    else
        return 1
    fi
    read -r actual_sha256 _ <<< "$output"
    [[ "$actual_sha256" =~ ^[0-9a-f]{64}$ ]] || return 1
    printf '%s\n' "$actual_sha256"
}

_acfs_license_profile_actual_sha256() {
    local output=""
    local actual_sha256=""

    if [[ -x /usr/bin/sha256sum ]]; then
        output="$(acfs_license_exclusion_profile_payload | /usr/bin/sha256sum 2>/dev/null)" || return 1
    elif [[ -x /usr/bin/shasum ]]; then
        output="$(acfs_license_exclusion_profile_payload | /usr/bin/shasum -a 256 2>/dev/null)" || return 1
    else
        return 1
    fi
    read -r actual_sha256 _ <<< "$output"
    [[ "$actual_sha256" =~ ^[0-9a-f]{64}$ ]] || return 1
    printf '%s\n' "$actual_sha256"
}

acfs_license_policy_verify_profile() {
    local actual_profile_sha256=""

    ACFS_LICENSE_POLICY_REASON=""
    if [[ "${ACFS_LICENSE_EXCLUSION_PROFILE_ID:-}" != "LICX-core-guide-license-exclusion-v1" \
        || "${ACFS_LICENSE_EXCLUSION_PROFILE_SHA256:-}" != "f7e9575697b7e6d18f5059c92430a01fb0bbd43b944c3b1073be4804badbe513" \
        || "${ACFS_LICENSE_LIC1_SHA256:-}" != "9bfd85c340c6223482e07b96c668600e0db9a18b8a4f25e45f77f0129af63300" \
        || "${ACFS_LICENSE_LIC2_SHA256:-}" != "89b56c5a62cea238a9e9d3b6ff88a2923a88bafd45c982a523dba5c7de5b51ee" \
        || "${ACFS_LICENSE_HELD_COUNT:-}" != "27" \
        || "${ACFS_LICENSE_PLAIN_MIT_ONLY_COUNT:-}" != "1" \
        || "${ACFS_LICENSE_UNRESOLVED_COUNT:-}" != "0" \
        || "${ACFS_LICENSE_HELD_CSV:-}" != "stack.beads_rust,stack.agent_settings_backup,stack.caam,stack.cross_agent_session_resumer,stack.pcr,stack.automated_plan_reviser,stack.brenner_bot,stack.eidetic_engine_cli,stack.frankensearch,stack.jeffreysprompts,stack.meta_skill,stack.pi_agent_rust,stack.process_triage,stack.rch,stack.ru,stack.doodlestein_self_releaser,stack.franken_markdown,stack.slb,stack.srps,stack.storage_ballast_helper,stack.mcp_agent_mail,stack.beads_viewer,stack.ultimate_bug_scanner,stack.dcg,stack.cass,stack.cm,stack.ntm" \
        || "${ACFS_LICENSE_PLAIN_MIT_ONLY_CSV:-}" != "stack.power_failure_resumer" \
        || "${ACFS_LICENSE_R1_PLAN_HELD_CSV:-}" != "stack.mcp_agent_mail,stack.beads_rust,stack.beads_viewer" ]]; then
        ACFS_LICENSE_POLICY_REASON="LIC1+LIC2 exclusion profile bindings were shadowed"
        return 1
    fi
    actual_profile_sha256="$(_acfs_license_profile_actual_sha256 2>/dev/null || true)"
    if [[ "$actual_profile_sha256" != "$ACFS_LICENSE_EXCLUSION_PROFILE_SHA256" ]]; then
        ACFS_LICENSE_POLICY_REASON="LIC1+LIC2 exclusion profile digest mismatch"
        return 1
    fi
    return 0
}

acfs_license_policy_module_is_held() {
    local module_id="${1:-}"
    [[ -n "$module_id" ]] || return 1
    case ",$ACFS_LICENSE_HELD_CSV," in
        *",$module_id,"*) return 0 ;;
        *) return 1 ;;
    esac
}

acfs_license_policy_module_is_plain_mit_only() {
    local module_id="${1:-}"
    [[ -n "$module_id" ]] || return 1
    case ",$ACFS_LICENSE_PLAIN_MIT_ONLY_CSV," in
        *",$module_id,"*) return 0 ;;
        *) return 1 ;;
    esac
}

acfs_license_policy_admit_entry() {
    local entry="${1:-}"
    local module_id="${2:-}"

    ACFS_LICENSE_POLICY_REASON=""
    acfs_license_policy_verify_profile || return $?

    case "$entry" in
        default|filtered|direct|install|update|doctor|doctor-fix|doctor-fix-finalize|repair|autofix|resume|finalize|failure-cleanup|service|configuration|list|probe|plan|print|helper) ;;
        *)
            ACFS_LICENSE_POLICY_REASON="unsupported LIC1+LIC2 lifecycle entry: ${entry:-<empty>}"
            return 1
            ;;
    esac

    if [[ -n "$module_id" ]]; then
        if acfs_license_policy_module_is_held "$module_id"; then
            ACFS_LICENSE_POLICY_REASON="LIC1+LIC2 HOLD rejects $module_id before $entry; express written permission is absent (LIC1 $ACFS_LICENSE_LIC1_SHA256; LIC2 $ACFS_LICENSE_LIC2_SHA256)"
            return 1
        fi
        # PFR is license-only plain MIT.  This function records that narrow
        # classification; the R1 qualification HOLD still rejects it later.
        return 0
    fi

    if acfs_w2_partial_safe_requested; then
        if acfs_w2_partial_safe_verify_allowlist; then
            return 0
        fi
        ACFS_LICENSE_POLICY_REASON="${ACFS_W2_PARTIAL_SAFE_POLICY_REASON:-W2 PARTIAL_SAFE allowlist verification failed}"
        return 1
    fi

    ACFS_LICENSE_POLICY_REASON="LIC1+LIC2 HOLD rejects moduleless $entry before the R1 plan can inspect stack.mcp_agent_mail, stack.beads_rust, or stack.beads_viewer; express written permission is absent"
    return 1
}

_acfs_r1_runtime_root() {
    local runtime_root=""

    runtime_root="$(cd "$CONTRACT_SCRIPT_DIR/../.." 2>/dev/null && pwd -P)" || return 1
    [[ -n "$runtime_root" && "$runtime_root" == /* && "$runtime_root" != "/" ]] || return 1
    printf '%s\n' "$runtime_root"
}

_acfs_r1_verify_bound_file() {
    local runtime_root="${1:-}"
    local relative_path="${2:-}"
    local expected_sha256="${3:-}"
    local actual_sha256=""

    [[ -n "$runtime_root" && -n "$relative_path" && "$expected_sha256" =~ ^[0-9a-f]{64}$ ]] || return 1
    actual_sha256="$(_acfs_r1_sha256_file "$runtime_root/$relative_path" 2>/dev/null || true)"
    if [[ "$actual_sha256" != "$expected_sha256" ]]; then
        ACFS_R1_POLICY_REASON="R1 bound source identity mismatch: $relative_path"
        return 1
    fi
    return 0
}

acfs_r1_runtime_verify_profile() {
    local actual_profile_sha256=""
    local runtime_root=""

    ACFS_R1_POLICY_REASON=""
    if ! acfs_license_policy_verify_profile; then
        ACFS_R1_POLICY_REASON="${ACFS_LICENSE_POLICY_REASON:-LIC1+LIC2 exclusion profile is unavailable}"
        return 1
    fi
    if [[ "${ACFS_R1_RUNTIME_PROFILE_ID:-}" != "R1-held-module-exclusion-runtime-v1" \
        || "${ACFS_R1_RUNTIME_PROFILE_SHA256:-}" != "3dd1bf41b051765c36cc75c210a6482d624fc85448cfba02841300eff8ce2bdc" \
        || "${ACFS_R1_SOURCE_JSON_SHA256:-}" != "33bca439667099cc56b98539aa825658a5f2f72f5d9dbd28d9212ab9cf3a427c" \
        || "${ACFS_R1_SOURCE_MD_SHA256:-}" != "7141b4fa4c5362a44f7f0f61bdec7a7eef9b4bfbc6f8c3f408bb4ab8d18ca37b" \
        || "${ACFS_R1_U5V2_VERIFIER_SHA256:-}" != "e70a27302ec46439f51797b4945ae54aae81ce9e4d49daa7bbc3e971cfc24445" \
        || "${ACFS_R1_U5_BASE_COMMIT:-}" != "890bd2e235c3f29a94029b6d4b3c4308abb6f027" \
        || "${ACFS_R1_U5_BASE_TREE:-}" != "8e1da65b3345a25fdac54eec3959932a70bab5fd" \
        || "${ACFS_R1_MANIFEST_SHA256:-}" != "61fed87a0aa299fc6e6c657afb23845ec46137392393d0113e8d11b50b7dda65" \
        || "${ACFS_R1_GENERATOR_SHA256:-}" != "db0fa865c687630ec9b6290db9039ad457c5a8f0bc64f604af5c46a95ac0ea6f" \
        || "${ACFS_R1_MANIFEST_INDEX_SHA256:-}" != "6329351b2b546ee5ee5ac3b00535972664a246bcc907175a4d7f45d2f377beae" \
        || "${ACFS_R1_INSTALL_SH_SHA256:-}" != "3a47aefccdc35e92afe39c50c22071f29b25bfa3c4bb41d9f2147f752797c764" \
        || "${ACFS_R1_SECURITY_SHA256:-}" != "047fae70c75de78e903654f7a59e94f7ef510c26d4dbf0face1ade7696cd89be" \
        || "${ACFS_R1_CHECKSUMS_SHA256:-}" != "36bbd2eba33e6ef70871f8c321623ba6d0b46720569c23b7ea5f1e91c9d0e83c" \
        || "${ACFS_R1_INSTALL_HELPERS_SHA256:-}" != "707e771ceebc84c8a2bbe043059fb1ed361bb10fffc8ce3314ccba949839f07f" \
        || "${ACFS_R1_PROGRESS_SHA256:-}" != "c75a9d6ff3c4be155b892344e135ed12b99ca444a1e6dca61d491f200d3719a7" \
        || "${ACFS_R1_MODULE_SELECTOR_SHA256:-}" != "b524b6179e6eed45852d876043e17ff5563bbfb32b22401752ff9d11079c61b0" \
        || "${ACFS_R1_EXPORT_CONFIG_SHA256:-}" != "0cfa29731605ca45377a6e10fdd8e261bc16aff7de8219af67542c35a017e787" \
        || "${ACFS_R1_STATE_SHA256:-}" != "76409a938231e88a3232d65ccbca095f1b505bee893eaa463b33b851df6a0813" \
        || "${ACFS_R1_STACK_SHA256:-}" != "4350275e6776d76a496cd9ee8ddb3e10449e2836c6dece032503e17e7d674e58" \
        || "${ACFS_R1_UPDATE_SHA256:-}" != "4774a90d8911b5c18e6aafb5e33114314c85188aeaa22e6777b2a20e6a054043" \
        || "${ACFS_R1_DOCTOR_SHA256:-}" != "ffdacc227261ea77b1798dc7b4a97aeb2ccfc2875acf6b764350131c7b74994a" \
        || "${ACFS_R1_DOCTOR_FIX_SHA256:-}" != "5abc547533c4074630c973cac403a393497954a30952f24d755d52f456882b22" \
        || "${ACFS_R1_SERVICES_SHA256:-}" != "eba54b8c1b54974fccc56a969e702c5e8f9f928a334692736ff53ddf1ebd68f5" \
        || "${ACFS_R1_GENERATED_BASE_SHA256:-}" != "a7d9e2d5f2aa028cfb83f1c470c0e3eb95447f4f80dd5eab0201c9c47ae12391" \
        || "${ACFS_R1_GENERATED_USERS_SHA256:-}" != "b90a4abab9dd9414ccfcac98ef4c09c57dc96950294a469bd58e984b4a68826c" \
        || "${ACFS_R1_GENERATED_FILESYSTEM_SHA256:-}" != "f9b22dfc41c435be31f863fc7ad37f9ebaf6e795dac5b87d4be78eca28fc51ab" \
        || "${ACFS_R1_GENERATED_CLI_SHA256:-}" != "1871b26476c88926c107c047d83cb90eb0cb2a0c3ab0bafbe632b6989e6247b6" \
        || "${ACFS_R1_GENERATED_LANG_SHA256:-}" != "6976f5724294934aa320da4ac50323d69d22349184f5ec60a632df5fca8605c1" \
        || "${ACFS_R1_GENERATED_STACK_SHA256:-}" != "ac6c6138410d71f94ebd8231707d7994b182c01d241678341fb952c64cce6320" \
        || "${ACFS_R1_GENERATED_DOCTOR_SHA256:-}" != "5e3389aac6674ad652b58e54ee9f5147ac4fe885ec34271777ee6411d597be1e" \
        || "${ACFS_W2_GENERATED_PARTIAL_SAFE_SHA256:-}" != "88a375113e99108f6567bd210ac38cb5f0d268de109890da36d5056c1b4942b3" \
        || "${ACFS_R1_SEED_CSV:-}" != "users.ubuntu,base.filesystem,cli.modern,stack.mcp_agent_mail,stack.beads_rust,stack.beads_viewer" \
        || "${ACFS_R1_PLAN_CSV:-}" != "base.system,users.ubuntu,base.filesystem,cli.modern,lang.bun,lang.uv,lang.rust,lang.go,stack.mcp_agent_mail,stack.beads_rust,stack.beads_viewer" \
        || "${ACFS_R1_HELD_CSV:-}" != "stack.caam,stack.slb,stack.srps,stack.storage_ballast_helper,stack.cross_agent_session_resumer,stack.doodlestein_self_releaser,stack.agent_settings_backup,stack.pcr,stack.franken_markdown,stack.power_failure_resumer" ]]; then
        ACFS_R1_POLICY_REASON="R1 runtime profile bindings were shadowed"
        return 1
    fi
    actual_profile_sha256="$(_acfs_r1_profile_actual_sha256 2>/dev/null || true)"
    if [[ "$actual_profile_sha256" != "$ACFS_R1_RUNTIME_PROFILE_SHA256" ]]; then
        ACFS_R1_POLICY_REASON="R1 runtime profile digest mismatch"
        return 1
    fi

    runtime_root="$(_acfs_r1_runtime_root 2>/dev/null || true)"
    if [[ -z "$runtime_root" ]]; then
        ACFS_R1_POLICY_REASON="R1 runtime root is unavailable"
        return 1
    fi

    _acfs_r1_verify_bound_file "$runtime_root" "acfs.manifest.yaml" "$ACFS_R1_MANIFEST_SHA256" || return 1
    _acfs_r1_verify_bound_file "$runtime_root" "packages/manifest/src/generate.ts" "$ACFS_R1_GENERATOR_SHA256" || return 1
    _acfs_r1_verify_bound_file "$runtime_root" "scripts/generated/manifest_index.sh" "$ACFS_R1_MANIFEST_INDEX_SHA256" || return 1
    _acfs_r1_verify_bound_file "$runtime_root" "install.sh" "$ACFS_R1_INSTALL_SH_SHA256" || return 1
    _acfs_r1_verify_bound_file "$runtime_root" "scripts/lib/security.sh" "$ACFS_R1_SECURITY_SHA256" || return 1
    _acfs_r1_verify_bound_file "$runtime_root" "checksums.yaml" "$ACFS_R1_CHECKSUMS_SHA256" || return 1
    _acfs_r1_verify_bound_file "$runtime_root" "scripts/lib/install_helpers.sh" "$ACFS_R1_INSTALL_HELPERS_SHA256" || return 1
    _acfs_r1_verify_bound_file "$runtime_root" "scripts/lib/progress.sh" "$ACFS_R1_PROGRESS_SHA256" || return 1
    _acfs_r1_verify_bound_file "$runtime_root" "scripts/lib/module_selector.sh" "$ACFS_R1_MODULE_SELECTOR_SHA256" || return 1
    _acfs_r1_verify_bound_file "$runtime_root" "scripts/lib/export-config.sh" "$ACFS_R1_EXPORT_CONFIG_SHA256" || return 1
    _acfs_r1_verify_bound_file "$runtime_root" "scripts/lib/state.sh" "$ACFS_R1_STATE_SHA256" || return 1
    _acfs_r1_verify_bound_file "$runtime_root" "scripts/lib/stack.sh" "$ACFS_R1_STACK_SHA256" || return 1
    _acfs_r1_verify_bound_file "$runtime_root" "scripts/lib/update.sh" "$ACFS_R1_UPDATE_SHA256" || return 1
    _acfs_r1_verify_bound_file "$runtime_root" "scripts/lib/doctor.sh" "$ACFS_R1_DOCTOR_SHA256" || return 1
    _acfs_r1_verify_bound_file "$runtime_root" "scripts/lib/doctor_fix.sh" "$ACFS_R1_DOCTOR_FIX_SHA256" || return 1
    _acfs_r1_verify_bound_file "$runtime_root" "scripts/lib/acfs-services.sh" "$ACFS_R1_SERVICES_SHA256" || return 1
    _acfs_r1_verify_bound_file "$runtime_root" "scripts/generated/install_base.sh" "$ACFS_R1_GENERATED_BASE_SHA256" || return 1
    _acfs_r1_verify_bound_file "$runtime_root" "scripts/generated/install_users.sh" "$ACFS_R1_GENERATED_USERS_SHA256" || return 1
    _acfs_r1_verify_bound_file "$runtime_root" "scripts/generated/install_filesystem.sh" "$ACFS_R1_GENERATED_FILESYSTEM_SHA256" || return 1
    _acfs_r1_verify_bound_file "$runtime_root" "scripts/generated/install_cli.sh" "$ACFS_R1_GENERATED_CLI_SHA256" || return 1
    _acfs_r1_verify_bound_file "$runtime_root" "scripts/generated/install_lang.sh" "$ACFS_R1_GENERATED_LANG_SHA256" || return 1
    _acfs_r1_verify_bound_file "$runtime_root" "scripts/generated/install_stack.sh" "$ACFS_R1_GENERATED_STACK_SHA256" || return 1
    _acfs_r1_verify_bound_file "$runtime_root" "scripts/generated/doctor_checks.sh" "$ACFS_R1_GENERATED_DOCTOR_SHA256" || return 1
    if acfs_w2_partial_safe_requested; then
        _acfs_r1_verify_bound_file "$runtime_root" "scripts/generated/install_w2_partial_safe.sh" "$ACFS_W2_GENERATED_PARTIAL_SAFE_SHA256" || return 1
    fi
    return 0
}

acfs_r1_runtime_module_is_held() {
    local module_id="${1:-}"
    [[ -n "$module_id" ]] || return 1
    case ",$ACFS_R1_HELD_CSV," in
        *",$module_id,"*) return 0 ;;
        *) return 1 ;;
    esac
}

acfs_r1_runtime_module_is_planned() {
    local module_id="${1:-}"
    local plan_csv="$ACFS_R1_PLAN_CSV"
    [[ -n "$module_id" ]] || return 1
    if acfs_w2_partial_safe_requested; then
        acfs_w2_partial_safe_verify_allowlist || return 1
        plan_csv="$ACFS_W2_PARTIAL_SAFE_PLAN_CSV"
    fi
    case ",$plan_csv," in
        *",$module_id,"*) return 0 ;;
        *) return 1 ;;
    esac
}

acfs_r1_runtime_admit_entry() {
    local entry="${1:-}"
    local module_id="${2:-}"

    ACFS_R1_POLICY_REASON=""
    # Verify the complete content-addressed runtime envelope before evaluating
    # the separate license exclusion. A license HOLD must not let a shadowed or
    # drifted R1 profile escape identity verification at the entry boundary.
    acfs_r1_runtime_verify_profile || return $?
    if ! acfs_license_policy_admit_entry "$entry" "$module_id"; then
        ACFS_R1_POLICY_REASON="${ACFS_LICENSE_POLICY_REASON:-LIC1+LIC2 lifecycle exclusion failed closed}"
        return 1
    fi

    case "$entry" in
        default|filtered|direct|install|update|doctor|doctor-fix|doctor-fix-finalize|repair|autofix|resume|finalize|failure-cleanup|service|configuration|list|probe|plan|print|helper) ;;
        *)
            ACFS_R1_POLICY_REASON="unsupported R1 lifecycle entry: ${entry:-<empty>}"
            return 1
            ;;
    esac

    case "$entry" in
        default)
            ACFS_R1_POLICY_REASON="R1 rejects default selection; supply the exact six ordered --only seeds"
            return 1
            ;;
        resume)
            ACFS_R1_POLICY_REASON="R1 rejects resume-derived selection; begin from the exact six ordered --only seeds"
            return 1
            ;;
        finalize)
            ACFS_R1_POLICY_REASON="R1 rejects broad legacy finalize; no finalize module is in the exact plan"
            return 1
            ;;
        direct|probe|helper)
            # Never trust an inherited/exported validation marker. Recompute
            # the exact graph and manifest bindings at the call boundary.
            # The W2 selection engine needs moduleless metadata helpers to
            # load the bound manifest before a plan can exist.  That narrow
            # bootstrap exception requires the exact immutable allowlist and
            # ends as soon as the plan is validated.  Module entrypoints never
            # receive this exception.
            if acfs_w2_partial_safe_requested \
                && [[ -z "$module_id" ]] \
                && [[ "${ACFS_R1_PLAN_VALIDATED:-false}" != "true" ]]; then
                acfs_w2_partial_safe_verify_allowlist || {
                    ACFS_R1_POLICY_REASON="${ACFS_W2_PARTIAL_SAFE_POLICY_REASON:-W2 PARTIAL_SAFE allowlist verification failed}"
                    return 1
                }
            elif ! acfs_r1_runtime_validate_plan; then
                if [[ -z "${ACFS_R1_POLICY_REASON:-}" ]]; then
                    ACFS_R1_POLICY_REASON="R1 rejects $entry dispatch without an exact validated eleven-module plan"
                fi
                return 1
            fi
            ;;
    esac

    if [[ -n "$module_id" ]]; then
        if acfs_r1_runtime_module_is_held "$module_id"; then
            ACFS_R1_POLICY_REASON="R1 held module rejected before $entry lifecycle: $module_id"
            return 1
        fi
        if ! acfs_r1_runtime_module_is_planned "$module_id"; then
            ACFS_R1_POLICY_REASON="R1 out-of-plan module rejected before $entry lifecycle: $module_id"
            return 1
        fi
    fi
    return 0
}

_acfs_r1_array_csv() {
    local joined=""
    joined="$(IFS=,; printf '%s' "$*")"
    printf '%s\n' "$joined"
}

acfs_r1_runtime_prepare_selection() {
    local requested_csv=""
    local entry="filtered"
    local dispatch_var=""
    local dispatch_value=""
    local skip_tags_count=0
    local skip_categories_count=0

    if builtin declare -p SKIP_TAGS >/dev/null 2>&1; then
        skip_tags_count=${#SKIP_TAGS[@]}
    fi
    if builtin declare -p SKIP_CATEGORIES >/dev/null 2>&1; then
        skip_categories_count=${#SKIP_CATEGORIES[@]}
    fi

    # A direct profile/selection helper call is itself a moduleless lifecycle
    # boundary.  Reject it before reading caller arrays, profile markers, the
    # manifest index, or installed predicates.  A later policy revision must
    # explicitly replace this HOLD before selection data may be inspected.
    acfs_r1_runtime_admit_entry filtered || return $?

    if [[ ${#ONLY_MODULES[@]} -eq 0 ]] \
        && [[ ${#ONLY_PHASES[@]} -eq 0 ]] \
        && [[ ${#SKIP_MODULES[@]} -eq 0 ]] \
        && [[ $skip_tags_count -eq 0 ]] \
        && [[ $skip_categories_count -eq 0 ]] \
        && [[ -z "${ACFS_CLI_PROFILE:-}" ]] \
        && [[ -z "${ACFS_SELECTED_PROFILE:-}" ]]; then
        entry="default"
        ACFS_R1_SELECTION_ORIGIN="default"
    else
        ACFS_R1_SELECTION_ORIGIN="filtered"
    fi

    acfs_r1_runtime_admit_entry "$entry" || return $?

    if [[ ${#ONLY_PHASES[@]} -ne 0 ]] \
        || [[ ${#SKIP_MODULES[@]} -ne 0 ]] \
        || [[ $skip_tags_count -ne 0 ]] \
        || [[ $skip_categories_count -ne 0 ]] \
        || [[ "${NO_DEPS:-false}" == "true" ]] \
        || [[ -n "${ACFS_CLI_PROFILE:-}" ]] \
        || [[ -n "${ACFS_SELECTED_PROFILE:-}" ]]; then
        ACFS_R1_POLICY_REASON="R1/W2 requires the exact ordered --only seeds with dependency closure and no profile, phase, or skip selectors"
        return 1
    fi

    if [[ "${ACFS_FORCE_RESUME:-false}" == "true" ]] \
        || [[ "${ACFS_FORCE_REINSTALL:-false}" == "true" ]] \
        || [[ "${RESET_STATE_ONLY:-false}" == "true" ]] \
        || [[ "${SKIP_PREFLIGHT:-false}" == "true" ]] \
        || [[ "${SKIP_UBUNTU_UPGRADE:-false}" == "true" ]] \
        || [[ "${SKIP_POSTGRES:-false}" == "true" ]] \
        || [[ "${SKIP_VAULT:-false}" == "true" ]] \
        || [[ "${SKIP_CLOUD:-false}" == "true" ]] \
        || [[ -n "${ACFS_GENERATED_MIGRATED_CATEGORIES:-}" ]]; then
        ACFS_R1_POLICY_REASON="R1 rejects resume, reset, force, skip, and generated-category lifecycle overrides"
        return 1
    fi

    requested_csv="$(_acfs_r1_array_csv "${ONLY_MODULES[@]}")"
    local expected_seed_csv="$ACFS_R1_SEED_CSV"
    if acfs_w2_partial_safe_requested; then
        if ! acfs_w2_partial_safe_verify_allowlist; then
            ACFS_R1_POLICY_REASON="${ACFS_W2_PARTIAL_SAFE_POLICY_REASON:-W2 PARTIAL_SAFE allowlist verification failed}"
            return 1
        fi
        expected_seed_csv="$ACFS_W2_PARTIAL_SAFE_SEED_CSV"
    fi
    if [[ "$requested_csv" != "$expected_seed_csv" ]]; then
        ACFS_R1_POLICY_REASON="R1 explicit seed sequence mismatch"
        return 1
    fi

    case "${ACFS_USE_GENERATED:-1}" in
        1) ;;
        *)
            ACFS_R1_POLICY_REASON="R1 requires ACFS_USE_GENERATED=1"
            return 1
            ;;
    esac
    for dispatch_var in BASE FILESYSTEM SHELL CLI NETWORK LANG TOOLS DB CLOUD AGENTS STACK ACFS; do
        local dispatch_name="ACFS_USE_GENERATED_${dispatch_var}"
        dispatch_value="${!dispatch_name:-}"
        case "$dispatch_value" in
            ""|1) ;;
            *)
                ACFS_R1_POLICY_REASON="R1 rejects generated-dispatch override ACFS_USE_GENERATED_${dispatch_var}=${dispatch_value}"
                return 1
                ;;
        esac
    done
    if [[ -n "${ACFS_USE_GENERATED_USERS:-}" ]]; then
        ACFS_R1_POLICY_REASON="R1 owns the users.ubuntu orchestration exception; ACFS_USE_GENERATED_USERS is forbidden"
        return 1
    fi
    ACFS_USE_GENERATED=1
    export ACFS_USE_GENERATED ACFS_R1_SELECTION_ORIGIN
    return 0
}

acfs_r1_runtime_validate_plan() {
    local resolved_csv=""
    local expected_plan_csv="$ACFS_R1_PLAN_CSV"
    local module_id=""
    local expected_phase=""
    local expected_deps=""

    acfs_r1_runtime_admit_entry "${ACFS_R1_SELECTION_ORIGIN:-filtered}" || return $?
    if [[ "${ACFS_MANIFEST_INDEX_LOADED:-false}" != "true" ]] \
        || [[ "${ACFS_MANIFEST_SHA256:-}" != "$ACFS_R1_MANIFEST_SHA256" ]]; then
        ACFS_R1_POLICY_REASON="R1 manifest/index cross-binding mismatch"
        return 1
    fi

    if acfs_w2_partial_safe_requested; then
        if ! acfs_w2_partial_safe_verify_allowlist; then
            ACFS_R1_POLICY_REASON="${ACFS_W2_PARTIAL_SAFE_POLICY_REASON:-W2 PARTIAL_SAFE allowlist verification failed}"
            return 1
        fi
        expected_plan_csv="$ACFS_W2_PARTIAL_SAFE_PLAN_CSV"
    fi
    resolved_csv="$(_acfs_r1_array_csv "${ACFS_EFFECTIVE_PLAN[@]}")"
    if [[ "$resolved_csv" != "$expected_plan_csv" ]]; then
        ACFS_R1_POLICY_REASON="R1 resolved module order mismatch"
        return 1
    fi

    for module_id in "${ACFS_EFFECTIVE_PLAN[@]}"; do
        if acfs_r1_runtime_module_is_held "$module_id"; then
            ACFS_R1_POLICY_REASON="R1 held intersection is not empty: $module_id"
            return 1
        fi
    done

    local -a expected_modules=(
        base.system users.ubuntu base.filesystem cli.modern
        lang.bun lang.uv lang.rust lang.go
    )
    if ! acfs_w2_partial_safe_requested; then
        expected_modules+=(stack.mcp_agent_mail stack.beads_rust stack.beads_viewer)
    fi
    for module_id in "${expected_modules[@]}"; do
        case "$module_id" in
            base.system) expected_phase="1"; expected_deps="" ;;
            users.ubuntu) expected_phase="2"; expected_deps="" ;;
            base.filesystem) expected_phase="3"; expected_deps="users.ubuntu" ;;
            cli.modern) expected_phase="5"; expected_deps="base.system" ;;
            lang.bun|lang.uv|lang.rust) expected_phase="6"; expected_deps="base.system,users.ubuntu" ;;
            lang.go) expected_phase="6"; expected_deps="base.system" ;;
            stack.mcp_agent_mail) expected_phase="9"; expected_deps="lang.bun,lang.uv,users.ubuntu" ;;
            stack.beads_rust) expected_phase="9"; expected_deps="lang.rust,users.ubuntu" ;;
            stack.beads_viewer) expected_phase="9"; expected_deps="lang.go,stack.beads_rust,users.ubuntu" ;;
        esac
        if [[ "${ACFS_MODULE_PHASE[$module_id]:-}" != "$expected_phase" ]] \
            || [[ "${ACFS_MODULE_DEPS[$module_id]:-}" != "$expected_deps" ]]; then
            ACFS_R1_POLICY_REASON="R1 phase/dependency identity mismatch: $module_id"
            return 1
        fi
    done
    ACFS_R1_PLAN_VALIDATED=true
    return 0
}

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

    if ! acfs_r1_runtime_admit_entry "$operation" "$module_id"; then
        ACFS_CORE_POLICY_REASON="${ACFS_R1_POLICY_REASON:-R1 runtime admission unavailable}"
        if [[ "$module_id" == "stack.mcp_agent_mail" ]]; then
            ACFS_CORE_POLICY_REASON+="; C5 commissioning HOLD: design fb60a0f0aac8d877f0170cd17e043e51605c8d61f63da6b854e02abec90f0e6b is non-authorizing and no future independently accepted exact C5 capsule identity exists"
        fi
        return 1
    fi

    case "$operation" in
        install|update|doctor|service) ;;
        *)
            ACFS_CORE_POLICY_REASON="unsupported core policy operation: ${operation:-<empty>}"
            return 1
            ;;
    esac

    case "$module_id" in
        stack.mcp_agent_mail)
            ACFS_CORE_POLICY_REASON="C5 commissioning HOLD: design fb60a0f0aac8d877f0170cd17e043e51605c8d61f63da6b854e02abec90f0e6b is non-authorizing and no future independently accepted exact C5 capsule identity exists"
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

acfs_core_policy_contract() {
    local module_id="${1:-}"
    acfs_license_policy_admit_entry helper "$module_id" || return 1
    case "$module_id" in
        stack.mcp_agent_mail)
            printf '\n'
            ;;
        stack.beads_rust)
            printf '%s\n' "source_commit=7eaf34b76927b4deadc913889f50fb06a8f803d7;installer_url=https://raw.githubusercontent.com/Dicklesworthstone/beads_rust/7eaf34b76927b4deadc913889f50fb06a8f803d7/install.sh;installer_sha256=b2b3ed0ae2712e53a72d48afd5a980a7c1d346bb6e6b9fb9e4f3b20566726c2f;version=v0.5.3;artifact_url=https://github.com/Dicklesworthstone/beads_rust/releases/download/v0.5.3/br-0.5.3-linux_aarch64.tar.gz;artifact_sha256=9781aec596be155dfff31c0ab4d140d076107422e0e703c5137b2d2edcff4bfb;binary_sha256=f7d105e685da6c49dd87b0335d11d5fe2aa8765033a78cfbfb00dee7a4b1e123"
            ;;
        stack.beads_viewer)
            printf '%s\n' "source_commit=95a706caf57fc5fde846a453da5f28677d4a81b8;version=v0.22.0;artifact_url=https://github.com/Dicklesworthstone/beads_viewer/releases/download/v0.22.0/bv_linux_arm64.tar.gz;archive_sha256=23d451b87bb9dccfb94fab416b0243d107919d9d56458087475afda5a617aa89;binary_sha256=ee1dd03701a33d86e6496fb7021a96461e3c172e2a8be5b2ced554c7c378b320;selected_member=bv"
            ;;
        *)
            return 1
            ;;
    esac
}

_acfs_core_policy_target_home() {
    local target_home="${TARGET_HOME:-}"

    target_home="${target_home%/}"
    [[ -n "$target_home" && "$target_home" == /* && "$target_home" != "/" ]] || return 1
    printf '%s\n' "$target_home"
}

acfs_core_policy_expected_binary_path() {
    local module_id="${1:-}"
    local target_home=""

    acfs_license_policy_admit_entry probe "$module_id" || return 1

    target_home="$(_acfs_core_policy_target_home 2>/dev/null || true)"
    [[ -n "$target_home" ]] || return 1
    case "$module_id" in
        stack.beads_rust)
            printf '%s\n' "$target_home/.local/bin/br"
            ;;
        stack.beads_viewer)
            printf '%s\n' "$target_home/.local/bin/bv"
            ;;
        *)
            return 1
            ;;
    esac
}

acfs_core_policy_expected_bv_versioned_path() {
    local target_home=""

    acfs_license_policy_admit_entry probe stack.beads_viewer || return 1

    target_home="$(_acfs_core_policy_target_home 2>/dev/null || true)"
    [[ -n "$target_home" ]] || return 1
    printf '%s\n' "$target_home/.local/lib/acfs/bv/v0.22.0/bv"
}

acfs_core_policy_expected_binary_sha256() {
    local module_id="${1:-}"
    acfs_license_policy_admit_entry probe "$module_id" || return 1
    case "$module_id" in
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
    local module_id="${1:-}"
    local operation="${2:-}"
    local supplied_contract="${3:-}"
    local binary_path="${4:-}"
    local output=""
    local actual_sha256=""

    [[ -n "$binary_path" ]] || return 1
    acfs_core_policy_enforce "$module_id" "$operation" "$supplied_contract" || return 1
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
    local module_id="${1:-}"
    local operation="${2:-}"
    local supplied_contract="${3:-}"
    local binary_path="${4:-}"

    [[ -n "$binary_path" ]] || return 1
    acfs_core_policy_enforce "$module_id" "$operation" "$supplied_contract" || return 1
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
    local expected_binary_path=""
    local expected_bv_target=""
    local actual_bv_target=""
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

    actual_sha256="$(_acfs_core_policy_sha256_file "$module_id" "$operation" "$supplied_contract" "$binary_path" 2>/dev/null || true)"
    if [[ "$actual_sha256" != "$expected_sha256" ]]; then
        ACFS_CORE_POLICY_REASON="$module_id installed binary digest mismatch"
        return 1
    fi

    expected_binary_path="$(acfs_core_policy_expected_binary_path "$module_id" 2>/dev/null || true)"
    if [[ -z "$expected_binary_path" || "$binary_path" != "$expected_binary_path" ]]; then
        ACFS_CORE_POLICY_REASON="$module_id canonical binary path mismatch"
        return 1
    fi

    case "$module_id" in
        stack.beads_rust)
            if [[ -L "$binary_path" ]]; then
                ACFS_CORE_POLICY_REASON="stack.beads_rust canonical binary must be a regular file, not a symlink"
                return 1
            fi
            version_pattern='(^|[[:space:]])v?0[.]5[.]3([[:space:]]|$)'
            ;;
        stack.beads_viewer)
            expected_bv_target="$(acfs_core_policy_expected_bv_versioned_path 2>/dev/null || true)"
            if [[ -z "$expected_bv_target" || ! -L "$binary_path" \
                || ! -f "$expected_bv_target" || ! -x "$expected_bv_target" \
                || -L "$expected_bv_target" ]]; then
                ACFS_CORE_POLICY_REASON="stack.beads_viewer canonical versioned binary or public symlink is unavailable"
                return 1
            fi
            if [[ ! -x /usr/bin/readlink ]]; then
                ACFS_CORE_POLICY_REASON="stack.beads_viewer canonical symlink cannot be verified"
                return 1
            fi
            actual_bv_target="$(/usr/bin/readlink "$binary_path" 2>/dev/null || true)"
            if [[ "$actual_bv_target" != "$expected_bv_target" ]]; then
                ACFS_CORE_POLICY_REASON="stack.beads_viewer canonical symlink target mismatch"
                return 1
            fi
            actual_sha256="$(_acfs_core_policy_sha256_file "$module_id" "$operation" "$supplied_contract" "$expected_bv_target" 2>/dev/null || true)"
            if [[ "$actual_sha256" != "$expected_sha256" ]]; then
                ACFS_CORE_POLICY_REASON="stack.beads_viewer versioned binary digest mismatch"
                return 1
            fi
            version_pattern='(^|[[:space:]])v?0[.]22[.]0([[:space:]]|$)'
            ;;
        *)
            ACFS_CORE_POLICY_REASON="$module_id has no pinned binary version"
            return 1
            ;;
    esac

    version_output="$(_acfs_core_policy_version_output "$module_id" "$operation" "$supplied_contract" "$binary_path" 2>/dev/null || true)"
    if [[ ! "$version_output" =~ $version_pattern ]]; then
        ACFS_CORE_POLICY_REASON="$module_id installed binary version mismatch"
        return 1
    fi

    ACFS_CORE_POLICY_REASON=""
    return 0
}

# A doctor repair may create only the public bv symlink, and only from the
# exact versioned binary installed by the content-addressed archive route.
# This separate admission intentionally provides no authority to link Cargo
# outputs, PATH-resolved commands, or any br source.
acfs_core_policy_admit_repair_source() {
    local module_id="${1:-}"
    local operation="${2:-}"
    local supplied_contract="${3:-}"
    local source_path="${4:-}"
    local expected_source_path=""
    local expected_sha256=""
    local actual_sha256=""
    local version_output=""

    acfs_r1_runtime_admit_entry repair "$module_id" || return $?
    acfs_core_policy_enforce "$module_id" "$operation" "$supplied_contract" || return $?
    if [[ "$module_id" != "stack.beads_viewer" ]]; then
        ACFS_CORE_POLICY_REASON="$module_id has no admitted symlink repair source"
        return 1
    fi

    expected_source_path="$(acfs_core_policy_expected_bv_versioned_path 2>/dev/null || true)"
    expected_sha256="$(acfs_core_policy_expected_binary_sha256 "$module_id" 2>/dev/null || true)"
    if [[ -z "$expected_source_path" || "$source_path" != "$expected_source_path" \
        || ! -f "$source_path" || ! -x "$source_path" || -L "$source_path" ]]; then
        ACFS_CORE_POLICY_REASON="stack.beads_viewer repair source path is not canonical"
        return 1
    fi

    actual_sha256="$(_acfs_core_policy_sha256_file "$module_id" "$operation" "$supplied_contract" "$source_path" 2>/dev/null || true)"
    if [[ -z "$expected_sha256" || "$actual_sha256" != "$expected_sha256" ]]; then
        ACFS_CORE_POLICY_REASON="stack.beads_viewer repair source digest mismatch"
        return 1
    fi
    version_output="$(_acfs_core_policy_version_output "$module_id" "$operation" "$supplied_contract" "$source_path" 2>/dev/null || true)"
    if [[ ! "$version_output" =~ (^|[[:space:]])v?0[.]22[.]0([[:space:]]|$) ]]; then
        ACFS_CORE_POLICY_REASON="stack.beads_viewer repair source version mismatch"
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

    if ! acfs_license_policy_admit_entry install "$module_id"; then
        ACFS_CORE_POLICY_REASON="${ACFS_LICENSE_POLICY_REASON:-LIC1+LIC2 core installer execution is held}"
        return 1
    fi

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
