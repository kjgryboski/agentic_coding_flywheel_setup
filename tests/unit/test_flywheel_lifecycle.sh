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
        case "$*" in
            *flywheel-qualification-host.sh*)
                printf '{"schema":"agent-flywheel.qualification-host/v1","status":"pass","summary":{"pass":6,"fail":0}}\n'
                ;;
            *flywheel-partial-safe-doctor.sh*)
                printf '{"schema":"agent-flywheel.partial-safe-doctor/v1","claim":"PARTIAL_SAFE","status":"pass","summary":{"pass":13,"warn":0,"fail":0}}\n'
                ;;
        esac
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
mkdir -p "$QUALIFICATION_ROOT/config" "$QUALIFICATION_ROOT/.github/workflows" "$QUALIFICATION_ROOT/scripts"
git -C "$QUALIFICATION_ROOT" init -q
printf 'schema_version: 2\n' >"$QUALIFICATION_ROOT/acfs.manifest.yaml"
printf '0.8.0\n' >"$QUALIFICATION_ROOT/VERSION"
printf '# Repository instructions\n' >"$QUALIFICATION_ROOT/AGENTS.md"
printf 'name: test\non: push\njobs: {}\n' >"$QUALIFICATION_ROOT/.github/workflows/test.yml"
cp "$REPO_ROOT/config/flywheel-partial-safe-allowlist.json" \
    "$QUALIFICATION_ROOT/config/flywheel-partial-safe-allowlist.json"
cp "$REPO_ROOT/scripts/flywheel-repository-control.py" \
    "$QUALIFICATION_ROOT/scripts/flywheel-repository-control.py"
git -C "$QUALIFICATION_ROOT" add \
    acfs.manifest.yaml VERSION AGENTS.md .github/workflows/test.yml \
    config/flywheel-partial-safe-allowlist.json scripts/flywheel-repository-control.py
git -C "$QUALIFICATION_ROOT" -c user.name=Flywheel -c user.email=flywheel.invalid@example.test \
    commit -qm initial
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

export FLYWHEEL_SOURCE_REPO="$QUALIFICATION_ROOT"
mkdir -p "$FLYWHEEL_STATE_HOME"
chmod 0700 "$FLYWHEEL_STATE_HOME"
printf 'do-not-overwrite\n' >"$TEST_ROOT/symlink-target"
ln -s "$TEST_ROOT/symlink-target" "$FLYWHEEL_STATE_HOME/source-root"
ln -s "$TEST_ROOT/symlink-target" "$FLYWHEEL_STATE_HOME/installation.json"
HOME="$TEST_ROOT/home" "$REPO_ROOT/flywheel" mac install --quiet
[[ ! -L "$FLYWHEEL_STATE_HOME/source-root" ]]
[[ ! -L "$FLYWHEEL_STATE_HOME/installation.json" ]]
[[ "$(<"$TEST_ROOT/symlink-target")" == "do-not-overwrite" ]]
python3 - "$FLYWHEEL_STATE_HOME/installation.json" "$QUALIFICATION_ROOT" <<'PY'
import json
import subprocess
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle)
head = subprocess.check_output(["git", "-C", sys.argv[2], "rev-parse", "HEAD"], text=True).strip()
tree = subprocess.check_output(["git", "-C", sys.argv[2], "rev-parse", "HEAD^{tree}"], text=True).strip()
assert value["schema"] == "agent-flywheel.installation/v1"
assert value["source"]["head"] == head
assert value["source"]["tree"] == tree
assert len(value["bundle"]["sha256"]) == 64
assert value["modules"] == {"approved": 8, "licensing_held": 27}
PY

status_rc=0
status_json="$("$REPO_ROOT/flywheel" status --json)" || status_rc=$?
[[ "$status_rc" -eq 1 ]]
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["schema"] == "agent-flywheel.status/v2"
assert value["claim"] == "PARTIAL_SAFE"
assert value["status"] == "Stopped"
assert value["readiness"] == "attention"
assert value["vm"] == {"healthy":False,"name":"agent-flywheel-ubuntu2404","status":"Stopped"}
assert value["source"]["clean"] is True
assert value["source"]["matches_installation"] is True
assert value["installation"]["status"] == "recorded"
assert value["installation"]["matches_current_allowlist"] is True
assert value["modules"]["approved_count"] == 8
assert value["modules"]["pending_licensing_approvals"] == 27
assert value["repository_rollout"] == {"status":"not_connected"}
assert any(item["code"] == "vm_not_running" for item in value["blockers"])
' "$status_json"

"$REPO_ROOT/flywheel" start --quiet
grep -F -- '--stateful -- '"$TEST_ROOT/limactl"' start agent-flywheel-ubuntu2404' "$CALLS" >/dev/null

