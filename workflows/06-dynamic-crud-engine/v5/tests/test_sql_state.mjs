import { PGlite } from '@electric-sql/pglite'; import fs from 'node:fs';
// Runs the WHOLE state-check file (psql meta-commands and :'expect' substituted), not just the DO block.
const file = (e) => fs.readFileSync(new URL('../../../../hosting3m-workspace/projects/agro-erp/database/migrations/094_state_check.sql', import.meta.url), 'utf8')
  .split('\n').filter(l => !l.startsWith('\\')).join('\n').replace(":'expect'", `'${e}'`);
const body = f => fs.readFileSync(new URL('../../../../hosting3m-workspace/projects/agro-erp/database/migrations/' + f, import.meta.url), 'utf8').split('-- @@FINALIZE')[0].split('\n').filter(l => !l.startsWith('\\')).join('\n');
const db = new PGlite();
await db.exec(`CREATE TABLE companys(id_company int primary key); INSERT INTO companys VALUES (1);
CREATE TABLE hotel_maintenance_tickets(id serial primary key, room_id int, status text, priority text, created_at timestamp default now());
CREATE TABLE crud_models(model_name text, x int); INSERT INTO hotel_maintenance_tickets(room_id) VALUES (1);`);
let bad = 0;
const chk = async (e, pass) => { let ok = true, msg = ''; try { await db.exec(file(e)); } catch (x) { ok = false; msg = x.message; await db.exec('ROLLBACK').catch(() => {}); }
  const good = ok === pass; if (!good) bad++; console.log(good ? 'PASS' : 'FAIL', 'state', e, ok ? 'OK' : '-> ' + msg); };
await chk('before', true); await chk('applied_094', false);
await db.exec(body('094_hotel_tickets_tenant.sql') + '\nCOMMIT;');
await chk('applied_094', true); await chk('before', false); await chk('applied_095', false);
await db.exec(body('095_hotel_tickets_drop_default.sql') + '\nCOMMIT;');
await chk('applied_095', true); await chk('applied_094', false);
await db.exec(body('094_rollback.sql') + '\nCOMMIT;'); await chk('applied_094', true);
await chk('bogus', false);
console.log(bad ? 'STATE TESTS FAILED' : 'STATE TESTS OK'); process.exit(bad ? 1 : 0);
