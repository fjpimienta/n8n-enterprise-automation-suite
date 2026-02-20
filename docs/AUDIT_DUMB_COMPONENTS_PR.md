# 🎴 Audit: Presentation Components (RoomCard & Header) - OnPush, Template Logic & Clean Inputs

## Executive Summary

| Severity | Finding | Impact |
|----------|---------|--------|
| **HIGH** | Ningún componente usa OnPush | Ciclos de CD innecesarios en cada tick |
| **HIGH** | HeaderComponent inyecta ThemeService | Componente presentacional acoplado; no reutilizable |
| **MEDIUM** | Header: themeService.currentTheme() llamado 3× en template | Múltiples lecturas del servicio en cada render |
| **LOW** | RoomCard: isArrivalToday() nunca usado | Código muerto |
| **LOW** | RoomCard: mezcla @Output() EventEmitter y output() | Inconsistencia de API |

**Recomendación:** Aplicar OnPush en ambos; desacoplar Header de ThemeService vía Input/Output; eliminar código muerto en RoomCard.

---

## Changes Checklist

- [ ] **RoomCard:** Añadir `ChangeDetectionStrategy.OnPush`
- [ ] **RoomCard:** Eliminar `isArrivalToday()` (no usado)
- [ ] **RoomCard:** Unificar outputs a `output()`; eliminar EventEmitter legacy
- [ ] **Header:** Añadir `ChangeDetectionStrategy.OnPush`
- [ ] **Header:** Eliminar inyección de ThemeService; añadir `currentTheme` input y `onThemeToggle` output
- [ ] **Parent (si usa Header):** Pasar `[currentTheme]` y `(onThemeToggle)`

---

## Deep Technical Details

### 1. Estrategia de Renderizado (OnPush)

| Componente | Estado actual | Acción |
|------------|---------------|--------|
| RoomCard | Default | Añadir OnPush |
| Header | Default | Añadir OnPush |

Con OnPush, Angular solo ejecuta CD cuando:
- Cambian los `@Input()` / `input()`
- Se disparan eventos en el template
- Los Observables con async pipe emiten
- Se llama manualmente a `markForCheck()`

---

### 2. Lógica en el Template

**RoomCard:**
- No hay llamadas a funciones en `{{ }}`; se usan propiedades de `room()` directamente ✓
- `isArrivalToday()` existe pero no se usa en el template; el dato viene de `room().hasIncomingToday` ✓

**Header:**
- `themeService.currentTheme()` aparece 3 veces: en `[class]`, `@if` y `@else`
- Cada lectura se evalúa en cada ciclo de CD
- Solución: recibe `currentTheme` como input; el padre pasa `themeService.currentTheme()` una vez

---

### 3. Inputs Limpios

**RoomCard:** ✓
- `room = input.required<any>()` — datos solo vía input
- Sin inyección de servicios

**Header:** ✗
- Inyecta `ThemeService` para leer `currentTheme` y llamar `toggleTheme`
- Para ser presentacional: `currentTheme = input.required<'light'|'dark'>()` y `onThemeToggle = output<void>()`
- El padre inyecta ThemeService y conecta: `[currentTheme]="themeService.currentTheme()"` y `(onThemeToggle)="themeService.toggleTheme()"`

---

## Testing Protocol

| # | Test | Expected |
|---|------|----------|
| 1 | RoomCard con OnPush → cambios de room() actualizan vista | Pass |
| 2 | Header sin ThemeService → compila con inputs/outputs | Pass |
| 3 | Header (onThemeToggle) → padre recibe evento | Pass |
| 4 | RoomCard sin isArrivalToday → sin errores | Pass |

---

## Senior Checklist

- [ ] Migrar RoomCard `room` de `any` a `Room` (o tipo extendido con displayDate, hasIncomingToday)
- [ ] Verificar dónde se usa HeaderComponent para actualizar el parent

---

## Código Refactorizado

### room-card.component.ts

```typescript
import { ChangeDetectionStrategy, Component, input, output } from '@angular/core';
import { CommonModule } from '@angular/common';

@Component({
  selector: 'app-room-card',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './room-card.component.html',
  styleUrl: './room-card.component.css',
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class RoomCardComponent {
  room = input.required<any>();
  onSelect = output<any>();
  onReportIssue = output<void>();
}
```

### room-card.component.html

Sin cambios: ya usa solo propiedades de `room()` y no llama a métodos. `onClick` y `onReportIssue` se sustituyen por `onSelect` y `onReportIssue` (output). Verificar que el parent use `(onSelect)` y `(onReportIssue)` — actualmente el Dashboard usa `(onSelect)="onSelectRoom($event)"` y `(onReportIssue)="openMaintenanceReport(room)"`. En el RoomCard, `onReportIssue` no lleva argumento; el parent ya tiene `room` en el contexto del `@for`. Se mantiene `onReportIssue.emit()` sin argumentos; el parent usa `openMaintenanceReport(room)` pasando el `room` del loop. OK.

---

### header.component.ts

```typescript
import { ChangeDetectionStrategy, Component, input, output } from '@angular/core';

@Component({
  selector: 'app-header',
  standalone: true,
  imports: [],
  templateUrl: './header.component.html',
  styleUrl: './header.component.css',
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class HeaderComponent {
  isAdmin = input.required<boolean>();
  currentTheme = input.required<'light' | 'dark'>();

  onRefresh = output<void>();
  onRefreshMain = output<void>();
  onGenerateReport = output<void>();
  onLogout = output<void>();
  onOpenMaintenance = output<void>();
  onThemeToggle = output<void>();
}
```

