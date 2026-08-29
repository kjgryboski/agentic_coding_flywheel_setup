#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/flywheel-lifecycle-test.XXXXXXXX")"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

CALLS="$TEST_ROOT/calls"
STATUS_FILE="$TEST_ROOT/status"
printf 'Stopped\n' >"$STATUS_FILE"
: >"$CALLS"

cat >"$TEST_ROOT/limactl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
    list)
        status="$(cat "$FLYWHEEL_TEST_STATUS_FILE")"
        printf '{"name":"agent-flywheel-ubuntu2404","status":"%s"}\n' "$status"
        ;;
    shell)
        printf '%s\n' "$*" >>"$FLYWHEEL_TEST_CALLS"
        printf '{"claim":"PARTIAL_SAFE","status":"pass"}\n'
        ;;
    stop)
        printf '%s\n' "$*" >>"$FLYWHEEL_TEST_CALLS"
        ;;
    copy)
        printf '%s\n' "$*" >>"$FLYWHEEL_TEST_CALLS"
        ;;
    *)
        printf 'unexpected limactl command: %s\n' "$*" >&2
        exit 2
        ;;
esac
SH

cat >"$TEST_ROOT/heavy-run" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$FLYWHEEL_TEST_CALLS"
SH

chmod 0755 "$TEST_ROOT/limactl" "$TEST_ROOT/heavy-run"

export FLYWHEEL_LIMACTL="$TEST_ROOT/limactl"
export FLYWHEEL_HEAVY_RUN="$TEST_ROOT/heavy-run"
export FLYWHEEL_STATE_HOME="$TEST_ROOT/state"
export FLYWHEEL_SOURCE_REPO="$REPO_ROOT"
export FLYWHEEL_TEST_CALLS="$CALLS"
export FLYWHEEL_TEST_STATUS_FILE="$STATUS_FILE"

status_rc=0
status_json="$("$REPO_ROOT/flywheel" status --json)" || status_rc=$?
[[ "$status_rc" -eq 1 ]]
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value == {
    "claim":"PARTIAL_SAFE",
    "schema":"agent-flywheel.status/v1",
    "status":"Stopped",
    "vm":"agent-flywheel-ubuntu2404",
}
' "$status_json"

"$REPO_ROOT/flywheel" start --quiet
grep -F -- '--stateful -- '"$TEST_ROOT/limactl"' start agent-flywheel-ubuntu2404' "$CALLS" >/dev/null

printf 'Running\n' >"$STATUS_FILE"
doctor_json="$("$REPO_ROOT/flywheel" doctor --json)"
python3 -c 'import json,sys; value=json.loads(sys.argv[1]); assert value["status"] == "pass"' "$doctor_json"
grep -F -- 'scripts/flywheel-partial-safe-doctor.sh --json' "$CALLS" >/dev/null

"$REPO_ROOT/flywheel" stop --quiet
grep -F -- 'stop agent-flywheel-ubuntu2404' "$CALLS" >/dev/null

printf 'flywheel lifecycle tests: PASS\n'
