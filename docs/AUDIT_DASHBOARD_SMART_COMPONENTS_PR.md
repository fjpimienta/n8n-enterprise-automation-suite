# 📊 Audit: Dashboard Smart Components - Filtrado, Change Detection & Comunicación

## Executive Summary

| Severity | Finding | Impact |
|----------|---------|--------|
| **HIGH** | RoomFilters inyecta BookingService y muta `searchQuery` directamente | Acoplamiento fuerte; componente no reutilizable; viola flujo unidireccional |
| **HIGH** | Dashboard y RoomFilters sin OnPush | Ciclos de CD innecesarios en componente con muchos hijos |
| **MEDIUM** | `get isAdmin` como getter impuro | Se evalúa en cada CD; debería ser `computed()` |
| **MEDIUM** | RoomFilters: input `rooms` no usado | Código muerto; el parent no pasa `[rooms]` |
| **LOW** | BookingService.roomsWithStatus: O(rooms × reservations) | `find`/`filter`/`some` anidados por habitación; optimizable con Map |
| **INFO** | Filtrado delegado a BookingService en `computed()` | filteredRooms y groupedRooms ya memoizados y O(n) |

**Nota:** El filtrado de habitaciones vive en **BookingService** (filteredRooms, groupedRooms, roomsWithStatus). Los 4 archivos auditarán solo Dashboard y RoomFilters; las optimizaciones de BookingService se documentan como cross-cutting.

---

## Changes Checklist

- [ ] **RoomFilters:** Eliminar inyección de BookingService; usar `@Output() onSearchChange` para búsqueda
- [ ] **RoomFilters:** Eliminar input `rooms` no usado
- [ ] **Dashboard:** Pasar handler de búsqueda a RoomFilters; actualizar template
- [ ] **Dashboard:** Añadir `ChangeDetectionStrategy.OnPush`
- [ ] **Dashboard:** Convertir `get isAdmin` en `computed()`
- [ ] **RoomFilters:** Añadir `ChangeDetectionStrategy.OnPush`

---

## Deep Technical Details

### 1. Rendimiento de Filtrado

**Arquitectura actual:** El Dashboard **no** filtra habitaciones; delega en BookingService:

```
Dashboard → bookingService.groupedRooms() → filteredRooms() → roomsWithStatus()
```

| Computed | Complejidad | Memoización |
|----------|-------------|-------------|
| `roomsWithStatus` | O(rooms × reservations) | ✓ computed |
| `filteredRooms` | O(n) por filter | ✓ computed |
| `groupedRooms` | O(n) con Map | ✓ computed |

**roomsWithStatus:** Por cada habitación ejecuta `find()`, `filter()`, `sort()`, `some()` sobre `allReservations`. Con 30 habitaciones y 50 reservas ≈ 1500+ operaciones. Optimización: precalcular `Map<roomId, ReservationsForRoom>` en O(n) y hacer lookup O(1) por habitación.

**groupedRooms:** Usa `rooms.sort()` sobre arrays referenciados del Map — muta datos compartidos. Usar `[...rooms].sort()` para evitar efectos secundarios.

---

### 2. Change Detection

| Componente | Estrategia actual | Recomendación |
|------------|-------------------|---------------|
| Dashboard | Default (CheckAlways) | OnPush |
| RoomFilters | Default | OnPush |

Con `provideZonelessChangeDetection()`, la CD ya está optimizada por signals, pero **OnPush** reduce trabajo: Angular solo recorre el subárbol cuando `@Input()` cambian o hay eventos locales.

---

### 3. Comunicación de Componentes

**Flujo actual:**

| Evento | RoomFilters | Dashboard |
|--------|-------------|-----------|
| Cambio de filtro | `onFilterChange.emit(filter)` | `bookingService.filter.set($event)` ✓ |
| Búsqueda | `bookingService.searchQuery.set(value)` ✗ | — |
| Gestión usuarios | `onManageUsers.emit()` | `openUserManagement()` ✓ |
| Gestión huéspedes | `onManageGuests.emit()` | `openGuestManagement()` ✓ |
| Reservas | `onReservations.emit()` | `openReservations()` ✓ |

**Problema:** La búsqueda **bypasea** al Dashboard. RoomFilters inyecta BookingService y muta estado global. Esto genera:

