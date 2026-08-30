#!/usr/bin/env bash
set -euo pipefail
umask 077

PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH

readonly FLYWHEEL_SWAP_DIR="/var/lib/agent-flywheel"
readonly FLYWHEEL_SWAP_FILE="$FLYWHEEL_SWAP_DIR/swapfile"
readonly FLYWHEEL_SWAP_LOCK="$FLYWHEEL_SWAP_DIR/.swap.lock"
readonly FLYWHEEL_SWAP_SIZE_BYTES=8589934592
readonly FLYWHEEL_SWAP_SWAPPINESS=10
readonly FLYWHEEL_SWAP_UNIT="agent-flywheel-swap.service"
readonly FLYWHEEL_SWAP_UNIT_FILE="/etc/systemd/system/$FLYWHEEL_SWAP_UNIT"
readonly FLYWHEEL_SWAP_SYSCTL_FILE="/etc/sysctl.d/90-agent-flywheel-swap.conf"
FLYWHEEL_SWAP_CANDIDATE=""

flywheel_swap_error() {
    printf 'Flywheel swap setup failed: %s\n' "$*" >&2
}

flywheel_swap_die() {
    flywheel_swap_error "$@"
    return 1
}

flywheel_swap_require_command() {
    local command_name="$1"

    command -v "$command_name" >/dev/null 2>&1 \
        || flywheel_swap_die "required command is unavailable: $command_name"
}

flywheel_swap_cleanup_candidate() {
    if [[ -n "$FLYWHEEL_SWAP_CANDIDATE" ]] \
        && [[ -e "$FLYWHEEL_SWAP_CANDIDATE" || -L "$FLYWHEEL_SWAP_CANDIDATE" ]]; then
        rm -f -- "$FLYWHEEL_SWAP_CANDIDATE" || true
    fi
    FLYWHEEL_SWAP_CANDIDATE=""
}

flywheel_swap_signature_type() {
    local path="$1"

    blkid -p -s TYPE -o value -- "$path" 2>/dev/null || true
}

flywheel_swap_validate_file() {
    local path="$1"
    local expected_size="${2:-$FLYWHEEL_SWAP_SIZE_BYTES}"
    local expected_uid="${3:-0}"
    local expected_gid="${4:-0}"
    local metadata=""
    local size=""
    local uid=""
    local gid=""
    local mode=""
    local links=""
    local signature=""

    if [[ -L "$path" ]]; then
        flywheel_swap_die "refusing symlinked swapfile: $path"
        return 1
    fi
    if [[ ! -f "$path" ]]; then
        flywheel_swap_die "refusing nonregular swapfile: $path"
        return 1
    fi

    metadata="$(stat -c '%s %u %g %a %h' -- "$path")" \
        || return 1
    read -r size uid gid mode links <<<"$metadata"
    if [[ "$size" != "$expected_size" ]]; then
        flywheel_swap_die "swapfile size is $size bytes; expected $expected_size"
        return 1
    fi
    if [[ "$uid" != "$expected_uid" || "$gid" != "$expected_gid" ]]; then
        flywheel_swap_die "swapfile must be owned by uid:gid $expected_uid:$expected_gid"
        return 1
    fi
    if [[ "$mode" != "600" ]]; then
        flywheel_swap_die "swapfile mode is $mode; expected 600"
        return 1
    fi
    if [[ "$links" != "1" ]]; then
        flywheel_swap_die "swapfile has $links hard links; expected exactly one"
        return 1
    fi

    signature="$(flywheel_swap_signature_type "$path")"
    if [[ "$signature" != "swap" ]]; then
        flywheel_swap_die "existing swapfile has no mkswap signature"
        return 1
    fi
}

flywheel_swap_is_active() {
    local path="$1"
    local swaps_file="${2:-/proc/swaps}"

    [[ -r "$swaps_file" ]] || return 1
    awk -v expected="$path" 'NR > 1 && $1 == expected { found = 1 } END { exit !found }' \
        "$swaps_file"
}

