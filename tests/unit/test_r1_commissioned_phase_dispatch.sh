#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"

node - "$REPO_ROOT/install.sh" \
    "$REPO_ROOT/scripts/generated/manifest_index.sh" \
    "$REPO_ROOT/scripts/lib/contract.sh" <<'NODE'
const fs = require('node:fs');

const [installPath, indexPath, contractPath] = process.argv.slice(2);
const install = fs.readFileSync(installPath, 'utf8');
const index = fs.readFileSync(indexPath, 'utf8');
const contract = fs.readFileSync(contractPath, 'utf8');

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function functionBlock(source, name) {
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = source.match(new RegExp(`^${escaped}\\(\\) \\{\\n([\\s\\S]*?)^\\}`, 'm'));
  assert(match, `missing ${name}() source block`);
  return match[1];
}

function associativeArray(source, declaration) {
  const escaped = declaration.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = source.match(new RegExp(`^${escaped}=\\(\\n([\\s\\S]*?)^\\)`, 'm'));
  assert(match, `missing ${declaration}`);

  const values = new Map();
  for (const entry of match[1].matchAll(/^  \['([^']+)'\]="([^"]*)"$/gm)) {
    values.set(entry[1], entry[2]);
  }
  return values;
}

function scalar(source, name) {
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = source.match(new RegExp(`^${escaped}="([^"]*)"$`, 'm'));
  assert(match, `missing ${name}`);
  return match[1];
}

const main = functionBlock(install, 'main');
const agentsPhase = functionBlock(install, 'install_agents_phase');
const phaseCalls = [...main.matchAll(
  /^\s*_run_phase_with_report "([^"]+)" "(\d+)\/(\d+) ([^"]+)" ([a-zA-Z0-9_]+) \|\| true$/gm,
)].map((match) => ({
  id: match[1],
  current: Number(match[2]),
  total: Number(match[3]),
  label: match[4],
  fn: match[5],
  offset: match.index,
}));

const expectedDispatch = [
  ['user_setup', 'normalize_user'],
  ['filesystem', 'setup_filesystem'],
  ['cli_tools', 'install_cli_tools'],
  ['languages', 'install_languages'],
  ['agents', 'install_agents_phase'],
  ['stack', 'install_stack_phase'],
];

assert(
  phaseCalls.length === expectedDispatch.length,
  `expected ${expectedDispatch.length} R1 phase calls, found ${phaseCalls.length}`,
);
for (const [position, phase] of phaseCalls.entries()) {
  const [expectedId, expectedFunction] = expectedDispatch[position];
  assert(
    phase.id === expectedId && phase.fn === expectedFunction,
    `phase ${position + 1} must dispatch ${expectedId} via ${expectedFunction}; found ${phase.id} via ${phase.fn}`,
  );
  assert(phase.current === position + 1, `phase ${phase.id} has progress numerator ${phase.current}`);
  assert(
    phase.total === phaseCalls.length,
    `phase ${phase.id} reports total ${phase.total}; loop contains ${phaseCalls.length} phases`,
  );
  assert(phase.label.trim().length > 0, `phase ${phase.id} has an empty progress label`);
}

const agentsDispatch = phaseCalls.find((phase) => phase.id === 'agents');
const stackDispatch = phaseCalls.find((phase) => phase.id === 'stack');
assert(agentsDispatch.offset < stackDispatch.offset, 'agents phase must run before stack/PCR');

assert(
  /acfs_run_generated_category_phase\s+"agents"\s+"7"/.test(agentsPhase),
  'install_agents_phase must dispatch generated agents phase 7',
);

const phases = associativeArray(index, 'declare -gA ACFS_MODULE_PHASE');
const categories = associativeArray(index, 'declare -gA ACFS_MODULE_CATEGORY');
const dependencies = associativeArray(index, 'declare -gA ACFS_MODULE_DEPS');
assert(phases.get('agents.claude') === '7', 'agents.claude must remain in manifest phase 7');
assert(categories.get('agents.claude') === 'agents', 'agents.claude must remain in the agents category');
assert(phases.get('stack.pcr') === '9', 'stack.pcr must remain in manifest phase 9');
assert(
  (dependencies.get('stack.pcr') || '').split(',').includes('agents.claude'),
  'stack.pcr must retain its agents.claude dependency',
);

const commissionedPlan = scalar(contract, 'ACFS_W3_COMMISSIONING_PLAN_CSV').split(',');
const claudePosition = commissionedPlan.indexOf('agents.claude');
const pcrPosition = commissionedPlan.indexOf('stack.pcr');
assert(claudePosition >= 0, 'commissioned plan must contain agents.claude');
assert(pcrPosition >= 0, 'commissioned plan must contain stack.pcr');
assert(claudePosition < pcrPosition, 'commissioned plan must order agents.claude before stack.pcr');

const helperStart = main.indexOf('_run_phase_with_report() {');
const firstDispatch = phaseCalls[0].offset;
assert(helperStart >= 0 && helperStart < firstDispatch, 'missing R1 phase-report helper');
const helper = main.slice(helperStart, firstDispatch);

function assertReporterTotal(callName) {
  const escaped = callName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = helper.match(new RegExp(`${escaped}\\s+"\\$phase_num"\\s+(?:"\\$phase_total"|(\\d+))`));
  assert(match, `${callName} must receive the R1 phase total after phase_num`);
  if (match[1]) {
    assert(
      Number(match[1]) === phaseCalls.length,
      `${callName} reports total ${match[1]}; loop contains ${phaseCalls.length} phases`,
    );
  } else {
    assert(
      /local phase_total=.*phase_display/.test(helper),
      `${callName} uses phase_total without deriving it from phase_display`,
    );
  }
}

assertReporterTotal('show_progress_header');
assertReporterTotal('report_failure');

console.log('R1 commissioned phase dispatch: PASS');
NODE