- **Acoplamiento:** RoomFilters depende de BookingService; no puede usarse en otro contexto.
- **Violación de flujo unidireccional:** El padre no controla el estado de búsqueda.
- **Dificultad de testing:** Hay que mockear BookingService para probar RoomFilters.

**Solución:** Añadir `onSearchChange = output<string>()` y que el Dashboard actualice `bookingService.searchQuery.set($event)`. RoomFilters recibe `searchQuery` como `@Input()` para el valor mostrado.

---

## Testing Protocol

| # | Test | Expected |
|---|------|----------|
| 1 | RoomFilters sin BookingService inyectado → compila y funciona | Pass |
| 2 | Escribir en búsqueda → Dashboard recibe evento y actualiza filter | Pass |
| 3 | Dashboard con OnPush → cambios de signals actualizan vista | Pass |
| 4 | isAdmin como computed → solo se recalcula cuando currentUser cambia | Pass |
| 5 | Cambiar filtro → groupedRooms se actualiza (una re-evaluación) | Pass |

---

## Senior Checklist

- [ ] Evaluar optimización de `roomsWithStatus` con Map<roomId, reservations> en BookingService
- [ ] Considerar `groupedRooms` con `[...rooms].sort()` para evitar mutación
- [ ] Documentar convención: componentes presentacionales sin inyección de servicios de estado

---

## Código Refactorizado

### dashboard.component.ts

```typescript
import { ChangeDetectionStrategy, Component, inject, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router } from '@angular/router';
import { FormsModule } from '@angular/forms';
import { Booking, Guest, Room, User } from '@core/models/hotel.types';
// ... resto de imports sin cambios

@Component({
  selector: 'app-dashboard',
  standalone: true,
  imports: [CommonModule, FormsModule, CheckinFormComponent, CheckoutFormComponent, RoomCardComponent,
    RoomFiltersComponent, RoomDetailModalComponent, UserFormModalComponent, UserListComponent,
    GuestFormModalComponent, GuestListComponent, SkeletonComponent, ReservationManagerComponent,
    RoomChecklistModalComponent, ExpenseFormModalComponent, MaintenanceTicketModalComponent,
    MaintenanceMonitorModalComponent],
  templateUrl: './dashboard.component.html',
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class DashboardComponent {
  private router = inject(Router);
  private authService = inject(AuthService);
  public hotelService = inject(HotelService);
  public adminService = inject(AdminService);
  public bookingService = inject(BookingService);
  public reportService = inject(ReportService);

  viewMode = signal<'details' | 'checkin' | 'checkout_validation' | 'guest_mgmt' | 'user_mgmt' | 'reservation' | 'checklist'>('details');
  reportFilter = signal<'day' | 'week' | 'month' | 'year'>('day');
  isUserModalOpen = signal(false);
  isGuestModalOpen = signal(false);
  isExpenseModalOpen = signal(false);
  showReportModal = false;
  collapsedGroups = signal<Set<string>>(new Set());
  expandedGroups = signal<Set<string>>(new Set());
  maintenanceRoom = signal<Room | null>(null);
  showMaintenanceMonitor = false;
  maintenanceFilterRoomId: number | null = null;

  activeBooking = signal<Booking | any>(null);

  tempUser: User = this.getEmptyUser();
  tempGuest: Guest = this.getEmptyGuest();

  dailyReport = {
    total_sales: 0,
    paid_in: 0,
    pending: 0,
    total_expenses: 0,
    balance: 0,
    transactions: [] as any[],
    expenseTransactions: [] as any[],
    periodLabel: 'Hoy'
  };

  /** Computed para evitar evaluación en cada CD */
  readonly isAdmin = computed(() =>
    this.authService.hasRole('ADMIN')
  );

  // ... resto de métodos sin cambios (ngOnInit, refresh, refreshMain, onSelectRoom, etc.)
}
```

---

### dashboard.component.html (cambios en app-room-filters)

```html
<app-room-filters
  [currentFilter]="bookingService.filter()"
  [searchQuery]="bookingService.searchQuery()"
  [isAdmin]="isAdmin()"
  (onFilterChange)="bookingService.filter.set($event)"
  (onSearchChange)="bookingService.searchQuery.set($event)"
  (onManageGuests)="openGuestManagement()"
  (onManageUsers)="openUserManagement()"
  (onReservations)="openReservations()">
</app-room-filters>
```

