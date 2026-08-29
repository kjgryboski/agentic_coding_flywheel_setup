#!/usr/bin/env bash
# Focused, offline adversarial checks for the R1 commissioning envelope.

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/acfs-r1-admission.XXXXXX")" || exit 1

passed=0
failed=0

cleanup_test_artifacts() {
    if [[ -n "$TMP_ROOT" && "$TMP_ROOT" == "${TMPDIR:-/tmp}/acfs-r1-admission."* ]]; then
        chmod -R u+w "$TMP_ROOT" 2>/dev/null || true
        rm -rf -- "$TMP_ROOT"
    fi
}
trap cleanup_test_artifacts EXIT

pass() {
    passed=$((passed + 1))
    printf 'PASS: %s\n' "$1"
}

fail() {
    failed=$((failed + 1))
    printf 'FAIL: %s\n' "$1" >&2
    [[ -n "${2:-}" ]] && printf '  %s\n' "$2" >&2
}

expect_success() {
    local label="$1"
    shift
    if "$@"; then
        pass "$label"
    else
        fail "$label" "unexpected nonzero status"
    fi
}

expect_failure() {
    local label="$1"
    shift
    if "$@"; then
        fail "$label" "unexpected success"
    else
        pass "$label"
    fi
}

# Avoid loading logging.sh under macOS Bash 3.2. The runtime target uses modern
# Bash, but these policy functions themselves are deliberately portable.
ACFS_BLUE="test"
# shellcheck source=../../scripts/lib/contract.sh
source "$REPO_ROOT/scripts/lib/contract.sh"

expect_success "content-addressed LIC1+LIC2 exclusion profile verifies" \
    acfs_license_policy_verify_profile
expect_success "content-addressed R1 profile verifies" acfs_r1_runtime_verify_profile

if [[ "$ACFS_LICENSE_EXCLUSION_PROFILE_SHA256" == "f7e9575697b7e6d18f5059c92430a01fb0bbd43b944c3b1073be4804badbe513" \
    && "$ACFS_LICENSE_LIC1_SHA256" == "9bfd85c340c6223482e07b96c668600e0db9a18b8a4f25e45f77f0129af63300" \
    && "$ACFS_LICENSE_LIC2_SHA256" == "89b56c5a62cea238a9e9d3b6ff88a2923a88bafd45c982a523dba5c7de5b51ee" \
    && "$ACFS_LICENSE_HELD_COUNT" == "27" \
    && "$ACFS_LICENSE_PLAIN_MIT_ONLY_COUNT" == "1" \
    && "$ACFS_LICENSE_UNRESOLVED_COUNT" == "0" ]]; then
    pass "final LIC1/LIC2 identities and 27/1/0 classification are exact"
else
    fail "final LIC1/LIC2 identities and 27/1/0 classification are exact"
fi

moduleless_entries=(default filtered install update doctor doctor-fix doctor-fix-finalize repair autofix resume finalize failure-cleanup service configuration list probe plan print helper)

license_payload="$(acfs_license_exclusion_profile_payload)"
license_row_count="$(printf '%s\n' "$license_payload" | /usr/bin/awk -F= '$1 == "row" { count++ } END { print count + 0 }')"
license_held_row_count="$(printf '%s\n' "$license_payload" | /usr/bin/awk -F'\\|' '/^row=/ && $4 ~ /^held_lic[12]$/ { count++ } END { print count + 0 }')"
license_lic1_row_count="$(printf '%s\n' "$license_payload" | /usr/bin/awk -F'\\|' '/^row=/ && $4 == "held_lic1" { count++ } END { print count + 0 }')"
license_lic2_row_count="$(printf '%s\n' "$license_payload" | /usr/bin/awk -F'\\|' '/^row=/ && $4 == "held_lic2" { count++ } END { print count + 0 }')"
license_pfr_row_count="$(printf '%s\n' "$license_payload" | /usr/bin/awk -F'\\|' '/^row=stack[.]power_failure_resumer[|]/ && $4 == "plain_mit_license_only_non_authorizing" { count++ } END { print count + 0 }')"
license_unique_module_count="$(printf '%s\n' "$license_payload" | /usr/bin/awk -F'[=|]' '$1 == "row" { seen[$2]=1 } END { for (id in seen) count++; print count + 0 }')"
if [[ "$license_row_count" == "28" && "$license_held_row_count" == "27" \
    && "$license_lic1_row_count" == "20" && "$license_lic2_row_count" == "7" \
    && "$license_pfr_row_count" == "1" && "$license_unique_module_count" == "28" ]]; then
    pass "license profile binds 28 unique module/repository/commit rows without unresolved entries"
else
    fail "license profile binds 28 unique module/repository/commit rows without unresolved entries" \
        "rows=$license_row_count held=$license_held_row_count lic1=$license_lic1_row_count lic2=$license_lic2_row_count pfr=$license_pfr_row_count unique=$license_unique_module_count"
fi

