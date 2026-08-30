#!/usr/bin/env bash
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
CLEARANCE="${ACFS_W3_TEST_CLEARANCE:-}"
passed=0
failed=0
TMP_PARENT="${TMPDIR:-/tmp}"
TMP_PARENT="${TMP_PARENT%/}"
TMP_ROOT="$(mktemp -d "$TMP_PARENT/acfs-w3-clearance.XXXXXXXX")" || exit 1

cleanup() {
    if [[ -n "$TMP_ROOT" && "$TMP_ROOT" == "$TMP_PARENT/acfs-w3-clearance."* ]]; then
        chmod -R u+w "$TMP_ROOT" 2>/dev/null || true
        rm -rf -- "$TMP_ROOT"
    fi
}
trap cleanup EXIT

pass() { passed=$((passed + 1)); printf 'PASS: %s\n' "$1"; }
fail() { failed=$((failed + 1)); printf 'FAIL: %s%s\n' "$1" "${2:+ -- $2}" >&2; }

if [[ -z "$CLEARANCE" ]]; then
    printf 'ACFS_W3_TEST_CLEARANCE is required\n' >&2
    exit 2
fi

source "$REPO_ROOT/scripts/lib/contract.sh"
ACFS_LICENSE_CLEARANCE_FILE="$CLEARANCE"
export ACFS_LICENSE_CLEARANCE_FILE

if acfs_license_clearance_active; then
    pass "exact immutable license-clearance receipt is active"
else
    fail "exact immutable license-clearance receipt is active" "$ACFS_LICENSE_CLEARANCE_POLICY_REASON"
fi

cp "$CLEARANCE" "$TMP_ROOT/writable.json"
chmod 0644 "$TMP_ROOT/writable.json"
ACFS_LICENSE_CLEARANCE_FILE="$TMP_ROOT/writable.json"
if acfs_license_clearance_verify >/dev/null 2>&1; then
    fail "writable clearance receipt is rejected" "writable receipt admitted"
else
    pass "writable clearance receipt is rejected"
fi

cp "$CLEARANCE" "$TMP_ROOT/tampered.json"
chmod 0644 "$TMP_ROOT/tampered.json"
printf '\n' >> "$TMP_ROOT/tampered.json"
chmod 0444 "$TMP_ROOT/tampered.json"
ACFS_LICENSE_CLEARANCE_FILE="$TMP_ROOT/tampered.json"
if acfs_license_clearance_verify >/dev/null 2>&1; then
    fail "tampered clearance receipt is rejected" "digest mismatch admitted"
else
    pass "tampered clearance receipt is rejected"
fi

ln -s "$CLEARANCE" "$TMP_ROOT/link.json"
ACFS_LICENSE_CLEARANCE_FILE="$TMP_ROOT/link.json"
if acfs_license_clearance_verify >/dev/null 2>&1; then
    fail "symlinked clearance receipt is rejected" "symlink admitted"
else
    pass "symlinked clearance receipt is rejected"
fi

ACFS_LICENSE_CLEARANCE_FILE="$CLEARANCE"
ACFS_PARTIAL_SAFE_ALLOWLIST_FILE="$REPO_ROOT/config/flywheel-partial-safe-allowlist.json"
if acfs_license_clearance_verify >/dev/null 2>&1; then
    fail "conflicting commissioning authorities are rejected" "dual authority admitted"
else
    pass "conflicting commissioning authorities are rejected"
fi
unset ACFS_PARTIAL_SAFE_ALLOWLIST_FILE
export ACFS_LICENSE_CLEARANCE_FILE

