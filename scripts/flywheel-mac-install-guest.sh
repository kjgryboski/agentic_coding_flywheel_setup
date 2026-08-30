#!/usr/bin/env bash
set -euo pipefail
shopt -s lastpipe 2>/dev/null || true
umask 022

if (($# != 1)); then
    printf 'Usage: %s ABSOLUTE_SOURCE_ROOT\n' "${0##*/}" >&2
    exit 2
fi
if ((EUID != 0)); then
    printf 'Flywheel guest installation must run through sudo.\n' >&2
    exit 2
fi

SOURCE_ROOT="${1%/}"
TARGET_USER="ubuntu"
TARGET_HOME="/home/ubuntu"
STATE_ROOT="/var/lib/agent-flywheel"
INSTALL_ALLOWLIST="$STATE_ROOT/install-allowlist.json"
DOCTOR_ALLOWLIST="$STATE_ROOT/doctor-allowlist.json"
SOURCE_ALLOWLIST="$SOURCE_ROOT/config/flywheel-partial-safe-allowlist.json"
INSTALL_CLEARANCE="$STATE_ROOT/install-license-clearance.json"
DOCTOR_CLEARANCE="$STATE_ROOT/doctor-license-clearance.json"
SOURCE_CLEARANCE="$SOURCE_ROOT/config/flywheel-license-clearance.json"
INSTALL_LOG="/var/log/agent-flywheel/install-$(date -u +%Y%m%dT%H%M%SZ).log"
ACTIVE_STATE="$TARGET_HOME/.acfs/state.json"
STATE_HISTORY="$STATE_ROOT/state-history"
CONVERGENCE_RECEIPT="$STATE_ROOT/convergence.json"
LICENSE_CLEARED=false
W3_TRANSITION_ACTIVE=false
W3_TRANSITION_STATE=""
W3_TRANSITION_SHA256=""

if [[ "$SOURCE_ROOT" != /opt/agent-flywheel-acfs-* || ! -d "$SOURCE_ROOT/.git" ]]; then
    printf 'Refusing untrusted Flywheel source root: %s\n' "$SOURCE_ROOT" >&2
    exit 2
fi
if [[ ! -f "$SOURCE_ALLOWLIST" || -L "$SOURCE_ALLOWLIST" ]]; then
    printf 'The source checkout has no regular PARTIAL_SAFE allowlist.\n' >&2
    exit 2
fi
if [[ -f "$SOURCE_CLEARANCE" && ! -L "$SOURCE_CLEARANCE" ]]; then
    LICENSE_CLEARED=true
fi

install -d -o root -g root -m 0755 "$STATE_ROOT" /var/log/agent-flywheel
install -o root -g root -m 0444 "$SOURCE_ALLOWLIST" "$INSTALL_ALLOWLIST"
install -o ubuntu -g ubuntu -m 0444 "$SOURCE_ALLOWLIST" "$DOCTOR_ALLOWLIST"
if [[ "$LICENSE_CLEARED" == "true" ]]; then
    install -o root -g root -m 0444 "$SOURCE_CLEARANCE" "$INSTALL_CLEARANCE"
    install -o ubuntu -g ubuntu -m 0444 "$SOURCE_CLEARANCE" "$DOCTOR_CLEARANCE"
fi

doctor() {
    local -a authority_env=(ACFS_PARTIAL_SAFE_ALLOWLIST_FILE="$DOCTOR_ALLOWLIST")
    if [[ "$LICENSE_CLEARED" == "true" ]]; then
        authority_env=(ACFS_LICENSE_CLEARANCE_FILE="$DOCTOR_CLEARANCE")
    fi
    sudo -u ubuntu env \
        HOME="$TARGET_HOME" \
        PATH="$TARGET_HOME/.local/bin:$TARGET_HOME/.bun/bin:$TARGET_HOME/.cargo/bin:/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        TARGET_USER="$TARGET_USER" \
        TARGET_HOME="$TARGET_HOME" \
        FLYWHEEL_SOURCE_ROOT="$SOURCE_ROOT" \
        "${authority_env[@]}" \
        bash -p "$SOURCE_ROOT/scripts/flywheel-partial-safe-doctor.sh" --json
}

doctor_partial_safe() {
    sudo -u ubuntu env \
        HOME="$TARGET_HOME" \
        PATH="$TARGET_HOME/.local/bin:$TARGET_HOME/.bun/bin:$TARGET_HOME/.cargo/bin:/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        TARGET_USER="$TARGET_USER" \
        TARGET_HOME="$TARGET_HOME" \
        FLYWHEEL_SOURCE_ROOT="$SOURCE_ROOT" \
        ACFS_PARTIAL_SAFE_ALLOWLIST_FILE="$DOCTOR_ALLOWLIST" \
        bash -p "$SOURCE_ROOT/scripts/flywheel-partial-safe-doctor.sh" --json
}

exit_if_existing_state_is_healthy() {
    [[ -f "$ACTIVE_STATE" ]] || return 1
    doctor || return 1
    if [[ "$LICENSE_CLEARED" == "true" ]]; then
        printf '{"action":"unchanged","claim":"LICENSE_CLEARED_PARTIAL","status":"pass"}\n'
    else
        printf '{"action":"unchanged","claim":"PARTIAL_SAFE","status":"pass"}\n'
    fi
    return 0
}

state_sha256() {
    /usr/bin/sha256sum "$1" | /usr/bin/awk 'NR == 1 { print $1 }'
}

restore_w3_transition() {
    local failed_state=""
    local failed_sha256=""

    [[ "$W3_TRANSITION_ACTIVE" == "true" ]] || return 0
    if [[ -e "$ACTIVE_STATE" || -L "$ACTIVE_STATE" ]]; then
        failed_sha256="$(state_sha256 "$ACTIVE_STATE" 2>/dev/null || printf unknown)"
        failed_state="$STATE_HISTORY/failed-license-cleared-$(date -u +%Y%m%dT%H%M%SZ)-${failed_sha256:0:16}.json"
        if [[ -e "$failed_state" || -L "$failed_state" ]]; then
            failed_state="$STATE_HISTORY/failed-license-cleared-$(date -u +%Y%m%dT%H%M%SZ)-$$-${failed_sha256:0:16}.json"
        fi
        mv -- "$ACTIVE_STATE" "$failed_state"
        chown root:root "$failed_state"
        chmod 0444 "$failed_state"
    fi
    install -d -o ubuntu -g ubuntu -m 0755 "$TARGET_HOME/.acfs"
    install -o ubuntu -g ubuntu -m 0644 "$W3_TRANSITION_STATE" "$ACTIVE_STATE"
    if [[ "$(state_sha256 "$ACTIVE_STATE")" != "$W3_TRANSITION_SHA256" ]]; then
        printf 'Failed to restore the exact pre-convergence ACFS state. Preserved source: %s\n' \
            "$W3_TRANSITION_STATE" >&2
        return 1
    fi
    W3_TRANSITION_ACTIVE=false
    printf 'Restored the exact pre-convergence ACFS state after a failed commissioning attempt.\n' >&2
}

prepare_w3_transition() {
    local state_name=""

    if [[ ! -f "$ACTIVE_STATE" || -L "$ACTIVE_STATE" ]]; then
        printf 'Refusing to converge a missing, nonregular, or symlinked ACFS state file.\n' >&2
        return 1
    fi
    if [[ -L "$STATE_ROOT" || -L "$STATE_HISTORY" ]]; then
        printf 'Refusing a symlinked Flywheel state-history path.\n' >&2
        return 1
    fi
    install -d -o root -g root -m 0700 "$STATE_HISTORY"
    W3_TRANSITION_SHA256="$(state_sha256 "$ACTIVE_STATE")"
    [[ "$W3_TRANSITION_SHA256" =~ ^[0-9a-f]{64}$ ]] || return 1
    state_name="partial-safe-$(date -u +%Y%m%dT%H%M%SZ)-${W3_TRANSITION_SHA256:0:16}.json"
    W3_TRANSITION_STATE="$STATE_HISTORY/$state_name"
    if [[ -e "$W3_TRANSITION_STATE" || -L "$W3_TRANSITION_STATE" ]]; then
        W3_TRANSITION_STATE="$STATE_HISTORY/partial-safe-$(date -u +%Y%m%dT%H%M%SZ)-$$-${W3_TRANSITION_SHA256:0:16}.json"
    fi
    mv -- "$ACTIVE_STATE" "$W3_TRANSITION_STATE"
    W3_TRANSITION_ACTIVE=true
    if ! chown root:root "$W3_TRANSITION_STATE" \
        || ! chmod 0444 "$W3_TRANSITION_STATE" \
        || [[ "$(state_sha256 "$W3_TRANSITION_STATE")" != "$W3_TRANSITION_SHA256" ]]; then
        restore_w3_transition
        return 1
    fi
}

finalize_w3_transition() {
    local candidate=""

    [[ "$W3_TRANSITION_ACTIVE" == "true" ]] || return 0
    candidate="$(mktemp "$STATE_ROOT/.convergence.XXXXXXXX")"
    jq -cn \
        --arg prior_state "$W3_TRANSITION_STATE" \
        --arg prior_state_sha256 "$W3_TRANSITION_SHA256" \
        --arg source_head "$(git -C "$SOURCE_ROOT" rev-parse HEAD)" \
        --arg completed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{schema:"agent-flywheel.convergence/v1",status:"pass",from:"PARTIAL_SAFE",to:"LICENSE_CLEARED_PARTIAL",prior_state:{path:$prior_state,sha256:$prior_state_sha256},source:{head:$source_head},completed_at:$completed_at}' \
        >"$candidate"
    chmod 0444 "$candidate"
    mv -f -- "$candidate" "$CONVERGENCE_RECEIPT"
    chown root:root "$CONVERGENCE_RECEIPT"
    W3_TRANSITION_ACTIVE=false
}

trap restore_w3_transition EXIT

bash -p "$SOURCE_ROOT/scripts/flywheel-ensure-swap.sh"
sudo -u ubuntu env \
    HOME="$TARGET_HOME" \
    FLYWHEEL_SOURCE_ROOT="$SOURCE_ROOT" \
    bash -p "$SOURCE_ROOT/scripts/flywheel-qualification-host.sh" --json >/dev/null
if exit_if_existing_state_is_healthy; then
    exit 0
fi

apt-get -o Acquire::Retries=3 update
apt-get -o DPkg::Lock::Timeout=120 install -y \
    curl git ca-certificates unzip tar xz-utils jq build-essential gnupg lsb-release

if [[ -f "$ACTIVE_STATE" ]]; then
    if exit_if_existing_state_is_healthy; then
        exit 0
    fi
    if [[ "$LICENSE_CLEARED" != "true" ]]; then
        printf 'Existing ACFS state is not healthy; refusing automatic replacement.\n' >&2
        printf 'Preserve and reconcile %s before a fresh install.\n' "$TARGET_HOME/.acfs/state.json" >&2
        exit 1
    fi
    if ! doctor_partial_safe >/dev/null; then
        printf 'Existing state failed its original PARTIAL_SAFE doctor; refusing convergence.\n' >&2
        exit 1
    fi
    prepare_w3_transition
    printf 'Converging the existing PARTIAL_SAFE state to the license-cleared profile.\n' >&2
fi

install -o root -g root -m 0600 /dev/null "$INSTALL_LOG"

head="$(git -C "$SOURCE_ROOT" rev-parse HEAD)"
install_authority=(ACFS_PARTIAL_SAFE_ALLOWLIST_FILE="$INSTALL_ALLOWLIST")
install_modules=(
    users.ubuntu base.filesystem cli.modern lang.bun lang.uv lang.rust lang.go
)
if [[ "$LICENSE_CLEARED" == "true" ]]; then
    install_authority=(ACFS_LICENSE_CLEARANCE_FILE="$INSTALL_CLEARANCE")
    install_modules+=(
        stack.ntm stack.meta_skill stack.automated_plan_reviser stack.jeffreysprompts
        stack.process_triage stack.ultimate_bug_scanner stack.beads_rust stack.beads_viewer
        stack.cass stack.cm stack.caam stack.slb stack.dcg stack.ru stack.brenner_bot
        stack.rch stack.srps stack.frankensearch stack.storage_ballast_helper
        stack.cross_agent_session_resumer stack.doodlestein_self_releaser
        stack.agent_settings_backup stack.pcr stack.eidetic_engine_cli
        stack.franken_markdown stack.pi_agent_rust
    )
fi
install_args=()
for module_id in "${install_modules[@]}"; do
    install_args+=(--only "$module_id")
done
set +e
# limactl may give this lifecycle process a PTY. Start the installer in a new
# session with closed stdin so --yes cannot discover or reopen that terminal.
/usr/bin/setsid --wait env \
    "${install_authority[@]}" \
    TARGET_USER="$TARGET_USER" \
    TARGET_HOME="$TARGET_HOME" \
    bash -p "$SOURCE_ROOT/install.sh" \
        --yes \
        --mode vibe \
        --ref "$head" \
        --checksums-ref "$head" \
        "${install_args[@]}" </dev/null >"$INSTALL_LOG" 2>&1
install_status=$?
set -e
if ((install_status != 0)); then
    printf 'Flywheel installation failed; owner-only log retained at %s\n' "$INSTALL_LOG" >&2
    exit "$install_status"
fi

doctor
finalize_w3_transition
