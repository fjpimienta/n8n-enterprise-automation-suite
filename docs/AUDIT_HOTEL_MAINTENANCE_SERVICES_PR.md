# 🏨 Audit: HotelService & MaintenanceService - State, Cache, Memory Leaks & Big O

## Executive Summary

| Severity | Finding | Impact |
|----------|---------|--------|
| **CRITICAL** | RoomChecklistModal: suscripción sin `takeUntilDestroyed` | Callbacks ejecutándose sobre componente destruido; riesgo de Memory Leak y errores en runtime |
| **HIGH** | MaintenanceService: sin caché ni signals | Cada `loadTickets()` = nueva petición HTTP; componentes duplicados generarían llamadas redundantes |
| **HIGH** | HotelService.getTodayChecklist: Observable frío sin `shareReplay` | Múltiples suscriptores = múltiples peticiones HTTP idénticas |
| **MEDIUM** | MaintenanceMonitorModal: `filteredTickets` como getter impuro | Se evalúa en cada ciclo de Change Detection; debería ser `computed()` |
| **MEDIUM** | MaintenanceMonitorModal: mutación con `allTickets.sort()` | `sort()` muta el array original; puede afectar caché si se introduce |
| **LOW** | Big O: Servicios sin transformaciones O(n²) | HotelService y MaintenanceService no agrupan/filtran datos; complejidad aceptable |

**Recomendación:** Implementar caché con signals en MaintenanceService, añadir `shareReplay` o caché en getTodayChecklist, y corregir suscripciones en RoomChecklistModal.

---

## Changes Checklist

- [ ] **RoomChecklistModal:** Usar `takeUntilDestroyed()` en suscripciones a HotelService
- [ ] **MaintenanceService:** Añadir signal `tickets` + `loadTickets()` con caché; exponer `tickets` como readonly
- [ ] **HotelService:** Añadir caché por `roomId` para `getTodayChecklist` con `shareReplay(1)` o Map con TTL
- [ ] **MaintenanceMonitorModal:** Convertir `filteredTickets` en `computed()`; usar `[...data].sort()` para evitar mutación
- [ ] **MaintenanceMonitorModal:** Migrar `isLoading` a signal para reactividad correcta en zoneless

---

## Deep Technical Details

### 1. Gestión de Estado y Caché

#### HotelService

| Método | Patrón actual | Problema |
|--------|---------------|----------|
| `getTodayChecklist(roomId)` | Observable frío | Sin `shareReplay`; cada `.subscribe()` dispara nueva petición HTTP |
| `saveChecklist` / `updateChecklist` | Observable frío | Mutaciones; no invalidan caché (no existe) |
| `updateRoomStatus` | Retorna Observable sin suscripción en servicio | El componente debe suscribirse; OK |

**Flujo actual:** RoomChecklistModal abre → `getTodayChecklist(roomId).subscribe()` → 1 HTTP. Si hubiera dos modales para la misma habitación (caso extremo) o re-suscripción, habría duplicados.

**Solución:** Caché por `(roomId, date)` con TTL corto (ej. 5 min) o `shareReplay({ bufferSize: 1, refCount: true })` para la misma petición en vuelo.

---

#### MaintenanceService

| Método | Patrón actual | Problema |
|--------|---------------|----------|
| `getTickets()` | `async` → Promise; sin caché | Cada llamada = nueva petición HTTP |
| `createTicket` / `updateTicket` | Mutaciones | No invalidan estado compartido |

**Flujo actual:** MaintenanceMonitorModal en `ngOnInit` → `loadTickets()` → `getTickets()` → HTTP. El resultado se guarda en signal local del componente. No hay estado compartido a nivel servicio.

**Riesgo:** Si Dashboard mostrara dos instancias de MaintenanceMonitorModal (ej. en tabs o rutas hijas), cada una haría su propia petición. Actualmente hay una sola instancia, pero la arquitectura no escala.

**Solución:** Mover `tickets` al MaintenanceService como signal; `loadTickets()` actualiza el signal; componentes leen `maintenanceService.tickets()`. Opcional: TTL para no re-fetchear si la última carga fue hace < X segundos.

---

### 2. Fugas de Memoria y Anti-patrones

#### RoomChecklistModalComponent (consumidor de HotelService)

```typescript
ngOnInit() {
  this.hotelService.getTodayChecklist(this.room().id).subscribe({
    next: (data) => { /* ... this.isLoading = false */ },
    error: (err) => { /* ... */ }
  });
}
```

**Problemas:**

1. **Sin desuscripción:** Si el usuario cierra el modal antes de que el HTTP responda, el callback `next` se ejecutará sobre un componente ya destruido. Asignar `this.isLoading = false` puede provocar "ExpressionChangedAfterItHasBeenCheckedError" o actualizaciones en vistas destruidas.

2. **Suscripciones en saveChecklist:** `updateChecklist().subscribe()` y `saveChecklist().subscribe()` son one-shot; el Observable completa tras una emisión, por lo que se limpia solo. El riesgo es menor pero el patrón sigue siendo frágil: si el HTTP tarda y el usuario cierra el modal, el callback podría ejecutarse en un componente destruido.

