import { Injectable, signal, inject, computed } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { environment } from '@env/environment';
import { PhTransaction } from '@core/models/pista.types';
import { PhClient } from '@core/models/client.types';
import { PhInstructor } from '@core/models/instructor.types';
import { firstValueFrom, tap, Observable, of } from 'rxjs';

@Injectable({ providedIn: 'root' })
export class IceOperationsService {
  private http = inject(HttpClient);

  // ==========================================================
  // 1. CONFIGURACIÓN DE ENDPOINTS
  // ==========================================================
  private apiUrl = (environment as any).apiUrl_crud || `${environment.apiUrl}/crud/v3`;
  private apiUrlTransactions = `${this.apiUrl}/transactions`;
  private apiUrlClients = `${this.apiUrl}/ph_clients`;
  private apiUrlInstructors = `${this.apiUrl}/ph_instructores`;
  private apiUrlInventory = `${this.apiUrl}/ph_inventory`;

  // ==========================================================
  // 2. ESTADO REACTIVO (SIGNALS & CACHE)
  // ==========================================================

  // -- Stores en Memoria (Evitan peticiones repetitivas) --
  private clientsCache = signal<PhClient[]>([]);
  private instructorsCache = signal<PhInstructor[]>([]);
  private inventoryCache = signal<any[]>([]);

  // -- Flags de Estado --
  private dataLoaded = { clients: false, instructors: false, inventory: false };
  public catalogsLoaded = signal<boolean>(false); // Para mostrar/ocultar el loading inicial
  public isLoading = signal<boolean>(false); // Para transacciones

  // -- Monitor de Pista --
  private skatersSignal = signal<PhTransaction[]>([]);

  // Selector derivado: Solo muestra patinadores activos
  public activeSkaters = computed(() =>
    this.skatersSignal().filter(s => s.status === 'ACT')
  );

  // ==========================================================
  // 3. MÉTODOS DE DATOS MAESTROS (CARGA & BÚSQUEDA)
  // ==========================================================

  /**
   * 🔄 PRE-CARGA DE DATOS: Descarga todos los catálogos en paralelo.
   * Se debe llamar al iniciar el componente de Entrada.
   */
  async preloadCatalogs() {
    // Si ya están cargados, no hacemos nada (ahorra datos)
    if (this.dataLoaded.clients && this.dataLoaded.instructors) {
      this.catalogsLoaded.set(true);
      return;
    }

    try {
      // Peticiones en paralelo para máxima velocidad
      const [clientsRes, instructorsRes, inventoryRes] = await Promise.all([
        firstValueFrom(this.http.post<{ data: PhClient[] }>(this.apiUrlClients, {
          operation: 'getall', model: 'ph_clients', where: { status: 'ACT' }
        })),
        firstValueFrom(this.http.post<{ data: PhInstructor[] }>(this.apiUrlInstructors, {
          operation: 'getall', model: 'ph_instructores', where: { status: 'ACT' }
        })),
        firstValueFrom(this.http.post<{ data: any[] }>(this.apiUrlInventory, {
          operation: 'getall', model: 'ph_inventory'
        }))
      ]);

      // Guardamos en Signals locales
      this.clientsCache.set(Array.isArray(clientsRes) ? clientsRes : (clientsRes.data || []));
      this.instructorsCache.set(Array.isArray(instructorsRes) ? instructorsRes : (instructorsRes.data || []));
      this.inventoryCache.set(Array.isArray(inventoryRes) ? inventoryRes : (inventoryRes.data || []));

      // Marcamos como listos
      this.dataLoaded.clients = true;
      this.dataLoaded.instructors = true;
      this.catalogsLoaded.set(true);

      console.log('✅ Catálogos listos en memoria RAM');

    } catch (error) {
      console.error('❌ Error precargando catálogos:', error);
    }
  }