flywheel_swap_validate_directory() {
    local metadata=""
    local uid=""
    local gid=""
    local mode=""
    local mode_value=0

    if [[ -L "$FLYWHEEL_SWAP_DIR" ]]; then
        flywheel_swap_die "refusing symlinked state directory: $FLYWHEEL_SWAP_DIR"
        return 1
    fi
    if [[ ! -e "$FLYWHEEL_SWAP_DIR" ]]; then
        install -d -o root -g root -m 0755 "$FLYWHEEL_SWAP_DIR"
    fi
    if [[ ! -d "$FLYWHEEL_SWAP_DIR" ]]; then
        flywheel_swap_die "state path is not a directory: $FLYWHEEL_SWAP_DIR"
        return 1
    fi

    metadata="$(stat -c '%u %g %a' -- "$FLYWHEEL_SWAP_DIR")" || return 1
    read -r uid gid mode <<<"$metadata"
    if [[ "$uid" != "0" || "$gid" != "0" ]]; then
        flywheel_swap_die "state directory must be owned by root:root"
        return 1
    fi
    mode_value=$((8#$mode))
    if (( (mode_value & 0022) != 0 )); then
        flywheel_swap_die "state directory must not be group- or world-writable"
        return 1
    fi
}

flywheel_swap_validate_lock() {
    local metadata=""

    if [[ -L "$FLYWHEEL_SWAP_LOCK" || ! -f "$FLYWHEEL_SWAP_LOCK" ]]; then
        flywheel_swap_die "swap lock must be a regular, nonsymlink file"
        return 1
    fi
    metadata="$(stat -c '%u:%g:%a:%h' -- "$FLYWHEEL_SWAP_LOCK")" || return 1
    if [[ "$metadata" != "0:0:600:1" ]]; then
        flywheel_swap_die "swap lock metadata is incompatible: $metadata"
        return 1
    fi
}

flywheel_swap_acquire_lock() {
    if [[ -e "$FLYWHEEL_SWAP_LOCK" || -L "$FLYWHEEL_SWAP_LOCK" ]]; then
        flywheel_swap_validate_lock || return 1
    else
        # Noclobber makes concurrent first creation atomic: every contender
        # subsequently opens and locks the same inode instead of replacing it.
        (set -o noclobber; : >"$FLYWHEEL_SWAP_LOCK") 2>/dev/null || true
        flywheel_swap_validate_lock || return 1
    fi

    exec 9<>"$FLYWHEEL_SWAP_LOCK"
    flock -x -w 120 9 \
        || flywheel_swap_die "timed out waiting for the swap convergence lock"
    flywheel_swap_validate_directory
    flywheel_swap_validate_lock
}

flywheel_swap_create() {
    local candidate=""
    local candidate_device=""
    local directory_device=""

    FLYWHEEL_SWAP_CANDIDATE="$(mktemp "$FLYWHEEL_SWAP_DIR/.swapfile.XXXXXXXX")"
    candidate="$FLYWHEEL_SWAP_CANDIDATE"
    if [[ -L "$candidate" || ! -f "$candidate" ]]; then
        flywheel_swap_die "failed to create a regular swapfile candidate"
        return 1
    fi

    candidate_device="$(stat -c '%d' -- "$candidate")"
    directory_device="$(stat -c '%d' -- "$FLYWHEEL_SWAP_DIR")"
    if [[ "$candidate_device" != "$directory_device" ]]; then
        flywheel_swap_cleanup_candidate
        flywheel_swap_die "swapfile candidate is not on the destination filesystem"
        return 1
    fi

    if ! dd if=/dev/zero of="$candidate" bs=1048576 count=8192 conv=fsync status=none \
        || ! chown root:root "$candidate" \
        || ! chmod 0600 "$candidate" \
        || ! mkswap "$candidate" >/dev/null; then
        flywheel_swap_cleanup_candidate
        flywheel_swap_die "could not allocate and format the 8 GiB swapfile candidate"
        return 1
    fi
    if ! flywheel_swap_validate_file "$candidate"; then
        flywheel_swap_cleanup_candidate
        return 1
    fi

    if [[ -e "$FLYWHEEL_SWAP_FILE" || -L "$FLYWHEEL_SWAP_FILE" ]]; then
        flywheel_swap_cleanup_candidate
        flywheel_swap_die "swapfile appeared while its candidate was being prepared"
        return 1
    fi
    if ! mv -T -- "$candidate" "$FLYWHEEL_SWAP_FILE"; then
        flywheel_swap_cleanup_candidate
        flywheel_swap_die "could not atomically publish the swapfile"
        return 1
    fi
    FLYWHEEL_SWAP_CANDIDATE=""
    flywheel_swap_validate_file "$FLYWHEEL_SWAP_FILE"
}

flywheel_swap_publish_persistence_file() {
    local destination="$1"
    local expected_content="$2"
    local parent="${destination%/*}"
    local name="${destination##*/}"
    local candidate=""
    local metadata=""

    if [[ -L "$parent" || ! -d "$parent" ]]; then
        flywheel_swap_die "persistence directory is unavailable or unsafe: $parent"
        return 1
    fi
    if [[ -e "$destination" || -L "$destination" ]]; then
        if [[ -L "$destination" || ! -f "$destination" ]]; then
            flywheel_swap_die "refusing nonregular persistence file: $destination"
            return 1
        fi
        metadata="$(stat -c '%u:%g:%a:%h' -- "$destination")" || return 1
        if [[ "$metadata" != "0:0:644:1" || "$(<"$destination")" != "$expected_content" ]]; then
            flywheel_swap_die "existing persistence file does not match the Flywheel contract: $destination"
            return 1
        fi
        return 0
    fi

    candidate="$(mktemp "$parent/.$name.XXXXXXXX")" || return 1
    if [[ -L "$candidate" || ! -f "$candidate" ]]; then
        flywheel_swap_die "failed to create a regular persistence candidate for $destination"
        return 1
    fi
    if ! printf '%s\n' "$expected_content" >"$candidate" \
        || ! chown root:root "$candidate" \
        || ! chmod 0644 "$candidate" \
        || ! sync -f "$candidate" \
        || ! mv -T -- "$candidate" "$destination"; then
        rm -f -- "$candidate" 2>/dev/null || true
        flywheel_swap_die "could not atomically publish $destination"
        return 1
    fi
    metadata="$(stat -c '%u:%g:%a:%h' -- "$destination")" || return 1
    if [[ "$metadata" != "0:0:644:1" || "$(<"$destination")" != "$expected_content" ]]; then
        flywheel_swap_die "published persistence file failed validation: $destination"
        return 1
    fi
}

flywheel_swap_converge_persistence() {
    local unit_content=""
    local sysctl_content="vm.swappiness = $FLYWHEEL_SWAP_SWAPPINESS"

    unit_content="$(cat <<EOF
[Unit]
Description=Agent Flywheel persistent swap
DefaultDependencies=no
After=local-fs.target
Before=swap.target
ConditionPathExists=$FLYWHEEL_SWAP_FILE

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/swapon -- $FLYWHEEL_SWAP_FILE
ExecStop=/usr/sbin/swapoff -- $FLYWHEEL_SWAP_FILE

[Install]
WantedBy=swap.target
EOF
)"
    flywheel_swap_publish_persistence_file "$FLYWHEEL_SWAP_UNIT_FILE" "$unit_content"
    flywheel_swap_publish_persistence_file "$FLYWHEEL_SWAP_SYSCTL_FILE" "$sysctl_content"
    systemctl daemon-reload
    systemctl enable "$FLYWHEEL_SWAP_UNIT" >/dev/null
    if [[ "$(systemctl is-enabled "$FLYWHEEL_SWAP_UNIT" 2>/dev/null || true)" != "enabled" ]]; then
        flywheel_swap_die "persistent swap unit is not enabled"
        return 1
    fi
}

flywheel_swap_assert_platform() {
    local os_id=""
    local os_release=""

    if [[ "$(uname -s)" != "Linux" ]]; then
        flywheel_swap_die "this helper supports Linux only"
        return 1
    fi
    if [[ -f /usr/lib/os-release && ! -L /usr/lib/os-release ]]; then
        os_release="/usr/lib/os-release"
    elif [[ -f /etc/os-release && ! -L /etc/os-release ]]; then
        os_release="/etc/os-release"
    else
        flywheel_swap_die "cannot verify a regular Ubuntu os-release file"
        return 1
    fi
    os_id="$(awk -F= '$1 == "ID" { value = $2; gsub(/^"|"$/, "", value); print tolower(value); exit }' "$os_release")"
    if [[ "$os_id" != "ubuntu" ]]; then
        flywheel_swap_die "this helper supports Ubuntu only"
        return 1
    fi
}

flywheel_swap_main() {
    local command_name=""

    if (($# != 0)); then
        flywheel_swap_die "this helper accepts no arguments"
        return 2
    fi
    if ((EUID != 0)); then
        flywheel_swap_die "this helper must run as root"
        return 2
    fi
    flywheel_swap_assert_platform

    for command_name in awk blkid cat chmod chown dd flock install mktemp mkswap mv rm \
        stat swapon sync sysctl systemctl uname; do
        flywheel_swap_require_command "$command_name"
    done

    flywheel_swap_validate_directory
    flywheel_swap_acquire_lock
    trap flywheel_swap_cleanup_candidate EXIT

    if [[ -e "$FLYWHEEL_SWAP_FILE" || -L "$FLYWHEEL_SWAP_FILE" ]]; then
        flywheel_swap_validate_file "$FLYWHEEL_SWAP_FILE"
    else
        flywheel_swap_create
    fi
    flywheel_swap_converge_persistence

    if ! flywheel_swap_is_active "$FLYWHEEL_SWAP_FILE"; then
        swapon -- "$FLYWHEEL_SWAP_FILE"
    fi
    if ! flywheel_swap_is_active "$FLYWHEEL_SWAP_FILE"; then
        flywheel_swap_die "swapfile is not active in /proc/swaps"
        return 1
    fi

    sysctl -q -w "vm.swappiness=$FLYWHEEL_SWAP_SWAPPINESS"
    if [[ "$(sysctl -n vm.swappiness)" != "$FLYWHEEL_SWAP_SWAPPINESS" ]]; then
        flywheel_swap_die "vm.swappiness did not converge to $FLYWHEEL_SWAP_SWAPPINESS"
        return 1
    fi

    flywheel_swap_validate_file "$FLYWHEEL_SWAP_FILE"
    printf 'Flywheel swap ready: %s bytes at %s; vm.swappiness=%s\n' \
        "$FLYWHEEL_SWAP_SIZE_BYTES" "$FLYWHEEL_SWAP_FILE" "$FLYWHEEL_SWAP_SWAPPINESS"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    flywheel_swap_main "$@"
fi