IFS=',' read -r -a license_held_modules <<< "$ACFS_LICENSE_HELD_CSV"
poison_fixture="$TMP_ROOT/license-poison-fixture"
poison_marker="$poison_fixture/poison-callback-fired"
matrix_failures="$TMP_ROOT/license-poison-matrix-failures"
mkdir -p "$poison_fixture/home/.local/bin" "$poison_fixture/bin" "$poison_fixture/state"
printf 'manifest sentinel\n' > "$poison_fixture/state/manifest-index"
printf 'checksum sentinel\n' > "$poison_fixture/state/checksums"
printf 'state sentinel\n' > "$poison_fixture/state/state.json"
printf 'progress sentinel\n' > "$poison_fixture/state/progress"
printf 'config sentinel\n' > "$poison_fixture/state/config"
printf 'log sentinel\n' > "$poison_fixture/state/log"
printf 'receipt sentinel\n' > "$poison_fixture/state/receipt"
printf '#!/bin/sh\nprintf "binary:%s\\n" "$0" >> "$ACFS_POISON_MARKER"\nexit 97\n' \
    > "$poison_fixture/bin/poison"
chmod 0755 "$poison_fixture/bin/poison"
for poison_name in br bv am cass cm ntm curl git jq tmux systemctl ss lsof; do
    ln -s poison "$poison_fixture/bin/$poison_name"
done
ln -s "$poison_fixture/bin/poison" "$poison_fixture/home/.local/bin/br"
ln -s "$poison_fixture/bin/poison" "$poison_fixture/home/.local/bin/bv"

poison_fixture_snapshot() {
    local path=""
    while IFS= read -r path; do
        if [[ -L "$path" ]]; then
            printf 'L|%s|%s\n' "${path#"$poison_fixture"/}" "$(/usr/bin/readlink "$path")"
        elif [[ -f "$path" ]]; then
            printf 'F|%s|' "${path#"$poison_fixture"/}"
            /usr/bin/shasum -a 256 "$path" | /usr/bin/awk '{print $1}'
        elif [[ -d "$path" ]]; then
            printf 'D|%s\n' "${path#"$poison_fixture"/}"
        fi
    done < <(/usr/bin/find "$poison_fixture" -print | LC_ALL=C /usr/bin/sort)
}

