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

python3 - "$REPO_ROOT/config/flywheel-partial-safe-allowlist.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle)
contract = value["commissioning_scope"]["qualification_host_contract"]
assert contract == {
    "architectures": ["aarch64", "x86_64"],
    "clean_source_identity_required": True,
    "host_identity": "any-compliant-host",
    "id": "agent-flywheel.qualification-host/v1",
    "isolation_required": True,
    "minimum_bash_major": 4,
    "minimum_disk_gib": 20,
    "ubuntu_version": "24.04",
}
assert "supported_hosts" not in value["commissioning_scope"]
PY

QUALIFICATION_ROOT="$TEST_ROOT/qualification-source"
mkdir -p "$QUALIFICATION_ROOT"
git -C "$QUALIFICATION_ROOT" init -q
git -C "$QUALIFICATION_ROOT" -c user.name=Flywheel -c user.email=flywheel.invalid@example.test \
    commit --allow-empty -qm initial
printf 'ID=ubuntu\nVERSION_ID="24.04"\n' >"$TEST_ROOT/os-release"
cat >"$TEST_ROOT/uname" <<'SH'
#!/usr/bin/env bash
[[ "${1:-}" == "-m" ]] && printf 'aarch64\n' || exec /usr/bin/uname "$@"
SH
cat >"$TEST_ROOT/df" <<'SH'
#!/usr/bin/env bash
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
printf '/dev/mock 100000000 1 60000000 1%% /\n'
SH
cat >"$TEST_ROOT/systemd-detect-virt" <<'SH'
#!/usr/bin/env bash
printf 'qemu\n'
SH
chmod 0755 "$TEST_ROOT/uname" "$TEST_ROOT/df" "$TEST_ROOT/systemd-detect-virt"
qualification_json="$(
    PATH="$TEST_ROOT:$PATH" \
    FLYWHEEL_SOURCE_ROOT="$QUALIFICATION_ROOT" \
    FLYWHEEL_OS_RELEASE_FILE="$TEST_ROOT/os-release" \
    FLYWHEEL_BASH_MAJOR=5 \
    FLYWHEEL_BASH_VERSION=5.2.0 \
    "$REPO_ROOT/scripts/flywheel-qualification-host.sh" --json
)"
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["status"] == "pass"
assert value["summary"] == {"fail":0,"pass":6}
assert value["contract"]["host_identity"] == "any-compliant-host"
assert value["contract"]["architectures"] == ["aarch64","x86_64"]
assert value["contract"]["minimum_disk_gib"] == 20
' "$qualification_json"

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