**Solución:** Usar `takeUntilDestroyed()` de Angular (con `DestroyRef`):

```typescript
constructor() {
  const destroyRef = inject(DestroyRef);
  // ...
}
// En ngOnInit:
this.hotelService.getTodayChecklist(this.room().id).pipe(
  takeUntilDestroyed(this.destroyRef)
).subscribe({ ... });
```

O inyectar `DestroyRef` y pasarlo a `takeUntilDestroyed()`.

---

#### Mutación de arrays

En MaintenanceMonitorModal:

```typescript
const data = allTickets.sort((a, b) => ...);
```

`Array.prototype.sort()` **muta** el array original. `allTickets` proviene de la respuesta de la API. Si en el futuro se cachea esa respuesta, la mutación afectaría al caché compartido.

**Solución:** `const data = [...allTickets].sort(...)` para trabajar sobre una copia.

---

### 3. Big O en transformaciones

| Servicio | Método | Operación | Complejidad |
|----------|--------|-----------|-------------|
| HotelService | `getTodayChecklist` | `map()` sobre respuesta (1-2 ítems) | O(1) |
| HotelService | Resto | Sin transformaciones de listas | — |
| MaintenanceService | `request` | Pass-through | O(1) |
| MaintenanceMonitorModal | `filteredTickets` (getter) | `filter` × 2 + `filter` por room | O(n) |

**Conclusión:** No hay ciclos anidados O(n²) en los servicios. Las transformaciones son lineales.

---

## Testing Protocol

| # | Test | Expected |
|---|------|----------|
| 1 | Abrir RoomChecklistModal, cerrar antes de que cargue → sin errores en consola | Pass |
| 2 | Abrir RoomChecklistModal, cargar, cerrar, reabrir otra habitación → suscripción anterior cancelada | Pass |
| 3 | Dos componentes consumiendo MaintenanceService.tickets() → 1 sola petición HTTP (con caché) | Pass |
| 4 | getTodayChecklist con 2 suscriptores simultáneos → 1 petición HTTP (con shareReplay) | Pass |
| 5 | loadTickets → sort no muta el array original | Pass |
| 6 | filteredTickets como computed → no se recalcula si tickets/filter no cambian | Pass |

---

## Senior Checklist

- [ ] Evaluar TTL de caché para tickets (ej. 30s) vs. invalidación manual tras create/update
- [ ] Considerar `toSignal()` en componentes para migrar Observables a signals y reducir suscripciones manuales
- [ ] Revisar si AdminService.saveUser y otros `.subscribe()` en componentes necesitan `takeUntilDestroyed`

---

## Código Refactorizado

### maintenance.service.ts

```typescript
import { HttpClient } from '@angular/common/http';
import { Injectable, inject, signal, computed } from '@angular/core';
import { environment } from '@env/environment';
import { AdminService } from '@features/admin/services/admin.service';
import { lastValueFrom } from 'rxjs';

@Injectable({
  providedIn: 'root'
})
export class MaintenanceService {
  private http = inject(HttpClient);
  private apiUrl = environment.apiUrl_crud;
  private adminService = inject(AdminService);

  /** Estado centralizado; evita peticiones duplicadas cuando varios componentes piden tickets */
  private readonly _tickets = signal<any[]>([]);
  readonly tickets = this._tickets.asReadonly();

  private _loadingTickets = signal(false);
  readonly loadingTickets = this._loadingTickets.asReadonly();

  private _lastFetchTime = 0;
  private static readonly CACHE_TTL_MS = 30_000; // 30 segundos

  /** Carga tickets con caché TTL; múltiples componentes comparten el mismo estado */
  async loadTickets(forceRefresh = false): Promise<any[]> {
    const now = Date.now();
    if (!forceRefresh && this._tickets().length > 0 && (now - this._lastFetchTime) < MaintenanceService.CACHE_TTL_MS) {
      return this._tickets();
    }

    this._loadingTickets.set(true);
    try {
      const data = await this.getTickets();
      const priorityVal: Record<string, number> = { 'CRITICAL': 3, 'NORMAL': 2, 'LOW': 1 };
      const sorted = [...data].sort((a: any, b: any) =>
        (priorityVal[b.priority] || 0) - (priorityVal[a.priority] || 0)
      );
      this._tickets.set(sorted);
      this._lastFetchTime = now;
      return sorted;
    } finally {
      this._loadingTickets.set(false);
    }
  }

  /** Invalida caché tras mutación (crear/actualizar ticket) */
  invalidateTicketsCache(): void {
    this._lastFetchTime = 0;
  }

  async getTickets(filters: any = {}): Promise<any[]> {
    const payload = {
      operation: 'getall',
      table_name: 'hotel_maintenance_tickets',
      action: 'list',
      filters: filters
    };
    const result = await this.request(payload);
    return Array.isArray(result) ? result : [];
  }

  async createTicket(ticket: any): Promise<any> {
    const payload = {
      operation: 'insert',
      table_name: 'hotel_maintenance_tickets',
      fields: {
        ...ticket,
        status: 'PENDING',
        created_at: new Date().toISOString()
      }
    };
    const res = await this.request(payload);
    this.invalidateTicketsCache();
    return res;
  }

  async updateTicket(id: number, data: any): Promise<any> {
    const payload = {
      operation: 'update',
      table_name: 'hotel_maintenance_tickets',
      id: id,
      fields: data
    };
    const res = await this.request(payload);
    this.invalidateTicketsCache();
    return res;
  }

  private async request(body: any): Promise<any> {
    try {
      const res: any = await lastValueFrom(
        this.http.post(`${this.apiUrl}/hotel_maintenance_tickets`, body, {
          headers: this.adminService.getAuthHeaders()
        })
      );
      return res.data ?? [];
    } catch (error) {
      console.error('Maintenance API Error:', error);
      throw error;
    }
  }
}
```