poison_before="$(poison_fixture_snapshot)"
(
    ACFS_POISON_MARKER="$poison_marker"
    export ACFS_POISON_MARKER
    PATH="$poison_fixture/bin:/usr/bin:/bin"
    HOME="$poison_fixture/home"
    export PATH HOME

    poison_callback() {
        builtin printf '%s\n' "$*" >> "$ACFS_POISON_MARKER"
        return 97
    }
    for callback_name in \
        command type stat readlink sha256sum shasum cat curl wget git jq tmux systemctl ss lsof ps pgrep kill sleep \
        mktemp mkdir mv ln rm chmod chown cp tar gzip \
        acfs_module_is_installed acfs_generated_ensure_selection should_run_module acfs_security_init \
        fetch_checksum get_checksum verify_checksum fetch_and_run fetch_and_run_with_runner \
        acfs_download_to_file acfs_stage_verified_installer acfs_fetch_url_content \
        binary_path binary_installed get_tool_version prepare_target_context augment_path_for_target_user \
        state_get_file state_init state_write_atomic state_load state_set_resume_hint state_mark_interrupted \
        progress_init progress_start progress_update progress_complete progress_count_modules \
        run_as_target run_as_target_shell run_as_root_shell run_as_current_shell run_as_target_runner \
        install_mcp_agent_mail install_beads_rust install_bv install_meta_skill install_skills \
        _initialize_bins _session_exists _port_is_listening _agent_mail_is_healthy \
        _native_agent_mail_unit_available _native_agent_mail_is_active _require_tmux \
        print_fix_summary end_autofix_session print_undo_summary report_success webhook_notify acfs_summary_emit; do
        eval "$callback_name() { poison_callback '$callback_name'; }"
    done
    shopt -s expand_aliases
    alias br='poison_callback alias-br'
    alias bv='poison_callback alias-bv'
    alias am='poison_callback alias-am'

    matrix_rc=0
    : > "$matrix_failures"
    for lifecycle in "${moduleless_entries[@]}"; do
        if acfs_r1_runtime_admit_entry "$lifecycle" >/dev/null 2>&1; then
            builtin printf 'moduleless:%s\n' "$lifecycle" >> "$matrix_failures"
            matrix_rc=1
        elif [[ "${ACFS_R1_POLICY_REASON:-}" != *"LIC1+LIC2 HOLD"* ]]; then
            builtin printf 'moduleless-nonlicense:%s:%s\n' "$lifecycle" \
                "${ACFS_R1_POLICY_REASON:-missing}" >> "$matrix_failures"
            matrix_rc=1
        fi
    done
    for module_id in "${license_held_modules[@]}"; do
        for lifecycle in direct probe install update doctor doctor-fix repair service configuration helper list; do
            if acfs_r1_runtime_admit_entry "$lifecycle" "$module_id" >/dev/null 2>&1; then
                builtin printf '%s:%s\n' "$module_id" "$lifecycle" >> "$matrix_failures"
                matrix_rc=1
            elif [[ "${ACFS_R1_POLICY_REASON:-}" != *"LIC1+LIC2 HOLD"* ]]; then
                builtin printf '%s:%s:nonlicense:%s\n' "$module_id" "$lifecycle" \
                    "${ACFS_R1_POLICY_REASON:-missing}" >> "$matrix_failures"
                matrix_rc=1
            fi
        done
    done
    [[ ! -e "$poison_marker" ]] || matrix_rc=1
    exit "$matrix_rc"
)
matrix_rc=$?
poison_after="$(poison_fixture_snapshot)"
matrix_failure_text="$(/bin/cat "$matrix_failures" 2>/dev/null || true)"
if [[ $matrix_rc -eq 0 && ${#license_held_modules[@]} -eq 27 \
    && ! -e "$poison_marker" && "$poison_before" == "$poison_after" ]]; then
    pass "all moduleless and 27x11 held lifecycle gates reject before poisoned callbacks or fixture mutation"
else
    fail "all moduleless and 27x11 held lifecycle gates reject before poisoned callbacks or fixture mutation" \
        "rc=$matrix_rc poison=$([[ -e "$poison_marker" ]] && printf yes || printf no) failures=$matrix_failure_text"
fi

ACFS_R1_PLAN_VALIDATED=false
expect_failure "direct entry needs an exact validated plan" \
    acfs_r1_runtime_admit_entry direct base.system
ACFS_R1_PLAN_VALIDATED=true
expect_failure "inherited plan-valid marker cannot authorize direct entry" \
    acfs_r1_runtime_admit_entry direct base.system
expect_success "license policy records PFR as plain-MIT-only" \
    acfs_license_policy_admit_entry direct stack.power_failure_resumer
expect_failure "PFR remains rejected by its prior qualification HOLD" \
    acfs_r1_runtime_admit_entry direct stack.power_failure_resumer

if acfs_core_policy_enforce stack.mcp_agent_mail doctor ""; then
    fail "Agent Mail remains on hard C5 HOLD" "core policy unexpectedly admitted it"
elif [[ "$ACFS_CORE_POLICY_REASON" == *"no future independently accepted exact C5 capsule identity exists"* ]]; then
    pass "Agent Mail remains on hard C5 HOLD"
else
    fail "Agent Mail remains on hard C5 HOLD" "$ACFS_CORE_POLICY_REASON"
fi

fake_home="$TMP_ROOT/home"
marker="$TMP_ROOT/arbitrary-binary-executed"
mkdir -p "$fake_home/.local/bin" "$fake_home/.local/lib/acfs/bv/v0.22.0"
cat > "$fake_home/.local/bin/br" <<EOF
#!/usr/bin/env bash
touch "$marker"
printf 'br v0.5.3\n'
EOF
cat > "$fake_home/.local/lib/acfs/bv/v0.22.0/bv" <<EOF
#!/usr/bin/env bash
touch "$marker"
printf 'bv v0.22.0\n'
EOF
chmod 0755 "$fake_home/.local/bin/br" "$fake_home/.local/lib/acfs/bv/v0.22.0/bv"
ln -s "$fake_home/.local/lib/acfs/bv/v0.22.0/bv" "$fake_home/.local/bin/bv"
TARGET_HOME="$fake_home"

expect_failure "held br contract accessor returns no identity" \
    acfs_core_policy_contract stack.beads_rust
expect_failure "held bv contract accessor returns no identity" \
    acfs_core_policy_contract stack.beads_viewer
expect_failure "version-printing arbitrary br bytes are rejected before inspection" \
    acfs_core_policy_admit_binary stack.beads_rust doctor "untrusted" "$fake_home/.local/bin/br"
expect_failure "version-printing arbitrary bv bytes are rejected before inspection" \
    acfs_core_policy_admit_binary stack.beads_viewer doctor "untrusted" "$fake_home/.local/bin/bv"
if [[ -e "$marker" ]]; then
    fail "license-held core binaries are never executed" "arbitrary binary executed"
else
    pass "license-held core binaries are never executed"
fi

if rg -q -F 'source_commit=7eaf34b76927b4deadc913889f50fb06a8f803d7' "$REPO_ROOT/scripts/lib/contract.sh" \
    && rg -q -F 'installer_sha256=b2b3ed0ae2712e53a72d48afd5a980a7c1d346bb6e6b9fb9e4f3b20566726c2f' "$REPO_ROOT/scripts/lib/contract.sh" \
    && rg -q -F 'artifact_sha256=9781aec596be155dfff31c0ab4d140d076107422e0e703c5137b2d2edcff4bfb' "$REPO_ROOT/scripts/lib/contract.sh" \
    && rg -q -F 'binary_sha256=f7d105e685da6c49dd87b0335d11d5fe2aa8765033a78cfbfb00dee7a4b1e123' "$REPO_ROOT/scripts/lib/contract.sh" \
    && rg -q -F 'source_commit=95a706caf57fc5fde846a453da5f28677d4a81b8' "$REPO_ROOT/scripts/lib/contract.sh" \
    && rg -q -F 'archive_sha256=23d451b87bb9dccfb94fab416b0243d107919d9d56458087475afda5a617aa89' "$REPO_ROOT/scripts/lib/contract.sh" \
    && rg -q -F 'binary_sha256=ee1dd03701a33d86e6496fb7021a96461e3c172e2a8be5b2ced554c7c378b320' "$REPO_ROOT/scripts/lib/contract.sh" \
    && rg -q -F 'selected_member=bv' "$REPO_ROOT/scripts/lib/contract.sh" \
    && rg -q -F '/.local/lib/acfs/bv/v0.22.0/bv' "$REPO_ROOT/scripts/lib/contract.sh"; then
    pass "held br/bv exact identity and canonical-symlink contracts remain frozen"
else
    fail "held br/bv exact identity and canonical-symlink contracts remain frozen"
fi

helpers_rebind_def="$(sed -n '/^_acfs_install_helpers_rebind_canonical_contract()/,/^}$/p' "$REPO_ROOT/scripts/lib/install_helpers.sh")"
helpers_admit_def="$(sed -n '/^_acfs_install_helpers_admit()/,/^}$/p' "$REPO_ROOT/scripts/lib/install_helpers.sh")"
module_probe_def="$(sed -n '/^acfs_module_is_installed()/,/^}$/p' "$REPO_ROOT/scripts/lib/install_helpers.sh")"
source_index_def="$(sed -n '/^source_manifest_index()/,/^}$/p' "$REPO_ROOT/scripts/lib/install_helpers.sh")"
helper_marker="$TMP_ROOT/direct-helper-inspected-held-module"
fake_generated="$TMP_ROOT/fake-generated"
mkdir -p "$fake_generated"
printf 'touch %q\n' "$helper_marker" > "$fake_generated/manifest_index.sh"
if (
    eval "$helpers_rebind_def"
    eval "$helpers_admit_def"
    eval "$module_probe_def"
    eval "$source_index_def"
    acfs_r1_runtime_admit_entry() { return 0; }
    INSTALL_HELPERS_DIR="$REPO_ROOT/scripts/lib"
    ACFS_GENERATED_DIR="$fake_generated"
    ACFS_MANIFEST_INDEX_LOADED=false
    acfs_module_is_installed stack.beads_rust || true
    source_manifest_index
); then
    fail "direct helper/index paths remain held against preloaded policy" \
        "fake manifest index was unexpectedly admitted"
elif [[ -e "$helper_marker" ]]; then
    fail "direct helper/index paths remain held against preloaded policy" \
        "fake held-module metadata executed"
else
    pass "direct helper/index paths remain held against preloaded policy"
fi

early_gate_def="$(sed -n '/^acfs_enforce_early_license_exclusion()/,/^}$/p' "$REPO_ROOT/install.sh")"
upstream_load_def="$(sed -n '/^acfs_load_upstream_checksums()/,/^}$/p' "$REPO_ROOT/install.sh")"
if (
    eval "$early_gate_def"
    eval "$upstream_load_def"
    acfs_r1_runtime_admit_entry() { return 0; }
    SCRIPT_DIR="$REPO_ROOT"
    ACFS_UPSTREAM_LOADED=true
    acfs_load_upstream_checksums
); then
    fail "direct checksum helper rejects a preloaded policy and loaded-marker bypass" \
        "preloaded admission function unexpectedly bypassed the canonical contract"
else
    pass "direct checksum helper rejects a preloaded policy and loaded-marker bypass"
fi

readonly_security_output="$(
    /usr/bin/env ACFS_BLUE=test /bin/bash -c '
        _acfs_security_admit_module_operation() { return 0; }
        readonly -f _acfs_security_admit_module_operation
        source "$1"
    ' _ "$REPO_ROOT/scripts/lib/security.sh" 2>&1
)"
readonly_security_rc=$?
if [[ $readonly_security_rc -ne 0 \
    && "$readonly_security_output" == *"imported ACFS security policy helper is not replaceable"* ]]; then
    pass "readonly security helper cannot shadow direct checksum HOLD"
