#!/usr/bin/env bash
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
ALLOWLIST="${ACFS_W2_TEST_ALLOWLIST:-}"
passed=0
failed=0

pass() {
    passed=$((passed + 1))
    printf 'PASS: %s\n' "$1"
}

fail() {
    failed=$((failed + 1))
    printf 'FAIL: %s%s\n' "$1" "${2:+ -- $2}" >&2
}

if [[ -z "$ALLOWLIST" ]]; then
    printf 'ACFS_W2_TEST_ALLOWLIST is required\n' >&2
    exit 2
fi

source "$REPO_ROOT/scripts/lib/contract.sh"
ACFS_PARTIAL_SAFE_ALLOWLIST_FILE="$ALLOWLIST"
export ACFS_PARTIAL_SAFE_ALLOWLIST_FILE

if acfs_w2_partial_safe_active; then
    pass "exact immutable PARTIAL_SAFE allowlist is active"
else
    fail "exact immutable PARTIAL_SAFE allowlist is active" "$ACFS_W2_PARTIAL_SAFE_POLICY_REASON"
fi

if acfs_license_policy_admit_entry filtered; then
    pass "moduleless selection is admitted only with the exact allowlist"
else
    fail "moduleless selection is admitted only with the exact allowlist" "$ACFS_LICENSE_POLICY_REASON"
fi

if acfs_r1_runtime_admit_entry helper; then
    pass "exact allowlist admits only moduleless pre-plan metadata bootstrap"
else
    fail "exact allowlist admits only moduleless pre-plan metadata bootstrap" "$ACFS_R1_POLICY_REASON"
fi

ONLY_MODULES=(users.ubuntu base.filesystem cli.modern lang.bun lang.uv lang.rust lang.go)
ONLY_PHASES=()
SKIP_MODULES=()
unset SKIP_TAGS SKIP_CATEGORIES
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
    pass "exact seven safe seeds are accepted"
else
    fail "exact seven safe seeds are accepted" "$ACFS_R1_POLICY_REASON"
fi

if node - "$REPO_ROOT/scripts/generated/manifest_index.sh" <<'NODE'
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
const seeds = ['users.ubuntu', 'base.filesystem', 'cli.modern', 'lang.bun', 'lang.uv', 'lang.rust', 'lang.go'];
const expected = ['base.system', 'users.ubuntu', 'base.filesystem', 'cli.modern', 'lang.bun', 'lang.uv', 'lang.rust', 'lang.go'];
const closure = new Set();
function add(id) {
  if (closure.has(id)) return;
  for (const dep of (deps.get(id) || '').split(',').filter(Boolean)) add(dep);
  closure.add(id);
}
seeds.forEach(add);
const resolved = order.filter((id) => closure.has(id));
if (JSON.stringify(resolved) !== JSON.stringify(expected)) throw new Error(`safe graph mismatch: ${resolved.join(',')}`);
NODE
then
    pass "exact eight-module dependency closure is generated"
else
    fail "exact eight-module dependency closure is generated"
fi

held=(
    stack.beads_rust stack.agent_settings_backup stack.caam stack.cross_agent_session_resumer
    stack.pcr stack.automated_plan_reviser stack.brenner_bot stack.eidetic_engine_cli
    stack.frankensearch stack.jeffreysprompts stack.meta_skill stack.pi_agent_rust
    stack.process_triage stack.rch stack.ru stack.doodlestein_self_releaser
    stack.franken_markdown stack.slb stack.srps stack.storage_ballast_helper
    stack.mcp_agent_mail stack.beads_viewer stack.ultimate_bug_scanner stack.dcg
    stack.cass stack.cm stack.ntm
)
held_failures=0
for module_id in "${held[@]}"; do
    if acfs_r1_runtime_admit_entry direct "$module_id" >/dev/null 2>&1; then
        held_failures=$((held_failures + 1))
    fi
done
if [[ $held_failures -eq 0 ]]; then
    pass "all 27 held module entrypoints remain rejected"
else
    fail "all 27 held module entrypoints remain rejected" "$held_failures unexpectedly admitted"
fi

if (( BASH_VERSINFO[0] >= 4 )); then
    source "$REPO_ROOT/scripts/generated/manifest_index.sh"
    ACFS_MANIFEST_INDEX_LOADED=true
    ACFS_EFFECTIVE_PLAN=(base.system users.ubuntu base.filesystem cli.modern lang.bun lang.uv lang.rust lang.go)
    if acfs_r1_runtime_validate_plan; then
        pass "exact eight-module runtime plan is accepted"
    else
        fail "exact eight-module runtime plan is accepted" "$ACFS_R1_POLICY_REASON"
    fi
    ACFS_EFFECTIVE_PLAN+=(stack.mcp_agent_mail)
    if acfs_r1_runtime_validate_plan >/dev/null 2>&1; then
        fail "held plan intersection fails closed" "held plan unexpectedly admitted"
    else
        pass "held plan intersection fails closed"
    fi
else
    pass "supported-host runtime-plan challenge is reserved for Bash 4+"
fi

unset ACFS_PARTIAL_SAFE_ALLOWLIST_FILE
if acfs_license_policy_admit_entry filtered >/dev/null 2>&1; then
    fail "default U6 moduleless HOLD remains closed" "selection admitted without allowlist"
else
    pass "default U6 moduleless HOLD remains closed"
fi

printf '\nW2 PARTIAL_SAFE commissioning: %d passed, %d failed\n' "$passed" "$failed"
[[ $failed -eq 0 ]]
