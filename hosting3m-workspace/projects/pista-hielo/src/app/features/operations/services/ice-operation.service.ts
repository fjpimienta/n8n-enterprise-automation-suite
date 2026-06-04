import { Injectable, signal, inject, computed } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { environment } from '@env/environment';
import { PhClient } from '@core/models/client.types';
import { PhInstructor } from '@core/models/instructor.types';
import { firstValueFrom, tap, Observable, of } from 'rxjs';
import { PhTransaction } from '@core/models/transaction.types';

@Injectable({ providedIn: 'root' })
export class IceOperationsService {
  private http = inject(HttpClient);

  private PRICES = {
    GENERAL: { 30: 50, 60: 80, 0: 100, EXTRA: 30 }, // 0 = Libre
    ALUMNO: { 30: 30, 60: 50, 0: 70, EXTRA: 20 }
  };

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
  // 2. Corrige preloadCatalogs (Cerca de la línea 50)
  async preloadCatalogs() {
    if (this.dataLoaded.clients && this.dataLoaded.instructors) {
      this.catalogsLoaded.set(true);
      return;
    }

    try {
      const [clientsRes, instructorsRes, inventoryRes] = await Promise.all([
        firstValueFrom(this.http.post<{ data: PhClient[] }>(this.apiUrlClients, {
          operation: 'getall', model: 'ph_clients', where: { status: 'ACT' }
        })).catch(() => ({ data: [] })), // Captura error individual y devuelve array vacío
        firstValueFrom(this.http.post<{ data: PhInstructor[] }>(this.apiUrlInstructors, {
          operation: 'getall', model: 'ph_instructores', where: { status: 'ACT' }
        })).catch(() => ({ data: [] })),
        firstValueFrom(this.http.post<{ data: any[] }>(this.apiUrlInventory, {
          operation: 'getall', model: 'ph_inventory'
        })).catch(() => ({ data: [] }))
      ]);

      this.clientsCache.set(clientsRes?.data || []);
      this.instructorsCache.set(instructorsRes?.data || []);
      this.inventoryCache.set(inventoryRes?.data || []);

      this.dataLoaded.clients = true;
      this.dataLoaded.instructors = true;
      this.catalogsLoaded.set(true);

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

  // 1. Corrige fetchActiveSkaters (Cerca de la línea 170)
  async fetchActiveSkaters() {
    this.isLoading.set(true);
    try {
      const response = await firstValueFrom(
        this.http.post<{ data: PhTransaction[] }>(this.apiUrlTransactions, {
          operation: 'getall', model: 'transactions', where: { status: 'ACT' }
        })
      );
      // BLINDAJE: Si response o response.data es null/undefined, asigna un array vacío
      this.skatersSignal.set(response?.data ?? []);
    } catch (error) {
      console.error('❌ Error sincronizando pista:', error);
      this.skatersSignal.set([]); // Limpiamos el monitor en caso de error de red
    } finally {
      this.isLoading.set(false);
    }
  }

  startSession(payload: { skate_number: string; rental_type: string; instructor_id?: string; notes?: string; client_id?: number; duration?: number }) {
    const now = new Date();
    const timeString = now.toTimeString().split(' ')[0];

    // CAMBIO: Usamos la función local en lugar de toISOString() que usa UTC
    const localDateISO = this.getLocalDateISO(); // <--- NUEVA LÍNEA

    const fields: any = {
      transaction_type: payload.rental_type.includes('LIBRE') ? 'RENTAL' : 'CLASS',
      status: 'ACT',
      transaction_date: localDateISO, // <--- CAMBIADO (antes era dateString)
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

  /**
   * Obtiene el nombre del cliente desde el CACHÉ local usando su ID.
   * Esto evita hacer JOINs complejos en el backend.
   */
  getClientName(clientId?: number): string {
    if (!clientId) return 'Cliente Anónimo';
    const client = this.clientsCache().find(c => c.id === clientId);
    return client ? client.full_name : `Cliente #${clientId}`;
  }

  /**
   * Calcula cuánto debe pagar el cliente en este momento exacto.
   */
  calculateSessionCost(metadata: any, elapsedMinutes: number) {
    // Determinar categoría (Fallback a GENERAL si no existe)
    const rawCat = metadata.client_category || (metadata.rental_type?.includes('ALUMNO') ? 'ALUMNO' : 'GENERAL');
    const category = rawCat === 'ALUMNO' ? 'ALUMNO' : 'GENERAL';

    const duration = metadata.duration || 0; // 0 = Libre
    const rates = this.PRICES[category];

    let total = 0;
    let isOvertime = false;

    // Lógica de Cobro
    if (duration === 0) {
      // Tarifa Libre (Pago único)
      total = rates[0];
    } else {
      // Tarifa por Tiempo (30 o 60)
      total = rates[duration as 30 | 60] || rates[60];

      // Tiempo Extra (Tolerancia 5 min)
      if (elapsedMinutes > (duration + 5)) {
        isOvertime = true;
        const extraMinutes = elapsedMinutes - duration;
        const extraBlocks = Math.ceil(extraMinutes / 30); // Cobra por cada fracción de 30 min
        total += (extraBlocks * rates.EXTRA);
      }
    }

    return { total, isOvertime, categoryLabel: category };
  }

  // ==========================================================
  // 5. HELPERS PRIVADOS
  // ==========================================================

  /**
   * Genera un string de fecha local (YYYY-MM-DDTHH:mm:ss)
   * Evita el problema de UTC que cambia el día si es tarde en la noche.
   */
  private getLocalDateISO(): string {
    const now = new Date();
    const year = now.getFullYear();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    const day = String(now.getDate()).padStart(2, '0');
    const hours = String(now.getHours()).padStart(2, '0');
    const minutes = String(now.getMinutes()).padStart(2, '0');
    const seconds = String(now.getSeconds()).padStart(2, '0');

    return `${year}-${month}-${day}T${hours}:${minutes}:${seconds}`;
  }

}