else
    fail "readonly security helper cannot shadow direct checksum HOLD" \
        "rc=$readonly_security_rc output=$readonly_security_output"
fi

service_output="$(
    /usr/bin/env ACFS_BLUE=test /bin/bash -c '
        acfs_core_policy_enforce() { return 0; }
        source "$1" --source-test cmd_status
    ' _ "$REPO_ROOT/scripts/lib/acfs-services.sh" 2>&1
)"
service_rc=$?
if [[ $service_rc -ne 0 && "$service_output" == *"no future independently accepted exact C5 capsule identity exists"* ]]; then
    pass "ambient Agent Mail policy function cannot shadow service HOLD"
else
    fail "ambient Agent Mail policy function cannot shadow service HOLD" "rc=$service_rc output=$service_output"
fi

readonly_service_output="$(
    /usr/bin/env ACFS_BLUE=test /bin/bash -c '
        acfs_core_policy_enforce() { return 0; }
        readonly -f acfs_core_policy_enforce
        source "$1" --source-test cmd_status
    ' _ "$REPO_ROOT/scripts/lib/acfs-services.sh" 2>&1
)"
readonly_service_rc=$?
if [[ $readonly_service_rc -ne 0 \
    && "$readonly_service_output" == *"Refusing a readonly or imported ACFS policy function"* ]]; then
    pass "readonly Agent Mail policy function forces service rejection"
