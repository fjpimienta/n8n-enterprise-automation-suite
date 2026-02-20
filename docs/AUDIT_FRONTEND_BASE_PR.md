# 🎯 Audit: Frontend Base - Sidebar RBAC, Main Layout CD & Data Utils Big O

## Executive Summary

| Severity | Finding | Impact |
|----------|---------|--------|
| **CRITICAL** | Sidebar sin RBAC reactivo | Menú muestra "Finanzas" a usuarios no-ADMIN; incoherencia con roleGuard; UX confusa |
| **HIGH** | Main Layout sin OnPush | Cambios de detección innecesarios; `isMobileMenuOpen` no usado (dead code) |
| **MEDIUM** | DateUtilsService: `todayStr` recrea Date en cada acceso | Micro-overhead si se usa en bucles o templates con alta frecuencia |
| **LOW** | getRoomNumber O(n²) en DailyReport | Llamada O(n) dentro de @for → O(transactions × rooms); patrón replicable |

**Nota:** El AuthService usa **signals** (no Observables). No hay riesgo de Memory Leaks por suscripciones; el Sidebar debe consumir signals vía `computed()` para filtrar menú por rol.

---

## Changes Checklist

- [ ] **Sidebar:** Añadir `visibleMenu` computed que filtre secciones/ítems según `authService.hasRole()` o `authService.isAdmin()`
- [ ] **Sidebar:** Renderizar `visibleMenu` en lugar de `menu` estático
- [ ] **Main Layout:** Añadir `ChangeDetectionStrategy.OnPush` y eliminar `isMobileMenuOpen` (dead code)
- [ ] **DateUtilsService:** Memoizar `todayStr` por día natural (opcional, baja prioridad)
- [ ] **Data Utils (cross-cutting):** Crear `buildIdLookupMap<T>()` para patrones ID→objeto O(1); aplicar en DailyReport

---

## Deep Technical Details

### 1. Sidebar: RBAC Reactivo y Memory Leaks

**Problema actual:** El menú es un array estático. No hay filtrado por rol:

```typescript
menu: NavSection[] = [
  // ...
  { title: 'FINANZAS', items: [{ label: 'Caja y Gastos', route: '/dashboard/finanzas', icon: 'wallet' }] }
];
```

La ruta `/dashboard/finanzas` está protegida por `roleGuard(['ADMIN'])`, pero el Sidebar **muestra** el enlace a todos. Usuario EDITOR ve el ítem, hace clic → redirect a `/unauthorized`. **Incoherencia visual vs. seguridad.**

**AuthService usa signals, no Observables:** No hay `subscribe()` ni `async` pipe. Por tanto, **no hay riesgo de Memory Leaks** por desuscripciones. La solución correcta es un `computed()` que derive el menú visible:

```typescript
visibleMenu = computed(() => {
  const isAdmin = this.authService.isAdmin();
  return this.menu
    .map(section => ({
      ...section,
      items: section.items.filter(item =>
        item.route.includes('/finanzas') ? isAdmin : true
      )
    }))
    .filter(section => section.items.length > 0);
});
```

**Complejidad:** O(sections × items) por re-evaluación, típicamente 3×6 ≈ 18 operaciones. Aceptable. El `computed` solo se re-evalúa cuando `currentUser` cambia (logout/login).

---

### 2. Main Layout: Change Detection Strategy

**Problema actual:**

```typescript
@Component({
  // Sin changeDetection → Default (CheckAlways)
})
export class MainLayoutComponent {
  isMobileMenuOpen = false;  // ⚠️ Nunca usado; el template usa isSidebarOpen()
  isSidebarOpen = signal(false);
}
```

- **Default strategy:** Angular reevalúa el componente en cada ciclo de CD (zoneless: en cada tick de signals).
- **Dead code:** `isMobileMenuOpen` no se usa. El template usa `isSidebarOpen()` (signal).

**App usa `provideZonelessChangeDetection()`:** Con zoneless, la CD ya está optimizada por signals. Aun así, **OnPush** reduce trabajo en componentes que solo dependen de `@Input()` y eventos: Angular no recorrerá el subárbol si los inputs no han cambiado.

**Recomendación:** Añadir `changeDetection: ChangeDetectionStrategy.OnPush` y eliminar `isMobileMenuOpen`.

---

### 3. Data Utils (DateUtilsService): Big O

**Archivo actual:** `data-utils.service.ts` expone `DateUtilsService` (utilidades de fecha, no transformaciones de datos genéricas).

| Método | Complejidad | Nota |
|--------|-------------|------|
| `todayStr` | O(1) | Crea `new Date()` en cada acceso; si se llama en un loop o en muchos componentes por ciclo, overhead mínimo pero evitable |
| `formatToInputDate` | O(1) | Correcto |

