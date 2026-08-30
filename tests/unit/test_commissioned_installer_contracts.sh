#!/usr/bin/env bash
# Offline source qualification for the exact W3 commissioned installer set.
# No installer is downloaded or executed by this test.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"

if ! command -v node >/dev/null 2>&1; then
    printf 'FAIL: node is required for commissioned installer source qualification\n' >&2
    exit 1
fi

node - \
    "$REPO_ROOT/acfs.manifest.yaml" \
    "$REPO_ROOT/checksums.yaml" \
    "$REPO_ROOT/config/flywheel-license-clearance.json" \
    "$REPO_ROOT/packages/manifest/src/generate.ts" \
    "$REPO_ROOT/scripts/generated/install_stack.sh" <<'NODE'
const fs = require('node:fs');

const [manifestPath, checksumsPath, clearancePath, generatorPath, generatedPath] =
  process.argv.slice(2);
const manifestSource = fs.readFileSync(manifestPath, 'utf8');
const checksumsSource = fs.readFileSync(checksumsPath, 'utf8');
const clearance = JSON.parse(fs.readFileSync(clearancePath, 'utf8'));
const generatorSource = fs.readFileSync(generatorPath, 'utf8');
const generatedSource = fs.readFileSync(generatedPath, 'utf8');

const expectedCommissionedInstallers = [
  ['stack.ntm', 'ntm'],
  ['stack.meta_skill', 'ms'],
  ['stack.automated_plan_reviser', 'apr'],
  ['stack.jeffreysprompts', 'jfp'],
  ['stack.process_triage', 'pt'],
  ['stack.ultimate_bug_scanner', 'ubs'],
  ['stack.beads_rust', 'br'],
  ['stack.cass', 'cass'],
  ['stack.cm', 'cm'],
  ['stack.caam', 'caam'],
  ['stack.slb', 'slb'],
  ['stack.dcg', 'dcg'],
  ['stack.ru', 'ru'],
  ['stack.brenner_bot', 'brenner_bot'],
  ['stack.rch', 'rch'],
  ['stack.srps', 'srps'],
  ['stack.frankensearch', 'fsfs'],
  ['stack.storage_ballast_helper', 'sbh'],
  ['stack.cross_agent_session_resumer', 'casr'],
  ['stack.doodlestein_self_releaser', 'dsr'],
  ['stack.agent_settings_backup', 'asb'],
  ['stack.pcr', 'pcr'],
  ['stack.eidetic_engine_cli', 'ee'],
  ['stack.franken_markdown', 'fmd'],
  ['stack.pi_agent_rust', 'pi'],
];

const sourceBuildExpectations = {
  ms: {
    module: 'stack.meta_skill',
    repository: 'Dicklesworthstone/meta_skill',
    source_repo: 'https://github.com/Dicklesworthstone/meta_skill.git',
    source_commit: '2a4bc62a04c98d8812bfe68b77c862d87e1731e3',
    source_tree: '956bd9e6426d120341d50a30722b41ddd7f688c7',
    cargo_lock_sha256: 'd7684ea8c8392092df67e2aee4fb9e74fae0359389572760235217838a5c3181',
    cargo_toml_sha256: '9f0dc83afc2f236d4c4af16dbd16fc1639a9f0d00e07db23f949482c5eeeda4f',
    version: 'ms 0.2.2',
  },
  jfp: {
    module: 'stack.jeffreysprompts',
    repository: 'Dicklesworthstone/jeffreysprompts.com',
    source_repo: 'https://github.com/Dicklesworthstone/jeffreysprompts.com.git',
    source_commit: '2cec2d5257ef0da32a856b51673f243b6c72a3e2',
    source_tree: '79fc4e85f86a6e1e809e212004a4cc848e1d19ee',
    cargo_lock_sha256: 'd17941a5a85c4f4eda4f4cb070125ebf6b1af7e403846e6b35915c6d95f25c9d',
    cargo_toml_sha256: 'c902d565b250385fe4619cad99a5d68f923355c6833735d730f5a5979254378f',
    version: 'jfp 0.1.0',
  },
  ee: {
    module: 'stack.eidetic_engine_cli',
    repository: 'Dicklesworthstone/eidetic_engine_cli',
    source_repo: 'https://github.com/Dicklesworthstone/eidetic_engine_cli.git',
    source_commit: '0fc6801c91edc0764cf405b049024a25c3199e09',
    source_tree: '179ac1bb86320f3874b34cec1cbcca2b85c7eadf',
    cargo_lock_sha256: 'd4a9012264d98026a6e2fd85a04b2ff3c85e636ebdcfb970f310a9f0421004cc',
    cargo_toml_sha256: '2ae5549883ab45efca3f7eadd62130f24a4ff29f1c6216475dfa615646006598',
    stack_lock_sha256: '9b649eff8925fd22d980e7bbddd7ff479ff6318c14f141fe9a8343b7a4db2738',
    checkout_sha256: 'a0f5041e4c13ba6faeb23df1e25ce3dc693c96dd9b2667d9d351e82e0dccde3c',
    version: 'ee 0.14.2',
  },
  fmd: {
    module: 'stack.franken_markdown',
    repository: 'Dicklesworthstone/franken_markdown',
    source_repo: 'https://github.com/Dicklesworthstone/franken_markdown.git',
    source_commit: '5637bad86e3c0deacab6411a734715015b143a12',
    source_tree: 'f2d92693543fb542596f4aa00a402e832938caf1',
    cargo_lock_sha256: '3114ddb930a116a042e62d36f3a906f341414f6791383360c179c6337cb54ff0',
    cargo_toml_sha256: '8cd3d68fcc88ede03ef1179d93fad1828d517b61469b3ef3c89aed237dcddabd',
    version: 'fmd 0.4.2',
  },
};