---

### room-filters.component.ts

```typescript
import { CommonModule } from '@angular/common';
import { ChangeDetectionStrategy, Component, input, output } from '@angular/core';
import { Room } from '@core/models/hotel.types';

@Component({
  selector: 'app-room-filters',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './room-filters.component.html',
  styleUrl: './room-filters.component.css',
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class RoomFiltersComponent {
  currentFilter = input.required<string>();
  searchQuery = input<string>('');
  isAdmin = input.required<boolean>();

  onFilterChange = output<string>();
  onSearchChange = output<string>();
  onManageUsers = output<void>();
  onManageGuests = output<void>();
  onReservations = output<void>();

  filterOptions = [
    { label: '🟢 Disponible', value: 'available', activeClass: 'btn-success' },
    { label: '🔒 Ocupada', value: 'occupied', activeClass: 'btn-danger' },
    { label: '🗑️ Limpieza', value: 'dirty', activeClass: 'btn-warning' },
    { label: '🔧 Mantenimiento', value: 'maintenance', activeClass: 'btn-secondary' },
    { label: '📅 Reservada', value: 'reserved', activeClass: 'btn-info' }
  ];

  setFilter(filter: string) {
    this.onFilterChange.emit(filter);
  }

  onSearch(event: Event) {
    const input = event.target as HTMLInputElement;
    this.onSearchChange.emit(input.value);
  }

  clearSearch() {
    this.onSearchChange.emit('');
  }
}
```

---

### room-filters.component.html

```html
<div class="mb-3">

  <div class="mb-4">
    <div class="input-icon mb-3 position-relative">
      <span class="input-icon-addon ps-2">
        <svg xmlns="http://www.w3.org/2000/svg" class="icon text-muted" width="24" height="24"
          viewBox="0 0 24 24" stroke-width="2" stroke="currentColor" fill="none">
          <path stroke="none" d="M0 0h24v24H0z" fill="none" />
          <path d="M10 10m-7 0a7 7 0 1 0 14 0a7 7 0 1 0 -14 0" />
          <path d="M21 21l-6 -6" />
        </svg>
      </span>

      <input type="text" #searchInput class="form-control" placeholder="Buscar habitación..."
        [value]="searchQuery()" (input)="onSearch($event)">

      @if (searchQuery().length > 0) {
        <span class="input-icon-addon end-0 cursor-pointer text-danger pe-2"
          (click)="clearSearch(); searchInput.value = ''" title="Limpiar búsqueda">
          <svg xmlns="http://www.w3.org/2000/svg" class="icon" width="24" height="24" viewBox="0 0 24 24"
            stroke-width="3" stroke="currentColor" fill="none">
            <path stroke="none" d="M0 0h24v24H0z" fill="none" />
            <path d="M18 6l-12 12" />
            <path d="M6 6l12 12" />
          </svg>
        </span>
      }
    </div>
  </div>

  <div class="filters-scroll-container">
    @for (option of filterOptions; track option.value) {
      <button type="button" class="big-filter-btn cursor-pointer" [class.active]="currentFilter() === option.value"
        [class]="'big-filter-btn cursor-pointer filter-' + option.value" (click)="setFilter(option.value)">
        {{ option.label }}
      </button>
    }
  </div>

</div>
```

---

## Migración

1. **RoomFilters:** Quitar `inject(BookingService)` y el input `rooms`. Añadir `searchQuery` input y `onSearchChange` output.
2. **Dashboard template:** Pasar `[searchQuery]`, `(onSearchChange)` y usar `isAdmin()` en lugar de `isAdmin`.
3. **Dashboard:** Sustituir `get isAdmin` por `readonly isAdmin = computed(...)`.
4. **Dashboard & RoomFilters:** Añadir `changeDetection: ChangeDetectionStrategy.OnPush`.

**Nota:** El `clearSearch()` emite `''`. El parent debe hacer `searchInput.value = ''` para resetear el input visualmente — el `(click)` en el template ya incluye `searchInput.value = ''`; al emitir `''`, el siguiente ciclo de CD mostrará el valor vacío vía `[value]="searchQuery()"`.
