#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
GUEST_INSTALLER="$REPO_ROOT/scripts/flywheel-mac-install-guest.sh"

launch_block="$({
    sed -n '/^set +e$/,/^install_status=\$?$/p' "$GUEST_INSTALLER"
} 2>/dev/null)"

[[ "$launch_block" == *'/usr/bin/setsid --wait env'* ]]
[[ "$launch_block" == *$'        --yes \\'* ]]
[[ "$launch_block" == *'"${install_args[@]}" </dev/null >"$INSTALL_LOG" 2>&1'* ]]
[[ "$launch_block" == *$'install_status=$?'* ]]

# On the Ubuntu guest platform, exercise the launch primitive from a parent
# that owns a PTY. The child must neither see stdin as a TTY nor be able to
# reopen the parent's controlling terminal, and setsid --wait must preserve its
# exit status.
if [[ "$(uname -s)" == "Linux" ]]; then
    pty_output=""
    launch_status=0
    set +e
    pty_output="$(
        script -qec \
            "/usr/bin/setsid --wait env bash -c '[[ ! -t 0 ]] || exit 90; if exec 3<>/dev/tty 2>/dev/null; then exit 91; fi; printf detached; exit 23' </dev/null" \
            /dev/null 2>&1
    )"
    launch_status=$?
    set -e

    [[ "$launch_status" -eq 23 ]]
    [[ "$pty_output" == *detached* ]]
fi

printf 'flywheel mac guest installer noninteractive launch: PASS\n'
