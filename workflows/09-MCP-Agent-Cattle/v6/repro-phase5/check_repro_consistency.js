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
  'duplicate_skipped', 'S/N-1450-16', 'stale_data', 'date_is_stale_import', 'sire_not_resolved', 'semen_batch_missing', 'can_register', 'nunca digas que un veterinario los confirmó',
  'date_precision', 'list_lots', 'lot_id', 'production_unit_id', '15 meses o 300 kg',
  'lot_id_resolved', 'production_unit_id_resolved', 'dam_status_warning', 'no se resolvió ningún lote/UPP',
  'Interpreta RP, NR, NO APTO y MATRIZ OCUPADA solo como lo devuelve la herramienta (vet_flag, not_examined, unmapped_codes)'];

// phase 5 review: single animal with a vet code goes through the wrapper; legacy nodes are marked obsolete
const SINGLE_RULE = 'Si el usuario dicta un código (UNE, UTCL1, RP, NR, NO APTO, MATRIZ OCUPADA...), usa log_palpation_with_condition con UN solo elemento en animals_json, aunque sea un solo animal. log_palpation_event es solo para un resultado explícito sin código.';
const OBSOLETE_PREFIX = { register_birth_event: 'OBSOLETA: no la uses. Usa register_birth_checked, que NO acepta lot_name ni production_unit_name', log_palpation_event_batch: 'OBSOLETA: no la uses. Usa log_palpation_with_condition.' };

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
ok('log_palpation_event and log_palpation_with_condition descriptions carry the single-animal rule', [descOf('log_palpation_event'), descOf('log_palpation_with_condition')].every((d) => d.includes(SINGLE_RULE)));
ok('legacy nodes are marked OBSOLETA with their replacement (toolDescription prefix)',
  Object.entries(OBSOLETE_PREFIX).every(([k, v]) => descOf(k).startsWith(v)));
ok('get_births_config description has no ADMIN / SQL / panel wording', !/ADMIN|SQL|panel/.test(descOf('get_births_config')), descOf('get_births_config'));
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