printf 'Running\n' >"$STATUS_FILE"
running_json="$("$REPO_ROOT/flywheel" status --json)"
[[ "$running_json" == "$("$REPO_ROOT/flywheel" status --json)" ]]
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["readiness"] == "ready"
assert value["qualification"]["status"] == "pass"
assert value["doctor"]["status"] == "pass"
assert [item["code"] for item in value["blockers"]] == ["receipt_not_connected"]
' "$running_json"
running_text="$("$REPO_ROOT/flywheel" status)"
[[ "$running_text" == *'Flywheel: ready'* ]]
[[ "$running_text" == *'VM: agent-flywheel-ubuntu2404 (Running)'* ]]
[[ "$running_text" == *'Modules: 8 approved; 27 licensing approvals pending'* ]]
[[ "$running_text" == *'Qualification: pass'* ]]
[[ "$running_text" == *'Doctor: pass'* ]]
[[ "$running_text" == *'Repository rollout: not_connected'* ]]
[[ "$running_text" == *'Blocker [repository_rollout]: receipt_not_connected'* ]]

printf '{"schema":"agent-flywheel.repository-rollout/v1","status":"pass","scope":"synthetic-pilot-only","repository":"synthetic/local","bookclub_eligible":true}\n' \
    >"$TEST_ROOT/rollout.json"
rollout_json="$("$REPO_ROOT/flywheel" status --json --rollout-receipt "$TEST_ROOT/rollout.json")"
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
rollout=value["repository_rollout"]
assert rollout["status"] == "evidence_connected"
assert rollout["scope"] == "synthetic-pilot-only"
assert rollout["bookclub_eligible"] is True
assert len(rollout["receipt_sha256"]) == 64
assert [item["code"] for item in value["blockers"]] == ["live_rollout_not_proven"]
' "$rollout_json"

python3 - "$TEST_ROOT/synthetic-pilot.json" <<'PY'
import hashlib
import json
import sys

