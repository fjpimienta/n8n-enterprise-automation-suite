import { PGlite } from '@electric-sql/pglite';
import fs from 'node:fs'; import path from 'node:path'; import crypto from 'node:crypto';
const here = import.meta.dirname;
const MIG = path.resolve(here, '../../../../hosting3m-workspace/projects/agro-erp/database/migrations');
const wf = JSON.parse(fs.readFileSync(path.resolve(here, '../v5-crud.json'), 'utf8'));
const nodeCode = (name) => wf.nodes.find(n => n.name === name).parameters.jsCode;
const sqlBody = f => fs.readFileSync(path.join(MIG, f), 'utf8').split('-- @@FINALIZE')[0].split('\n').filter(l => !l.startsWith('\\')).join('\n');
let pass = 0, fail = 0;
const ok = (c, name, extra = '') => { if (c) { pass++; console.log('  PASS', name); } else { fail++; console.log('  FAIL', name, extra); } };

const db = new PGlite();
await db.exec(`
CREATE TABLE companys (id_company serial PRIMARY KEY, company_name text);
INSERT INTO companys(id_company, company_name) VALUES (1,'Owner'),(2,'Hotel A'),(3,'Hotel B');
CREATE TABLE hotel_rooms (id serial PRIMARY KEY, room_number text, id_company int NOT NULL DEFAULT 2, is_active boolean DEFAULT true, created_at timestamp DEFAULT now());
CREATE TABLE hotel_reviews (id serial PRIMARY KEY, guest_name text, created_at timestamp DEFAULT now());
CREATE TABLE hotel_guests (id serial PRIMARY KEY, full_name text, id_company int NOT NULL, is_active boolean DEFAULT true, created_at timestamp DEFAULT now());
CREATE TABLE hotel_capital_injections (id serial PRIMARY KEY, amount numeric, id_company int NOT NULL, created_at timestamp DEFAULT now());
CREATE TABLE hotel_bookings (id serial PRIMARY KEY, room_id int REFERENCES hotel_rooms(id), id_company int NOT NULL, status text, check_in timestamp DEFAULT now(), created_at timestamp DEFAULT now());
CREATE TABLE hotel_maintenance_tickets (id serial PRIMARY KEY, room_id int, status varchar(20) DEFAULT 'PENDING', description text, is_active boolean DEFAULT true, created_at timestamp DEFAULT now());
INSERT INTO hotel_rooms(room_number,id_company) VALUES ('101',2),('102',3);
INSERT INTO hotel_guests(full_name,id_company) VALUES ('A1',2),('A2',2),('B1',3);
INSERT INTO hotel_capital_injections(amount,id_company) VALUES (100,2),(900,3);
INSERT INTO hotel_bookings(room_id,id_company,status) VALUES (1,2,'A'),(2,3,'B');
INSERT INTO hotel_maintenance_tickets(room_id,description) VALUES (1,'legacy t1'),(2,'legacy t2');
`);

console.log('== migration 094 on real PG (pglite)');
await db.exec(sqlBody('094_hotel_tickets_tenant.sql') + '\nCOMMIT;');
let r = await db.query(`SELECT id_company, count(*)::int n FROM hotel_maintenance_tickets GROUP BY 1`);
ok(r.rows.length === 1 && r.rows[0].id_company === 1 && r.rows[0].n === 2, '094: existing tickets get company 1');
r = await db.query(`SELECT is_nullable, column_default FROM information_schema.columns WHERE table_name='hotel_maintenance_tickets' AND column_name='id_company'`);
ok(r.rows[0].is_nullable === 'NO' && r.rows[0].column_default === '1', '094: NOT NULL DEFAULT 1');
let threw = false; try { await db.exec(sqlBody('094_hotel_tickets_tenant.sql')); } catch (e) { threw = /already exists/.test(e.message); await db.exec('ROLLBACK').catch(()=>{}); }
ok(threw, '094: second run aborts (idempotence guard)');
await db.exec(`INSERT INTO hotel_maintenance_tickets(room_id,description,id_company) VALUES (2,'B ticket',3)`);

