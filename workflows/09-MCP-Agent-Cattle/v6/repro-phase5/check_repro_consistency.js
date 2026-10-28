#!/usr/bin/env node
/*
 * Phase 5 - offline consistency check between the MCP server export and the two livestock agent prompts.
 * No dependencies, no network. The only optional external call is `git show develop:<file>` to read the PREVIOUS prompts
 * (to prove the leading "=" and every {{ }} expression are untouched); if git or the branch is not available that one check is SKIPPED.
 *
 * Usage:  node check_repro_consistency.js [--baseline-ref <git ref>]       (default ref: develop)
 * Exit code 0 = every check passed, 1 = at least one FAIL.
 */
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const V6 = path.resolve(__dirname, '..');
const REF = process.argv.includes('--baseline-ref') ? process.argv[process.argv.indexOf('--baseline-ref') + 1] : 'develop';
const MCP_FILE = 'v6_MCP_Server_Cattle.json';
const AGENTS = { chat: 'v6_ai_chat_cattle.json', whatsapp: 'v6_WhatsApp_Agent_Cattle.json' };
const PHASE_FILES = [1, 2, 3, 4].map((p) => `repro-phase${p}/repro_phase${p}_tools.json`);

// documented exceptions: out of the dictionary on purpose
const LEGACY_KEPT_AS_NODE = ['register_birth_event', 'log_palpation_event_batch'];   // rollback path of 087; backlog items 24 and 25
const FORBIDDEN_TOOL = ['get_table_metadata'];                                       // A4 says it is NOT allowed
const NOT_EXPOSED = ['sp_repro_condition_code_set', 'sp_repro_empadre_set_config', 'sp_repro_births_set_config'];

// the owner's decisions (phase 5): confirmation levels
const NEW_READS = ['get_dam_reproductive_history', 'get_dam_birth_history', 'list_births', 'get_births_summary', 'list_unregistered_historical_births',
  'identifier_quality_report', 'list_historical_births', 'get_births_config', 'births_batch_preview', 'get_empadre_config',
  'list_heifers_eligible_for_empadre', 'list_empadre_entries', 'list_open_cows', 'list_palpation_due', 'list_upcoming_calvings', 'list_unmapped_uterine_codes'];
const NEW_ROUTINE = ['register_birth_checked', 'log_palpation_with_condition', 'log_empadre_entry', 'log_empadre_entry_batch'];
const NEW_CONFIRM = ['births_batch_register', 'register_historical_birth', 'void_historical_birth', 'void_empadre_entry'];
const EXPECTED = {
  1: ['get_livestock_info', 'find_livestock_by_criteria', 'find_calf_by_dam', 'count_livestock', 'list_pending_requests', 'list_lots', 'preview_livestock_sale_order', ...NEW_READS],
  2: ['log_cattle_weight', 'log_health_event', 'log_vaccination_event', 'log_supplement_event', 'log_palpation_event', 'log_breeding_event', 'log_deworming_event',
      'log_weaning_event', 'register_ranch_expense', 'register_livestock_purchase', 'move_livestock', ...NEW_ROUTINE],
  3: ['log_mortality_event', 'request_livestock_sale_order', 'request_livestock_sale', 'review_pending_request', 'cancel_pending_request', 'update_livestock_tag',
      'log_castration_event', 'void_event', ...NEW_CONFIRM],
};
const REQUIRED_G_WORDS = ['not_examined', 'needs_explicit_result', 'NEEDS_EXPLICIT_RESULT', 'DIAGNOSIS_UNRECOGNIZED', 'DIAGNOSIS_CONFLICT', 'vet_flag', 'POSTPARTUM', 'UNFIT',
  'rp_without_registered_birth', 'palpation_code_contradicts_result', 'known_meanings', 'composite_unconfirmed', 'known_pending', 'possible_duplicate', "force='true'",
  'duplicate_skipped', 'S/N-1450-16', 'stale_data', 'date_is_stale_import', 'sire_not_resolved', 'semen_batch_missing', 'can_register', 'NO un veterinario',
  'date_precision', 'list_lots', 'lot_id', 'production_unit_id', '15 meses o 300 kg'];