const failures = [];
let passed = 0;

function pass(label) {
  passed += 1;
  process.stdout.write(`PASS: ${label}\n`);
}

function fail(label, detail) {
  failures.push(`${label}: ${detail}`);
  process.stderr.write(`FAIL: ${label} -- ${detail}\n`);
}

function check(label, condition, detail) {
  if (condition) pass(label);
  else fail(label, detail);
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function yamlScalar(raw) {
  const value = raw.trim();
  if (value.startsWith('"')) return JSON.parse(value);
  if (value.startsWith("'") && value.endsWith("'")) {
    return value.slice(1, -1).replace(/''/g, "'");
  }
  return value;
}

function topLevelModuleBlocks(source) {
  const starts = [...source.matchAll(/^  - id: ([^\n]+)$/gm)];
  const blocks = new Map();
  for (let index = 0; index < starts.length; index += 1) {
    const start = starts[index];
    const end = starts[index + 1]?.index ?? source.length;
    blocks.set(start[1], source.slice(start.index, end));
  }
  return blocks;
}

function manifestSection(block, name) {
  const lines = block.split('\n');
  const start = lines.findIndex((line) => line === `    ${name}:`);
  if (start < 0) return '';
  const selected = [];
  for (let index = start + 1; index < lines.length; index += 1) {
    if (/^    \S/.test(lines[index])) break;
    selected.push(lines[index]);
  }
  return selected.join('\n');
}

function sectionField(section, name) {
  const match = section.match(new RegExp(`^      ${escapeRegExp(name)}: (.+)$`, 'm'));
  return match ? yamlScalar(match[1]) : undefined;
}

function manifestNotes(block) {
  const notes = new Map();
  for (const match of manifestSection(block, 'notes').matchAll(/^      - "([^"=]+)=([^"\n]+)"$/gm)) {
    notes.set(match[1], match[2]);
  }
  return notes;
}

function checksumEntries(source) {
  const entries = new Map();
  const starts = [...source.matchAll(/^  ([a-zA-Z0-9_]+):$/gm)];
  for (let index = 0; index < starts.length; index += 1) {
    const start = starts[index];
    const end = starts[index + 1]?.index ?? source.length;
    const block = source.slice(start.index, end);
    const url = block.match(/^    url: (.+)$/m);
    const sha256 = block.match(/^    sha256: (.+)$/m);
    entries.set(start[1], {
      url: url ? yamlScalar(url[1]) : undefined,
      sha256: sha256 ? yamlScalar(sha256[1]) : undefined,
    });
  }
  return entries;
}

function generatedFunction(source, moduleName) {
  const marker = `acfs_generated_install_${moduleName}() {`;
  const start = source.indexOf(marker);
  if (start < 0) return '';
  const next = source.slice(start + marker.length).search(/^acfs_generated_install_[a-z0-9_]+\(\) \{$/m);
  return next < 0
    ? source.slice(start)
    : source.slice(start, start + marker.length + next);
}

function generatorBranch(tool, nextTool) {
  const elseMarker = `} else if (tool === '${tool}') {`;
  const firstMarker = `if (tool === '${tool}') {`;
  const elseStart = generatorSource.indexOf(elseMarker);
  const firstStart = generatorSource.indexOf(firstMarker);
  const marker = elseStart >= 0 ? elseMarker : firstMarker;
  const start = elseStart >= 0 ? elseStart : firstStart;
  if (start < 0) return '';
  const endMarker = `} else if (tool === '${nextTool}') {`;
  const end = generatorSource.indexOf(endMarker, start + marker.length);
  return end < 0 ? generatorSource.slice(start) : generatorSource.slice(start, end);
}

function generatorLiteral(branch, variable) {
  const matches = [...branch.matchAll(new RegExp(`local ${escapeRegExp(variable)}="([^"]+)"`, 'g'))];
  return matches.length === 1 ? matches[0][1] : undefined;
}

const manifestModules = topLevelModuleBlocks(manifestSource);
const checksumMap = checksumEntries(checksumsSource);
const clearanceModules = new Map(clearance.modules.map((entry) => [entry.id, entry]));
const expectedMap = new Map(expectedCommissionedInstallers);
const expectedModuleSet = new Set(expectedMap.keys());
const holdSet = new Set(clearance.commissioning.independent_holds);

const actualCommissionedVerified = clearance.commissioning.seed_modules
  .filter((moduleId) => moduleId.startsWith('stack.'))
  .filter((moduleId) => !holdSet.has(moduleId))
  .filter((moduleId) => manifestSection(manifestModules.get(moduleId) || '', 'verified_installer'));

check(
  'commissioning resolves exactly 25 verified-installer modules',
  actualCommissionedVerified.length === 25
    && actualCommissionedVerified.every((moduleId) => expectedModuleSet.has(moduleId))
    && expectedCommissionedInstallers.every(([moduleId]) => actualCommissionedVerified.includes(moduleId)),
  `actual=${actualCommissionedVerified.join(',')}`,
);

check(
  'license clearance is exact-revision private commissioning authority',
  clearance.status === 'LICENSE_CLEARED'
    && clearance.scope.exact_revisions_only === true
    && clearance.scope.environment === 'private_nonproduction'
    && clearance.commissioning.fully_commissioned === false
    && holdSet.has('stack.mcp_agent_mail'),
  'clearance scope or independent-hold contract drifted',
);

const seenUrls = new Set();
const installerBindingFailures = [];
const exactSourceTools = new Set(['ms', 'jfp', 'rch', 'ee', 'fmd']);
for (const [moduleId, expectedTool] of expectedCommissionedInstallers) {
  const block = manifestModules.get(moduleId) || '';
  const verified = manifestSection(block, 'verified_installer');
  const tool = sectionField(verified, 'tool');
  const manifestUrl = sectionField(verified, 'url');
  const license = clearanceModules.get(moduleId);
  const checksum = checksumMap.get(expectedTool);

  if (!block) installerBindingFailures.push(`${moduleId}: manifest module missing`);
  if (tool !== expectedTool) {
    installerBindingFailures.push(`${moduleId}: tool=${tool ?? 'missing'}, expected=${expectedTool}`);
  }
  if (!license) installerBindingFailures.push(`${moduleId}: license identity missing`);
  if (!checksum?.url || !checksum?.sha256) {
    installerBindingFailures.push(`${moduleId}: checksum entry ${expectedTool} incomplete`);
    continue;
  }
  if (!/^[0-9a-f]{64}$/.test(checksum.sha256)) {
    installerBindingFailures.push(`${moduleId}: invalid SHA-256 ${checksum.sha256}`);
  }
  if (exactSourceTools.has(expectedTool)) continue;
  if (license) {
    const expectedPrefix = `https://raw.githubusercontent.com/${license.repository}/${license.commit}/`;
    if (!checksum.url.startsWith(expectedPrefix) || checksum.url.length === expectedPrefix.length) {
      installerBindingFailures.push(
        `${moduleId}: URL is not pinned to licensed ${license.repository}@${license.commit}: ${checksum.url}`,
      );
    }
  }
  if (manifestUrl !== undefined && manifestUrl !== checksum.url) {
    installerBindingFailures.push(
      `${moduleId}: manifest URL does not equal checksum URL (${manifestUrl} != ${checksum.url})`,
    );
  }
  if (seenUrls.has(checksum.url)) installerBindingFailures.push(`${moduleId}: duplicate URL ${checksum.url}`);
  seenUrls.add(checksum.url);
}

check(
  'all 20 executed installer URLs are immutable and bound to checksum plus license identity',
  installerBindingFailures.length === 0 && seenUrls.size === 20,
  installerBindingFailures.join('; ') || `unique_urls=${seenUrls.size}`,
);

const jfpGeneratedInstaller = generatedFunction(generatedSource, 'stack_jeffreysprompts');
check(
  'all five source-built modules cover Linux with no mutable installer fallback',
  jfpGeneratedInstaller.includes('if [[ "$(uname -s 2>/dev/null)" == "Linux" ]]; then')
    && jfpGeneratedInstaller.includes('exact source commissioning is supported only on Linux')
    && !jfpGeneratedInstaller.includes('local tool="jfp"')
    && !jfpGeneratedInstaller.includes('url="${KNOWN_INSTALLERS[$tool]:-}"')
    && !jfpGeneratedInstaller.includes('run_as_target_runner \'bash\' "$verified_installer_file"')
    && ['stack_meta_skill', 'stack_rch', 'stack_eidetic_engine_cli', 'stack_franken_markdown']
      .every((moduleName) => {
        const generated = generatedFunction(generatedSource, moduleName);
        return generated.includes('if [[ "$(uname -s 2>/dev/null)" == "Linux" ]]; then')
          && generated.includes('exact source commissioning is supported only on Linux')
          && !generated.includes('url="${KNOWN_INSTALLERS[$tool]:-}"')
          && !generated.includes('run_as_target_runner \'bash\' "$verified_installer_file"');
      }),
  'source-build platform coverage or fallback execution route drifted',
);

const caamVerified = manifestSection(manifestModules.get('stack.caam') || '', 'verified_installer');
const caamGenerated = generatedFunction(generatedSource, 'stack_caam');
check(
  'CAAM is exactly NONINTERACTIVE=1 in manifest and generated execution',
  /^      env: \["NONINTERACTIVE=1"\]$/m.test(caamVerified)
    && !/^      env: \[[^\n]*,[^\n]*\]$/m.test(caamVerified)
    && caamGenerated.includes("run_as_target_runner 'env' 'NONINTERACTIVE=1' 'bash' \"$verified_installer_file\""),
  'CAAM noninteractive environment contract drifted',
);

const slbVerified = manifestSection(manifestModules.get('stack.slb') || '', 'verified_installer');
const slbGenerated = generatedFunction(generatedSource, 'stack_slb');
check(
  'SLB uses the exact target-user local INSTALL_DIR',
  /^      env: \["INSTALL_DIR=\$TARGET_HOME\/\.local\/bin"\]$/m.test(slbVerified)
    && slbGenerated.includes("run_as_target_runner 'env' 'INSTALL_DIR='\"$TARGET_HOME\"'/.local/bin' 'bash' \"$verified_installer_file\""),
  'SLB INSTALL_DIR is not exactly $TARGET_HOME/.local/bin',
);

const sourceBuildFailures = [];
const nextSourceBranch = { ms: 'rch', jfp: 'ee', ee: 'fmd', fmd: 'fsfs' };
const generatedModuleName = {
  ms: 'meta_skill',
  jfp: 'jeffreysprompts',
  ee: 'eidetic_engine_cli',
  fmd: 'franken_markdown',
};
for (const [tool, expected] of Object.entries(sourceBuildExpectations)) {
  const block = manifestModules.get(expected.module) || '';
  const notes = manifestNotes(block);
  const license = clearanceModules.get(expected.module);
  const branch = generatorBranch(tool, nextSourceBranch[tool]);
  const generated = generatedFunction(generatedSource, `stack_${generatedModuleName[tool]}`);
  const variableExpectations = {
    [`${tool}_source_repo`]: expected.source_repo,
    [`${tool}_source_commit`]: expected.source_commit,
    [`${tool}_source_tree`]: expected.source_tree,
    [`${tool}_cargo_lock_sha256`]: expected.cargo_lock_sha256,
    [`${tool}_cargo_toml_sha256`]: expected.cargo_toml_sha256,
  };
  if (tool === 'ee') {
    variableExpectations.ee_stack_lock_sha256 = expected.stack_lock_sha256;
    variableExpectations.ee_checkout_sha256 = expected.checkout_sha256;
  }

  if (license?.repository !== expected.repository || license?.commit !== expected.source_commit) {
    sourceBuildFailures.push(`${tool}: source commit/repository diverges from license identity`);
  }
  if (notes.get('linux_source_commit') !== expected.source_commit
      || notes.get('linux_source_tree') !== expected.source_tree
      || notes.get('linux_cargo_lock_sha256') !== expected.cargo_lock_sha256) {
    sourceBuildFailures.push(`${tool}: manifest source-build notes drifted`);
  }
  if (tool === 'ee'
      && notes.get('linux_franken_stack_lock_sha256') !== expected.stack_lock_sha256) {
    sourceBuildFailures.push('ee: manifest franken-stack.lock identity drifted');
  }
  for (const [variable, value] of Object.entries(variableExpectations)) {
    if (generatorLiteral(branch, variable) !== value) {
      sourceBuildFailures.push(`${tool}: generator ${variable} is not ${value}`);
    }
    if (!generated.includes(`local ${variable}="${value}"`)) {
      sourceBuildFailures.push(`${tool}: generated ${variable} is not ${value}`);
    }
  }

  const installedCheck = manifestSection(block, 'installed_check');
  const command = sectionField(installedCheck, 'command');
  const binary = tool;
  if (command !== `test "$(${binary} --version 2>/dev/null)" = "${expected.version}"`) {
    sourceBuildFailures.push(`${tool}: installed_check does not require ${expected.version}`);
  }
  if (!branch.includes(`[[ "$${tool}_version" == "${expected.version}" ]]`)
      || !generated.includes(`[[ "$${tool}_version" == "${expected.version}" ]]`)) {
    sourceBuildFailures.push(`${tool}: source-built binary version is not exactly ${expected.version}`);
  }
  for (const fragment of [
    `fetch --depth 1 origin "$${tool}_source_commit"`,
    `checkout --detach "$${tool}_source_commit"`,
    'rev-parse HEAD',
    'rev-parse "HEAD^{tree}"',
    'status --porcelain=v1 --untracked-files=all',
    tool === 'fmd' ? 'build --locked --jobs 1' : `--bin ${binary}`,
  ]) {
    if (!branch.includes(fragment) || !generated.includes(fragment)) {
      sourceBuildFailures.push(`${tool}: missing source-build guard ${fragment}`);
    }
  }
}

check(
  'MS, JFP, EE, and FMD exact source identities, lock inputs, and versions are enforced',
  sourceBuildFailures.length === 0,
  sourceBuildFailures.join('; '),
);

const rchGenerated = generatedFunction(generatedSource, 'stack_rch');
check(
  'RCH exact source identity, split profiles, bounded jobs, and binary versions are enforced',
  rchGenerated.includes('local rch_source_commit="0a982fdee2ca5ce26791dd17b83285916a7b97f6"')
    && rchGenerated.includes('local rch_source_tree="368cc8c1426f6f7b30c505ffbc6ca9769a5d06d7"')
    && rchGenerated.includes('local rch_cargo_lock_sha256="c115964866335f4194dd83350f0a800f5af507a99e23943eef31812d79536e4a"')
    && rchGenerated.includes('--profile wrapper-release --package rch --bin rch')
    && rchGenerated.includes('--profile daemon-release --package rchd --package rch-wkr')
    && rchGenerated.includes('rch_target_dir="$rch_build_cache_parent/rch-$rch_source_commit-$rch_toolchain-$rch_target"')
    && rchGenerated.includes('--target-dir "$rch_target_dir"')
    && rchGenerated.includes('CARGO_BUILD_JOBS=1 RUSTFLAGS=')
    && rchGenerated.includes('rch 1.0.60 (commit 0a982fdee2ca)')
    && rchGenerated.includes('rchd 1.0.60 (commit 0a982fdee2ca)')
    && rchGenerated.includes('rch-wkr 1.0.60 (commit 0a982fdee2ca)'),
  'RCH exact-source build contract drifted',
);

process.stdout.write(`\nCommissioned installer contracts: ${passed} passed, ${failures.length} failed\n`);
if (failures.length > 0) process.exitCode = 1;
NODE
