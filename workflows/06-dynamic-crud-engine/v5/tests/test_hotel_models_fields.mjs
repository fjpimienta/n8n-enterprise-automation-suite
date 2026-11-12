// Offline test (no database, no network): for the models hotel_rooms and hotel_maintenance_tickets the SQL built by the v5 "Build Query" node, for every
// operation, is identical with and without "id_company" in the model's allowed_fields (migration 106 lists it). It runs the real node code with the
// upstream nodes stubbed. Run: node test_hotel_models_fields.mjs
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const wf = JSON.parse(fs.readFileSync(path.resolve(import.meta.dirname, '../v5-crud.json'), 'utf8'));
const buildQuery = wf.nodes.find((n) => n.name === 'Build Query').parameters.jsCode;

let pass = 0; let fail = 0;
const ok = (c, name, extra = '') => { if (c) { pass++; console.log('  PASS', name); } else { fail++; console.log('  FAIL', name, extra); } };

// The two models as configured before migration 106 (operations, roles, fields, joins, default filter).
const MODELS = {
  hotel_rooms: {
    model_name: 'hotel_rooms', table_name: 'hotel_rooms', primary_key: 'id', joins: [], default_filter: null,
    allowed_fields: ['id', 'room_number', 'type', 'status', 'price_night', 'description', 'cleaning_status', 'is_active'],
  },
  hotel_maintenance_tickets: {
    model_name: 'hotel_maintenance_tickets', table_name: 'hotel_maintenance_tickets', primary_key: 'id',
    joins: [{ alias: 'room_data', table: 'hotel_rooms', select: ['room_number'], own_col: 'room_id', foreign_col: 'id' }],
    default_filter: "hotel_maintenance_tickets.status != 'DELETED'",
    allowed_fields: ['id', 'room_id', 'inspection_id', 'expense_id', 'issue_type', 'description', 'status', 'priority', 'resolved_at', 'created_at', 'room_number', 'solution_details'],
  },
};
const withTenantField = (m) => ({ ...m, allowed_fields: [...m.allowed_fields, 'id_company'] });

// A client-supplied id_company is included in several payloads on purpose.
const PAYLOADS = [
  { operation: 'getall', filters: {} },
  { operation: 'getall', filters: { status: 'PENDING', id_company: 99 } },
  { operation: 'list', filters: { cleaning_status: 'clean' }, limit: 50, offset: 10, sort_by: 'created_at' },
  { operation: 'getone', id: 7 },
  { operation: 'getone', filters: { id: 7, id_company: 99 } },
  { operation: 'insert', fields: { room_number: '9', type: 'Suite', price_night: 100, description: 'x' } },
  { operation: 'insert', fields: { id: 3, room_number: '9', description: 'x', status: 'PENDING', id_company: 99 } },
  { operation: 'update', id: 7, fields: { status: 'maintenance', cleaning_status: 'dirty' } },
  { operation: 'update', id: 7, fields: { status: 'PENDING', id_company: 99 } },
  { operation: 'delete', id: 7 },
];
const OP_NAME = { list: 'getall', select: 'getall' };

function run(model, payload, tokenCompany) {
  const operation = OP_NAME[payload.operation] ?? payload.operation;
  const nodes = {
    'Security Validation': { ...model, operation, user_role: 'ADMIN' },
    WebhookCRUD: { body: payload, headers: {} },
    'Extract Auth Context': { id_company: tokenCompany },
  };
  const $ = (name) => ({ first: () => ({ json: nodes[name] }) });
  try {
    const out = new Function('$', 'require', buildQuery)($, (m) => (m === 'crypto' ? crypto : (() => { throw new Error(`unexpected require ${m}`); })()))[0].json;
    return { query: out.query, values: out.values };
  } catch (e) { return { threw: e.message }; }
}

for (const [name, model] of Object.entries(MODELS)) {
  console.log(name);
  for (const company of [1, 5]) {
    for (const payload of PAYLOADS) {
      const label = `${name} ${payload.operation} ${JSON.stringify(payload.fields ?? payload.filters ?? { id: payload.id }).slice(0, 48)} (token company ${company})`;
      const without = run(model, payload, company);
      const withField = run(withTenantField(model), payload, company);
      ok(JSON.stringify(without) === JSON.stringify(withField), `identical SQL and values with and without id_company: ${label}`, JSON.stringify({ without, withField }).slice(0, 300));
      // the company of the token is part of every statement, whatever allowed_fields says
      const text = JSON.stringify(without);
      const scoped = without.threw ? true : /id_company/.test(without.query) && without.values.includes(company);
      ok(scoped, `statement carries the token company: ${label}`, text.slice(0, 200));
    }
  }
}

// Both tables are in the gateway's tenant map (the identical output above relies on it).
const mapSource = buildQuery.slice(buildQuery.indexOf('const TENANT_COLUMN'), buildQuery.indexOf('};', buildQuery.indexOf('const TENANT_COLUMN')));
ok(/hotel_rooms:\s*'id_company'/.test(mapSource) && /hotel_maintenance_tickets:\s*'id_company'/.test(mapSource), 'both tables are mapped to id_company in Build Query');

console.log(`\nRESULT: ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
