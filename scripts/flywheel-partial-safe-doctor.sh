#!/usr/bin/env bash
set -euo pipefail
shopt -s lastpipe 2>/dev/null || true
umask 022

SOURCE_ROOT="${FLYWHEEL_SOURCE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
ALLOWLIST="${ACFS_PARTIAL_SAFE_ALLOWLIST_FILE:-$SOURCE_ROOT/config/flywheel-partial-safe-allowlist.json}"
TARGET_USER="${TARGET_USER:-ubuntu}"
TARGET_HOME="${TARGET_HOME:-/home/$TARGET_USER}"
FORMAT="text"

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
export ACFS_PARTIAL_SAFE_ALLOWLIST_FILE="$ALLOWLIST" TARGET_USER TARGET_HOME

checks=()
failures=0
record() {
    local id="$1"
    local status="$2"
    local detail="$3"
    checks+=("$id"$'\t'"$status"$'\t'"$detail")
    [[ "$status" == "pass" ]] || failures=$((failures + 1))
}

if acfs_w2_partial_safe_verify_allowlist; then
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

held=(
    stack.beads_rust stack.agent_settings_backup stack.caam stack.cross_agent_session_resumer
    stack.pcr stack.automated_plan_reviser stack.brenner_bot stack.eidetic_engine_cli
    stack.frankensearch stack.jeffreysprompts stack.meta_skill stack.pi_agent_rust
    stack.process_triage stack.rch stack.ru stack.doodlestein_self_releaser
    stack.franken_markdown stack.slb stack.srps stack.storage_ballast_helper
    stack.mcp_agent_mail stack.beads_viewer stack.ultimate_bug_scanner stack.dcg
    stack.cass stack.cm stack.ntm
)
unexpected=()
for module_id in "${held[@]}"; do
    if acfs_r1_runtime_admit_entry direct "$module_id" >/dev/null 2>&1; then
        unexpected+=("$module_id")
    fi
done
if ((${#unexpected[@]} == 0)); then
    record held_exclusions pass "27/27 rejected before lifecycle activity"
else
    record held_exclusions fail "unexpectedly admitted: ${unexpected[*]}"
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
rows=[]
for line in sys.stdin:
    line=line.rstrip("\n")
    if not line:
        continue
    identifier,status,detail=line.split("\t",2)
    rows.append({"id":identifier,"status":status,"detail":detail})
failures=sum(row["status"] != "pass" for row in rows)
print(json.dumps({
    "schema":"agent-flywheel.partial-safe-doctor/v1",
    "claim":"PARTIAL_SAFE",
    "fully_commissioned":False,
    "status":"pass" if failures == 0 else "fail",
    "checks":rows,
    "summary":{"pass":len(rows)-failures,"warn":0,"fail":failures},
},sort_keys=True,separators=(",",":")))
'
else
    for item in "${checks[@]}"; do
        IFS=$'\t' read -r id status detail <<<"$item"
        printf '%-24s %-4s %s\n' "$id" "$status" "$detail"
    done
fi

((failures == 0))
