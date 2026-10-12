import { Injectable, inject, signal } from '@angular/core';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { catchError, of } from 'rxjs';
import { ApiResponse } from '@core/interfaces/api-response.interface';
import { environment } from '@env/environment';
import { Company } from '@core/models/company.model';
import { AccessProcedureResult, CompanyMember, MemberFormData } from '@core/models/company-member.model';
import { buildUpdateFields, normalizeEmail } from '@shared/utils/member-access.util';
import { Guest } from '@core/models/guest.model';
import { BreedCatalog } from '@core/models/breed-catalog.model';
import { LifestageCatalog } from '@core/models/lifestage-catalog.model';
import { DecisionAutorizacion, PendingAuthorization } from '@core/models/pending-authorization.model';
import { SaleData } from '@core/models/sale.model';
import { stripPhantomRows } from '@core/utils/gateway-empty-row.util';
import { parseGatewayTimestamp } from '@shared/utils/authorization-deadline.util';
import { TenantService } from 'core-auth';

/** fecha_resolucion is a UTC timestamp without offset; rows without it sort last. */
const resolutionTime = (row: PendingAuthorization): number =>
  row.fecha_resolucion ? parseGatewayTimestamp(row.fecha_resolucion).getTime() : 0;

@Injectable({
  providedIn: 'root',
})
export class AdminService {
  private http = inject(HttpClient);
  private apiUrl_crud = environment.apiUrl_crud;
  private tenantService = inject(TenantService);
  public loadingMembers = signal<boolean>(false);
  public members = signal<CompanyMember[]>([]);
  public membersError = signal<string | null>(null);
  public loadingGuests = signal<boolean>(false);
  public guests = signal<Guest[]>([]);
  public companies = signal<Company[]>([]);
  public loadingCompanies = signal<boolean>(false);
  public loadingReservations = signal<boolean>(false);

  public reservations = signal<any[]>([]);

  public breeds = signal<BreedCatalog[]>([]);
  public loadingBreeds = signal<boolean>(false);

  public lifestages = signal<LifestageCatalog[]>([]);
  public loadingLifestages = signal<boolean>(false);

  public pendingAuthorizations = signal<PendingAuthorization[]>([]);
  public authorizationHistory = signal<PendingAuthorization[]>([]);
  public loadingAuthorizations = signal<boolean>(false);
  public authorizationError = signal<string | null>(null);