### header.component.html

```html
<div class="page-header d-print-none text-white bg-dark py-3">
    <div class="container-xl">
        <div class="row g-2 align-items-center">
            <div class="col">
                <h2 class="page-title text-white" (click)="onRefreshMain.emit()"
                    style="cursor: pointer; user-select: none;" title="Click para refrescar datos">
                    <svg xmlns="http://www.w3.org/2000/svg" class="icon icon-tabler icon-tabler-building-skyscraper"
                        width="24" height="24" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor" fill="none"
                        stroke-linecap="round" stroke-linejoin="round">
                        <path stroke="none" d="M0 0h24v24H0z" fill="none" />
                        <path d="M3 21l18 0" />
                        <path d="M5 21v-14l8 -4l8 4v14" />
                        <path d="M19 21v-10l-6 -4" />
                        <path d="M9 9l0 .01" />
                        <path d="M9 12l0 .01" />
                        <path d="M9 15l0 .01" />
                        <path d="M9 18l0 .01" />
                    </svg>
                    &nbsp;Hotel San José
                </h2>
            </div>
            <div class="col-auto ms-auto d-flex gap-2">
                <button class="btn btn-icon btn-dark" (click)="onRefresh.emit()" title="Refrescar">
                    <svg xmlns="http://www.w3.org/2000/svg" class="icon" width="24" height="24" viewBox="0 0 24 24"
                        stroke-width="2" stroke="currentColor" fill="none">
                        <path stroke="none" d="M0 0h24v24H0z" fill="none" />
                        <path d="M20 11a8.1 8.1 0 0 0 -15.5 -2m-.5 -4v4h4" />
                        <path d="M4 13a8.1 8.1 0 0 0 15.5 2m.5 4v-4h-4" />
                    </svg>
                </button>

                <button class="btn btn-icon" (click)="onThemeToggle.emit()"
                    [class.btn-dark]="currentTheme() === 'light'"
                    [class.btn-light]="currentTheme() === 'dark'" title="Cambiar tema">

                    @if (currentTheme() === 'dark') {
                    <svg xmlns="http://www.w3.org/2000/svg" class="icon" width="24" height="24" viewBox="0 0 24 24"
                        stroke-width="2" stroke="currentColor" fill="none">
                        <path stroke="none" d="M0 0h24v24H0z" fill="none" />
                        <path d="M12 12m-4 0a4 4 0 1 0 8 0a4 4 0 1 0 -8 0" />
                        <path
                            d="M3 12h1m8 -9v1m8 8h1m-9 8v1m-6.4 -15.4l.7 .7m12.1 -.7l-.7 .7m0 11.4l.7 .7m-12.1 -.7l-.7 .7" />
                    </svg>
                    }

                    @else {
                    <svg xmlns="http://www.w3.org/2000/svg" class="icon" width="24" height="24" viewBox="0 0 24 24"
                        stroke-width="2" stroke="currentColor" fill="none">
                        <path stroke="none" d="M0 0h24v24H0z" fill="none" />
                        <path d="M12 3c.132 0 .263 0 .393 0a7.5 7.5 0 0 0 7.92 12.446a9 9 0 1 1 -8.313 -12.454z" />
                    </svg>
                    }
                </button>
                <div class="nav-item me-2">
                    <button class="btn btn-icon" (click)="onOpenMaintenance.emit()" title="Tickets de Mantenimiento">
                        <svg xmlns="http://www.w3.org/2000/svg"
                            class="icon icon-tabler icon-tabler-alert-triangle text-warning" width="24" height="24"
                            viewBox="0 0 24 24" stroke-width="2" stroke="currentColor" fill="none"
                            stroke-linecap="round" stroke-linejoin="round">
                            <path stroke="none" d="M0 0h24v24H0z" fill="none" />
                            <path d="M12 9v4" />
                            <path
                                d="M10.363 3.591l-8.106 13.534a1.914 1.914 0 0 0 1.636 2.871h16.214a1.914 1.914 0 0 0 1.636 -2.87l-8.106 -13.536a1.914 1.914 0 0 0 -3.274 0z" />
                            <path d="M12 16h.01" />
                        </svg>
                    </button>
                </div>

                @if (isAdmin()) {
                <button (click)="onGenerateReport.emit()" class="btn btn-primary btn-sm me-2">
                    💰 Caja
                </button>
                }
                <button (click)="onLogout.emit()" class="btn btn-danger btn-sm">Salir</button>
            </div>
        </div>
    </div>
</div>
```

---

## Migración

1. **RoomCard:** El parent usa `(onSelect)` y `(onReportIssue)`; ambos siguen funcionando con `output()`.
2. **Header:** Si existe un parent que usa app-header, actualizar a:
   ```html
   <app-header
     [isAdmin]="isAdmin()"
     [currentTheme]="themeService.currentTheme()"
     (onRefresh)="refresh()"
     (onRefreshMain)="refreshMain()"
     (onGenerateReport)="generateDailyReport()"
     (onLogout)="logout()"
     (onOpenMaintenance)="openMaintenanceMonitor()"
     (onThemeToggle)="themeService.toggleTheme()">
   </app-header>
   ```