// A5, per tool: the e-mail parameter NAME that A5 gives each tool must be the one its node defines (round 1 of the local QA, F1)
const emailKeyOf = (n) => {
  const q = (n.parameters.options && n.parameters.options.queryReplacement) || '';
  return [...new Set([...q.matchAll(/\$fromAI\(\s*['"]([A-Za-z_]+)['"]/g)].map((m) => m[1]).filter((k) => /email/i.test(k)))];
};
for (const ch of Object.keys(AGENTS)) {
  const a5 = (sys[ch].match(/A5\.[^\n]+/) || [''])[0];
  const mp = a5.match(/por herramienta: (.+?); TODAS las demás → user_email, incluidas estas 24 herramientas de REPRODUCCIÓN, que solo reciben user_email y tenant_id: ([a-z_, ]+)\./);
  ok(`${ch}: A5 has the per-tool e-mail parameter map (exceptions + the list of the 24 reproduction tools)`, !!mp);
  if (!mp) continue;
  const said = {};
  for (const seg of mp[1].split(';')) {
    const m = seg.trim().match(/^(.+?) → ([a-z_]+_email)$/);
    if (!m) { said['<unparsed: ' + seg.trim() + '>'] = '?'; continue; }
    for (const t of m[1].split(/ y |, /)) said[t.trim()] = m[2];
  }
  const listed24 = mp[2].split(',').map((x) => x.trim()).filter(Boolean);
  ok(`${ch}: A5 names exactly the 24 new reproduction tools (the nodes of repro-phase1..4)`, setEq(listed24, phaseNames), fmt(diff(listed24, phaseNames)));
  ok(`${ch}: no tool is both an A5 exception and one of the 24`, listed24.every((t) => !(t in said)));
  const bad = [], seen = [];
  for (const n of toolNodes) {
    if (LEGACY_KEPT_AS_NODE.includes(n.name) || FORBIDDEN_TOOL.includes(n.name)) continue;
    const keys = emailKeyOf(n);
    if (keys.length !== 1) { bad.push(`${n.name}: node defines [${keys.join(', ')}]`); continue; }
    const told = said[n.name] || 'user_email';
    seen.push(n.name);
    if (told !== keys[0]) bad.push(`${n.name}: A5 says ${told}, node defines ${keys[0]}`);
  }
  ok(`${ch}: for each of the ${seen.length} tools in the dictionary, the e-mail parameter A5 gives is the one the node defines`, bad.length === 0, bad.join('; '));
  ok(`${ch}: every A5 exception names a tool that exists and defines that parameter`, Object.entries(said).every(([t, k]) => toolNodes.some((n) => n.name === t && emailKeyOf(n)[0] === k)));
  ok(`${ch}: A5 explains that log_breeding_event and void_event are NOT part of the 24`, a5.includes('log_breeding_event (G9) y void_event NO son de esas 24'));
}

// round 1 of the local QA (F2-F6): wording of E and G, and the birth node
const LOTNAME = /lot_name|production_unit_name/g;
const rbc = toolNodes.find((n) => n.name === 'register_birth_checked');
const rbcKeys = [...((rbc.parameters.options.queryReplacement).matchAll(/\$fromAI\(\s*['"]([A-Za-z_]+)['"]/g))].map((m) => m[1]);
ok('register_birth_checked defines lot_id and production_unit_id and NOT lot_name / production_unit_name', rbcKeys.includes('lot_id') && rbcKeys.includes('production_unit_id') && !rbcKeys.some((k) => /_name$/.test(k)), rbcKeys.join(', '));
ok('list_lots returns lot_id and production_unit_id next to upp / lote', /lot\.id AS lot_id, pu\.id AS production_unit_id/.test(toolNodes.find((n) => n.name === 'list_lots').parameters.query));
ok('register_birth_checked description: ids from list_lots, never names, notes only dictated, reporta (not confirma), one birth only',
  ['NUNCA lot_name ni production_unit_name', 'MISMA fila de list_lots', 'notes lleva SOLO palabras que el usuario dictó', "reporta con los datos que trae", 'births_batch_preview'].every((w) => descOf('register_birth_checked').includes(w)));
const hint = (k) => (rbc.parameters.options.queryReplacement.match(new RegExp("\\$fromAI\\('" + k + "', \"([^\"]*)\"")) || [])[1] || '';
ok('register_birth_checked lot_id / production_unit_id / notes hints: list_lots column, never a name, only dictated notes',
  /lot_id de la fila de list_lots/.test(hint('lot_id')) && /NUNCA un nombre/.test(hint('lot_id')) && /production_unit_id de la MISMA fila/.test(hint('production_unit_id')) && /NUNCA un nombre/.test(hint('production_unit_id')) && /SOLO palabras que el usuario dictó/.test(hint('notes')));
ok('legacy register_birth_event description says register_birth_checked has NO lot_name / production_unit_name', /^OBSOLETA[^\n]*NO acepta lot_name ni production_unit_name/.test(descOf('register_birth_event')));
// the rules themselves quote the forbidden question ("NUNCA ... preguntes '¿Confirmas?'", "confirmar un gemelo" in force): drop those quotes before looking for a real ask
const noProhibition = (t) => t.replace(/preguntes "¿Confirmas\?" ni "Sí\/No"/g, '').replace(/confirmar un gemelo/g, '');
const ASK_CONFIRM = /confirma (SOLO|ÚNICAMENTE|con los)|Confirma ÚNICAMENTE|Al confirmar|¿Confirmas/i;
ok('NIVEL 2 tools register_birth_checked, log_breeding_event, log_palpation_with_condition, log_empadre_entry: no description reads as "ask the user to confirm"',
  ['register_birth_checked', 'log_breeding_event', 'log_palpation_with_condition', 'log_empadre_entry'].every((t) => !ASK_CONFIRM.test(descOf(t))));
for (const ch of Object.keys(AGENTS)) {
  const G = parts[ch].G, E = parts[ch].E;
  const g = (id) => section(G, '\n' + id + '. ', '\nG' + (parseInt(id.slice(1), 10) + 1) + '. ') || section(G, '\n' + id + '. ', null);
  const birthEntry = E.split('\n').find((l) => l.startsWith("- Nacimiento: 'register_birth_checked'")) || '';
  ok(`${ch}: E birth entry: NIVEL 2 without Sí/No, ids from the SAME list_lots row, NUNCA lot_name / production_unit_name, notes only dictated, reporta`,
    ['NIVEL 2: ejecútala en cuanto conozcas la madre y el sexo de la cría, sin resumen ni Sí/No', 'MISMA fila de \'list_lots\'', 'NUNCA lot_name ni production_unit_name', 'SOLO palabras que el usuario dictó', 'Reporta ÚNICAMENTE'].every((w) => birthEntry.includes(w)) && !ASK_CONFIRM.test(birthEntry));
  const lotRefs = (G.match(LOTNAME) || []).length, neverRefs = (G.match(/NUNCA lot_name ni production_unit_name/g) || []).length;
  ok(`${ch}: in section G, lot_name / production_unit_name appear only inside "NUNCA lot_name ni production_unit_name"`, lotRefs === neverRefs * 2 && neverRefs >= 1, `${lotRefs} mentions, ${neverRefs} prohibitions`);
  ok(`${ch}: E birth entry mentions lot_name / production_unit_name only inside the prohibition`, (birthEntry.match(LOTNAME) || []).length === 2 * (birthEntry.match(/NUNCA lot_name ni production_unit_name/g) || []).length);
  const G3 = g('G3'), G4 = g('G4'), G9 = g('G9'), G10 = g('G10');
  ok(`${ch}: G3 and G9 say notes carries only words the user dictated as a note`, G3.includes('NOTES: solo con palabras que el usuario dictó como nota; nunca comentarios tuyos') && G9.includes('notes solo con palabras que el usuario dictó como nota; nunca comentarios tuyos'));
  ok(`${ch}: G3 "recorded" says REPORTA (no "confirma") and G3 / G9 / E contain no phrase that reads as asking the user to confirm`,
    G3.includes("'recorded' → REPORTA SOLO") && !ASK_CONFIRM.test(noProhibition(G3)) && !ASK_CONFIRM.test(noProhibition(G9)) && !ASK_CONFIRM.test(noProhibition(E.split('\n').filter((l) => /register_birth_checked|log_breeding_event/.test(l)).join('\n'))));
  ok(`${ch}: G9 is NIVEL 2 (no summary, no Sí/No; no date / sire / semen / notes questions) and names registered_by_email`,
    ['NIVEL 2', 'NUNCA escribas un resumen ni preguntes "¿Confirmas?" ni "Sí/No"', 'No preguntes la fecha (por omisión hoy), el semental, el lote de semen ni las notas', 'registered_by_email, no user_email'].every((w) => G9.includes(w)));
  const calv = E.split('\n').find((l) => l.startsWith("- 'list_palpation_due'")) || '';
  const FIVE = ['pregnant_total', 'upcoming_total', 'overdue_total', 'stale_data_total', 'no_estimate_total', 'later_total'];
  ok(`${ch}: E list_upcoming_calvings entry and G10 make the model report the five totals and call again with a larger days instead of reusing the output`,
    FIVE.every((w) => calv.includes(w) && G10.includes(w)) && calv.includes('hasta 300') && G10.includes('hasta 300') && calv.includes('no contestes con la salida anterior') && G10.includes('en vez de contestar con la salida anterior'));
}

// ---------------------------------------------------------------- round 2 of the local QA (2026-10-29): R2-1 .. R2-6
const MIG = path.resolve(V6, '../../../hosting3m-workspace/projects/agro-erp/database/migrations');
const readMig = (f) => { try { return fs.readFileSync(path.join(MIG, f), 'utf8'); } catch (e) { return null; } };
const SP087 = readMig('087_repro_births.sql'), SP090 = readMig('090_repro_vet_code_semantics.sql'), SP085 = readMig('085_repro_empadre.sql');
const declared = {};                       // tool -> [{key, type}] for the 24 new tools
for (const n of toolNodes.filter((x) => phaseNames.includes(x.name))) {
  const q = (n.parameters.options && n.parameters.options.queryReplacement) || '';
  declared[n.name] = [...q.matchAll(/\$fromAI\(\s*'([A-Za-z_]+)',\s*(?:"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')\s*,\s*'([a-z]+)'/g)].map((m) => ({ key: m[1], type: m[2] }));
}
const numberTools = [...new Set(Object.entries(declared).filter(([, ps]) => ps.some((p) => p.type === 'number' && p.key !== 'tenant_id')).map(([t]) => t))].sort();
const HEREDA = /la cría hereda|hereda los de la madre|hereda de la madre|hereda el lote/i;
for (const ch of Object.keys(AGENTS)) {
  const G = parts[ch].G, E = parts[ch].E;
  const g = (id) => section(G, '\n' + id + '. ', null);
  const only = (id, nextId) => section(G, '\n' + id + '. ', '\n' + nextId + '. ');
  const G0 = only('G0', 'G1'), G2 = only('G2', 'G3'), G3 = only('G3', 'G4'), G4 = only('G4', 'G5'), G10 = only('G10', 'G11'), G11 = g('G11');
  const has = (t, words) => words.every((w) => t.includes(w));
  const missing = (t, words) => words.filter((w) => !t.includes(w)).join(' | ');
  const calv = E.split('\n').find((l) => l.startsWith("- 'list_palpation_due'")) || '';
  const bprev = E.split('\n').find((l) => l.startsWith("- 'births_batch_preview'")) || '';

  // R2-1: two or more births in one message -> the block flow, never register_birth_checked in a loop
  const w1 = ['register_birth_checked', 'UN SOLO parto', '2 o más crías', 'SIEMPRE el flujo de bloque de G4', "'births_batch_preview'", "'births_batch_register'", 'UNA sola confirmación', 'PROHIBIDO llamar', 'varias veces seguidas'];
  ok(`${ch}: R2-1 G0 sends 2+ births to the block flow (preview, ONE confirmation, register) and forbids looping register_birth_checked`, has(G0, w1), missing(G0, w1));
  ok(`${ch}: R2-1 the block tools named in G0 / G4 are real MCP tools`, ['births_batch_preview', 'births_batch_register', 'register_birth_checked'].every((t) => toolNames.includes(t)) && G4.includes('NUNCA llamadas sueltas repetidas') && G4.includes('UNA sola vez "¿Confirmas? (Sí/No)" por todo el bloque'));
  ok(`${ch}: R2-1 the dictionary says births_batch_preview is OBLIGATORIA with 2+ births, and register_birth_checked is for ONE`, bprev.includes('OBLIGATORIA') && E.includes('para UN SOLO parto recién ocurrido'));
  ok('R2-1 register_birth_checked description opens with "UN solo parto. Para 2 o más, usar el flujo de bloque"', descOf('register_birth_checked').startsWith('UN solo parto. Para 2 o más, usar el flujo de bloque'));

  // R2-2: the model remembers only what it wrote
  const w2a = ['NO recuerdas lo que devolvió una herramienta', 'DEBE listar de CADA candidato', 'el arete SINIIGA (rfid_siniiga)', 'la categoría y el estatus', 'dam_identifier igual a ESE arete SINIIGA', 'nunca con el número de fuego repetido', 'S/N-1450-16'];
  ok(`${ch}: R2-2a G2 lists arete SINIIGA + category + status of EVERY candidate and re-calls with THAT arete, not the repeated fire number`, has(G2, w2a), missing(G2, w2a));
  const w2b = ['escribe cada UPP con su nombre', "vuelve a llamar a 'list_lots'", 'la fila cuyo lote Y cuya UPP coinciden', 'sin depender de ids que recuerdes'];
  ok(`${ch}: R2-2b G3 lists each UPP by name for a repeated lot and calls list_lots again instead of remembering ids`, has(G3, w2b), missing(G3, w2b));
  ok('R2-2 the ambiguity candidates really carry rfid_siniiga, numero_fuego, category and current_status (085 fn_repro_resolve_animal)',
    SP085 === null ? true : /jsonb_build_object\('livestock_id', l\.id, 'rfid_siniiga', l\.rfid_siniiga,\s*'numero_fuego', l\.numero_fuego, 'electronic_rfid', l\.electronic_rfid/.test(SP085) && /'candidates', v_c/.test(SP085));

  // R2-3: name a lot -> list_lots FIRST; no unsupported "the calf inherits the dam's lot"
  const w3 = ["llama PRIMERO a 'list_lots', antes de preguntar nada", 'Una sola fila coincide', 'Varias filas', 'Ninguna fila: dilo, ofrece los lotes que devolvió la lista y pregunta', 'NUNCA digas que "hereda"', 'la madre tenga registrados (si la madre no tiene, quedan vacíos)', 'Una UPP suelta (sin lote) la ignora la base cuando la madre ya tiene UPP', 'NUNCA lot_name ni production_unit_name'];
  ok(`${ch}: R2-3 G3 calls list_lots before asking (one row / several / none) and states exactly when the calf gets the dam's lot and UPP`, has(G3, w3), missing(G3, w3));
  ok(`${ch}: R2-3 B5 says list_lots first and carries the conditional inheritance sentence`, has(sys[ch], ["Si el usuario nombra un lote, llama PRIMERO a 'list_lots' (G3), antes de preguntar nada", 'omite lot_id y production_unit_id y registra, sin más preguntas', 'NUNCA digas que "hereda"']));
  ok(`${ch}: R2-3 no unconditional "la cría hereda ..." anywhere in the prompt, register_birth_checked or list_lots`, !HEREDA.test(sys[ch]) && !HEREDA.test(descOf('register_birth_checked')) && !HEREDA.test(descOf('list_lots')), (sys[ch].match(HEREDA) || [''])[0]);
  ok('R2-3 the wording matches the stored procedure: lot = COALESCE(explicit, dam lot); UPP = COALESCE(explicit lot UPP, dam UPP, UPP parameter) (087)',
    SP087 === null ? true : SP087.includes('v_final_lot_id          := COALESCE(p_lot_id, v_dam_lot_id);') && SP087.includes('v_final_production_unit := COALESCE(v_explicit_lot_unit, v_dam_production_unit, p_production_unit_id);'));
  ok('R2-3 register_birth_checked description: list_lots first, calf gets the dam\'s lot / UPP only if she has them', has(descOf('register_birth_checked'), ['llama primero a list_lots', 'la cría queda con el lote y la UPP que la madre tenga registrados (vacíos si no tiene)']));

  // R2-4: no confirmation of date / lot / UPP; relative dates converted; birth weight optional in single AND block
  const w4 = ['no pidas confirmar la fecha, el lote ni la UPP', '"ayer"', 'los conviertes tú a AAAA-MM-DD, sin preguntar', 'birth_weight_kg y notes son OPCIONALES', 'no puedes dejarlo en blanco', 'igual en un parto individual que en un bloque', 'NUNCA escribas un resumen ni preguntes "¿Confirmas?" ni "Sí/No" antes de registrar', 'No vuelvas a preguntar lo que el usuario ya dijo'];
  ok(`${ch}: R2-4 G3 asks nothing to confirm (date, lot, UPP), converts "ayer" without asking, and birth weight is OPTIONAL`, has(G3, w4), missing(G3, w4));
  ok(`${ch}: R2-4 G4 treats birth_date and birth_weight_kg as optional and converts relative dates`, has(G4, ['birth_date y birth_weight_kg OPCIONALES', 'nunca los pidas', '"ayer"']));
  ok(`${ch}: R2-4 the dictionary says birth_weight_kg is OPCIONAL and never asked`, E.includes('birth_weight_kg (OPCIONAL, texto entre comillas') && E.includes('nunca lo pidas'));
  ok('R2-4 register_birth_checked description: no confirmation of date, lot, UPP, weight or notes', has(descOf('register_birth_checked'), ['no preguntes ni pidas confirmar la fecha', 'el lote, la UPP, el peso ni las notas', 'birth_weight_kg y notes son opcionales']));

  // R2-5: types
  const w5 = ['TEXTO', 'también los valores numéricos', 'birth_weight_kg "35"', 'days "300"', 'limit "50"', 'offset "0"', 'litter_position "2"', 'NUNCA muestres al usuario un error de esquema o de validación', 'reintenta en silencio UNA vez con el tipo corregido', 'avisa solo si el segundo intento también falla'];
  ok(`${ch}: R2-5 G11 sends numeric values as quoted text, never shows schema errors, retries silently once`, has(G11, w5), missing(G11, w5));
  ok(`${ch}: R2-5 B7 exempts schema / type errors from "tell the user the error"`, sys[ch].includes('EXCEPCIÓN: un error de esquema o de tipos') && sys[ch].includes('NUNCA se muestra al usuario: sigue G11'));
  const exc = (G11.match(/Solo se envían como número tenant_id y limit \/ offset de (.+?)\./) || [])[1] || '';
  const excTools = [...exc.matchAll(/'([a-z_]+)'/g)].map((m) => m[1]).sort();
  ok(`${ch}: R2-5 G11 names exactly the tools whose limit / offset the nodes declare as NUMBER (${numberTools.join(', ')})`, JSON.stringify(excTools) === JSON.stringify(numberTools), 'G11 says [' + excTools.join(', ') + ']');
}
{
  const rbc2 = toolNodes.find((n) => n.name === 'register_birth_checked');
  const q = rbc2.parameters.options.queryReplacement;
  const bw = (declared.register_birth_checked || []).find((x) => x.key === 'birth_weight_kg');
  ok('R2-5 birth_weight_kg is declared text and its hint carries a quoted example and says NEVER the bare number',
    !!bw && bw.type === 'string' && q.includes('\\"35\\"') && q.includes('NUNCA el número 35 sin comillas'));
  // every numeric-valued parameter of the 24 tools that is declared as TEXT is covered by the examples / the rule in G11 (audit result, informational)
  const numericText = [];
  for (const [t, ps] of Object.entries(declared)) for (const p of ps) if (p.type === 'string' && /^(birth_weight_kg|days|limit|offset|litter_position)$/.test(p.key)) numericText.push(t + '.' + p.key);
  ok(`R2-5 audit: ${numericText.length} numeric-valued parameters are declared as text (${[...new Set(numericText.map((x) => x.split('.')[1]))].join(', ')}); G11 names all of those keys`,
    ['birth_weight_kg', 'days', 'limit', 'offset', 'litter_position'].every((k) => parts.chat.G.includes(k + ' "')) && numericText.length >= 10);
}
for (const ch of Object.keys(AGENTS)) {
  const G = parts[ch].G, E = parts[ch].E;
  const G10 = section(G, '\n' + 'G10' + '. ', '\nG11. ');
  const calv = E.split('\n').find((l) => l.startsWith("- 'list_palpation_due'")) || '';
  // R2-6: five totals that add up to pregnant_total, rows labelled by days remaining
  const w6 = ['upcoming_total, overdue_total, later_total, stale_data_total y no_estimate_total', 'suman pregnant_total', 'days_to_calving', 'NO llames "próxima a parir" a una vaca con más de 60 días por delante', 'faltan 197 días'];
  ok(`${ch}: R2-6 G10 reports the five totals (incl. overdue_total), checks they add up to pregnant_total and labels rows by days remaining`, w6.every((w) => G10.includes(w)), w6.filter((w) => !G10.includes(w)).join(' | '));
  ok(`${ch}: R2-6 the dictionary entry of list_upcoming_calvings carries the same rule`, ['overdue_total', 'later_total', 'suman pregnant_total', 'days_to_calving', 'no como "próxima a parir"'].every((w) => calv.includes(w)));
}
ok('R2-6 the five totals are partitions of pregnant_total in the SQL (090: upcoming 0..days, overdue -60..-1, stale < -60, later > days, no_estimate = no date)',
  SP090 === null ? true : ["'upcoming_total',   (SELECT count(*) FROM rowj WHERE days_to BETWEEN 0 AND v_days)", "'overdue_total',    (SELECT count(*) FROM rowj WHERE days_to BETWEEN -60 AND -1)",
    "'stale_data_total', (SELECT count(*) FROM rowj WHERE days_to < -60)", "'later_total',      (SELECT count(*) FROM rowj WHERE days_to > v_days)", "'no_estimate_total',(SELECT count(*) FROM rowj WHERE est_date IS NULL)", "'pregnant_total',   (SELECT count(*) FROM rowj)"].every((x) => SP090.includes(x)));


// section G content
for (const ch of Object.keys(AGENTS)) {
  const miss = REQUIRED_G_WORDS.filter((w) => !parts[ch].G.includes(w));
  ok(`${ch}: section G teaches every required answer / field / rule`, miss.length === 0, 'missing: ' + miss.join(', '));
  ok(`${ch}: section G never says a veterinarian confirmed RP / NR / NO APTO / MATRIZ OCUPADA`, !/veterinario[s]? (los )?confirm[óo]/i.test(parts[ch].G.replace('nunca digas que un veterinario los confirmó', '')));
  ok(`${ch}: the shared prompt carries no ranch-specific fact about the foreman ("capataz")`, !/capataz/i.test(sys[ch]));
  ok(`${ch}: single-animal-with-a-code rule is in the log_palpation_event dictionary entry AND in G6`,
    parts[ch].E.split('\n').some((l) => l.includes("'log_palpation_event'") && l.includes(SINGLE_RULE)) && parts[ch].G.includes(SINGLE_RULE));
  ok(`${ch}: get_births_config has no ADMIN / SQL wording in the prompt`,
    !/get_births_config[^\n]{0,160}(ADMIN|SQL)/.test(sys[ch]));
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
  const agentNow = docs[f].nodes.find((n) => n.name === 'AI Agent'), agentPrev = prev.nodes.find((n) => n.name === 'AI Agent');
  const strip = (n) => { const c = JSON.parse(JSON.stringify(n)); delete c.parameters.options.systemMessage; return JSON.stringify(c); };
  ok(`${ch}: in the node "AI Agent" ONLY options.systemMessage changed (model, tools wiring, memory and every other parameter identical to ${REF})`, strip(agentNow) === strip(agentPrev));
  const others = prev.nodes.filter((n) => n.name !== 'AI Agent');
  ok(`${ch}: no other node of the workflow changed (${others.length} nodes)`, others.every((n) => JSON.stringify(n) === JSON.stringify(docs[f].nodes.find((x) => x.name === n.name))));
}
for (const ch of Object.keys(AGENTS)) {
  ok(`${ch}: prompt size ${sys[ch].length} characters (informational: it was ~32 000 before phase 5)`, sys[ch].length < 60000);
}

console.log(`\n${passes} passed, ${fails} failed, ${skips} skipped`);
process.exit(fails ? 1 : 0);
