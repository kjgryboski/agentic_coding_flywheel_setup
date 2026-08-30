#!/usr/bin/env bash
set -euo pipefail
shopt -s lastpipe 2>/dev/null || true
umask 022

SOURCE_ROOT="${FLYWHEEL_SOURCE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
ALLOWLIST="${ACFS_PARTIAL_SAFE_ALLOWLIST_FILE:-$SOURCE_ROOT/config/flywheel-partial-safe-allowlist.json}"
CLEARANCE="${ACFS_LICENSE_CLEARANCE_FILE:-}"
TARGET_USER="${TARGET_USER:-ubuntu}"
TARGET_HOME="${TARGET_HOME:-/home/$TARGET_USER}"
FORMAT="text"
LICENSE_CLEARED=false

usage() {
    printf 'Usage: %s [--json]\n' "${0##*/}"
}

while (($#)); do
    case "$1" in
        --json) FORMAT="json" ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

if [[ ! -r "$SOURCE_ROOT/scripts/lib/contract.sh" ]]; then
    printf 'Flywheel doctor cannot read the ACFS runtime contract.\n' >&2
    exit 2
fi

# shellcheck source=lib/contract.sh
source "$SOURCE_ROOT/scripts/lib/contract.sh"
if [[ -n "$CLEARANCE" ]]; then
    LICENSE_CLEARED=true
    unset ACFS_PARTIAL_SAFE_ALLOWLIST_FILE
    export ACFS_LICENSE_CLEARANCE_FILE="$CLEARANCE"
else
    export ACFS_PARTIAL_SAFE_ALLOWLIST_FILE="$ALLOWLIST"
fi
export TARGET_USER TARGET_HOME

checks=()
failures=0
record() {
    local id="$1"
    local status="$2"
    local detail="$3"
    checks+=("$id"$'\t'"$status"$'\t'"$detail")
    [[ "$status" == "pass" ]] || failures=$((failures + 1))
}

if [[ "$LICENSE_CLEARED" == "true" ]] && acfs_license_clearance_verify; then
    record license_clearance pass "$(sha256sum "$CLEARANCE" | awk '{print $1}')"
elif [[ "$LICENSE_CLEARED" == "true" ]]; then
    record license_clearance fail "${ACFS_LICENSE_CLEARANCE_POLICY_REASON:-clearance rejected}"
elif acfs_w2_partial_safe_verify_allowlist; then
    record allowlist pass "$(sha256sum "$ALLOWLIST" | awk '{print $1}')"
else
    record allowlist fail "${ACFS_W2_PARTIAL_SAFE_POLICY_REASON:-allowlist rejected}"
fi

if [[ "$(id -un 2>/dev/null || true)" == "$TARGET_USER" && "$HOME" == "$TARGET_HOME" ]]; then
    record target_identity pass "$TARGET_USER:$TARGET_HOME"
else
    record target_identity fail "run as $TARGET_USER with HOME=$TARGET_HOME"
fi

missing=()
for command_name in curl git update-ca-certificates unzip tar xz jq make gcc gpg lsb_release; do
    command -v "$command_name" >/dev/null 2>&1 || missing+=("$command_name")
done
if ((${#missing[@]} == 0)); then
    record base.system pass "11 required commands"
else
    record base.system fail "missing: ${missing[*]}"
fi

if id "$TARGET_USER" >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    record users.ubuntu pass "$TARGET_USER with noninteractive sudo"
else
    record users.ubuntu fail "target user or noninteractive sudo unavailable"
fi

if [[ -d /data/projects && -d "$TARGET_HOME/.acfs" && ! -L /data && ! -L /data/projects && ! -L "$TARGET_HOME/.acfs" ]]; then
    record base.filesystem pass "/data/projects and $TARGET_HOME/.acfs"
else
    record base.filesystem fail "required non-symlink directories unavailable"
fi

missing=()
for command_name in rg fzf direnv gh git-lfs; do
    command -v "$command_name" >/dev/null 2>&1 || missing+=("$command_name")
done
if ((${#missing[@]} == 0)); then
    record cli.modern pass "rg fzf direnv gh git-lfs"
else
    record cli.modern fail "missing: ${missing[*]}"
fi

for module_command in "lang.bun:bun" "lang.uv:uv" "lang.rust:rustc" "lang.rust:cargo" "lang.go:go"; do
    module_id="${module_command%%:*}"
    command_name="${module_command#*:}"
    if command -v "$command_name" >/dev/null 2>&1; then
        record "$module_id/$command_name" pass "$(command -v "$command_name")"
    else
        record "$module_id/$command_name" fail "$command_name missing"
    fi
done

licensed=(
    stack.beads_rust stack.agent_settings_backup stack.caam stack.cross_agent_session_resumer
    stack.pcr stack.automated_plan_reviser stack.brenner_bot stack.eidetic_engine_cli
    stack.frankensearch stack.jeffreysprompts stack.meta_skill stack.pi_agent_rust
    stack.process_triage stack.rch stack.ru stack.doodlestein_self_releaser
    stack.franken_markdown stack.slb stack.srps stack.storage_ballast_helper
    stack.mcp_agent_mail stack.beads_viewer stack.ultimate_bug_scanner stack.dcg
    stack.cass stack.cm stack.ntm
)
unexpected=()
if [[ "$LICENSE_CLEARED" == "true" ]]; then
    for module_id in "${licensed[@]}"; do
        if ! acfs_license_policy_admit_entry direct "$module_id" >/dev/null 2>&1; then
            unexpected+=("$module_id")
        fi
    done
    if ((${#unexpected[@]} == 0)); then
        record license_scope pass "27/27 exact revisions cleared at the license gate"
    else
        record license_scope fail "license gate rejected: ${unexpected[*]}"
    fi
else
    for module_id in "${licensed[@]}"; do
        if acfs_r1_runtime_admit_entry direct "$module_id" >/dev/null 2>&1; then
            unexpected+=("$module_id")
        fi
    done
    if ((${#unexpected[@]} == 0)); then
        record held_exclusions pass "27/27 rejected before lifecycle activity"
    else
        record held_exclusions fail "unexpectedly admitted: ${unexpected[*]}"
    fi
fi

if [[ "$LICENSE_CLEARED" == "true" ]]; then
    missing=()
    for module_command in \
        "tools.ast_grep:sg" "agents.claude:claude" \
        "stack.ntm:ntm" "stack.meta_skill:ms" "stack.automated_plan_reviser:apr" \
        "stack.jeffreysprompts:jfp" "stack.process_triage:pt" \
        "stack.ultimate_bug_scanner:ubs" "stack.beads_rust:br" \
        "stack.beads_viewer:bv" "stack.cass:cass" "stack.cm:cm" \
        "stack.caam:caam" "stack.slb:slb" "stack.dcg:dcg" "stack.ru:ru" \
        "stack.brenner_bot:brenner" "stack.rch:rch" "stack.srps:sysmoni" \
        "stack.frankensearch:fsfs" "stack.storage_ballast_helper:sbh" \
        "stack.cross_agent_session_resumer:casr" \
        "stack.doodlestein_self_releaser:dsr" "stack.agent_settings_backup:asb" \
        "stack.pcr:claude-post-compact-reminder" "stack.eidetic_engine_cli:ee" \
        "stack.franken_markdown:fmd" "stack.pi_agent_rust:pi"; do
        module_id="${module_command%%:*}"
        command_name="${module_command#*:}"
        command -v "$command_name" >/dev/null 2>&1 || missing+=("$module_id:$command_name")
    done
    if ((${#missing[@]} == 0)); then
        record expanded_modules pass "28/28 dependency and licensed module commands available"
    else
        record expanded_modules fail "missing: ${missing[*]}"
    fi

    if systemctl is-active ananicy-cpp >/dev/null 2>&1; then
        record stack.srps/service pass "ananicy-cpp active"
    else
        record stack.srps/service fail "ananicy-cpp inactive"
    fi

    if ! acfs_r1_runtime_admit_entry direct stack.mcp_agent_mail >/dev/null 2>&1 \
        && ! acfs_r1_runtime_admit_entry direct stack.power_failure_resumer >/dev/null 2>&1; then
        record independent_holds pass "Agent Mail C5 and PFR qualification holds preserved"
    else
        record independent_holds fail "an independent commissioning hold was lost"
    fi
fi

state_file="$TARGET_HOME/.acfs/state.json"
if [[ -f "$state_file" && ! -L "$state_file" ]] \
    && jq -e --arg user "$TARGET_USER" --arg home "$TARGET_HOME" '
        .schema_version == 3 and .version == "0.8.0" and
        .target_user == $user and .target_home == $home and
        .failed_phase == null and .failed_step == null
    ' "$state_file" >/dev/null 2>&1; then
    record state pass "schema 3, ACFS 0.8.0, no failed phase"
else
    record state fail "state missing, drifted, or failed"
fi

if [[ "$FORMAT" == "json" ]]; then
    printf '%s\n' "${checks[@]}" | python3 -c '
import json, sys
license_cleared=sys.argv[1] == "true"
rows=[]
for line in sys.stdin:
    line=line.rstrip("\n")
    if not line:
        continue
    identifier,status,detail=line.split("\t",2)
    rows.append({"id":identifier,"status":status,"detail":detail})
failures=sum(row["status"] != "pass" for row in rows)
print(json.dumps({
    "schema":"agent-flywheel.license-cleared-doctor/v1" if license_cleared else "agent-flywheel.partial-safe-doctor/v1",
    "claim":"LICENSE_CLEARED_PARTIAL" if license_cleared else "PARTIAL_SAFE",
    "fully_commissioned":False,
    "status":"pass" if failures == 0 else "fail",
    "checks":rows,
    "summary":{"pass":len(rows)-failures,"warn":0,"fail":failures},
},sort_keys=True,separators=(",",":")))
' "$LICENSE_CLEARED"
else
    for item in "${checks[@]}"; do
        IFS=$'\t' read -r id status detail <<<"$item"
        printf '%-24s %-4s %s\n' "$id" "$status" "$detail"
    done
fi

((failures == 0))