let fails = 0, passes = 0, skips = 0;
const ok = (label, cond, detail) => {
  if (cond) { passes++; console.log('OK    ' + label); }
  else { fails++; console.log('FAIL  ' + label + (detail ? '\n        ' + detail : '')); }
};
const skip = (label, why) => { skips++; console.log('SKIP  ' + label + '  (' + why + ')'); };
const setEq = (a, b) => a.length === b.length && a.every((x) => b.includes(x));
const diff = (a, b) => ({ onlyA: a.filter((x) => !b.includes(x)), onlyB: b.filter((x) => !a.includes(x)) });
const fmt = (d) => 'only in first: [' + d.onlyA.join(', ') + ']   only in second: [' + d.onlyB.join(', ') + ']';
const exprs = (t) => (t.match(/\{\{[\s\S]*?\}\}/g) || []);

// ---------------------------------------------------------------- 1. every JSON parses
const docs = {};
for (const f of [MCP_FILE, ...Object.values(AGENTS), ...PHASE_FILES]) {
  try { docs[f] = JSON.parse(fs.readFileSync(path.join(V6, f), 'utf8')); ok('JSON parses: ' + f, true); }
  catch (e) { ok('JSON parses: ' + f, false, e.message); }
}
if (fails) { console.log('\nStopping: a file does not parse.'); process.exit(1); }

const mcp = docs[MCP_FILE];
const toolNodes = mcp.nodes.filter((n) => n.type.endsWith('postgresTool'));
const toolNames = toolNodes.map((n) => n.name);
ok('MCP server: node names are unique', new Set(mcp.nodes.map((n) => n.name)).size === mcp.nodes.length);
ok('MCP server: 53 tool nodes (29 existing + 24 reproduction)', toolNames.length === 53, 'found ' + toolNames.length);
const trigger = mcp.nodes.find((n) => n.type.endsWith('mcpTrigger'));
ok('MCP server: every tool node is connected to the MCP trigger',
  toolNames.every((t) => { const c = mcp.connections[t]; return c && c.ai_tool && c.ai_tool[0] && c.ai_tool[0].some((x) => x.node === trigger.name); }));
const phaseNames = [].concat(...PHASE_FILES.map((f) => docs[f].nodes.map((n) => n.name)));
ok('the 24 nodes of repro-phase1..4 are all in the MCP server', phaseNames.length === 24 && phaseNames.every((n) => toolNames.includes(n)),
  fmt(diff(phaseNames, toolNames)));
ok('MCP server: each reproduction node equals its phase file node except position',
  phaseNames.every((n) => {
    const a = JSON.parse(JSON.stringify(toolNodes.find((x) => x.name === n))); delete a.position;
    const src = PHASE_FILES.map((f) => docs[f].nodes.find((x) => x.name === n)).find(Boolean);
    const b = JSON.parse(JSON.stringify(src)); delete b.position;
    return JSON.stringify(a) === JSON.stringify(b);
  }));
ok('the setters are NOT exposed (no node, not in any prompt)', NOT_EXPOSED.every((s) => !toolNames.includes(s)));

// ---------------------------------------------------------------- 2. prompts
const sys = {};
const baseline = {};
for (const [ch, f] of Object.entries(AGENTS)) {
  const agent = docs[f].nodes.filter((n) => n.name === 'AI Agent');
  ok(`${ch}: exactly one node "AI Agent"`, agent.length === 1);
  sys[ch] = agent[0].parameters.options.systemMessage;
  ok(`${ch}: systemMessage starts with "="`, sys[ch].startsWith('='));
}

const section = (msg, from, to) => { const i = msg.indexOf(from); const j = to ? msg.indexOf(to, i + 1) : msg.length; return i < 0 ? '' : msg.slice(i, j < 0 ? msg.length : j); };
const parts = {};
for (const ch of Object.keys(AGENTS)) {
  parts[ch] = {
    E: section(sys[ch], '🛠️ E. DICCIONARIO', '✨ F. PROTOCOLO'),
    G: section(sys[ch], '🧬 G. REPRODUCCIÓN', null),
    C: section(sys[ch], '🛑 C. PROTOCOLO', '🛑 D. FLUJOS'),
  };
  ok(`${ch}: sections E, G and C are present`, parts[ch].E.length > 1000 && parts[ch].G.length > 1000 && parts[ch].C.length > 200);
}
ok('both prompts carry EXACTLY the same section G', parts.chat.G === parts.whatsapp.G);