licensed=(
    stack.beads_rust stack.agent_settings_backup stack.caam stack.cross_agent_session_resumer
    stack.pcr stack.automated_plan_reviser stack.brenner_bot stack.eidetic_engine_cli
    stack.frankensearch stack.jeffreysprompts stack.meta_skill stack.pi_agent_rust
    stack.process_triage stack.rch stack.ru stack.doodlestein_self_releaser
    stack.franken_markdown stack.slb stack.srps stack.storage_ballast_helper
    stack.mcp_agent_mail stack.beads_viewer stack.ultimate_bug_scanner stack.dcg
    stack.cass stack.cm stack.ntm
)
license_failures=0
for module_id in "${licensed[@]}"; do
    acfs_license_policy_admit_entry direct "$module_id" >/dev/null 2>&1 \
        || license_failures=$((license_failures + 1))
done
if [[ $license_failures -eq 0 && ${#licensed[@]} -eq 27 ]]; then
    pass "all 27 exact revisions are admitted at the license gate"
else
    fail "all 27 exact revisions are admitted at the license gate" "$license_failures rejected"
fi

if acfs_r1_runtime_admit_entry helper; then
    pass "clearance admits only moduleless pre-plan metadata bootstrap"
else
    fail "clearance admits only moduleless pre-plan metadata bootstrap" "$ACFS_R1_POLICY_REASON"
fi

ONLY_MODULES=(
    users.ubuntu base.filesystem cli.modern lang.bun lang.uv lang.rust lang.go
    stack.ntm stack.meta_skill stack.automated_plan_reviser stack.jeffreysprompts
    stack.process_triage stack.ultimate_bug_scanner stack.beads_rust stack.beads_viewer
    stack.cass stack.cm stack.caam stack.slb stack.dcg stack.ru stack.brenner_bot
    stack.rch stack.srps stack.frankensearch stack.storage_ballast_helper
    stack.cross_agent_session_resumer stack.doodlestein_self_releaser
    stack.agent_settings_backup stack.pcr stack.eidetic_engine_cli
    stack.franken_markdown stack.pi_agent_rust
)
ONLY_PHASES=()
SKIP_MODULES=()
unset SKIP_TAGS SKIP_CATEGORIES ACFS_PARTIAL_SAFE_ALLOWLIST_FILE
NO_DEPS=false
ACFS_CLI_PROFILE=""
ACFS_SELECTED_PROFILE=""
ACFS_FORCE_RESUME=false
ACFS_FORCE_REINSTALL=false
RESET_STATE_ONLY=false
SKIP_PREFLIGHT=false
SKIP_UBUNTU_UPGRADE=false
SKIP_POSTGRES=false
SKIP_VAULT=false
SKIP_CLOUD=false
ACFS_GENERATED_MIGRATED_CATEGORIES=""
ACFS_USE_GENERATED=1

if acfs_r1_runtime_prepare_selection; then
    pass "exact 33-module expanded seed sequence is accepted"
else
    fail "exact 33-module expanded seed sequence is accepted" "$ACFS_R1_POLICY_REASON"
fi

graph_ok=false
manifest_index_loaded=false
if command -v node >/dev/null 2>&1 && ACFS_W3_SEEDS="$ACFS_W3_COMMISSIONING_SEED_CSV" \
ACFS_W3_PLAN="$ACFS_W3_COMMISSIONING_PLAN_CSV" \
node - "$REPO_ROOT/scripts/generated/manifest_index.sh" <<'NODE'
const fs = require('node:fs');
const index = fs.readFileSync(process.argv[2], 'utf8');
function block(name) {
  const match = index.match(new RegExp(`${name}=\\(\\n([\\s\\S]*?)\\n\\)`));
  if (!match) throw new Error(`missing ${name}`);
  return match[1];
}
function assoc(name) {
  const out = new Map();
  for (const match of block(name).matchAll(/^  \['([^']+)'\]="([^"]*)"$/gm)) out.set(match[1], match[2]);
  return out;
}
const order = [...block('ACFS_MODULES_IN_ORDER').matchAll(/^  "([^"]+)"$/gm)].map((m) => m[1]);
const deps = assoc('declare -gA ACFS_MODULE_DEPS');
const seeds = process.env.ACFS_W3_SEEDS.split(',');
const expected = process.env.ACFS_W3_PLAN.split(',');
const closure = new Set();
function add(id) {
  if (closure.has(id)) return;
  for (const dep of (deps.get(id) || '').split(',').filter(Boolean)) add(dep);
  closure.add(id);
}
seeds.forEach(add);
const resolved = order.filter((id) => closure.has(id));
if (JSON.stringify(resolved) !== JSON.stringify(expected)) throw new Error(`W3 graph mismatch: ${resolved.join(',')}`);
NODE
then
    graph_ok=true
elif ((BASH_VERSINFO[0] >= 4)); then
    source "$REPO_ROOT/scripts/generated/manifest_index.sh"
    manifest_index_loaded=true
    declare -A w3_closure=()
    w3_add_module() {
        local selected_module="$1"
        local dependency=""
        local -a dependencies=()
        [[ -z "${w3_closure[$selected_module]+present}" ]] || return 0
        IFS=',' read -r -a dependencies <<< "${ACFS_MODULE_DEPS[$selected_module]:-}"
        for dependency in "${dependencies[@]}"; do
            [[ -z "$dependency" ]] || w3_add_module "$dependency"
        done
        w3_closure["$selected_module"]=1
    }
    IFS=',' read -r -a w3_seeds <<< "$ACFS_W3_COMMISSIONING_SEED_CSV"
    for module_id in "${w3_seeds[@]}"; do
        w3_add_module "$module_id"
    done
    w3_resolved=()
    for module_id in "${ACFS_MODULES_IN_ORDER[@]}"; do
        [[ -z "${w3_closure[$module_id]+present}" ]] || w3_resolved+=("$module_id")
    done
    if [[ "$(_acfs_r1_array_csv "${w3_resolved[@]}")" == "$ACFS_W3_COMMISSIONING_PLAN_CSV" ]]; then
        graph_ok=true
    fi
fi
if [[ "$graph_ok" == "true" ]]; then
    pass "exact 36-module dependency closure is generated"
else
    fail "exact 36-module dependency closure is generated"
fi

if acfs_core_policy_enforce stack.mcp_agent_mail doctor "" >/dev/null 2>&1; then
    fail "Agent Mail C5 remains independently held" "core policy unexpectedly admitted it"
elif [[ "$ACFS_CORE_POLICY_REASON" == *"C5 commissioning HOLD"* ]]; then
    pass "Agent Mail C5 remains independently held"
else
    fail "Agent Mail C5 remains independently held" "$ACFS_CORE_POLICY_REASON"
fi

if acfs_r1_runtime_admit_entry direct stack.power_failure_resumer >/dev/null 2>&1; then
    fail "PFR qualification hold remains independent" "PFR unexpectedly admitted"
else
    pass "PFR qualification hold remains independent"
fi

if ((BASH_VERSINFO[0] >= 4)); then
    if [[ "$manifest_index_loaded" != "true" ]]; then
        source "$REPO_ROOT/scripts/generated/manifest_index.sh"
    fi
    ACFS_MANIFEST_INDEX_LOADED=true
    IFS=',' read -r -a ACFS_EFFECTIVE_PLAN <<< "$ACFS_W3_COMMISSIONING_PLAN_CSV"
    if acfs_r1_runtime_validate_plan; then
        pass "exact 36-module runtime plan is accepted"
    else
        fail "exact 36-module runtime plan is accepted" "$ACFS_R1_POLICY_REASON"
    fi
else
    pass "supported-host runtime-plan challenge is reserved for Bash 4+"
fi

unset ACFS_LICENSE_CLEARANCE_FILE
if acfs_license_policy_admit_entry direct stack.ntm >/dev/null 2>&1; then
    fail "default license HOLD remains closed" "module admitted without clearance"
else
    pass "default license HOLD remains closed"
fi

printf '\nW3 license clearance: %d passed, %d failed\n' "$passed" "$failed"
[[ $failed -eq 0 ]]
