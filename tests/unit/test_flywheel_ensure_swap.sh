#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
SWAP_HELPER="$REPO_ROOT/scripts/flywheel-ensure-swap.sh"
GUEST_INSTALLER="$REPO_ROOT/scripts/flywheel-mac-install-guest.sh"
STRICT_DOCTOR="$REPO_ROOT/scripts/flywheel-partial-safe-doctor.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/flywheel-swap-test.XXXXXXXX")"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

# shellcheck source=../../scripts/flywheel-ensure-swap.sh
source "$SWAP_HELPER"

test_uid="$(id -u)"
test_gid="$(id -g)"
valid_file="$TEST_ROOT/valid"
printf '0123456789abcdef' >"$valid_file"
chmod 0600 "$valid_file"

# The production helper runs only on Ubuntu and intentionally uses GNU stat.
# Supply deterministic GNU-style metadata while unit testing on either host OS.
stat() {
    local path="${*: -1}"

    case "${path##*/}" in
        valid)
            printf '16 %s %s 600 1\n' "$test_uid" "$test_gid"
            ;;
        wrong-size)
            printf '5 %s %s 600 1\n' "$test_uid" "$test_gid"
            ;;
        wrong-mode)
            printf '16 %s %s 644 1\n' "$test_uid" "$test_gid"
            ;;
        *)
            return 1
            ;;
    esac
}

flywheel_swap_signature_type() {
    printf 'swap\n'
}

[[ "$(stat -c '%s %u %g %a %h' -- "$valid_file")" == "16 $test_uid $test_gid 600 1" ]]
[[ "$(flywheel_swap_signature_type "$valid_file")" == "swap" ]]
flywheel_swap_validate_file "$valid_file" 16 "$test_uid" "$test_gid"

printf 'short' >"$TEST_ROOT/wrong-size"
chmod 0600 "$TEST_ROOT/wrong-size"
if flywheel_swap_validate_file "$TEST_ROOT/wrong-size" 16 "$test_uid" "$test_gid" >/dev/null 2>&1; then
    printf 'wrong-sized swapfile was accepted\n' >&2
    exit 1
fi

cp "$valid_file" "$TEST_ROOT/wrong-mode"
chmod 0644 "$TEST_ROOT/wrong-mode"
if flywheel_swap_validate_file "$TEST_ROOT/wrong-mode" 16 "$test_uid" "$test_gid" >/dev/null 2>&1; then
    printf 'wrong-mode swapfile was accepted\n' >&2
    exit 1
fi

ln -s "$valid_file" "$TEST_ROOT/symlink"
if flywheel_swap_validate_file "$TEST_ROOT/symlink" 16 "$test_uid" "$test_gid" >/dev/null 2>&1; then
    printf 'symlinked swapfile was accepted\n' >&2
    exit 1
fi

flywheel_swap_signature_type() {
    printf 'ext4\n'
}
[[ "$(flywheel_swap_signature_type "$valid_file")" == "ext4" ]]
if flywheel_swap_validate_file "$valid_file" 16 "$test_uid" "$test_gid" >/dev/null 2>&1; then
    printf 'nonswap signature was accepted\n' >&2
    exit 1
fi

proc_swaps="$TEST_ROOT/proc-swaps"
cat >"$proc_swaps" <<EOF
Filename                                Type            Size            Used            Priority
$FLYWHEEL_SWAP_FILE                     file            8388604         0               -2
${FLYWHEEL_SWAP_FILE}.other             file            8388604         0               -3
EOF
flywheel_swap_is_active "$FLYWHEEL_SWAP_FILE" "$proc_swaps"
if flywheel_swap_is_active "$FLYWHEEL_SWAP_DIR/missing" "$proc_swaps"; then
    printf 'inactive swapfile was reported active\n' >&2
    exit 1
fi

