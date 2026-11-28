import { HttpInterceptorFn, HttpRequest, HttpResponse } from '@angular/common/http';
import { delay, of } from 'rxjs';
import { environment } from '@env/environment';
import { DEMO_COMPANY_ID, buildDemoBookings, buildDemoRooms, buildDemoTickets } from './demo-data';
import { applyRoomUpdate, applyTicketUpdate, withRoomOverrides, withTicketOverrides } from './demo-store';

/**
 * Demo scenarios, selected with `?demo=<name>` on the page URL (QA of loading/empty/error states):
 * - `empty`: collections arrive as `data: [{}]` (the gateway's empty-collection shape).
 * - `error`: every CRUD read answers HTTP 200 with `error: true` (the Silent Error Shield case).
 * - `writeerror`: reads are normal, every write answers HTTP 200 with `error: true` (failed-write QA).
 */
export type DemoScenario = 'normal' | 'empty' | 'error' | 'writeerror';

export function scenarioFromSearch(search: string): DemoScenario {
  const value = new URLSearchParams(search).get('demo');
  return value === 'empty' || value === 'error' || value === 'writeerror' ? value : 'normal';
}

const DEMO_NOTICE = 'Modo demostración: sin escritura de datos.';

/** Unsigned, obviously fake JWT. `jwt-decode` only decodes; nothing validates the signature. */
export function buildDemoToken(role: 'ADMIN' | 'EDITOR' | 'CUSTOMER', now: Date = new Date()): string {
  const enc = (o: object) => btoa(JSON.stringify(o)).replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');
  const payload = {
    id: 9001, user: 'demo', email: 'demo@example.invalid', name: 'Usuario Demo', role,
    id_company: DEMO_COMPANY_ID, exp: Math.floor(now.getTime() / 1000) + 8 * 3600
  };
  return `${enc({ alg: 'none', typ: 'JWT' })}.${enc(payload)}.demo`;
}

const COMPANY = { id_company: DEMO_COMPANY_ID, company_name: 'Hotel Demo' };

function loginResponse(body: any, now: Date): unknown {
  const user = String(body?.user ?? '').toLowerCase();
  const pickedCompany = body?.id_company !== undefined && body?.id_company !== '' && body?.id_company !== null;
  if (user === 'multi' && !pickedCompany) {
    return {
      status: 'select_company',
      data: { companies: [
        { id_company: DEMO_COMPANY_ID, company_name: 'Hotel Demo', role: 'ADMIN' },
        { id_company: DEMO_COMPANY_ID + 1, company_name: 'Hotel Demo Norte', role: 'EDITOR' }
      ] }
    };
  }
  // `viewer` signs in with a role that has no action in the `next` UI (QA of read-only behavior).
  const role = user === 'editor' ? 'EDITOR' : user === 'viewer' ? 'CUSTOMER' : 'ADMIN';
  return { status: 'success', data: { token: buildDemoToken(role, now), company: { ...COMPANY, role } } };
}

function crudResponse(table: string, body: any, scenario: DemoScenario, now: Date): unknown {
  const operation = String(body?.operation ?? '');
  if (operation !== 'getall') {
    // The in-memory writes of the demo: room cleaning/status and ticket resolution (see demo-store.ts). Everything else is refused.
    if (operation === 'update' && scenario === 'normal' && (table === 'hotel_rooms' || table === 'hotel_maintenance_tickets')) {
      const result = table === 'hotel_rooms' ? applyRoomUpdate(body) : applyTicketUpdate(body);
      return result.ok
        ? { error: false, operation, data: [{ id: result.id, ...result.fields }], message: 'ok' }
        : { error: true, operation, data: [], message: result.message };
    }
    return { error: true, operation, data: [], message: scenario === 'writeerror' ? 'Demo: simulated write error' : DEMO_NOTICE };
  }
  if (scenario === 'error') {
    return { error: true, operation, data: [], message: 'Demo: simulated gateway error' };
  }
  if (scenario === 'empty') {
    return { error: false, operation, data: [{}], message: 'ok' };
  }
  let data: unknown[] = [];
  if (table === 'hotel_rooms') data = withRoomOverrides(buildDemoRooms());
  else if (table === 'hotel_bookings') data = buildDemoBookings(now);
  else if (table === 'hotel_maintenance_tickets') {
    const wanted = body?.fields?.status ?? body?.filters?.status;
    const roomId = Number(body?.filters?.room_id);
    data = withTicketOverrides(buildDemoTickets(now))
      .filter(t => !wanted || t.status === wanted)
      .filter(t => !Number.isInteger(roomId) || roomId <= 0 || t.room_id === roomId);
  }
  return { error: false, operation, data, message: 'ok' };
}

function route(req: HttpRequest<unknown>, scenario: DemoScenario, now: Date): unknown {
  const url = req.url;
  if (url.startsWith(environment.apiUrl_token)) return loginResponse(req.body, now);
  if (url.startsWith(environment.apiUrl_crud + '/')) {
    const table = url.slice(environment.apiUrl_crud.length + 1).split(/[?#]/)[0];
    return crudResponse(table, req.body, scenario, now);
  }
  if (url.startsWith(environment.apiUrl_ai)) {
    return { output: 'Respuesta de demostración: el asistente no está conectado.' };
  }
  return { error: true, data: [], message: 'Demo: endpoint no disponible' };
}

/**
 * Answers every HttpClient request with synthetic data. It NEVER calls `next`, so no request can
 * leave the browser through HttpClient while this interceptor is registered (fail-closed).
 */
export const demoMockInterceptor: HttpInterceptorFn = (req) => {
  const scenario = scenarioFromSearch(typeof location === 'undefined' ? '' : location.search);
  const body = route(req, scenario, new Date());
  return of(new HttpResponse({ status: 200, body })).pipe(delay(120));
};
