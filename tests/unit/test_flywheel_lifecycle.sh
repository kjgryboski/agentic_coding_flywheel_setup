#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/flywheel-lifecycle-test.XXXXXXXX")"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

CALLS="$TEST_ROOT/calls"
STATUS_FILE="$TEST_ROOT/status"
PRESENT_FILE="$TEST_ROOT/present"
PROFILE_FILE="$TEST_ROOT/profile"
QUERY_FILE="$TEST_ROOT/query"
printf 'Stopped\n' >"$STATUS_FILE"
printf '1\n' >"$PRESENT_FILE"
printf 'exact\n' >"$PROFILE_FILE"
printf 'ok\n' >"$QUERY_FILE"
: >"$CALLS"

cat >"$TEST_ROOT/limactl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
    list)
        printf '%s\n' "$*" >>"$FLYWHEEL_TEST_CALLS"
        [[ "$(cat "$FLYWHEEL_TEST_QUERY_FILE")" == "ok" ]] || exit 44
        [[ "$(cat "$FLYWHEEL_TEST_PRESENT_FILE")" == "1" ]] || exit 0
        status="$(cat "$FLYWHEEL_TEST_STATUS_FILE")"
        cpus=6
        [[ "$(cat "$FLYWHEEL_TEST_PROFILE_FILE")" == "exact" ]] || cpus=4
        printf '{"name":"agent-flywheel-ubuntu2404","status":"%s","vmType":"vz","arch":"aarch64","cpus":%s,"memory":10737418240,"disk":73014444032,"config":{"images":[{"location":"https://cloud-images.ubuntu.com/releases/24.04/release-20260814/ubuntu-24.04-server-cloudimg-arm64.img","arch":"aarch64","digest":"sha256:4a281a921b8d7db952895ab619736f10efe9f63e111fa5b5779ed18f023818aa"}],"plain":true,"mounts":[],"portForwards":[{"ignore":true}]}}\n' "$status" "$cpus"
        ;;
    validate)
        printf '%s\n' "$*" >>"$FLYWHEEL_TEST_CALLS"
        ;;
    start)
        printf '%s\n' "$*" >>"$FLYWHEEL_TEST_CALLS"
        printf '1\n' >"$FLYWHEEL_TEST_PRESENT_FILE"
        printf 'Running\n' >"$FLYWHEEL_TEST_STATUS_FILE"
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
        printf 'Stopped\n' >"$FLYWHEEL_TEST_STATUS_FILE"
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
[[ "${1:-}" == "--stateful" && "${2:-}" == "--" ]]
shift 2
"$@"
SH

chmod 0755 "$TEST_ROOT/limactl" "$TEST_ROOT/heavy-run"

export FLYWHEEL_LIMACTL="$TEST_ROOT/limactl"
export FLYWHEEL_HEAVY_RUN="$TEST_ROOT/heavy-run"
export FLYWHEEL_STATE_HOME="$TEST_ROOT/state"
export FLYWHEEL_SOURCE_REPO="$REPO_ROOT"
export FLYWHEEL_TEST_CALLS="$CALLS"
export FLYWHEEL_TEST_STATUS_FILE="$STATUS_FILE"
export FLYWHEEL_TEST_PRESENT_FILE="$PRESENT_FILE"
export FLYWHEEL_TEST_PROFILE_FILE="$PROFILE_FILE"
export FLYWHEEL_TEST_QUERY_FILE="$QUERY_FILE"

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
cp "$REPO_ROOT/config/flywheel-lima.yaml" \
    "$QUALIFICATION_ROOT/config/flywheel-lima.yaml"
cp "$REPO_ROOT/flywheel" "$QUALIFICATION_ROOT/flywheel"
cp "$REPO_ROOT/scripts/flywheel-repository-control.py" \
    "$QUALIFICATION_ROOT/scripts/flywheel-repository-control.py"
git -C "$QUALIFICATION_ROOT" add \
    acfs.manifest.yaml VERSION AGENTS.md flywheel .github/workflows/test.yml \
    config/flywheel-partial-safe-allowlist.json config/flywheel-lima.yaml \
    scripts/flywheel-repository-control.py
git -C "$QUALIFICATION_ROOT" -c user.name=Flywheel -c user.email=flywheel.invalid@example.test \
    commit -qm initial