  /**
   * ⚡ CREACIÓN RÁPIDA DE CLIENTE (Auto-provisioning)
   * Crea el cliente en BD y actualiza el Cache Local instantáneamente.
   */
  async createQuickClient(fullName: string): Promise<PhClient> {
    const payload = {
      full_name: fullName,
      client_category: 'GENERAL', // Por defecto entra como General
      status: 'ACT',
      created_at: new Date().toISOString()
    };

    // 1. Petición al Backend
    const response = await firstValueFrom(
      this.http.post<{ data: any }>(this.apiUrlClients, {
        operation: 'insert',
        model: 'ph_clients',
        fields: payload
      })
    );

    // 2. Normalizar respuesta (n8n a veces devuelve array o objeto)
    const newClient = Array.isArray(response) ? response[0] : (response.data ? response.data[0] : response.data);

    // 3. ¡MAGIA! Actualizamos el Cache Local (Signal)
    // Esto hace que el nuevo cliente exista inmediatamente para búsquedas futuras sin ir al servidor
    this.clientsCache.update(currentList => [...currentList, newClient]);

    return newClient;
  }

  /**
   * 🔎 Búsqueda Instantánea de Clientes (Filtra en RAM)
   */
  searchClients(term: string, category: 'ALUMNO' | 'GENERAL'): Observable<PhClient[]> {
    const list = this.clientsCache();

    // Si no hay término, devolvemos los primeros 50 para no saturar la UI
    if (!term) return of(list.filter(c => c.client_category === category).slice(0, 50));

    const lowerTerm = term.toLowerCase();

    // Filtro optimizado de JavaScript
    const filtered = list.filter(c =>
      c.status === 'ACT' &&
      c.client_category === category &&
      c.full_name.toLowerCase().includes(lowerTerm)
    );

    return of(filtered);
  }

  /**
   * 🔎 Búsqueda Instantánea de Instructores
   */
  searchInstructors(term: string): Observable<PhInstructor[]> {
    const list = this.instructorsCache();
    if (!term) return of(list);
    return of(list.filter(i => i.full_name.toLowerCase().includes(term.toLowerCase())));
  }

  /**
   * 🔎 Búsqueda Instantánea de Patines (Inventario)
   */
  searchSkates(term: string): Observable<any[]> {
    const list = this.inventoryCache();
    if (!term) return of(list.slice(0, 20));

    return of(list.filter(item =>
      (item.sku && item.sku.toString().includes(term)) ||
      (item.name && item.name.toLowerCase().includes(term.toLowerCase()))
    ));
  }

  // ==========================================================
  // 4. MÉTODOS DE OPERACIÓN (CHECK-IN / CHECK-OUT)
  // ==========================================================

  async fetchActiveSkaters() {
    this.isLoading.set(true);
    try {
      const response = await firstValueFrom(
        this.http.post<{ data: PhTransaction[] }>(this.apiUrlTransactions, {
          operation: 'getall', model: 'transactions', where: { status: 'ACT' }
        })
      );
      this.skatersSignal.set(response.data || []);
    } catch (error) {
      console.error('❌ Error sincronizando pista:', error);
    } finally {
      this.isLoading.set(false);
    }
  }

  startSession(payload: { skate_number: string; rental_type: string; instructor_id?: string; notes?: string; client_id?: number; duration?: number }) {
    const now = new Date();
    const timeString = now.toTimeString().split(' ')[0];
    const dateString = now.toISOString().split('T')[0];

    const fields: any = {
      transaction_type: payload.rental_type.includes('LIBRE') ? 'RENTAL' : 'CLASS',
      status: 'ACT',
      transaction_date: dateString,
      start_time: timeString,
      metadata: {
        skate_number: payload.skate_number,
        rental_type: payload.rental_type,
        notes: payload.notes || '',
        duration: payload.duration
      }
    };

    if (payload.client_id) fields.client_id = payload.client_id;
    if (payload.instructor_id) fields.instructor_id = Number(payload.instructor_id);

    return this.http.post<{ status: string, data: any }>(
      this.apiUrlTransactions, { operation: 'insert', model: 'transactions', fields: fields }
    ).pipe(tap(() => this.fetchActiveSkaters()));
  }

  closeSession(payload: { transactionId: number; endTime: string; finalAmount: number; paymentMethod: string }) {
    return this.http.post<{ status: string; data: any }>(
      this.apiUrlTransactions,
      {
        operation: 'update', model: 'transactions', id: payload.transactionId,
        fields: { status: 'FIN', end_time: payload.endTime, amount: payload.finalAmount, payment_method: payload.paymentMethod }
      }
    ).pipe(tap(() => this.fetchActiveSkaters()));
  }
}