  private getAuthHeaders() {
    const token = localStorage.getItem('authToken');
    return new HttpHeaders({
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`
    });
  }

  /* Companies Refactorizado: Blindaje contra nulos y errores de red */
  public loadCompanies() {
    this.loadingCompanies.set(true);

    // Verificación temprana: Si no hay token, no intentamos hacer la petición
    // para evitar saturar el backend con errores 401 obvios.
    if (!localStorage.getItem('authToken')) {
      console.warn('⚠️ loadCompanies cancelado: No hay token de autenticación disponible.');
      this.companies.set([]);
      this.loadingCompanies.set(false);
      return;
    }

    const payload = {
      entity: 'companys',
      table_name: 'companys',
      operation: 'getall',
      action: 'list',
      filters: {}
    };

    this.http.post<ApiResponse<Company>>(`${this.apiUrl_crud}/companys`, payload, {
      headers: this.getAuthHeaders()
    }).pipe(
      // 🛡️ Capturamos el error a nivel de flujo de RxJS
      catchError(error => {
        console.warn('⚠️ No se pudo cargar el catálogo de empresas:', error.message || error);
        // Retornamos un objeto "seguro" para que el subscribe no reviente
        return of({ status: 'error', data: [] } as any);
      })
    ).subscribe({
      next: (res) => {
        // 🛡️ Validación estricta de estructura antes de iterar
        if (res && Array.isArray(res.data)) {
          const sortedCompanies = res.data.sort((a: Company, b: Company) => {
            return String(a.id_company).localeCompare(String(b.id_company), undefined, { numeric: true });
          });
          this.companies.set(sortedCompanies);
        } else {
          this.companies.set([]);
        }
        this.loadingCompanies.set(false);
      },
      error: (err) => {
        // Este bloque ahora solo atrapará errores muy atípicos no cubiertos por catchError
        console.error('❌ Error no controlado en loadCompanies:', err);
        this.companies.set([]);
        this.loadingCompanies.set(false);
      }
    });
  }

  /* Obtiene el detalle completo de una UPP (incluye metadata JSONB de SINIIGA) */
  public getCompanyById(idCompany: number) {
    const payload = {
      entity: 'companys',
      table_name: 'companys',
      operation: 'getone',
      action: 'getone',
      filters: { id_company: idCompany }
    };
    return this.http.post<ApiResponse<Company>>(`${this.apiUrl_crud}/companys`, payload, {
      headers: this.getAuthHeaders()
    });
  }

  /* Alta o actualización de una UPP (Rancho) */
  public saveCompany(company: Partial<Company>, operation: 'insert' | 'update', idCompany?: number) {
    const payload = {
      entity: 'companys',
      table_name: 'companys',
      operation,
      id_company: idCompany,
      fields: company
    };
    return this.http.post<ApiResponse<Company>>(`${this.apiUrl_crud}/companys`, payload, {
      headers: this.getAuthHeaders()
    });
  }

  /**
   * Members of the ACTIVE company from `vw_company_members` (model `company_members`, migration 073):
   * never carries the password, and the gateway scopes it to `x-tenant-id`. Fail-closed: without a
   * resolved active company nothing is requested and the list stays empty.
   */
  public loadMembers(): void {
    const idCompany = this.tenantService.activeTenantId();
    if (!idCompany) {
      this.members.set([]);
      return;
    }

    this.loadingMembers.set(true);
    this.membersError.set(null);

    const payload = {
      entity: 'company_members',
      table_name: 'vw_company_members',
      operation: 'getall',
      filters: { id_company: idCompany }
    };

    this.http.post<ApiResponse<CompanyMember>>(`${this.apiUrl_crud}/company_members`, payload, {
      headers: this.getAuthHeaders()
    }).pipe(
      catchError(() => {
        this.membersError.set('No se pudo conectar con el servicio de personal.');
        return of<ApiResponse<CompanyMember>>({ error: true, operation: 'getall', message: '', data: [] });
      })
    ).subscribe(res => {
      // A response for a company that is no longer the active one is discarded.
      if (this.tenantService.activeTenantId() !== idCompany) return;

      // Fail-closed: only `error === false` with a `data` array is a valid list (a null body or an n8n
      // failure payload is an error, never "no members").
      if (!res || res.error !== false || !Array.isArray(res.data)) {
        this.membersError.set((res?.error === true && res.message) || this.membersError() || 'El servidor no confirmó la consulta del personal.');
        this.members.set([]);
      } else {
        const rows = stripPhantomRows(res.data, 'email')
          .filter(m => Number(m.id_company) === Number(idCompany));
        this.members.set(rows.sort((a, b) => (a.names || a.email).localeCompare(b.names || b.email)));
      }
      this.loadingMembers.set(false);
    });
  }

  /**
   * sp_access_add_user (call_sp). Creates the account only if the email does not exist yet; an
   * existing account is added to the company untouched (name/password are NOT changed). The actor
   * email is taken by the gateway from the JWT; the company from `x-tenant-id`.
   */
  public addMember(data: MemberFormData) {
    return this.callAccessProcedure('access_add_user', 'sp_access_add_user', {
      email: normalizeEmail(data.email),
      names: data.names.trim(),
      lastname: (data.lastname ?? '').trim(),
      phone: (data.phone ?? '').trim(),
      role: data.role,
      password: data.password
    });
  }

  /** sp_access_update_member (call_sp). Fields come from `buildUpdateFields` (null = keep current). */
  public updateMember(fields: ReturnType<typeof buildUpdateFields>) {
    return this.callAccessProcedure('access_update_member', 'sp_access_update_member', fields);
  }

  /** sp_access_set_active (call_sp): this company's membership only; never deletes, never touches the account. */
  public setMemberActive(email: string, isActive: boolean) {
    return this.callAccessProcedure('access_set_active', 'sp_access_set_active', { email, is_active: isActive });
  }

  private callAccessProcedure(model: string, procedure: string, fields: Record<string, unknown>) {
    const payload = { entity: model, table_name: procedure, operation: 'call_sp', fields };
    return this.http.post<{ error: boolean; message: string; data: AccessProcedureResult | null }>(
      `${this.apiUrl_crud}/${model}`, payload, { headers: this.getAuthHeaders() }
    );
  }

  /**
   * @deprecated Since migration 073 the gateway rejects writes to `user_companies` (memberships are
   * written only through sp_access_*). Its only caller (tenant-list, new company) never reaches it:
   * the JWT carries the email under `user`, not `email`. Granting the creator access to a new company
   * moves to the Users & Access module (platform admin, migration 074).
   */
  public saveUserCompany(
    email: string,
    idCompany: number,
    role: string,
    isActive = true,
    operation: 'insert' | 'update' = 'insert'
  ) {
    const payload = {
      entity: 'user_companies',
      table_name: 'user_companies',
      operation,
      email,
      id_company: idCompany,
      fields: { email, id_company: idCompany, role, is_active: isActive }
    };

    return this.http.post<ApiResponse<any>>(`${this.apiUrl_crud}/user_companies`, payload, {
      headers: this.getAuthHeaders()
    });
  }

  /* Breed Catalog (cattle_breed_catalog) — catálogo global de estándares zootécnicos por raza */
  public loadBreeds() {
    this.loadingBreeds.set(true);

    const payload = {
      entity: 'cattle_breed_catalog',
      table_name: 'cattle_breed_catalog',
      operation: 'getall',
      action: 'list',
      filters: {}
    };

    this.http.post<ApiResponse<BreedCatalog>>(`${this.apiUrl_crud}/cattle_breed_catalog`, payload, {
      headers: this.getAuthHeaders()
    }).subscribe({
      next: (res) => {
        const rawData = Array.isArray(res.data) ? res.data : [];
        const data = stripPhantomRows(rawData, 'id');
        const sortedBreeds = data.sort((a, b) => a.raza_grupo.localeCompare(b.raza_grupo));
        this.breeds.set(sortedBreeds);
        this.loadingBreeds.set(false);
      },
      error: (err) => {
        console.error('Error al cargar el catálogo de razas:', err);
        this.breeds.set([]);
        this.loadingBreeds.set(false);
      }
    });
  }

  public getBreedById(id: string) {
    const payload = {
      entity: 'cattle_breed_catalog',
      table_name: 'cattle_breed_catalog',
      operation: 'getone',
      action: 'getone',
      filters: { id }
    };
    return this.http.post<ApiResponse<BreedCatalog>>(`${this.apiUrl_crud}/cattle_breed_catalog`, payload, {
      headers: this.getAuthHeaders()
    });
  }

  public saveBreed(breed: Partial<BreedCatalog>, operation: 'insert' | 'update', id?: string) {
    const payload = {
      entity: 'cattle_breed_catalog',
      table_name: 'cattle_breed_catalog',
      operation,
      id,
      fields: breed
    };
    return this.http.post<ApiResponse<BreedCatalog>>(`${this.apiUrl_crud}/cattle_breed_catalog`, payload, {
      headers: this.getAuthHeaders()
    });
  }

  public deleteBreed(id: string) {
    const payload = {
      entity: 'cattle_breed_catalog',
      table_name: 'cattle_breed_catalog',
      operation: 'delete',
      id
    };
    return this.http.post<ApiResponse<any>>(`${this.apiUrl_crud}/cattle_breed_catalog`, payload, {
      headers: this.getAuthHeaders()
    });
  }

  /* Lifestage Catalog (cattle_lifestage_catalog) — catálogo global de transiciones de etapa de vida */
  public loadLifestages() {
    this.loadingLifestages.set(true);

    const payload = {
      entity: 'cattle_lifestage_catalog',
      table_name: 'cattle_lifestage_catalog',
      operation: 'getall',
      action: 'list',
      filters: {}
    };

    this.http.post<ApiResponse<LifestageCatalog>>(`${this.apiUrl_crud}/cattle_lifestage_catalog`, payload, {
      headers: this.getAuthHeaders()
    }).subscribe({
      next: (res) => {
        const data = Array.isArray(res.data) ? res.data : [];
        const sortedLifestages = data.sort((a, b) => a.categoria_origen.localeCompare(b.categoria_origen));
        this.lifestages.set(sortedLifestages);
        this.loadingLifestages.set(false);
      },
      error: (err) => {
        console.error('Error al cargar el catálogo de etapas de vida:', err);
        this.lifestages.set([]);
        this.loadingLifestages.set(false);
      }
    });
  }

  public getLifestageById(id: string) {
    const payload = {
      entity: 'cattle_lifestage_catalog',
      table_name: 'cattle_lifestage_catalog',
      operation: 'getone',
      action: 'getone',
      filters: { id }
    };
    return this.http.post<ApiResponse<LifestageCatalog>>(`${this.apiUrl_crud}/cattle_lifestage_catalog`, payload, {
      headers: this.getAuthHeaders()
    });
  }

  public saveLifestage(lifestage: Partial<LifestageCatalog>, operation: 'insert' | 'update', id?: string) {
    const payload = {
      entity: 'cattle_lifestage_catalog',
      table_name: 'cattle_lifestage_catalog',
      operation,
      id,
      fields: lifestage
    };
    return this.http.post<ApiResponse<LifestageCatalog>>(`${this.apiUrl_crud}/cattle_lifestage_catalog`, payload, {
      headers: this.getAuthHeaders()
    });
  }

  public deleteLifestage(id: string) {
    const payload = {
      entity: 'cattle_lifestage_catalog',
      table_name: 'cattle_lifestage_catalog',
      operation: 'delete',
      id
    };
    return this.http.post<ApiResponse<any>>(`${this.apiUrl_crud}/cattle_lifestage_catalog`, payload, {
      headers: this.getAuthHeaders()
    });
  }

  /* Guarda los cambios de un huésped (nuevo o editado) */
  /* Genera un ID interno único si no hay documento */
  public generateInternalId(): string {
    return `INT-${Date.now()}`;
  }

  /* Genera un email ficticio único si es necesario */
  public generateDummyEmail(): string {
    return `no-email-${Date.now()}@hosting3m.com`;
  }

  /**
   * Autorizaciones Pendientes (mortandad/venta). Fail-closed: sin tenant activo resuelto,
   * no se llama al gateway y ambas listas quedan vacías — nunca se asume el tenant.
   *
   * El modelo `pending_authorizations` no expone `created_at`, así que el `getall` del
   * gateway (su ORDER BY por defecto es literalmente `created_at`) rompe sin `sort_by`
   * explícito — se envía siempre `sort_by: 'fecha_solicitud'`.
   *
   * El gateway tampoco soporta un operador "distinto de" en los filtros (solo
   * `_gte/_lte/_gt/_lt` o igualdad), así que no se puede pedir `estado != 'PENDIENTE'` en
   * el servidor: se trae todo el tenant en una sola llamada y se separa aquí.
   */
  public loadAuthorizations(): void {
    const idCompany = this.tenantService.activeTenantId();
    if (!idCompany) {
      this.pendingAuthorizations.set([]);
      this.authorizationHistory.set([]);
      return;
    }

    this.loadingAuthorizations.set(true);
    this.authorizationError.set(null);

    const payload = {
      entity: 'pending_authorizations',
      table_name: 'pending_authorizations',
      operation: 'getall',
      filters: { id_company: idCompany },
      sort_by: 'fecha_solicitud'
    };

    this.http.post<ApiResponse<PendingAuthorization>>(`${this.apiUrl_crud}/pending_authorizations`, payload, {
      headers: this.getAuthHeaders()
    }).pipe(
      catchError(() => {
        this.authorizationError.set('No se pudo conectar con el servicio de autorizaciones.');
        return of<ApiResponse<PendingAuthorization>>({ error: true, operation: 'getall', message: '', data: [] });
      })
    ).subscribe(res => {
      if (res.error) {
        this.authorizationError.set(res.message || 'El servidor reportó un error al consultar las autorizaciones.');
        this.pendingAuthorizations.set([]);
        this.authorizationHistory.set([]);
      } else {
        const rows = stripPhantomRows(Array.isArray(res.data) ? res.data : [], 'id');

        const pending = rows.filter(r => r.estado === 'PENDIENTE');
        const history = rows
          .filter(r => r.estado !== 'PENDIENTE')
          .sort((a, b) => resolutionTime(b) - resolutionTime(a));

        this.pendingAuthorizations.set(pending);
        this.authorizationHistory.set(history);
      }
      this.loadingAuthorizations.set(false);
    });
  }

  /**
   * Calls `sp_resolver_autorizacion` through the Meta-CRUD model `resolver_autorizacion`
   * (operation: call_sp). No actor email is sent: the gateway takes it from the verified JWT
   * and overwrites any value in the body (migration 069). Only an active ADMIN of the company
   * may resolve; RECHAZADO and APROBADO_CON_EXCEPCION require `notas`. Approving a VENTA requires
   * `datosVenta` (migration 071, P0021); it is ignored for BAJA_MORTANDAD and RECHAZADO.
   */
  public resolveAuthorization(requestId: string, decision: DecisionAutorizacion, notas?: string, datosVenta?: SaleData) {
    const payload = {
      entity: 'resolver_autorizacion',
      table_name: 'sp_resolver_autorizacion',
      operation: 'call_sp',
      fields: {
        request_id: requestId,
        decision,
        notas: notas || undefined,
        datos_venta: datosVenta
      }
    };

    return this.http.post<ApiResponse<any>>(`${this.apiUrl_crud}/resolver_autorizacion`, payload, {
      headers: this.getAuthHeaders()
    });
  }

  /**
   * Calls `sp_cancelar_autorizacion` through the Meta-CRUD model `cancelar_autorizacion`
   * (operation: call_sp). Only the requester may cancel, with a mandatory reason, while the
   * request is PENDIENTE — enforced by the SP. No actor email is sent (taken from the JWT).
   */
  public cancelAuthorization(requestId: string, motivo: string) {
    const payload = {
      entity: 'cancelar_autorizacion',
      table_name: 'sp_cancelar_autorizacion',
      operation: 'call_sp',
      fields: {
        request_id: requestId,
        motivo
      }
    };

    return this.http.post<ApiResponse<any>>(`${this.apiUrl_crud}/cancelar_autorizacion`, payload, {
      headers: this.getAuthHeaders()
    });
  }

}