else
    fail "readonly Agent Mail policy function forces service rejection" \
        "rc=$readonly_service_rc output=$readonly_service_output"
fi

aggregate_def="$(sed -n '/^install_all_stack()/,/^}$/p' "$REPO_ROOT/scripts/lib/stack.sh")"
if (
    eval "$aggregate_def"
    _stack_rebind_canonical_contract() { return 0; }
    acfs_r1_runtime_admit_entry() { return 0; }
    log_step() { :; }
    log_error() { :; }
    log_success() { :; }
    install_mcp_agent_mail() { return 1; }
    install_beads_rust() { return 1; }
    install_bv() { return 1; }
    verify_stack() { return 1; }
    install_all_stack
); then
    fail "direct stack aggregate propagates child failures" "aggregate returned success"
else
    pass "direct stack aggregate propagates child failures"
fi

supplemental_def="$(sed -n '/^check_manifest_supplemental()/,/^}$/p' "$REPO_ROOT/scripts/lib/doctor.sh")"
if (
    eval "$supplemental_def"
    check() { [[ "$3" == "fail" ]]; }
    MANIFEST_CHECKS_LOADED=false
    MANIFEST_CHECKS_LOAD_ERROR="missing fixture"
    unset MANIFEST_CHECKS
    check_manifest_supplemental
); then
    fail "doctor rejects missing generated checks" "supplemental check returned success"
else
    pass "doctor rejects missing generated checks"
fi
if (
    eval "$supplemental_def"
    check() { [[ "$3" == "fail" ]]; }
    MANIFEST_CHECKS_LOADED=true
    MANIFEST_CHECKS_LOAD_ERROR="empty fixture"
    MANIFEST_CHECKS=()
    check_manifest_supplemental
); then
    fail "doctor rejects empty generated checks" "supplemental check returned success"
else
    pass "doctor rejects empty generated checks"
fi

read_only_def="$(sed -n '/^acfs_is_read_only_mode()/,/^}$/p' "$REPO_ROOT/install.sh")"
cleanup_def="$(sed -n '/^cleanup()/,/^}$/p' "$REPO_ROOT/install.sh")"
state_file="$TMP_ROOT/state.json"
printf '{"sentinel":"unchanged"}\n' > "$state_file"
state_before="$(/usr/bin/shasum -a 256 "$state_file" | /usr/bin/awk '{print $1}')"
state_writer_calls=0
eval "$read_only_def"
eval "$cleanup_def"
acfs_enforce_early_license_exclusion() { return 1; }
acfs_bootstrap_dir_is_owned_temp() { return 1; }
acfs_file_is_owned_temp() { return 1; }
acfs_release_install_lock() { :; }
acfs_log_close() { :; }
log_warn() { :; }
log_error() { :; }
print_resume_hint() { :; }
state_mark_interrupted() {
    state_writer_calls=$((state_writer_calls + 1))
    printf 'mutated\n' >> "$state_file"
}
BOOTSTRAP_ARCHIVE_FD=""
ACFS_BOOTSTRAP_DIR=""
ACFS_BOOTSTRAP_SUPERVISOR=true
ACFS_TMP_ARCHIVE=""
ACFS_TMP_INSTALL=""
ACFS_INSTALL_RUN_CONFIRMED=0
ACFS_SKILLS_AND_SUMMARY_DONE=0
ACFS_MODULE_FAILURES=()
ACFS_STATE_FILE="$state_file"
_ACFS_SIGNAL_RECEIVED=TERM

for read_only_flag in DRY_RUN PRINT_MODE LIST_MODULES PRINT_PLAN_MODE; do
    DRY_RUN=false
    PRINT_MODE=false
    LIST_MODULES=false
    PRINT_PLAN_MODE=false
    eval "$read_only_flag=true"
    false
    cleanup
done
state_after="$(/usr/bin/shasum -a 256 "$state_file" | /usr/bin/awk '{print $1}')"
if [[ $state_writer_calls -eq 0 && "$state_before" == "$state_after" ]]; then
    pass "simulated signal cleanup preserves read-only state bytes"
else
    fail "simulated signal cleanup preserves read-only state bytes" \
        "writer_calls=$state_writer_calls before=$state_before after=$state_after"
fi

print_hint_def="$(sed -n '/^print_resume_hint()/,/^}$/p' "$REPO_ROOT/install.sh")"
eval "$print_hint_def"
generate_resume_hint() { return 1; }
state_set_resume_hint() {
    state_writer_calls=$((state_writer_calls + 1))
    printf 'mutated\n' >> "$state_file"
}
log_info() { :; }
log_detail() { :; }
SCRIPT_DIR="$REPO_ROOT"
ACFS_VERIFIED_BOOTSTRAP_SOURCE=""
state_writer_calls=0
for read_only_flag in DRY_RUN PRINT_MODE LIST_MODULES PRINT_PLAN_MODE; do
    DRY_RUN=false
    PRINT_MODE=false
    LIST_MODULES=false
    PRINT_PLAN_MODE=false
    eval "$read_only_flag=true"
    print_resume_hint "stack" "fixture"