helper_source="$(<"$SWAP_HELPER")"
[[ "$helper_source" == *'readonly FLYWHEEL_SWAP_FILE="$FLYWHEEL_SWAP_DIR/swapfile"'* ]]
[[ "$helper_source" == *'readonly FLYWHEEL_SWAP_SIZE_BYTES=8589934592'* ]]
[[ "$helper_source" == *'readonly FLYWHEEL_SWAP_SWAPPINESS=10'* ]]
[[ "$helper_source" == *'readonly FLYWHEEL_SWAP_UNIT="agent-flywheel-swap.service"'* ]]
[[ "$helper_source" == *'readonly FLYWHEEL_SWAP_SYSCTL_FILE="/etc/sysctl.d/90-agent-flywheel-swap.conf"'* ]]
[[ "$helper_source" == *'(set -o noclobber; : >"$FLYWHEEL_SWAP_LOCK")'* ]]
[[ "$helper_source" == *'flock -x -w 120 9'* ]]
[[ "$helper_source" == *'mktemp "$FLYWHEEL_SWAP_DIR/.swapfile.XXXXXXXX"'* ]]
[[ "$helper_source" == *'candidate_device="$(stat -c '\''%d'\'' -- "$candidate")"'* ]]
[[ "$helper_source" == *'directory_device="$(stat -c '\''%d'\'' -- "$FLYWHEEL_SWAP_DIR")"'* ]]
[[ "$helper_source" == *'dd if=/dev/zero of="$candidate" bs=1048576 count=8192 conv=fsync status=none'* ]]
[[ "$helper_source" == *'chown root:root "$candidate"'* ]]
[[ "$helper_source" == *'chmod 0600 "$candidate"'* ]]
[[ "$helper_source" == *'mkswap "$candidate"'* ]]
[[ "$helper_source" == *'mv -T -- "$candidate" "$FLYWHEEL_SWAP_FILE"'* ]]
[[ "$helper_source" == *'flywheel_swap_publish_persistence_file "$FLYWHEEL_SWAP_UNIT_FILE" "$unit_content"'* ]]
[[ "$helper_source" == *'flywheel_swap_publish_persistence_file "$FLYWHEEL_SWAP_SYSCTL_FILE" "$sysctl_content"'* ]]
[[ "$helper_source" == *'ExecStart=/usr/sbin/swapon -- $FLYWHEEL_SWAP_FILE'* ]]
[[ "$helper_source" == *'ExecStop=/usr/sbin/swapoff -- $FLYWHEEL_SWAP_FILE'* ]]
[[ "$helper_source" == *'WantedBy=swap.target'* ]]
[[ "$helper_source" == *'systemctl enable "$FLYWHEEL_SWAP_UNIT"'* ]]
[[ "$helper_source" == *'systemctl is-enabled "$FLYWHEEL_SWAP_UNIT"'* ]]
[[ "$helper_source" == *'flywheel_swap_validate_file "$FLYWHEEL_SWAP_FILE"'* ]]
[[ "$helper_source" == *'flywheel_swap_create'* ]]
[[ "$helper_source" == *'swapon -- "$FLYWHEEL_SWAP_FILE"'* ]]
[[ "$helper_source" == *'sysctl -q -w "vm.swappiness=$FLYWHEEL_SWAP_SWAPPINESS"'* ]]
[[ "$helper_source" == *'if [[ "$(uname -s)" != "Linux" ]]'* ]]
[[ "$helper_source" == *'if [[ "$os_id" != "ubuntu" ]]'* ]]

call_pattern='bash -p "$SOURCE_ROOT/scripts/flywheel-ensure-swap.sh"'
[[ "$(grep -Fxc "$call_pattern" "$GUEST_INSTALLER")" -eq 1 ]]
call_line="$(grep -Fn "$call_pattern" "$GUEST_INSTALLER" | cut -d: -f1)"
apt_line="$(grep -n '^apt-get -o DPkg::Lock::Timeout=120 install -y' "$GUEST_INSTALLER" | cut -d: -f1)"
launch_line="$(grep -n '^/usr/bin/setsid --wait env' "$GUEST_INSTALLER" | cut -d: -f1)"
((call_line > apt_line && call_line < launch_line))

doctor_source="$(<"$STRICT_DOCTOR")"
[[ "$doctor_source" == *'swap_metadata="$(sudo -n stat -Lc '\''%U:%G:%a:%s:%h'\'' "$swap_file"'* ]]
[[ "$doctor_source" == *'"$swap_metadata" == "root:root:600:8589934592:1"'* ]]
[[ "$doctor_source" == *'"$swap_signature" == "swap"'* ]]
[[ "$doctor_source" == *'systemctl is-enabled "$swap_unit"'* ]]
[[ "$doctor_source" == *'"$swap_sysctl_content" == "vm.swappiness = 10"'* ]]
[[ "$doctor_source" == *'NR > 1 && $1 == expected { found = 1 }'* ]]
[[ "$doctor_source" == *'record host.swap_contract pass "8 GiB persistent swap active; vm.swappiness=10"'* ]]

printf 'flywheel swap convergence contract: PASS\n'