printf 'ID=ubuntu\nVERSION_ID="24.04"\n' >"$TEST_ROOT/os-release"
printf 'MemTotal: 10485760 kB\nSwapTotal: 8388608 kB\n' >"$TEST_ROOT/meminfo"
git -C "$QUALIFICATION_ROOT" bundle create "$TEST_ROOT/qualification-source.bundle" HEAD
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
    FLYWHEEL_SOURCE_BUNDLE="$TEST_ROOT/qualification-source.bundle" \
    FLYWHEEL_OS_RELEASE_FILE="$TEST_ROOT/os-release" \
    FLYWHEEL_MEMINFO_FILE="$TEST_ROOT/meminfo" \
    FLYWHEEL_BASH_MAJOR=5 \
    FLYWHEEL_BASH_VERSION=5.2.0 \
    "$REPO_ROOT/scripts/flywheel-qualification-host.sh" --json
)"
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["status"] == "pass"
assert value["summary"] == {"fail":0,"pass":9}
assert value["contract"]["host_identity"] == "any-compliant-host"
assert value["contract"]["architectures"] == ["aarch64","x86_64"]
assert value["contract"]["minimum_disk_gib"] == 20
assert value["contract"]["minimum_memory_gib"] == 8
assert value["contract"]["minimum_swap_gib"] == 8
assert value["source"]["clean"] is True
assert value["bundle"]["verified"] is True
assert len(value["receipt_sha256"]) == 64
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
cmp -s "$QUALIFICATION_ROOT/flywheel" "$TEST_ROOT/home/.local/bin/flywheel"
# The installed entrypoint must be able to converge again. Historically it
# tried to install itself onto itself and failed after the guest had succeeded.
HOME="$TEST_ROOT/home" "$TEST_ROOT/home/.local/bin/flywheel" mac install --quiet
cmp -s "$QUALIFICATION_ROOT/flywheel" "$TEST_ROOT/home/.local/bin/flywheel"
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
assert value["modules"] == {"approved": 8, "licensing_cleared": 0, "licensing_pending": 27}
PY

printf 'Stopped\n' >"$STATUS_FILE"
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
vm=value["vm"]
assert vm["healthy"] is False
assert vm["exists"] is True
assert vm["name"] == "agent-flywheel-ubuntu2404"
assert vm["status"] == "Stopped"
assert vm["query_status"] == "ok"
assert vm["contract"]["id"] == "agent-flywheel.mac-vm/v1"
assert vm["contract"]["matches"] is True
assert vm["mismatches"] == []
assert vm["resources"] == {
    "architecture":"aarch64",
    "cpus":6,
    "disk_bytes":73014444032,
    "exposed_guest_ports":False,
    "image":{
        "digest":"sha256:4a281a921b8d7db952895ab619736f10efe9f63e111fa5b5779ed18f023818aa",
        "location":"https://cloud-images.ubuntu.com/releases/24.04/release-20260814/ubuntu-24.04-server-cloudimg-arm64.img",
    },
    "memory_bytes":10737418240,
    "mount_count":0,
    "plain":True,
    "vm_type":"vz",
}
assert value["source"]["clean"] is True
assert value["source"]["matches_installation"] is True
assert value["installation"]["status"] == "recorded"
assert value["installation"]["matches_current_authority"] is True
assert value["modules"]["approved_count"] == 8
assert value["modules"]["pending_licensing_approvals"] == 27
assert value["repository_rollout"] == {"status":"not_connected"}
assert any(item["code"] == "vm_not_running" for item in value["blockers"])
' "$status_json"

"$REPO_ROOT/flywheel" start --quiet
grep -F -- '--stateful -- '"$TEST_ROOT/limactl"' start --tty=false agent-flywheel-ubuntu2404' "$CALLS" >/dev/null

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
[[ "$running_text" == *'VM exists: yes'* ]]
[[ "$running_text" == *'VM resources: vz/aarch64, 6 CPU, 10 GiB memory, 68 GiB disk, plain=true'* ]]
[[ "$running_text" == *'VM contract: match'* ]]
[[ "$running_text" == *'VM mismatches: none'* ]]
[[ "$running_text" == *'Modules: 8 approved; 27 licensing approvals pending'* ]]
[[ "$running_text" == *'Qualification: pass'* ]]
[[ "$running_text" == *'Doctor: pass'* ]]
[[ "$running_text" == *'Repository rollout: not_connected'* ]]
[[ "$running_text" == *'Blocker [repository_rollout]: receipt_not_connected'* ]]