value = {
    "bookclub_eligible": True,
    "external_mutation": False,
    "git": {"clean": True, "head": "a" * 40, "tree": "b" * 40},
    "qualification_scope": "synthetic-pilot-only",
    "repository": "kjgryboski/ops-steward",
    "schema": "ops-steward.github-admission-synthetic-pilot-receipt/v1",
    "verdict": "PASS",
}
canonical = (json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n").encode()
value["receipt_sha256"] = hashlib.sha256(canonical).hexdigest()
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(value, handle, sort_keys=True, separators=(",", ":"))
    handle.write("\n")
PY
synthetic_status_json="$("$REPO_ROOT/flywheel" status --json --rollout-receipt "$TEST_ROOT/synthetic-pilot.json")"
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
rollout=value["repository_rollout"]
assert rollout["status"] == "evidence_connected"
assert rollout["schema"] == "ops-steward.github-admission-synthetic-pilot-receipt/v1"
assert rollout["declared_status"] == "pass"
assert rollout["scope"] == "synthetic-pilot-only"
assert rollout["repository"] == "kjgryboski/ops-steward"
assert rollout["bookclub_eligible"] is True
assert rollout["external_mutation"] is False
assert rollout["git"]["clean"] is True
assert [item["code"] for item in value["blockers"]] == ["live_rollout_not_proven"]
' "$synthetic_status_json"
synthetic_status_text="$("$REPO_ROOT/flywheel" status --rollout-receipt "$TEST_ROOT/synthetic-pilot.json")"
[[ "$synthetic_status_text" == *'Flywheel: ready'* ]]
[[ "$synthetic_status_text" == *'Repository rollout: evidence_connected'* ]]
[[ "$synthetic_status_text" == *'Blocker [repository_rollout]: live_rollout_not_proven'* ]]

ln -s "$TEST_ROOT/rollout.json" "$TEST_ROOT/rollout-link.json"
linked_rollout_json="$("$REPO_ROOT/flywheel" status --json --rollout-receipt "$TEST_ROOT/rollout-link.json")"
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["repository_rollout"]["status"] == "invalid"
assert [item["code"] for item in value["blockers"]] == ["receipt_invalid"]
' "$linked_rollout_json"

doctor_json="$("$REPO_ROOT/flywheel" doctor --json)"
python3 -c 'import json,sys; value=json.loads(sys.argv[1]); assert value["status"] == "pass"' "$doctor_json"
grep -F -- 'scripts/flywheel-partial-safe-doctor.sh --json' "$CALLS" >/dev/null
doctor_text="$("$REPO_ROOT/flywheel" doctor)"
python3 -c 'import json,sys; value=json.loads(sys.argv[1]); assert value["status"] == "pass"' "$doctor_text"
grep -E -- 'scripts/flywheel-partial-safe-doctor\.sh$' "$CALLS" >/dev/null

capabilities_json="$("$REPO_ROOT/flywheel" capabilities --json)"
[[ "$capabilities_json" == "$("$REPO_ROOT/flywheel" capabilities --json)" ]]
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["schema"] == "agent-flywheel.capabilities/v1"
assert value["exit_codes"]["5"] == "operation_conflict"
assert value["feature_flags"]["portable_qualification_host"] is True
assert any(item["command"] == "flywheel status --json" for item in value["commands"])
assert any(item["command"] == "flywheel repository inspect PATH --json" for item in value["commands"])
' "$capabilities_json"
"$REPO_ROOT/flywheel" robot-docs guide | grep -F 'flywheel status --json --rollout-receipt FILE' >/dev/null

inspection_json="$("$REPO_ROOT/flywheel" repository inspect "$QUALIFICATION_ROOT" --json)"
[[ "$inspection_json" == "$("$REPO_ROOT/flywheel" repository inspect "$QUALIFICATION_ROOT" --json)" ]]
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["schema"] == "agent-flywheel.repository-inspection/v1"
assert value["status"] == "ready_for_bounded_setup_pr"
assert value["mutation_authorized"] is False
assert value["repository"]["clean"] is True
assert value["guidance"]["root_agents"]["path"] == "AGENTS.md"
assert value["guidance"]["unresolved_acfs_new"] == []
assert value["automation"]["github_workflows"] == [".github/workflows/test.yml"]
assert value["admission"]["live_rollout_eligible"] is False
assert len(value["inspection_sha256"]) == 64
' "$inspection_json"

python3 - "$TEST_ROOT/rollout-inventory.json" "$QUALIFICATION_ROOT" <<'PY'
import json
import sys

with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump({
        "schema": "agent-flywheel.rollout-inventory/v1",
        "repositories": [{"path": sys.argv[2], "cohort": "pilot"}],
    }, handle, sort_keys=True, separators=(",", ":"))
    handle.write("\n")
PY
plan_json="$("$REPO_ROOT/flywheel" rollout plan "$TEST_ROOT/rollout-inventory.json" --json)"
[[ "$plan_json" == "$("$REPO_ROOT/flywheel" rollout plan "$TEST_ROOT/rollout-inventory.json" --json)" ]]
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["schema"] == "agent-flywheel.progressive-rollout-plan/v1"
assert value["status"] == "ready_for_setup_prs"
assert value["execution_status"] == "plan_only"
assert value["mutation_authorized"] is False
assert value["repository_count"] == 1
assert value["cohorts"][0]["cohort"] == "pilot"
assert value["cohorts"][0]["live_rollout_eligible"] is False
assert len(value["plan_sha256"]) == 64
' "$plan_json"
printf '%s\n' "$plan_json" >"$TEST_ROOT/rollout-plan.json"
plan_status_json="$("$REPO_ROOT/flywheel" status --json --rollout-receipt "$TEST_ROOT/rollout-plan.json")"
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
rollout=value["repository_rollout"]
assert rollout["status"] == "evidence_connected"
assert rollout["schema"] == "agent-flywheel.progressive-rollout-plan/v1"
assert rollout["scope"] == "plan-only"
assert rollout["repository_count"] == 1
assert rollout["repository"]["name"] == "qualification-source"
assert rollout["repositories"] == [rollout["repository"]]
assert rollout["setup_pr_eligible"] is True
assert rollout["live_rollout_eligible"] is False
assert rollout["bookclub_eligible"] is None
assert [item["code"] for item in value["blockers"]] == ["live_rollout_not_proven"]
' "$plan_status_json"
python3 - "$TEST_ROOT/rollout-plan.json" "$TEST_ROOT/tampered-rollout-plan.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle)
value["repository_count"] = 2
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump(value, handle, sort_keys=True, separators=(",", ":"))
    handle.write("\n")
PY
tampered_plan_status_json="$("$REPO_ROOT/flywheel" status --json --rollout-receipt "$TEST_ROOT/tampered-rollout-plan.json")"
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["repository_rollout"]["status"] == "invalid"
assert [item["code"] for item in value["blockers"]] == ["receipt_invalid"]
' "$tampered_plan_status_json"

typo_rc=0
typo_error="$("$REPO_ROOT/flywheel" statsu 2>&1)" || typo_rc=$?
[[ "$typo_rc" -eq 2 ]]
[[ "$typo_error" == *'did you mean: flywheel status --json'* ]]

python3 - "$FLYWHEEL_STATE_HOME/installation.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle)
value["modules"]["approved"] = 9
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(value, handle, sort_keys=True, separators=(",", ":"))
    handle.write("\n")
PY
tampered_rc=0
tampered_json="$("$REPO_ROOT/flywheel" status --json)" || tampered_rc=$?
[[ "$tampered_rc" -eq 1 ]]
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["installation"]["status"] == "receipt_invalid"
assert any(item["code"] == "installation_receipt_invalid" for item in value["blockers"])
' "$tampered_json"

"$REPO_ROOT/flywheel" stop --quiet
grep -F -- 'stop agent-flywheel-ubuntu2404' "$CALLS" >/dev/null

printf 'flywheel lifecycle tests: PASS\n'