// ---- node harness
const mk = (code) => new Function('$', 'require', '$json', code);
const node = (json) => ({ first: () => ({ json }), item: { json } });
function runBuild(code, { table, model, op, body, tenant, extra = {}, headers = {} }) {
  const cfg = { table_name: table, model_name: model || table, operation: op, primary_key: 'id', allowed_fields: extra.allowed_fields || [], default_filter: extra.default_filter || null, joins: extra.joins || [] };
  const nodes = { 'Security Validation': node(cfg), 'WebhookCRUD': node({ body, headers }), 'Extract Auth Context': node({ user: { role: 'ADMIN' }, id_company: tenant }) };
  const out = mk(code)((n) => nodes[n], require_, undefined);
  return out[0].json;
}
import { createRequire } from 'node:module'; const require_ = createRequire(import.meta.url);
const patched = nodeCode('Build Query');
const AF = {
  hotel_guests: ['id','full_name','phone','email','doc_id','vip_status','id_company','is_active'],
  hotel_capital_injections: ['id','id_company','amount','description','injection_date','created_at'],
  hotel_bookings: ['id','room_id','guest_id','check_in','check_out','status','id_company','notes'],
  hotel_maintenance_tickets: ['id','room_id','status','description','is_active'],
  hotel_rooms: ['id','room_number','is_active','id_company'], hotel_reviews: ['id','guest_name'],
};
async function exec(code, p) { const q = runBuild(code, { ...p, extra: { allowed_fields: AF[p.table], ...(p.extra||{}) } }); await db.query('BEGIN'); try { const res = await db.query(q.query, q.values); await db.query('COMMIT'); return res.rows; } catch (e) { await db.query('ROLLBACK'); throw e; } }
const names = rows => rows.map(x => x.full_name || x.description || x.room_number).sort().join(',');

let rows;
console.log('== getall');
rows = await exec(patched, { table: 'hotel_guests', op: 'getall', body: { filters: { id_company: 3 } }, tenant: 2 });
ok(names(rows) === 'A1,A2', 'client id_company=3 ignored; only company 2', names(rows));
rows = await exec(patched, { table: 'hotel_guests', op: 'getall', body: {}, tenant: 3 });
ok(names(rows) === 'B1', 'company 3 sees only its guest', names(rows));
rows = await exec(patched, { table: 'hotel_maintenance_tickets', op: 'getall', body: {}, tenant: 1 });
ok(names(rows) === 'legacy t1,legacy t2', 'tickets scoped (company 1, legacy rows after 094)', names(rows));
rows = await exec(patched, { table: 'hotel_maintenance_tickets', op: 'getall', body: {}, tenant: 3 });
ok(names(rows) === 'B ticket', 'tickets scoped (company 3)', names(rows));
rows = await exec(patched, { table: 'hotel_capital_injections', model: 'hotel_capital', op: 'getall', body: {}, tenant: 2 });
ok(rows.length === 1 && Number(rows[0].amount) === 100, 'hotel_capital (table hotel_capital_injections) scoped');
rows = await exec(patched, { table: 'hotel_bookings', op: 'getall', body: {}, tenant: 3, extra: { joins: [{ table: 'hotel_rooms', own_col: 'room_id', foreign_col: 'id' }] } });
ok(rows.length === 1 && rows[0].status === 'B', 'bookings with join scoped, no ambiguous column');
rows = await exec(patched, { table: 'hotel_rooms', op: 'getall', body: { id_company: 3 }, tenant: 2 });
ok(names(rows) === '101', 'hotel_rooms scoped; spoofed id_company ignored', names(rows));
rows = await exec(patched, { table: 'hotel_rooms', op: 'update', body: { id: 2, room_number: 'X' }, tenant: 2 });
ok(rows.length === 0, 'hotel_rooms update of another company room affects 0 rows');
rows = await exec(patched, { table: 'hotel_reviews', op: 'getall', body: {}, tenant: 2 });
ok(rows.length === 0, 'hotel_reviews (no tenant column) still works');

console.log('== getone / update / delete');
rows = await exec(patched, { table: 'hotel_guests', op: 'getone', body: { id: 3 }, tenant: 2 });
ok(rows.length === 0, 'getone of another company id returns nothing');
rows = await exec(patched, { table: 'hotel_guests', op: 'getone', body: { id: 1 }, tenant: 2 });
ok(rows.length === 1 && rows[0].full_name === 'A1', 'getone own row works');
rows = await exec(patched, { table: 'hotel_guests', op: 'update', body: { id: 3, full_name: 'HACKED', id_company: 2 }, tenant: 2 });
ok(rows.length === 0, 'update of another company row affects 0 rows');
rows = await exec(patched, { table: 'hotel_guests', op: 'update', body: { id: 1, full_name: 'A1x', id_company: 3 }, tenant: 2 });
ok(rows.length === 1 && rows[0].id_company === 2 && rows[0].full_name === 'A1x', 'update own row; client cannot move it to company 3');
rows = await exec(patched, { table: 'hotel_maintenance_tickets', op: 'delete', body: { id: 3 }, tenant: 2 });
ok(rows.length === 0, 'delete (soft) of another company ticket affects 0 rows');
rows = await exec(patched, { table: 'hotel_maintenance_tickets', op: 'delete', body: { id: 1 }, tenant: 1 });
ok(rows.length === 1 && rows[0].is_active === false, 'delete own ticket works');