done
state_after="$(/usr/bin/shasum -a 256 "$state_file" | /usr/bin/awk '{print $1}')"
if [[ $state_writer_calls -eq 0 && "$state_before" == "$state_after" ]]; then
    pass "failure hints preserve read-only state bytes"
else
    fail "failure hints preserve read-only state bytes" \
        "writer_calls=$state_writer_calls before=$state_before after=$state_after"
fi

if node - "$REPO_ROOT/scripts/generated/manifest_index.sh" "$REPO_ROOT/scripts/generated/install_stack.sh" <<'NODE'
const fs = require('node:fs');
const [indexPath, stackPath] = process.argv.slice(2);
const index = fs.readFileSync(indexPath, 'utf8');
const stack = fs.readFileSync(stackPath, 'utf8');

function arrayBlock(name) {
  const match = index.match(new RegExp(`${name}=\\(\\n([\\s\\S]*?)\\n\\)`));
  if (!match) throw new Error(`missing ${name}`);
  return match[1];
}
function assoc(name) {
  const values = new Map();
  for (const match of arrayBlock(name).matchAll(/^  \['([^']+)'\]="([^"]*)"$/gm)) {
    values.set(match[1], match[2]);
  }
  return values;
}

const order = [...arrayBlock('ACFS_MODULES_IN_ORDER').matchAll(/^  "([^"]+)"$/gm)].map((m) => m[1]);
const deps = assoc('declare -gA ACFS_MODULE_DEPS');
const phases = assoc('declare -gA ACFS_MODULE_PHASE');
const seeds = ['users.ubuntu', 'base.filesystem', 'cli.modern', 'stack.mcp_agent_mail', 'stack.beads_rust', 'stack.beads_viewer'];
const expected = ['base.system', 'users.ubuntu', 'base.filesystem', 'cli.modern', 'lang.bun', 'lang.uv', 'lang.rust', 'lang.go', 'stack.mcp_agent_mail', 'stack.beads_rust', 'stack.beads_viewer'];
const closure = new Set();
function add(id) {
  if (closure.has(id)) return;
  for (const dep of (deps.get(id) || '').split(',').filter(Boolean)) add(dep);
  closure.add(id);
}
seeds.forEach(add);
const resolved = order.filter((id) => closure.has(id));
if (JSON.stringify(resolved) !== JSON.stringify(expected)) {
  throw new Error(`R1 graph mismatch: ${resolved.join(',')}`);
}
const expectedPhases = new Map([
  ['base.system', '1'], ['users.ubuntu', '2'], ['base.filesystem', '3'], ['cli.modern', '5'],
  ['lang.bun', '6'], ['lang.uv', '6'], ['lang.rust', '6'], ['lang.go', '6'],
  ['stack.mcp_agent_mail', '9'], ['stack.beads_rust', '9'], ['stack.beads_viewer', '9'],
]);
for (const [id, phase] of expectedPhases) {
  if (phases.get(id) !== phase) throw new Error(`phase mismatch: ${id}`);
}

const held = [
  'stack.beads_rust', 'stack.agent_settings_backup', 'stack.caam',
  'stack.cross_agent_session_resumer', 'stack.pcr', 'stack.automated_plan_reviser',
  'stack.brenner_bot', 'stack.eidetic_engine_cli', 'stack.frankensearch',
  'stack.jeffreysprompts', 'stack.meta_skill', 'stack.pi_agent_rust',
  'stack.process_triage', 'stack.rch', 'stack.ru',
  'stack.doodlestein_self_releaser', 'stack.franken_markdown', 'stack.slb',
  'stack.srps', 'stack.storage_ballast_helper', 'stack.mcp_agent_mail',
  'stack.beads_viewer', 'stack.ultimate_bug_scanner', 'stack.dcg',
  'stack.cass', 'stack.cm', 'stack.ntm',
];
for (const id of held) {
  const fn = `acfs_generated_install_${id.replaceAll('.', '_')}`;
  const start = stack.indexOf(`${fn}() {`);
  if (start < 0) throw new Error(`missing held function: ${id}`);
  const prefix = stack.slice(start, start + 4000);
  const gate = prefix.indexOf('acfs_r1_runtime_admit_entry direct "${module_id}"');
  const contract = prefix.indexOf('acfs_require_contract "module:${module_id}"');
  if (gate < 0 || contract < 0 || gate > contract) {
    throw new Error(`held direct gate ordering mismatch: ${id}`);
  }
}
NODE
then
    pass "exact 11-module graph and every held generated direct gate remain closed"
else
    fail "exact 11-module graph and every held generated direct gate remain closed"
fi

if node - \
    "$REPO_ROOT/install.sh" \
    "$REPO_ROOT/scripts/lib/contract.sh" \
    "$REPO_ROOT/scripts/lib/security.sh" \
    "$REPO_ROOT/scripts/lib/install_helpers.sh" \
    "$REPO_ROOT/scripts/lib/progress.sh" \
    "$REPO_ROOT/scripts/lib/module_selector.sh" \
    "$REPO_ROOT/scripts/lib/export-config.sh" \
    "$REPO_ROOT/scripts/lib/state.sh" <<'NODE'
