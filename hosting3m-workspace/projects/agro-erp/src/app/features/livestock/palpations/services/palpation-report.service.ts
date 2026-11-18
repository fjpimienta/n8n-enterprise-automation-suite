import { HttpClient, HttpErrorResponse } from '@angular/common/http';
import { Injectable, computed, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { environment } from '@env/environment';
import { AuthService, TenantService } from 'core-auth';
import { filter, firstValueFrom } from 'rxjs';
import {
  PALPATION_ALLOWED_ROLES,
  PalpationEventRow,
  PalpationHerdRow,
  ReportErrorReason,
  ReportStatus,
} from '../models/palpation.types';
import { ParseOutcome, parseEventRows, parseHerdRows } from '../utils/palpation-parse';

/** Page size sent to the gateway. The gateway's own default is 1500; we ask explicitly so the value is known. */
export const PALPATION_PAGE_SIZE = 1500;
/** Maximum pages per model. Reaching it marks the report as truncated instead of showing a partial list as complete. */
export const PALPATION_MAX_PAGES = 10;

const EVENTS_MODEL = 'vw_palpation_events';
const HERD_MODEL = 'vw_palpation_herd';
const EVENTS_KEY = 'health_log_id';
const HERD_KEY = 'livestock_id';

/** Result of loading one model. `stale` means the load was superseded (tenant or session changed) and must be dropped silently. */
type Loaded<T> =
  | { readonly kind: 'ok'; readonly rows: readonly T[]; readonly truncated: boolean }
  | { readonly kind: 'error'; readonly reason: ReportErrorReason }
  | { readonly kind: 'stale' };

/**
 * Fail-closed loader of the palpation report. Signals only; components read `status`, `events`, `herd` and `reason`.
 *
 * Rules (fail-closed):
 *  - no active tenant: no request, status `sin-tenant`;
 *  - role not in PALPATION_ALLOWED_ROLES: no request, status `sin-permiso`;
 *  - session `expired` or `grace`: no request (an expired token would make the auth interceptor log the user out);
 *  - the tenant or the session may change while a request is in flight: the answer is dropped (epoch check);
 *  - a body that is empty, not JSON, or has error:true is an error, never zero rows;
 *  - a row of another company invalidates the WHOLE response;
 *  - pages are requested with a unique sort key; a repeated key across pages is an error (unstable paging);
 *  - after PALPATION_MAX_PAGES full pages the report is `truncado`, and the rows loaded so far are kept and labelled as partial.
 *
 * The request body and the response are never logged or shown: the UI gets a generic reason only.
 */
@Injectable({ providedIn: 'root' })
export class PalpationReportService {
  private readonly http = inject(HttpClient);
  private readonly tenant = inject(TenantService);
  private readonly auth = inject(AuthService);
  private readonly crudUrl = environment.apiUrl_crud;

  /** Incremented on every load, reset, tenant change and logout. Late answers compare against it. */
  private epoch = 0;

  readonly status = signal<ReportStatus>('sin-tenant');
  readonly events = signal<readonly PalpationEventRow[]>([]);
  readonly herd = signal<readonly PalpationHerdRow[]>([]);
  readonly reason = signal<ReportErrorReason | null>(null);

  /** Rows whose result or ranch term is not recognised (events and herd). The UI shows a warning when it is above zero. */
  readonly unrecognizedCount = computed<number>(() =>
    this.events().filter(e => e.uninterpreted).length + this.herd().filter(h => h.uninterpreted).length,
  );

  readonly tenantId = computed<number | null>(() => {
    const id = this.tenant.activeTenantId();
    return typeof id === 'number' && Number.isInteger(id) && id > 0 ? id : null;
  });

  readonly role = computed<string | null>(() => this.tenant.activeTenant()?.role?.trim().toUpperCase() ?? null);

  constructor() {
    this.tenant.activeTenantChanges$.pipe(takeUntilDestroyed()).subscribe(() => this.reset());
    this.auth.sessionEvents$
      .pipe(filter(event => event.type === 'logout'), takeUntilDestroyed())
      .subscribe(() => this.reset());
  }

  /** Drops everything shown and invalidates requests in flight. */
  reset(): void {
    this.epoch += 1;
    this.events.set([]);
    this.herd.set([]);
    this.reason.set(null);
    this.status.set('sin-tenant');
  }

  /** `true` when the active company's role may read the report. */
  canRead(): boolean {
    const role = this.role();
    return role !== null && PALPATION_ALLOWED_ROLES.includes(role);
  }

  /** Loads the events and the herd of the active company. */
  async load(): Promise<void> {
    const tenantId = this.tenantId();
    if (tenantId === null) {
      this.reset();
      return;
    }
    if (!this.canRead()) {
      this.epoch += 1;
      this.events.set([]);
      this.herd.set([]);
      this.reason.set(null);
      this.status.set('sin-permiso');
      return;
    }
    const sessionBlocked = this.sessionBlock();
    if (sessionBlocked !== null) {
      this.epoch += 1;
      this.events.set([]);
      this.herd.set([]);
      this.reason.set(sessionBlocked);
      this.status.set('error');
      return;
    }

    const epoch = ++this.epoch;
    this.status.set('cargando');
    this.reason.set(null);

    const [ev, hd] = await Promise.all([
      this.loadAll<PalpationEventRow>(EVENTS_MODEL, EVENTS_KEY, tenantId, epoch, (text) => parseEventRows(text, tenantId)),
      this.loadAll<PalpationHerdRow>(HERD_MODEL, HERD_KEY, tenantId, epoch, (text) => parseHerdRows(text, tenantId)),
    ]);
    if (epoch !== this.epoch) return; // superseded: drop silently

    const failure = ev.kind === 'error' ? ev : hd.kind === 'error' ? hd : null;
    if (failure !== null) {
      this.events.set([]);
      this.herd.set([]);
      this.reason.set(failure.reason);
      this.status.set('error');
      return;
    }
    if (ev.kind !== 'ok' || hd.kind !== 'ok') return; // unreachable: stale was handled above
    this.events.set(ev.rows);
    this.herd.set(hd.rows);
    this.reason.set(null);
    if (ev.rows.length === 0 && hd.rows.length === 0) {
      this.status.set('vacio');
    } else {
      this.status.set(ev.truncated || hd.truncated ? 'truncado' : 'listo');
    }
  }

  /**
   * Timeline of one animal (drawer). Returns the parsed rows or an error reason. A single page is enough for one animal;
   * a full page is reported as truncated by the caller.
   */
  async loadHistory(livestockId: string): Promise<ParseOutcome<PalpationEventRow> & { readonly truncated?: boolean }> {
    const tenantId = this.tenantId();
    if (tenantId === null) return { ok: false, reason: 'no-tenant' };
    if (!this.canRead()) return { ok: false, reason: 'no-permission' };
    if (this.sessionBlock() !== null) return { ok: false, reason: 'session-expired' };
    const epoch = this.epoch;
    const body = {
      operation: 'getall',
      filter: { livestock_id: livestockId },
      sort_by: EVENTS_KEY,
      limit: PALPATION_PAGE_SIZE,
      offset: 0,
    };
    const text = await this.post(EVENTS_MODEL, body);
    if (epoch !== this.epoch) return { ok: false, reason: 'session-expired' };
    if (text.kind === 'failed') return { ok: false, reason: text.reason };
    const parsed = parseEventRows(text.body, tenantId);
    if (!parsed.ok) return parsed;
    return { ...parsed, truncated: parsed.rows.length >= PALPATION_PAGE_SIZE };
  }

  /** Reason to send nothing because of the session, or null when a request may be sent. */
  private sessionBlock(): ReportErrorReason | null {
    try {
      const state = this.auth.getSessionState();
      if (state === 'expired') return 'session-expired';
      if (state === 'grace') return 'network';
      return null;
    } catch {
      return 'session-expired';
    }
  }

  private async loadAll<T extends { readonly health_log_id?: string; readonly livestock_id?: string }>(
    model: string,
    key: string,
    tenantId: number,
    epoch: number,
    parse: (text: string) => ParseOutcome<T>,
  ): Promise<Loaded<T>> {
    const rows: T[] = [];
    const seen = new Set<string>();
    for (let page = 0; page < PALPATION_MAX_PAGES; page += 1) {
      const answer = await this.post(model, {
        operation: 'getall',
        sort_by: key,
        limit: PALPATION_PAGE_SIZE,
        offset: page * PALPATION_PAGE_SIZE,
      });
      if (epoch !== this.epoch) return { kind: 'stale' };
      if (answer.kind === 'failed') return { kind: 'error', reason: answer.reason };

      const parsed = parse(answer.body);
      if (!parsed.ok) return { kind: 'error', reason: parsed.reason };
      for (const row of parsed.rows) {
        const id = String((row as Record<string, unknown>)[key] ?? '');
        if (seen.has(id)) return { kind: 'error', reason: 'unexpected-shape' }; // unstable paging
        seen.add(id);
        rows.push(row);
      }
      if (parsed.rows.length < PALPATION_PAGE_SIZE) return { kind: 'ok', rows, truncated: false };
    }
    return { kind: 'ok', rows, truncated: true };
  }

  /** One POST to the gateway. Returns the raw text (the parser decides what it means) or the failure reason. */
  private async post(model: string, body: object): Promise<{ kind: 'ok'; body: string } | { kind: 'failed'; reason: ReportErrorReason }> {
    try {
      const text = await firstValueFrom(
        this.http.post(`${this.crudUrl}/${model}`, body, { responseType: 'text' }),
      );
      return { kind: 'ok', body: text ?? '' };
    } catch (e) {
      if (e instanceof HttpErrorResponse) {
        if (e.status === 0) return { kind: 'failed', reason: 'network' };
        return { kind: 'failed', reason: 'http-error' };
      }
      return { kind: 'failed', reason: 'network' };
    }
  }
}