printf '{"schema":"agent-flywheel.repository-rollout/v1","status":"pass","scope":"live-repository-rollout","repository":"synthetic/local","bookclub_eligible":true}\n' \
    >"$TEST_ROOT/rollout.json"
rollout_json="$("$REPO_ROOT/flywheel" status --json --rollout-receipt "$TEST_ROOT/rollout.json")"
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
rollout=value["repository_rollout"]
assert rollout["status"] == "invalid"
assert "unbound generic repository rollout receipts are not trusted" in rollout["error"]
assert [item["code"] for item in value["blockers"]] == ["receipt_invalid"]
' "$rollout_json"

cp "$REPO_ROOT/tests/unit/fixtures/ops-github-admission-synthetic-202040d1.json" \
    "$TEST_ROOT/synthetic-pilot.json"
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
assert rollout["git"]["head"] == "202040d1b72183225dfdfc665be78ad429eba3ff"
assert rollout["git"]["tree"] == "32be2a7b7b2940e45de2d2e847fbb9b14866c962"
assert rollout["receipt_sha256"] == "e01f5ca3f3ab55da1a2cf932f4643d6d0a68cac73c13d22b4baff02c3df9c58e"
assert rollout["artifact_sha256"] == "6a6232d3c98a56d6740f3382353cae785882d7ede2c51a2b28a0a0ef263544aa"
assert rollout["tests"]["run"] == 10
assert {field: rollout["tests"][field] for field in ("failures","errors","skipped")} == {
    "failures":0,"errors":0,"skipped":0,
}
assert all(rollout["claims"][claim] == "PASS" for claim in (
    "authenticated_webhook_ingestion",
    "duplicate_delivery",
    "forced_peer_first_concurrency_100_iterations",
    "one_create_zero_duplicate_updates_revision_one",
    "component_restart_retained_replay_zero_provider_io",
    "failure_closure_and_ambiguous_recovery",
))
assert rollout["claims"]["live_postgres_restart"] == "NOT_RUN"
assert rollout["claims"]["live_github_publication"] == "NOT_RUN"
assert [item["code"] for item in value["blockers"]] == ["live_rollout_not_proven"]
' "$synthetic_status_json"
synthetic_status_text="$("$REPO_ROOT/flywheel" status --rollout-receipt "$TEST_ROOT/synthetic-pilot.json")"
[[ "$synthetic_status_text" == *'Flywheel: ready'* ]]
[[ "$synthetic_status_text" == *'Repository rollout: evidence_connected'* ]]
[[ "$synthetic_status_text" == *'Blocker [repository_rollout]: live_rollout_not_proven'* ]]