---

### hotel.service.ts (getTodayChecklist con shareReplay)

```typescript
// Añadir al HotelService:

import { shareReplay } from 'rxjs';

/** Caché en vuelo por (roomId, date) para evitar peticiones duplicadas */
private checklistCache = new Map<string, Observable<any | null>>();

getTodayChecklist(roomId: number): Observable<any | null> {
  const today = new Date().toISOString().split('T')[0];
  const key = `${roomId}-${today}`;

  if (!this.checklistCache.has(key)) {
    const payload = {
      entity: "hotel_room_inspections",
      table_name: "hotel_room_inspections",
      operation: "getall",
      action: "list",
      filters: { room_id: roomId, inspection_date: today }
    };

    const req$ = this.http.post<any>(`${this.apiUrl_crud}/hotel_room_inspections`, payload).pipe(
      map((response: any) => {
        const data = response.data || response;
        return Array.isArray(data) && data.length > 0 ? data[0] : null;
      }),
      shareReplay({ bufferSize: 1, refCount: true })
    );
    this.checklistCache.set(key, req$);
  }
  return this.checklistCache.get(key)!;
}

/** Invalida caché de checklist tras save/update para que el próximo getTodayChecklist traiga datos frescos */
invalidateChecklistCache(roomId?: number): void {
  if (roomId) {
    const today = new Date().toISOString().split('T')[0];
    this.checklistCache.delete(`${roomId}-${today}`);
  } else {
    this.checklistCache.clear();
  }
}
```

Llamar `hotelService.invalidateChecklistCache(this.room().id)` en `handleSuccess` del RoomChecklistModal tras guardar.

---

### room-checklist-modal.component.ts (takeUntilDestroyed)

```typescript
import { Component, EventEmitter, Output, inject, input, DestroyRef } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
// ... resto de imports

export class RoomChecklistModalComponent {
  private hotelService = inject(HotelService);
  private destroyRef = inject(DestroyRef);

  // ...

  ngOnInit() {
    this.isLoading = true;
    this.hotelService.getTodayChecklist(this.room().id).pipe(
      takeUntilDestroyed(this.destroyRef)
    ).subscribe({
      next: (data) => { /* ... */ },
      error: (err) => { /* ... */ }
    });
  }

  saveChecklist() {
    this.isLoading = true;
    const obs = this.existingInspectionId
      ? this.hotelService.updateChecklist(...)
      : this.hotelService.saveChecklist(...);
    obs.pipe(takeUntilDestroyed(this.destroyRef)).subscribe({
      next: (res) => this.handleSuccess(res, this.existingInspectionId ? 'actualizado' : 'registrado'),
      error: (err) => this.handleError(err)
    });
  }
}
```

---

### maintenance-monitor-modal.component.ts (computed + signal isLoading)

```typescript
// Cambios clave:

tickets = signal<any[]>([]);
isLoading = signal(true);  // Era: isLoading = true

filteredTickets = computed(() => {
  const list = this.tickets();
  const specificRoom = this.targetRoomId();
  const filter = this.filter;
  let result = filter === 'PENDING'
    ? list.filter((t: any) => t.status !== 'RESOLVED')
    : list.filter((t: any) => t.status === 'RESOLVED');
  result = result.filter(t => t.id && (t.description || t.issue_type));
  if (specificRoom) {
    result = result.filter(t => t.room_id === specificRoom);
  }
  return result;
});

async loadTickets() {
  this.isLoading.set(true);
  try {
    const data = await this.maintenanceService.loadTickets();
    this.tickets.set(data);  // data ya viene ordenada, sin mutar original
  } catch (error) {
    console.error('Error cargando tickets:', error);
  } finally {
    this.isLoading.set(false);
  }
}
```

---

## Migración

1. MaintenanceService: Los componentes deben dejar de llamar `getTickets()` directamente y usar `loadTickets()` que actualiza el signal. Leer `maintenanceService.tickets()`.
2. MaintenanceMonitorModal: Cambiar `this.maintenanceService.getTickets()` por `this.maintenanceService.loadTickets()` y asignar a `this.tickets.set(data)`.
3. Tras `createTicket` o `updateTicket`, el servicio ya invalida caché; el componente puede llamar `loadTickets(true)` para refrescar de inmediato si lo desea.
4. RoomChecklistModal: Añadir `DestroyRef` y `takeUntilDestroyed` en todas las suscripciones a HotelService.