// tools named in the prompts
const TOOL_RE = /'((?:get|list|log|register|void|find|count|move|review|cancel|preview|request|update|births|identifier)_[a-z_]+)'/g;
const allowed = new Set(toolNames.filter((t) => !LEGACY_KEPT_AS_NODE.includes(t)));
const dict = {};
for (const ch of Object.keys(AGENTS)) {
  const named = new Set([...sys[ch].matchAll(TOOL_RE)].map((m) => m[1]));
  // parameter names look like tools sometimes (e.g. 'log_...'): keep only what is an MCP tool or clearly a tool verb used as a tool
  const unknown = [...named].filter((t) => !toolNames.includes(t));
  ok(`${ch}: every tool named in the prompt exists in the MCP server (and none is a legacy tool)`,
    unknown.length === 0 && LEGACY_KEPT_AS_NODE.every((l) => !sys[ch].includes(l)), 'unknown: [' + unknown.join(', ') + ']');
  dict[ch] = [...new Set([...parts[ch].E.matchAll(TOOL_RE)].map((m) => m[1]))].filter((t) => toolNames.includes(t)).sort();
  const expectedDict = toolNames.filter((t) => !LEGACY_KEPT_AS_NODE.includes(t) && !FORBIDDEN_TOOL.includes(t)).sort();
  ok(`${ch}: dictionary E lists every MCP tool except the documented ones (get_table_metadata, ${LEGACY_KEPT_AS_NODE.join(', ')})`, setEq(dict[ch], expectedDict),
    fmt(diff(dict[ch], expectedDict)));
  ok(`${ch}: nothing outside the MCP server is named as a tool (no sp_repro_* setter)`, NOT_EXPOSED.every((s) => !sys[ch].includes(s)));
}
ok('both prompts list the same tools in the dictionary', setEq(dict.chat, dict.whatsapp), fmt(diff(dict.chat, dict.whatsapp)));

// confirmation levels (section C) against the owner's decisions
for (const ch of Object.keys(AGENTS)) {
  const lvl = {};
  for (const n of [1, 2, 3]) {
    const m = parts[ch].C.match(new RegExp('- NIVEL ' + n + ' —[^:]*: ([^\\n]+)'));
    lvl[n] = m ? m[1].replace(/\.$/, '').split(',').map((s) => s.trim()).filter(Boolean) : [];
    ok(`${ch}: NIVEL ${n} list matches the decisions`, setEq(lvl[n], EXPECTED[n]), fmt(diff(lvl[n], EXPECTED[n])));
  }
  const all = [...lvl[1], ...lvl[2], ...lvl[3]];
  ok(`${ch}: no tool is in two levels`, new Set(all).size === all.length);
  ok(`${ch}: every dictionary tool has a level`, setEq(all.slice().sort(), dict[ch]), fmt(diff(all.slice().sort(), dict[ch])));
}

// each new tool's description agrees with its level
const descOf = (n) => toolNodes.find((x) => x.name === n).parameters.toolDescription || '';
const ASKS = /pide al usuario que confirme con Sí\/No/;
ok('NIVEL 2 tools: toolDescription does NOT ask for a Sí/No before calling', NEW_ROUTINE.every((t) => !ASKS.test(descOf(t))), NEW_ROUTINE.filter((t) => ASKS.test(descOf(t))).join(', '));
ok('NIVEL 3 tools: toolDescription KEEPS the Sí/No sentence', NEW_CONFIRM.every((t) => ASKS.test(descOf(t))), NEW_CONFIRM.filter((t) => !ASKS.test(descOf(t))).join(', '));
ok('NIVEL 1 tools: toolDescription does not ask for a Sí/No', NEW_READS.every((t) => !ASKS.test(descOf(t))));
ok('no toolDescription says an ADMIN changes settings / codes "desde el panel" (there is no panel)',
  toolNodes.filter((n) => /ADMIN[^.]*desde el panel/.test(n.parameters.toolDescription || '') && NEW_READS.concat(NEW_ROUTINE, NEW_CONFIRM).includes(n.name)).length === 0);

