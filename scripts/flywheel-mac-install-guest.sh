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
INSTALL_LOG="/var/log/agent-flywheel/install-$(date -u +%Y%m%dT%H%M%SZ).log"

if [[ "$SOURCE_ROOT" != /opt/agent-flywheel-acfs-* || ! -d "$SOURCE_ROOT/.git" ]]; then
    printf 'Refusing untrusted Flywheel source root: %s\n' "$SOURCE_ROOT" >&2
    exit 2
fi
if [[ ! -f "$SOURCE_ALLOWLIST" || -L "$SOURCE_ALLOWLIST" ]]; then
    printf 'The source checkout has no regular PARTIAL_SAFE allowlist.\n' >&2
    exit 2
fi

install -d -o root -g root -m 0755 "$STATE_ROOT" /var/log/agent-flywheel
install -o root -g root -m 0444 "$SOURCE_ALLOWLIST" "$INSTALL_ALLOWLIST"
install -o ubuntu -g ubuntu -m 0444 "$SOURCE_ALLOWLIST" "$DOCTOR_ALLOWLIST"

sudo -u ubuntu env \
    HOME="$TARGET_HOME" \
    FLYWHEEL_SOURCE_ROOT="$SOURCE_ROOT" \
    bash -p "$SOURCE_ROOT/scripts/flywheel-qualification-host.sh" --json >/dev/null

doctor() {
    sudo -u ubuntu env \
        HOME="$TARGET_HOME" \
        PATH="$TARGET_HOME/.local/bin:$TARGET_HOME/.bun/bin:$TARGET_HOME/.cargo/bin:/usr/local/go/bin:/usr/local/bin:/usr/bin:/bin" \
        TARGET_USER="$TARGET_USER" \
        TARGET_HOME="$TARGET_HOME" \
        FLYWHEEL_SOURCE_ROOT="$SOURCE_ROOT" \
        ACFS_PARTIAL_SAFE_ALLOWLIST_FILE="$DOCTOR_ALLOWLIST" \
        bash -p "$SOURCE_ROOT/scripts/flywheel-partial-safe-doctor.sh" --json
}

if [[ -f "$TARGET_HOME/.acfs/state.json" ]]; then
    if doctor; then
        printf '{"action":"unchanged","claim":"PARTIAL_SAFE","status":"pass"}\n'
        exit 0
    fi
    printf 'Existing ACFS state is not healthy; refusing automatic replacement.\n' >&2
    printf 'Preserve and reconcile %s before a fresh install.\n' "$TARGET_HOME/.acfs/state.json" >&2
    exit 1
fi

apt-get -o Acquire::Retries=3 update
install -o root -g root -m 0600 /dev/null "$INSTALL_LOG"

head="$(git -C "$SOURCE_ROOT" rev-parse HEAD)"
set +e
env \
    ACFS_PARTIAL_SAFE_ALLOWLIST_FILE="$INSTALL_ALLOWLIST" \
    TARGET_USER="$TARGET_USER" \
    TARGET_HOME="$TARGET_HOME" \
    bash -p "$SOURCE_ROOT/install.sh" \
        --yes \
        --mode vibe \
        --ref "$head" \
        --checksums-ref "$head" \
        --only users.ubuntu \
        --only base.filesystem \
        --only cli.modern \
        --only lang.bun \
        --only lang.uv \
        --only lang.rust \
        --only lang.go >"$INSTALL_LOG" 2>&1
install_status=$?
set -e
if ((install_status != 0)); then
    printf 'Flywheel installation failed; owner-only log retained at %s\n' "$INSTALL_LOG" >&2
    exit "$install_status"
fi

doctor