const fs = require('node:fs');
const [installPath, contractPath, securityPath, helpersPath, progressPath, selectorPath, exportPath, statePath] = process.argv.slice(2);
const files = Object.fromEntries([
  ['install', installPath], ['contract', contractPath], ['security', securityPath],
  ['helpers', helpersPath], ['progress', progressPath],
  ['selector', selectorPath], ['export', exportPath], ['state', statePath],
].map(([name, path]) => [name, fs.readFileSync(path, 'utf8')]));

function functionBlock(text, name) {
  const needle = `${name}() {`;
  const lineStart = text.indexOf(`\n${needle}`);
  const start = text.startsWith(needle) ? 0 : (lineStart < 0 ? -1 : lineStart + 1);
  if (start < 0) throw new Error(`missing function ${name}`);
  const rest = text.slice(start);
  const end = rest.search(/^}$/m);
  if (end < 0) throw new Error(`unterminated function ${name}`);
  return rest.slice(0, end + 1);
}

function assertBefore(text, earlier, later, label) {
  const a = text.indexOf(earlier);
  const b = text.indexOf(later);
  if (a < 0 || b < 0 || a >= b) {
    throw new Error(`${label}: ${earlier} must precede ${later}`);
  }
}

const main = functionBlock(files.install, 'main');
assertBefore(main, 'acfs_enforce_early_license_exclusion', 'acfs_normalize_verified_installer_cache_configuration', 'main pre-bootstrap gate');
assertBefore(main, 'acfs_enforce_early_license_exclusion', 'bootstrap_repo_archive', 'main pre-download gate');
const detect = functionBlock(files.install, 'detect_environment');
assertBefore(detect, 'acfs_r1_runtime_admit_entry', 'acfs_verify_internal_checksums_data', 'environment pre-ledger gate');

const admission = functionBlock(files.contract, 'acfs_r1_runtime_admit_entry');
assertBefore(admission, 'acfs_r1_runtime_verify_profile', 'acfs_license_policy_admit_entry', 'R1 identity-before-license gate');

for (const [name, marker] of [
  ['acfs_fetch_url_content', 'local url='],
  ['acfs_fetch_fresh_checksums_via_api', 'local api_url='],
  ['acfs_parse_checksums_content', 'local content='],
  ['acfs_required_upstream_tools', "printf '%s\\n'"],
  ['acfs_validate_upstream_checksums', 'ACFS_UPSTREAM_URLS'],
  ['acfs_load_upstream_checksums', 'ACFS_UPSTREAM_LOADED'],
  ['acfs_run_verified_upstream_script_as_target_with_env', 'acfs_load_upstream_checksums'],
  ['acfs_run_verified_upstream_script_as_target', 'local tool='],
  ['binary_path', 'local name='],
  ['binary_installed', 'binary_path'],
  ['_smoke_target_path', 'TARGET_HOME'],
  ['_smoke_run_as_target', 'local cmd='],
  ['acfs_smoke_install_fix_command', 'install_url='],
  ['run_smoke_test', 'critical_total='],
]) {
  assertBefore(functionBlock(files.install, name), 'acfs_enforce_early_license_exclusion', marker, `install direct ${name} gate`);
}

for (const [name, marker] of [
  ['acfs_download_to_file', 'local url='],
  ['acfs_installer_cache_snapshot_regular_file', 'local source_file='],
  ['acfs_installer_cache_verify_bound_file', 'local pack_root='],
  ['acfs_offline_pack_current_manifest_file', 'ACFS_MANIFEST_YAML'],
  ['acfs_offline_pack_locate', 'ACFS_VERIFIED_INSTALLER_CACHE'],
  ['acfs_offline_pack_validate_manifest', 'local pack_root='],
  ['acfs_offline_pack_verify_artifact', 'local url='],
  ['_acfs_offline_pack_verify_artifact_snapshot', 'local pack_root='],
  ['fetch_checksum', 'local url='],
  ['verify_checksum', 'local url='],
  ['acfs_stage_verified_installer', 'local staging_output_name='],
  ['fetch_and_run_with_runner', 'if [[ $# -lt 4 ]]'],
  ['fetch_and_run', 'local url='],
  ['fetch_and_run_with_recovery', 'local url='],
  ['print_upstream_urls', 'KNOWN_INSTALLERS'],
  ['print_current_checksums', 'KNOWN_INSTALLERS'],
  ['acfs_load_checksums_strict', 'local file='],
  ['load_checksums', 'CHECKSUMS_FILE'],
  ['get_checksum', 'LOADED_CHECKSUMS'],
  ['acfs_checksums_file_looks_valid', 'local file='],
  ['acfs_fetch_fresh_checksums_to_file', 'local dest='],
  ['acfs_refresh_loaded_checksums_from_remote', 'ACFS_CHECKSUMS_REMOTE_REFRESHED'],
  ['handle_all_checksum_mismatches', 'has_checksum_mismatches'],
  ['_handle_mismatches_noninteractive', 'CHECKSUM_MISMATCHES'],
  ['handle_checksum_mismatch', 'local tool='],
  ['check_installer_checksum', 'KNOWN_INSTALLERS'],
  ['verify_all_installers', 'KNOWN_INSTALLERS'],
  ['verify_all_installers_json', 'local checksums_digest='],
  ['acfs_validate_installer_checksum_report', 'local report_file='],
  ['acfs_verify_all_installers_json_from_file', 'local checksums_file='],
  ['acfs_validate_checksum_candidate', 'local current_file='],
]) {
  assertBefore(functionBlock(files.security, name), '_acfs_security_admit_module_operation', marker, `security direct ${name} gate`);
}
const securityMain = functionBlock(files.security, 'main');
assertBefore(securityMain, '_acfs_security_admit_module_operation', 'Parse --json flag', 'security command gate');