// A5: every e-mail and tenant parameter of every tool
const params = new Set();
for (const n of toolNodes) {
  const q = (n.parameters.options && n.parameters.options.queryReplacement) || '';
  for (const m of q.matchAll(/\$fromAI\(\s*['"]([A-Za-z_]+)['"]/g)) params.add(m[1]);
}
const emailParams = [...params].filter((p) => /email/i.test(p)).sort();
const tenantParams = [...params].filter((p) => /tenant/i.test(p)).sort();
for (const ch of Object.keys(AGENTS)) {
  const a5 = (sys[ch].match(/A5\.[^\n]+/) || [''])[0];
  const missing = emailParams.filter((p) => !a5.includes(p));
  ok(`${ch}: A5 lists every e-mail parameter name used by any MCP tool [${emailParams.join(', ')}]`, missing.length === 0, 'missing: ' + missing.join(', '));
  ok(`${ch}: A5 covers the tenant parameter [${tenantParams.join(', ')}]`, tenantParams.every((p) => a5.includes(p)));
  ok(`${ch}: A5 states that the reproduction tools take only user_email and tenant_id`, /REPRODUCCIÓN[^.]*user_email y tenant_id/.test(a5));
}
const newToolParams = new Set();
for (const n of toolNodes.filter((x) => phaseNames.includes(x.name))) {
  const q = (n.parameters.options && n.parameters.options.queryReplacement) || '';
  for (const m of q.matchAll(/\$fromAI\(\s*['"]([A-Za-z_]+)['"]/g)) if (/email|tenant/i.test(m[1])) newToolParams.add(m[1]);
}
ok('the 24 new tools use no e-mail/tenant parameter other than user_email and tenant_id', setEq([...newToolParams].sort(), ['tenant_id', 'user_email']), [...newToolParams].join(', '));

// section G content
for (const ch of Object.keys(AGENTS)) {
  const miss = REQUIRED_G_WORDS.filter((w) => !parts[ch].G.includes(w));
  ok(`${ch}: section G teaches every required answer / field / rule`, miss.length === 0, 'missing: ' + miss.join(', '));
  ok(`${ch}: section G never says a veterinarian confirmed RP / NR / NO APTO / MATRIZ OCUPADA`, !/veterinario[s]? (los )?confirm[óo]/i.test(parts[ch].G.replace(/NO un veterinario[^.]*\./, '')));
  ok(`${ch}: section G adds no role restriction (no "solo un ADMIN" outside the death / sale authorization)`, !/solo (un )?ADMIN (puede )?(registr|captur)/i.test(parts[ch].G));
}

// leading "=" and {{ }} expressions against the previous version of the file (git)
function previous(file) {
  try { return JSON.parse(execFileSync('git', ['-C', V6, 'show', `${REF}:workflows/09-MCP-Agent-Cattle/v6/${file}`], { stdio: ['ignore', 'pipe', 'ignore'], maxBuffer: 1 << 28 }).toString()); }
  catch (e) { return null; }
}
for (const [ch, f] of Object.entries(AGENTS)) {
  const prev = previous(f);
  if (!prev) { skip(`${ch}: "=" and {{ }} expressions identical to ${REF}`, 'git or ref not available'); continue; }
  const pm = prev.nodes.find((n) => n.name === 'AI Agent').parameters.options.systemMessage;
  ok(`${ch}: leading "=" and the ${exprs(pm).length} {{ }} expressions are identical to ${REF}`, pm[0] === '=' && sys[ch][0] === '=' && JSON.stringify(exprs(pm)) === JSON.stringify(exprs(sys[ch])));
  const pp = prev.nodes.find((n) => n.name === 'AI Agent Palma').parameters.options.systemMessage;
  ok(`${ch}: "AI Agent Palma" is untouched`, pp === docs[f].nodes.find((n) => n.name === 'AI Agent Palma').parameters.options.systemMessage);
  const pt = prev.nodes.find((n) => n.name === 'AI Agent').parameters.text;
  ok(`${ch}: the "text" input expression of "AI Agent" is untouched`, pt === docs[f].nodes.find((n) => n.name === 'AI Agent').parameters.text);
  const others = prev.nodes.filter((n) => n.name !== 'AI Agent');
  ok(`${ch}: no other node of the workflow changed (${others.length} nodes)`, others.every((n) => JSON.stringify(n) === JSON.stringify(docs[f].nodes.find((x) => x.name === n.name))));
}
for (const ch of Object.keys(AGENTS)) {
  ok(`${ch}: prompt size ${sys[ch].length} characters (informational: it was ~32 000 before phase 5)`, sys[ch].length < 60000);
}

console.log(`\n${passes} passed, ${fails} failed, ${skips} skipped`);
process.exit(fails ? 1 : 0);