python3 - "$TEST_ROOT/synthetic-pilot.json" "$TEST_ROOT/contradictory-pilot.json" <<'PY'
import hashlib
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle)
value["bookclub_eligible"] = False
value.pop("receipt_sha256")
canonical = (json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n").encode()
value["receipt_sha256"] = hashlib.sha256(canonical).hexdigest()
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump(value, handle, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    handle.write("\n")
PY
contradictory_json="$("$REPO_ROOT/flywheel" status --json --rollout-receipt "$TEST_ROOT/contradictory-pilot.json")"
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["repository_rollout"]["status"] == "invalid"
assert "verdict and BookClub eligibility contradict" in value["repository_rollout"]["error"]
' "$contradictory_json"

python3 - "$TEST_ROOT/synthetic-pilot.json" "$TEST_ROOT/malformed-pilot.json" <<'PY'
import hashlib
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle)
value["git"]["head"] = "A" * 40
value.pop("receipt_sha256")
canonical = (json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n").encode()
value["receipt_sha256"] = hashlib.sha256(canonical).hexdigest()
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump(value, handle, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    handle.write("\n")
PY
malformed_json="$("$REPO_ROOT/flywheel" status --json --rollout-receipt "$TEST_ROOT/malformed-pilot.json")"
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["repository_rollout"]["status"] == "invalid"
assert "exact lowercase Git object IDs" in value["repository_rollout"]["error"]
' "$malformed_json"

python3 - "$TEST_ROOT/synthetic-pilot.json" "$TEST_ROOT/unproven-pilot.json" <<'PY'
import hashlib
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle)
value["claims"]["duplicate_delivery"] = "UNPROVEN"
value.pop("receipt_sha256")
canonical = (json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n").encode()
value["receipt_sha256"] = hashlib.sha256(canonical).hexdigest()
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump(value, handle, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    handle.write("\n")
PY
unproven_json="$("$REPO_ROOT/flywheel" status --json --rollout-receipt "$TEST_ROOT/unproven-pilot.json")"
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["repository_rollout"]["status"] == "invalid"
assert "claim outcomes contradict" in value["repository_rollout"]["error"]
' "$unproven_json"

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

OPS_SOURCE="$TEST_ROOT/ops-source"
mkdir -p \
    "$OPS_SOURCE/scripts" \
    "$OPS_SOURCE/tests" \
    "$OPS_SOURCE/src/ops_steward"
git -C "$OPS_SOURCE" init -q -b main
git -C "$OPS_SOURCE" remote add origin https://github.com/kjgryboski/ops-steward.git
printf 'pilot producer fixture\n' >"$OPS_SOURCE/scripts/run-github-admission-synthetic-pilot.py"
printf 'pilot test fixture\n' >"$OPS_SOURCE/tests/test_github_admission_synthetic_pilot.py"
printf 'producer fixture\n' >"$OPS_SOURCE/src/ops_steward/github_admission_producer.py"
printf 'store fixture\n' >"$OPS_SOURCE/src/ops_steward/github_admission_store.py"
printf 'webhook fixture\n' >"$OPS_SOURCE/src/ops_steward/github_admission_webhook.py"
git -C "$OPS_SOURCE" add .
git -C "$OPS_SOURCE" -c user.name=Flywheel -c user.email=flywheel.invalid@example.test \
    commit -qm pilot-source

TARGET_ROOT="$TEST_ROOT/bookclub-target"
mkdir -p "$TARGET_ROOT"
git -C "$TARGET_ROOT" init -q -b main
git -C "$TARGET_ROOT" remote add origin https://github.com/example/bookclub.git
printf '# Repository instructions\n' >"$TARGET_ROOT/AGENTS.md"
printf '# BookClub fixture\n' >"$TARGET_ROOT/README.md"
git -C "$TARGET_ROOT" add AGENTS.md README.md
git -C "$TARGET_ROOT" -c user.name=Flywheel -c user.email=flywheel.invalid@example.test \
    commit -qm initial
git -C "$TARGET_ROOT" update-ref refs/remotes/origin/main HEAD

python3 - \
    "$REPO_ROOT/tests/unit/fixtures/ops-github-admission-synthetic-202040d1.json" \
    "$OPS_SOURCE" \
    "$TEST_ROOT/bound-pilot.json" <<'PY'
import hashlib
import json
import pathlib
import subprocess
import sys

template_path, source_path, output_path = sys.argv[1:]
source = pathlib.Path(source_path)
with open(template_path, encoding="utf-8") as handle:
    value = json.load(handle)
value["git"] = {
    "clean": True,
    "head": subprocess.check_output(["git", "-C", source_path, "rev-parse", "HEAD"], text=True).strip(),
    "tree": subprocess.check_output(["git", "-C", source_path, "rev-parse", "HEAD^{tree}"], text=True).strip(),
}
value["evidence_sha256"] = {
    relative: hashlib.sha256((source / relative).read_bytes()).hexdigest()
    for relative in value["evidence_sha256"]
}
value.pop("receipt_sha256")
canonical = (json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n").encode()
value["receipt_sha256"] = hashlib.sha256(canonical).hexdigest()
with open(output_path, "w", encoding="utf-8") as handle:
    json.dump(value, handle, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    handle.write("\n")
PY

eligibility_json="$("$REPO_ROOT/flywheel" repository eligibility "$TARGET_ROOT" \
    --pilot-receipt "$TEST_ROOT/bound-pilot.json" \
    --pilot-source "$OPS_SOURCE" \
    --target-repository example/bookclub \
    --json)"
[[ "$eligibility_json" == "$("$REPO_ROOT/flywheel" repository eligibility "$TARGET_ROOT" \
    --pilot-receipt "$TEST_ROOT/bound-pilot.json" \
    --pilot-source "$OPS_SOURCE" \
    --target-repository example/bookclub \
    --json)" ]]
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["schema"] == "agent-flywheel.repository-live-pilot-eligibility/v1"
assert value["status"] == "eligible"
assert value["outcome"] == "eligible_for_separately_authorized_live_pilot"
assert value["mutation_authorized"] is False
assert value["live_rollout_passed"] is False
assert value["synthetic_pilot_accepted"] is True
assert value["pilot"]["receipt"]["repository"] == "kjgryboski/ops-steward"
assert value["pilot"]["receipt"]["tests"]["run"] == 10
assert value["pilot"]["source"]["clean"] is True
assert value["pilot"]["source"]["evidence_verified"] is True
assert value["target"]["repository"] == "example/bookclub"
assert value["target"]["branch"] == "main"
assert value["target"]["head"] == value["target"]["upstream"]["head"]
assert value["target"]["tree"] == value["target"]["upstream"]["tree"]
assert value["target"]["divergence"] == {"ahead":0,"behind":0}
assert value["target"]["instructions"]["path"] == "AGENTS.md"
assert len(value["target"]["instructions"]["sha256"]) == 64
assert len(value["eligibility_sha256"]) == 64
' "$eligibility_json"
printf '%s\n' "$eligibility_json" >"$TEST_ROOT/eligibility.json"
eligibility_status="$("$REPO_ROOT/flywheel" status --json --rollout-receipt "$TEST_ROOT/eligibility.json")"
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
rollout=value["repository_rollout"]
assert rollout["status"] == "evidence_connected"
assert rollout["scope"] == "live-pilot-eligibility-only"
assert rollout["repository"] == "example/bookclub"
assert rollout["mutation_authorized"] is False
assert rollout["live_rollout_passed"] is False
assert [item["code"] for item in value["blockers"]] == ["live_rollout_not_proven"]
' "$eligibility_status"

python3 - "$TEST_ROOT/eligibility.json" "$TEST_ROOT/forged-eligibility.json" <<'PY'
import hashlib
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle)
receipt = value["pilot"]["receipt"]
receipt["git"]["head"] = "f" * 40
receipt.pop("receipt_sha256")
receipt_source = (json.dumps(receipt, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n").encode()
receipt["receipt_sha256"] = hashlib.sha256(receipt_source).hexdigest()
receipt_artifact = (json.dumps(receipt, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n").encode()
value["pilot"]["artifact_sha256"] = hashlib.sha256(receipt_artifact).hexdigest()
value.pop("eligibility_sha256")
eligibility_source = (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()
value["eligibility_sha256"] = hashlib.sha256(eligibility_source).hexdigest()
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump(value, handle, sort_keys=True, separators=(",", ":"))
    handle.write("\n")
PY
forged_eligibility_status="$("$REPO_ROOT/flywheel" status --json \
    --rollout-receipt "$TEST_ROOT/forged-eligibility.json")"
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["repository_rollout"]["status"] == "invalid"
assert "Ops pilot source has drifted from the sealed receipt" in value["repository_rollout"]["error"]
' "$forged_eligibility_status"

python3 - "$TEST_ROOT/eligibility.json" "$TEST_ROOT/missing-source-eligibility.json" "$TEST_ROOT/missing-target-eligibility.json" <<'PY'
import hashlib
import json
import sys

def write_with_digest(value, path):
    value.pop("eligibility_sha256")
    canonical = (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()
    value["eligibility_sha256"] = hashlib.sha256(canonical).hexdigest()
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(value, handle, sort_keys=True, separators=(",", ":"))
        handle.write("\n")

with open(sys.argv[1], encoding="utf-8") as handle:
    source_missing = json.load(handle)
source_missing["pilot"]["source"]["root"] += "-missing"
write_with_digest(source_missing, sys.argv[2])
with open(sys.argv[1], encoding="utf-8") as handle:
    target_missing = json.load(handle)
target_missing["target"]["root"] += "-missing"
write_with_digest(target_missing, sys.argv[3])
PY
for missing_receipt in \
    "$TEST_ROOT/missing-source-eligibility.json" \
    "$TEST_ROOT/missing-target-eligibility.json"; do
    missing_status="$("$REPO_ROOT/flywheel" status --json --rollout-receipt "$missing_receipt")"
    python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["repository_rollout"]["status"] == "invalid"
assert [item["code"] for item in value["blockers"]] == ["receipt_invalid"]
' "$missing_status"
done

printf 'target drift\n' >"$TARGET_ROOT/drift.txt"
target_dirty_status="$("$REPO_ROOT/flywheel" status --json --rollout-receipt "$TEST_ROOT/eligibility.json")"
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["repository_rollout"]["status"] == "invalid"
assert "target repository is dirty" in value["repository_rollout"]["error"]
' "$target_dirty_status"
git -C "$TARGET_ROOT" add drift.txt
git -C "$TARGET_ROOT" -c user.name=Flywheel -c user.email=flywheel.invalid@example.test \
    commit -qm target-drift
target_drift_rc=0
target_drift_error="$("$REPO_ROOT/flywheel" repository eligibility "$TARGET_ROOT" \
    --pilot-receipt "$TEST_ROOT/bound-pilot.json" \
    --pilot-source "$OPS_SOURCE" \
    --target-repository example/bookclub \
    --json 2>&1)" || target_drift_rc=$?
[[ "$target_drift_rc" -eq 2 ]]
[[ "$target_drift_error" == *'target repository has drifted from the locally observed origin/main'* ]]
target_head_drift_status="$("$REPO_ROOT/flywheel" status --json --rollout-receipt "$TEST_ROOT/eligibility.json")"
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["repository_rollout"]["status"] == "invalid"
assert "target repository has drifted from the locally observed origin/main" in value["repository_rollout"]["error"]
' "$target_head_drift_status"

git -C "$TARGET_ROOT" update-ref refs/remotes/origin/main HEAD
eligibility_after_head="$("$REPO_ROOT/flywheel" repository eligibility "$TARGET_ROOT" \
    --pilot-receipt "$TEST_ROOT/bound-pilot.json" \
    --pilot-source "$OPS_SOURCE" \
    --target-repository example/bookclub \
    --json)"
printf '%s\n' "$eligibility_after_head" >"$TEST_ROOT/eligibility-after-head.json"
git -C "$TARGET_ROOT" remote set-url origin https://github.com/example/other.git
target_remote_status="$("$REPO_ROOT/flywheel" status --json \
    --rollout-receipt "$TEST_ROOT/eligibility-after-head.json")"
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["repository_rollout"]["status"] == "invalid"
assert "target origin identifies example/other, expected example/bookclub" in value["repository_rollout"]["error"]
' "$target_remote_status"
git -C "$TARGET_ROOT" remote set-url origin https://github.com/example/bookclub.git

git -C "$TARGET_ROOT" update-index --assume-unchanged AGENTS.md
printf '# Drifted repository instructions\n' >"$TARGET_ROOT/AGENTS.md"
target_instructions_status="$("$REPO_ROOT/flywheel" status --json \
    --rollout-receipt "$TEST_ROOT/eligibility-after-head.json")"
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["repository_rollout"]["status"] == "invalid"
assert "target binding has drifted" in value["repository_rollout"]["error"]
' "$target_instructions_status"

printf 'source drift\n' >>"$OPS_SOURCE/src/ops_steward/github_admission_producer.py"
git -C "$OPS_SOURCE" add src/ops_steward/github_admission_producer.py
git -C "$OPS_SOURCE" -c user.name=Flywheel -c user.email=flywheel.invalid@example.test \
    commit -qm source-drift
source_drift_rc=0
source_drift_error="$("$REPO_ROOT/flywheel" repository eligibility "$TARGET_ROOT" \
    --pilot-receipt "$TEST_ROOT/bound-pilot.json" \
    --pilot-source "$OPS_SOURCE" \
    --target-repository example/bookclub \
    --json 2>&1)" || source_drift_rc=$?
[[ "$source_drift_rc" -eq 2 ]]
[[ "$source_drift_error" == *'Ops pilot source has drifted from the sealed receipt'* ]]
source_drift_status="$("$REPO_ROOT/flywheel" status --json \
    --rollout-receipt "$TEST_ROOT/eligibility-after-head.json")"
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["repository_rollout"]["status"] == "invalid"
assert "Ops pilot source has drifted from the sealed receipt" in value["repository_rollout"]["error"]
' "$source_drift_status"

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

printf 'validator trust drift\n' >"$QUALIFICATION_ROOT/validator-trust-drift.txt"
dirty_validator_status="$("$REPO_ROOT/flywheel" status --json \
    --rollout-receipt "$TEST_ROOT/rollout-plan.json")" || true
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["repository_rollout"]["status"] == "invalid"
assert "requires the clean exact source recorded by the installation receipt" in value["repository_rollout"]["error"]
' "$dirty_validator_status"
git -C "$QUALIFICATION_ROOT" add validator-trust-drift.txt
git -C "$QUALIFICATION_ROOT" -c user.name=Flywheel -c user.email=flywheel.invalid@example.test \
    commit -qm validator-source-drift
drifted_validator_status="$("$REPO_ROOT/flywheel" status --json \
    --rollout-receipt "$TEST_ROOT/rollout-plan.json")" || true
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["source"]["clean"] is True
assert value["source"]["matches_installation"] is False
assert value["repository_rollout"]["status"] == "invalid"
assert "requires the clean exact source recorded by the installation receipt" in value["repository_rollout"]["error"]
' "$drifted_validator_status"

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

# A genuinely absent named VM is created from the canonical pinned template.
: >"$CALLS"
printf '0\n' >"$PRESENT_FILE"
printf 'Stopped\n' >"$STATUS_FILE"
printf 'exact\n' >"$PROFILE_FILE"
printf 'ok\n' >"$QUERY_FILE"
"$REPO_ROOT/flywheel" start --quiet
grep -E -- 'validate .*/config/flywheel-lima\.yaml$' "$CALLS" >/dev/null
grep -E -- '--stateful -- .*/limactl start --tty=false --name=agent-flywheel-ubuntu2404 .*/config/flywheel-lima\.yaml$' "$CALLS" >/dev/null
[[ "$(<"$PRESENT_FILE")" == "1" ]]
[[ "$(<"$STATUS_FILE")" == "Running" ]]

# An inventory query failure is not treated as absence and cannot create a VM.
: >"$CALLS"
printf 'failed\n' >"$QUERY_FILE"
query_rc=0
query_error="$("$REPO_ROOT/flywheel" start --quiet 2>&1)" || query_rc=$?
[[ "$query_rc" -eq 3 ]]
[[ "$query_error" == *'cannot query Lima VM inventory; no VM was created or changed'* ]]
if grep -F -- '--stateful --' "$CALLS" >/dev/null; then
    printf 'query failure unexpectedly entered the heavy lifecycle guard\n' >&2
    exit 1
fi

# Existing resource drift is visible and blocks start without replacing the VM.
: >"$CALLS"
printf 'ok\n' >"$QUERY_FILE"
printf '1\n' >"$PRESENT_FILE"
printf 'Stopped\n' >"$STATUS_FILE"
printf 'drift\n' >"$PROFILE_FILE"
drift_rc=0
drift_error="$("$REPO_ROOT/flywheel" start --quiet 2>&1)" || drift_rc=$?
[[ "$drift_rc" -eq 2 ]]
[[ "$drift_error" == *'does not match the Flywheel contract (["cpus"]); it was not changed'* ]]
if grep -F -- '--stateful --' "$CALLS" >/dev/null; then
    printf 'resource drift unexpectedly entered the heavy lifecycle guard\n' >&2
    exit 1
fi
drift_status_rc=0
drift_status_json="$("$REPO_ROOT/flywheel" status --json)" || drift_status_rc=$?
[[ "$drift_status_rc" -eq 1 ]]
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
vm=value["vm"]
assert vm["exists"] is True
assert vm["resources"]["cpus"] == 4
assert vm["contract"]["matches"] is False
assert vm["mismatches"] == ["cpus"]
assert any(item["code"] == "vm_contract_drift" for item in value["blockers"])
' "$drift_status_json"
drift_status_text_rc=0
drift_status_text="$("$REPO_ROOT/flywheel" status 2>&1)" || drift_status_text_rc=$?
[[ "$drift_status_text_rc" -eq 1 ]]
[[ "$drift_status_text" == *'VM contract: mismatch'* ]]
[[ "$drift_status_text" == *'VM mismatches: cpus'* ]]

# Stop remains available during resource drift and does not repair or replace it.
: >"$CALLS"
printf 'Running\n' >"$STATUS_FILE"
"$REPO_ROOT/flywheel" stop --quiet
grep -F -- 'stop agent-flywheel-ubuntu2404' "$CALLS" >/dev/null
[[ "$(<"$STATUS_FILE")" == "Stopped" ]]
[[ "$(<"$PROFILE_FILE")" == "drift" ]]

printf 'flywheel lifecycle tests: PASS\n'