const sourceIndex = functionBlock(files.helpers, 'source_manifest_index');
assertBefore(sourceIndex, '_acfs_install_helpers_admit list', 'source "$index_path"', 'manifest-index gate');
const installed = functionBlock(files.helpers, 'acfs_module_is_installed');
assertBefore(installed, '_acfs_install_helpers_admit probe "$module_id"', 'ACFS_MODULE_INSTALLED_CHECK', 'installed-check gate');
const category = functionBlock(files.helpers, 'acfs_run_generated_category_phase');
assertBefore(category, '_acfs_install_helpers_admit helper', 'ACFS_EFFECTIVE_PLAN', 'generated-helper gate');

const progress = functionBlock(files.progress, 'progress_count_modules');
assertBefore(progress, '_progress_admit_module_metadata', 'ACFS_EFFECTIVE_PLAN', 'progress metadata gate');
const review = functionBlock(files.selector, 'acfs_render_selection_review');
assertBefore(review, '_acfs_install_helpers_admit list', 'ACFS_MODULES_IN_ORDER', 'selector list gate');
const exportMain = functionBlock(files.export, 'export_config_main');
assertBefore(exportMain, 'export_config_license_admit configuration', 'prepare_target_context', 'export configuration gate');
const toolVersion = functionBlock(files.export, 'get_tool_version');
assertBefore(toolVersion, 'export_config_license_admit probe', 'case "$tool"', 'export probe gate');

const stateInit = functionBlock(files.state, 'state_init');
assertBefore(stateInit, '_state_license_admit install', 'state_get_file', 'state init gate');
const stateWrite = functionBlock(files.state, 'state_write_atomic');
assertBefore(stateWrite, '_state_license_admit configuration', 'local file_path', 'state write gate');
const stateLoad = functionBlock(files.state, 'state_load');
assertBefore(stateLoad, '_state_license_admit resume', 'state_get_file', 'state load gate');
const stateSelection = functionBlock(files.state, 'state_selection_includes_phase');
assertBefore(stateSelection, '_state_license_admit helper', 'ACFS_EFFECTIVE_PLAN', 'state selection gate');
NODE
then
    pass "R1/license admission precedes every manifest/checksum/helper/probe/config/state surface"
else
    fail "R1/license admission precedes every manifest/checksum/helper/probe/config/state surface"
fi

provisional_lic2_sha='f826916338fee61849525bbbe3225844e7f3e1af5c08c3e17dd714ce643''22583'
if ! rg -q -F "$provisional_lic2_sha" \
    "$REPO_ROOT/install.sh" "$REPO_ROOT/scripts" "$REPO_ROOT/tests"; then
    pass "provisional LIC2 digest is absent from executable and test surfaces"
else
    fail "provisional LIC2 digest is absent from executable and test surfaces"
fi

mutable_branch_pattern='mcp_agent_mail/'"(main|master)"
cache_bust_pattern='mcp_agent_mail.*[$][(]date'
mutable_alias_pattern='alias[[:space:]]+am=.*run_server_with_token'
operator_surfaces=()
for operator_surface in \
    "$REPO_ROOT/docs" \
    "$REPO_ROOT/acfs" \
    "$REPO_ROOT/apps/web" \
    "$REPO_ROOT/.github" \
    "$REPO_ROOT/README.md" \
    "$REPO_ROOT/install.sh" \
    "$REPO_ROOT/acfs.manifest.yaml"; do
    [[ -e "$operator_surface" ]] && operator_surfaces+=("$operator_surface")
done
instruction_scan_output="$(
    rg -n \
        -e "$mutable_branch_pattern" \
        -e "$cache_bust_pattern" \
        -e "$mutable_alias_pattern" \
        "${operator_surfaces[@]}" 2>/dev/null
)"
instruction_scan_rc=$?
if [[ $instruction_scan_rc -eq 1 && -z "$instruction_scan_output" ]]; then
    pass "operator-facing surfaces contain no mutable Agent Mail instruction"
elif [[ $instruction_scan_rc -eq 0 ]]; then
    fail "operator-facing surfaces contain no mutable Agent Mail instruction" "$instruction_scan_output"
else
    fail "operator-facing surfaces contain no mutable Agent Mail instruction" \
        "repository-wide instruction scan could not run (rc=$instruction_scan_rc)"
fi

printf '\nR1 commissioning admission: %d passed, %d failed\n' "$passed" "$failed"
[[ $failed -eq 0 ]]