console.log('== insert');
rows = await exec(patched, { table: 'hotel_guests', op: 'insert', body: { full_name: 'N1', id_company: 3 }, tenant: 2 });
ok(rows.length === 1 && rows[0].id_company === 2, 'insert with client id_company=3 is stored with token company 2');
rows = await exec(patched, { table: 'hotel_guests', op: 'insert', body: { id: 3, full_name: 'TAKEOVER' }, tenant: 2 });
ok(rows.length === 0, 'upsert onto another company row id is blocked');
rows = await db.query(`SELECT full_name, id_company FROM hotel_guests WHERE id=3`).then(x => x.rows);
ok(rows[0].full_name === 'B1' && rows[0].id_company === 3, 'company 3 row untouched after the attempts');
rows = await exec(patched, { table: 'hotel_maintenance_tickets', op: 'insert', body: { room_id: 1, description: 'T-A' }, tenant: 2 });
ok(rows[0].id_company === 2, 'ticket insert gets company 2');
rows = await exec(patched, { table: 'hotel_maintenance_tickets', op: 'insert', body: { room_id: 2, description: 'T-B' }, tenant: 3 });
ok(rows[0].id_company === 3, 'ticket insert gets company 3');
rows = await exec(patched, { table: 'hotel_guests', op: 'insert', body: { id: 1, full_name: 'A1-upsert' }, tenant: 2 });
ok(rows.length === 1 && rows[0].full_name === 'A1-upsert' && rows[0].id_company === 2, 'upsert of own row still works');

console.log('== fail-closed');
const throws = (p) => { try { runBuild(patched, { extra: { allowed_fields: ['id'] }, ...p }); return false; } catch (e) { return e.message; } };
ok(throws({ table: 'hotel_guests', op: 'getall', body: {}, tenant: null }), 'no company in token -> error');
ok(throws({ table: 'hotel_guests', op: 'getall', body: {}, tenant: 0 }), 'company 0 -> error');
ok(throws({ table: 'hotel_guests', op: 'getall', body: {}, tenant: 'x' }), 'non numeric company -> error');
ok(throws({ table: 'users', op: 'getall', body: {}, tenant: 2 }), 'table not in map (users) -> denied');
ok(throws({ table: 'companys', op: 'getall', body: {}, tenant: 2 }), 'table not in map (companys) -> denied');
ok(throws({ table: 'sp_procesar_salida_ganado', op: 'call_sp', body: {}, tenant: 2 }), 'call_sp -> denied');
rows = runBuild(patched, { table: 'hotel_guests', op: 'getall', body: { filters: { 'id_company; DROP': 1, id_company: 3 } }, tenant: 2, extra: { allowed_fields: AF.hotel_guests } });
ok(!/DROP/.test(rows.query) && rows.values.includes(2) && !rows.values.includes(3), 'injection-looking key and spoofed company never reach SQL/values');

console.log('== Extract Auth Context');
const ea = (code, { verify, model = 'hotel_guests' }) => { const nodes = { 'Get Model Name': node({ model_name: model }), 'Verify Token': verify === undefined ? { first: () => { throw new Error('not run'); } } : node(verify) }; return mk(code)((n) => nodes[n], require_, undefined)[0].json; };
const eaP = nodeCode('Extract Auth Context');
const good = (c) => ({ status: 'success', data: { id_company: c, user: { role: 'admin', user: 'u@x' } } });
let o = ea(eaP, { verify: good(2) }); ok(!o.error && o.id_company === 2 && o.user.role === 'ADMIN', 'valid token -> role + id_company 2');
o = ea(eaP, { verify: good('3') }); ok(o.id_company === 3, 'string "3" from JWT -> 3');
for (const bad of [undefined, null, 0, -1, 2.5, 'abc', '']) { o = ea(eaP, { verify: good(bad) }); ok(o.error && o.status === 403 && o.code === 'NO_TENANT', `token company ${JSON.stringify(bad)} -> NO_TENANT`); }
o = ea(eaP, { verify: undefined, model: 'companys' }); ok(!o.error && o.user.role === 'CUSTOMER' && o.id_company === null, 'public companys path keeps working (no tenant)');
o = ea(eaP, { verify: undefined, model: 'hotel_guests' }); ok(o.error && o.code === 'NO_ROLE', 'no token on a hotel model -> NO_ROLE (unchanged)');

console.log(`\nRESULT: ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