**Mejora opcional:** Memoizar `todayStr` por día natural para evitar recalcular si la fecha no ha cambiado.

---

### 4. Patrón O(n²) Cross-Cutting: getRoomNumber en DailyReport

**Fuera de data-utils pero relevante:** En `daily-report-modal.component.ts`:

```typescript
getRoomNumber(id: number): string {
  const found = this.bookingService.rooms().find((r: any) => r.id === id);
  return found ? found.room_number : 'N/A';
}
```

Y en el template:

```html
@for (t of reportData().transactions; track t.id) {
  <td>Hab. {{ getRoomNumber(t.room_id) }}</td>
}
```

**Complejidad:** Por cada fila de la tabla se ejecuta `find()` sobre `rooms()` → O(transactions × rooms). Con 50 transacciones y 30 habitaciones ≈ 1500 comparaciones por render.

**Solución:** Construir un `Map<id, room_number>` una vez (en computed o al cargar datos) y hacer lookup O(1):

```typescript
roomNumberMap = computed(() => {
  const map = new Map<number, string>();
  this.bookingService.rooms().forEach(r => map.set(r.id, r.room_number));
  return map;
});
// En template: roomNumberMap().get(t.room_id) ?? 'N/A'
```

**Propuesta para data-utils:** Añadir función genérica reutilizable:

```typescript
buildIdLookupMap<T extends { id: number }>(items: T[], valueKey: keyof T): Map<number, T[keyof T]> {
  const map = new Map<number, T[keyof T]>();
  items.forEach(item => map.set(item.id, item[valueKey]));
  return map;
}
```

---

## Testing Protocol

| # | Test | Expected |
|---|------|----------|
| 1 | Usuario ADMIN ve ítem "Caja y Gastos" en Sidebar | Pass |
| 2 | Usuario EDITOR no ve ítem "Caja y Gastos" en Sidebar | Pass |
| 3 | Tras logout, menú se actualiza (computed re-evalúa) | Pass |
| 4 | Main Layout con OnPush: toggle sidebar sigue funcionando | Pass |
| 5 | DailyReport con 100 transacciones: render < 100ms (Chrome DevTools) | Pass |
| 6 | DateUtilsService.todayStr llamado 1000× en mismo día: mismo valor | Pass |

---

## Senior Checklist

- [ ] Definir convención: ¿menú con `roles?: string[]` por ítem para escalar a más rutas protegidas?
- [ ] Evaluar migrar `isSidebarOpen` a servicio compartido si se usa en múltiples layouts
- [ ] Documentar en ADR el uso de signals vs Observables para estado de auth/UI

---

## Código Refactorizado

### sidebar.component.ts

```typescript
import { Component, inject, output, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router, RouterLink, RouterLinkActive } from '@angular/router';
import { AuthService } from '@core/services/auth.service';
import { ThemeService } from '@core/services/theme.service';

interface NavItem {
  label: string;
  route: string;
  icon: string;
  /** Si se define, solo usuarios con este rol ven el ítem */
  requiredRole?: string;
}

interface NavSection {
  title: string;
  items: NavItem[];
}

@Component({
  selector: 'app-sidebar',
  standalone: true,
  imports: [CommonModule, RouterLink, RouterLinkActive],
  templateUrl: './sidebar.component.html',
  styleUrls: ['./sidebar.component.scss']
})
export class SidebarComponent {
  private authService = inject(AuthService);
  private router = inject(Router);
  public themeService = inject(ThemeService);
  toggleMenu = output<void>();
  closeMenu = output<void>();
  linkClicked = output<void>();

  private readonly menu: NavSection[] = [
    {
      title: 'OPERACIONES',
      items: [
        { label: 'Dashboard', route: '/dashboard', icon: 'layout-dashboard' },
        { label: 'Mantenimiento', route: '/dashboard/mantenimiento', icon: 'tool' },
        { label: 'Reservas', route: '/dashboard/reservas', icon: 'calendar' }
      ]
    },
    {
      title: 'ADMINISTRACIÓN',
      items: [
        { label: 'Huéspedes', route: '/dashboard/huespedes', icon: 'users' },
        { label: 'Personal', route: '/dashboard/personal', icon: 'user-check' },
        { label: 'Inventario', route: '/dashboard/inventario', icon: 'box' }
      ]
    },
    {
      title: 'FINANZAS',
      items: [
        { label: 'Caja y Gastos', route: '/dashboard/finanzas', icon: 'wallet', requiredRole: 'ADMIN' }
      ]
    }
  ];

  /** Menú filtrado por RBAC; se re-evalúa cuando currentUser cambia (sin memory leaks) */
  readonly visibleMenu = computed(() => {
    return this.menu
      .map(section => ({
        ...section,
        items: section.items.filter(item => {
          if (!item.requiredRole) return true;
          return this.authService.hasRole(item.requiredRole);
        })
      }))
      .filter(section => section.items.length > 0);
  });

  handleLinkClick() {
    this.linkClicked.emit();
  }

  onLogout() {
    this.authService.logout();
    this.router.navigate(['/login']);
    this.handleLinkClick();
  }
}
```

