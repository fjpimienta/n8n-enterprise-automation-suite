import { Injectable, inject, signal } from '@angular/core';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { catchError, of } from 'rxjs';
import { ApiResponse } from '@core/interfaces/api-response.interface';
import { environment } from '@env/environment';
import { Company } from '@core/models/company.model';
import { User } from '@core/models/user.model';
import { Guest } from '@core/models/guest.model';
import { BreedCatalog } from '@core/models/breed-catalog.model';
import { LifestageCatalog } from '@core/models/lifestage-catalog.model';
import { PendingAuthorization } from '@core/models/pending-authorization.model';
import { stripPhantomRows } from '@core/utils/gateway-empty-row.util';
import { TenantService, AuthService } from 'core-auth';

@Injectable({
  providedIn: 'root',
})
export class AdminService {
  private http = inject(HttpClient);
  private apiUrl_crud = environment.apiUrl_crud;
  private tenantService = inject(TenantService);
  private authService = inject(AuthService);
  public loadingUsers = signal<boolean>(false);
  public loadingGuests = signal<boolean>(false);
  public users = signal<User[]>([]);
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

  /* Users */
  public loadUsers() {
    const currentTenantId = this.tenantService.activeTenantId();
    this.loadingUsers.set(true);
    const payload = {
      entity: 'users',
      table_name: 'users',
      operation: 'getall',
      action: 'list',
      filters: { tenant_id: Number(currentTenantId) }
    };
    this.http.post<ApiResponse<User>>(`${this.apiUrl_crud}/users`, payload, {
      headers: this.getAuthHeaders()
    }).subscribe({
      next: (res) => {
        const data = Array.isArray(res.data) ? res.data : [];

        const validData = data.filter(u => u && u.email && u.email.trim() !== '');

        const sortedUsers = validData.sort((a, b) => {
          return (a.email || '').localeCompare(b.email || '');
        });

        this.users.set(sortedUsers);
        this.loadingUsers.set(false);
      },
      error: (err) => {
        console.error('Error en API:', err);
        this.users.set([]);
        this.loadingUsers.set(false);
      }
    });
  }

  /* Eliminar usuario (CASCADE elimina automáticamente user_companies vía FK) */
  public deleteUser(email: string) {
    const payload = {
      entity: 'users',
      table_name: 'users',
      operation: 'delete',
      email
    };
    return this.http.post<ApiResponse<any>>(`${this.apiUrl_crud}/users`, payload, {
      headers: this.getAuthHeaders()
    });
  }

  /* Guardar o actualizar usuario */
  public saveUser(user: Partial<User>, operation: 'insert' | 'update', email?: string) {
    const payload = {
      entity: 'users',
      table_name: 'users',
      operation: operation,
      email: email,
      fields: user
    };

    return this.http.post<ApiResponse<User>>(`${this.apiUrl_crud}/users`, payload, {
      headers: this.getAuthHeaders()
    });
  }

  /* Sincroniza el registro de pertenencia en user_companies (insert en alta, update en edición) */
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
          .sort((a, b) => new Date(b.fecha_resolucion ?? 0).getTime() - new Date(a.fecha_resolucion ?? 0).getTime());

        this.pendingAuthorizations.set(pending);
        this.authorizationHistory.set(history);
      }
      this.loadingAuthorizations.set(false);
    });
  }

  /**
   * Invoca `sp_resolver_autorizacion` vía el modelo Meta-CRUD `resolver_autorizacion`
   * (operation: call_sp). `resuelto_por_email` se resuelve internamente desde el usuario
   * autenticado — nunca se recibe como parámetro del caller.
   */
  public resolveAuthorization(requestId: string, decision: 'APROBADO' | 'RECHAZADO', notas?: string) {
    const payload = {
      entity: 'resolver_autorizacion',
      table_name: 'sp_resolver_autorizacion',
      operation: 'call_sp',
      fields: {
        request_id: requestId,
        decision,
        // El JWT real emitido por jwt-service (/generate-token) trae el correo bajo el
        // claim `user`, no `email` — la interfaz UserPayload de core-auth no coincide con
        // el shape real del token (verificado en microservices/jwt-service/index.js), así
        // que `.email` siempre resuelve a undefined y JSON.stringify elimina la clave del
        // payload de red por completo. Se lee el claim real directo; se conserva `.email`
        // como fallback por si ese desajuste se corrige más adelante en core-auth.
        resuelto_por_email: (this.authService.currentUser() as any)?.user ?? this.authService.currentUser()?.email,
        notas: notas || undefined
      }
    };

    return this.http.post<ApiResponse<any>>(`${this.apiUrl_crud}/resolver_autorizacion`, payload, {
      headers: this.getAuthHeaders()
    });
  }

}