---

### sidebar.component.html

```html
<div class="sidebar-content">

  <div class="sidebar-header">
    <div class="logo-area">
      <h2>Hotel San José</h2>
    </div>
    <button class="toggle-btn" (click)="toggleMenu.emit()">
      <i class="icon ti ti-menu-2"></i>
    </button>
  </div>

  <div class="nav-scroll-area">
    @for (section of visibleMenu(); track section.title) {
      <div class="nav-section">
        <span class="section-title">{{ section.title }}</span>
        @for (item of section.items; track item.label) {
          <a [routerLink]="item.route" routerLinkActive="active" (click)="handleLinkClick()"
            [routerLinkActiveOptions]="{exact: item.route === '/dashboard'}" class="nav-item">
            <i class="icon ti ti-{{ item.icon }}"></i>
            <span class="label">{{ item.label }}</span>
          </a>
        }
      </div>
    }
  </div>

  <div class="sidebar-footer">
    <button class="theme-btn" (click)="themeService.toggleTheme()">
      @if (themeService.currentTheme() === 'dark') {
        <i class="icon ti ti-sun"></i>
        <span>Modo Claro</span>
      } @else {
        <i class="icon ti ti-moon"></i>
        <span>Modo Oscuro</span>
      }
    </button>
    <button class="logout-btn" (click)="onLogout()">
      <i class="icon ti ti-logout"></i>
      <span>Cerrar Sesión</span>
    </button>
  </div>
</div>
```

---

### main-layout.component.ts

```typescript
import { ChangeDetectionStrategy, Component, signal } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { SidebarComponent } from '../sidebar/sidebar.component';

@Component({
  selector: 'app-main-layout',
  standalone: true,
  imports: [RouterOutlet, SidebarComponent],
  templateUrl: './main-layout.component.html',
  styleUrls: ['./main-layout.component.scss'],
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class MainLayoutComponent {
  isSidebarOpen = signal(false);

  toggleSidebar() {
    this.isSidebarOpen.update(val => !val);
  }
}
```

---

### data-utils.service.ts (DateUtilsService + utilidad genérica)

```typescript
import { Injectable } from '@angular/core';

@Injectable({ providedIn: 'root' })
export class DateUtilsService {
  private _todayStrCache: { date: string; value: string } | null = null;

  /** O(1) con memoización por día natural para evitar crear Date en cada acceso */
  get todayStr(): string {
    const today = new Date().toISOString().split('T')[0];
    if (this._todayStrCache?.date === today) {
      return this._todayStrCache.value;
    }
    this._todayStrCache = { date: today, value: today };
    return this._todayStrCache.value;
  }

  formatToInputDate(date: Date | string): string {
    return new Date(date).toISOString().split('T')[0];
  }

  /**
   * Construye un Map para lookup O(1) por id. Evita O(n²) cuando se hace
   * find() dentro de bucles (ej. getRoomNumber en tablas).
   */
  buildIdLookupMap<T extends { id: number }, K extends keyof T>(
    items: T[],
    valueKey: K
  ): Map<number, T[K]> {
    const map = new Map<number, T[K]>();
    items.forEach(item => map.set(item.id, item[valueKey]));
    return map;
  }
}
```

---

### daily-report-modal.component.ts (aplicar lookup O(1))

```typescript
// Añadir computed para room lookup O(1)
roomNumberMap = computed(() => {
  const map = new Map<number, string>();
  this.bookingService.rooms().forEach(r => map.set(r.id, r.room_number));
  return map;
});

// Reemplazar getRoomNumber por:
getRoomNumber(id: number): string {
  return this.roomNumberMap().get(id) ?? 'N/A';
}
```

O en el template directamente (evitando método impuro):

```html
<td class="fw-bold">Hab. {{ roomNumberMap().get(t.room_id) ?? 'N/A' }}</td>
```

---

## Migración

1. Sidebar: cambiar `menu` → `visibleMenu()` en el template; añadir `requiredRole: 'ADMIN'` al ítem Finanzas.
2. Main Layout: eliminar `isMobileMenuOpen`; añadir OnPush.
3. DateUtilsService: memoización de `todayStr` es opcional; `buildIdLookupMap` puede usarse donde haya patrones find-in-loop.
4. DailyReport: añadir `roomNumberMap` computed y usarlo en `getRoomNumber` o en template.
