import { Component, inject, signal, computed, OnInit, ChangeDetectionStrategy, effect } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ActivatedRoute, Router } from '@angular/router';
import { toSignal } from '@angular/core/rxjs-interop';
import { CattleApiService } from '@core/services/cattle-api.service';
import { CattleDataService } from '@core/services/cattle-data.service';
import { NgApexchartsModule } from 'ng-apexcharts';
import { ReproductiveDashboardComponent } from '../reproductive-dashboard/reproductive-dashboard.component';
import { EngordaDashboardComponent } from '../engorda-dashboard/engorda-dashboard.component';
import { ReproduccionDashboardComponent } from '../reproduccion-dashboard/reproduccion-dashboard.component';
import { CattleEventLogComponent } from '../cattle-event-log/cattle-event-log.component';
import { ExpenseModalComponent } from '../../../expenses/components/expense-modal/expense-modal.component';
import { ComplianceAlertCardComponent } from '../../../../compliance/components/compliance-alert-card/compliance-alert-card.component';
import { MetadataDetailModalComponent } from '@shared/components/metadata-detail-modal/metadata-detail-modal.component';
import { hasDisplayableMetadata } from '@shared/utils/metadata-view.util';
import { withoutFinancialMetadata } from '@shared/utils/financial-metadata.util';
import { HERD_STATUS_FILTER_OPTIONS, HerdStatusFilter, filterByHerdStatus } from '@shared/utils/herd-status.util';
import { SPECIES_FILTER_ALL, deriveAvailableSpecies, getAnimalSpecies } from '@shared/utils/species.util';
import { LOT_FILTER_ALL, deriveAvailableLots, getAnimalLot } from '@shared/utils/lot.util';
import { TenantService } from 'core-auth';
import { ThemeService } from '@core/services/theme.service';
import { Expense } from '../../../models/expense.model';
import { BusinessModel } from '../../../models/livestock.model';
import { Paginator } from '../../utils/paginator';

@Component({
  selector: 'app-main-dashboard',
  standalone: true,
  imports: [CommonModule, NgApexchartsModule, ReproductiveDashboardComponent, EngordaDashboardComponent, ReproduccionDashboardComponent, ExpenseModalComponent, ComplianceAlertCardComponent, MetadataDetailModalComponent, CattleEventLogComponent],
  templateUrl: './main-dashboard.component.html',
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class MainDashboardComponent implements OnInit {
  private cattleApi = inject(CattleApiService);
  private cattleDataService = inject(CattleDataService);
  private tenantService = inject(TenantService);
  public themeService = inject(ThemeService);
  private router = inject(Router);
  private route = inject(ActivatedRoute);

  public PRECIO_KILO = 65.00;

  // Misma fuente que cattle-list, adg-alerts, etc. — evita que el dashboard muestre
  // una copia del hato desincronizada del resto de la app.
  public cattleList = this.cattleDataService.cattleList;
  public expensesList = signal<Expense[]>([]);
  public isLoading = signal<boolean>(true);

  // Navegación y Filtros de Trazabilidad Biológica
  public activeSubTab = signal<'RESUMEN' | 'INVENTARIO' | 'GASTOS' | 'POR_ANIMAL' | 'EVENT_LOG'>('RESUMEN');
  public selectedSpecies = signal<string>(SPECIES_FILTER_ALL); // 🚀 Filtro maestro de especie
  public selectedLot = signal<string>(LOT_FILTER_ALL); // 🚀 Filtro de lote, combinable (AND) con especie
  public showExpenseModal = signal<boolean>(false);

  // 🔎 Búsqueda reactiva del tab Inventario Detallado
  public inventorySearch = signal<string>('');

  // 🐄 Filtro de estado de vida (venta/mortandad). Default: solo hato vivo.
  // Mismo criterio que el Censo Biológico (cattle-list) vía @shared/utils/herd-status.util.
  public readonly herdStatusOptions = HERD_STATUS_FILTER_OPTIONS;
  public herdStatusFilter = signal<HerdStatusFilter>('ACTIVOS');

  // Modal de detalle de metadata (JSONB variable por animal — sin shape fijo)
  public metadataAnimal = signal<any | null>(null);

  // 🔒 no-ADMIN nunca ve claves financieras del JSONB (purchase_price, seller_name, etc. —
  // ver financial-metadata.util.ts). Si tras quitarlas no queda nada mostrable, el ícono de
  // "Detalle" se oculta para ese rol, igual que ya pasaba con las claves puramente técnicas.
  public animalHasMetadata(animal: any): boolean {
    return hasDisplayableMetadata(this.getDisplayMetadata(animal));
  }

  public getDisplayMetadata(animal: any): unknown {
    return this.isAdminForActiveTenant() ? animal?.metadata : withoutFinancialMetadata(animal?.metadata);
  }

  public openMetadata(animal: any) {
    this.metadataAnimal.set(animal);
  }

  public closeMetadata() {
    this.metadataAnimal.set(null);
  }

  // Controlador de Paginación Reutilizable (ver mejora #3: composable basado en signals)
  public pagination = new Paginator(() => this.currentDataset().length);

  // Bridge reactivo: convierte los queryParams del Router en un Signal nativo de Angular.
  // initialValue evita `undefined` en el primer render (antes de que ActivatedRoute emita).
  private queryParams = toSignal(this.route.queryParamMap, { initialValue: this.route.snapshot.queryParamMap });

  // 🔗 Fuente única de verdad: el módulo activo se deriva de la URL (?tab=), nunca se escribe
  // directamente. setTab() solo navega; este computed reacciona al cambio de queryParams.
  public activeTab = computed<BusinessModel>(() => {
    const tab = this.queryParams().get('tab')?.toUpperCase();
    return tab === 'ENGORDA' || tab === 'REPRODUCCION' ? tab : 'CRIA';
  });

  // 🔒 Cattle Event Log es ADMIN-only. Deliberadamente leído de `tenantService.activeTenant()`,
  // NO de `authService.hasRole()`/`roleGuard` (JWT): el rol del JWT queda fijo al rol de la
  // empresa activa AL MOMENTO DEL LOGIN y no se actualiza al cambiar de rancho desde el Context
  // Switcher (ver `tenant-selector.component.ts#onSelect`, que solo llama `setActiveTenant()`,
  // sin re-emitir token). `activeTenant().role` sí es por-empresa y se actualiza en vivo en cada
  // cambio de contexto — es la única fuente correcta para un gate que depende de la empresa activa.
  public isAdminForActiveTenant = computed(() =>
    (this.tenantService.activeTenant()?.role || '').toUpperCase() === 'ADMIN'
  );

  // Sub-tabs financieros/de auditoría — ADMIN-only. GASTOS y POR_ANIMAL se suman aquí a raíz del
  // mismo hallazgo que Cattle Event Log: cattle_expenses alimenta ambos y es dato financiero que
  // un EDITOR (capataz) no debe poder ver.
  private static readonly ADMIN_ONLY_SUBTABS = new Set(['EVENT_LOG', 'GASTOS', 'POR_ANIMAL']);

  constructor() {
    /**
     * 🔄 EFECTO REACTIVO: Escucha activa del Contexto de Rancho.
     * Cada vez que el tenantService cambie el rancho activo en el header del ERP,
     * este bloque detectará el cambio de ID y re-orquestará el pipeline automáticamente.
     */
    effect(() => {
      const activeTenantId = this.tenantService.activeTenantId();

      if (activeTenantId) {
        //console.log(`🔄 [Dashboard Pipeline] Detectado cambio de rancho a ID: ${activeTenantId}. Re-indexando KPIs...`);
        this.loadDashboardData();
      }
    }, { allowSignalWrites: true }); // Permite que la escritura de isLoading y listas ocurra en cascada

    // 🔄 EFECTO REACTIVO: al cambiar de módulo (CRIA/ENGORDA/REPRODUCCION) resetea la sub-pestaña activa
    // y la paginación, para no dejar al usuario en una página de tabla vacía tras el cambio.
    effect(() => {
      this.activeTab();
      this.activeSubTab.set('RESUMEN');
      this.pagination.reset();
    }, { allowSignalWrites: true });

    // 🔒 EFECTO REACTIVO: si el usuario está en un tab ADMIN-only (Cattle Event Log, Historial de
    // Gastos, Costo por Animal — los tres financieros/de auditoría) y cambia de rancho activo
    // desde el Context Switcher hacia una empresa donde no es ADMIN, lo saca de inmediato — el rol
    // por-empresa (`activeTenant().role`) puede cambiar en cualquier momento sin recargar la app.
    effect(() => {
      if (MainDashboardComponent.ADMIN_ONLY_SUBTABS.has(this.activeSubTab()) && !this.isAdminForActiveTenant()) {
        this.activeSubTab.set('RESUMEN');
      }
    }, { allowSignalWrites: true });
  }

  ngOnInit() {
    // La carga inicial ahora es gestionada de manera única por el constructor a través del effect nativo,
    // garantizando sincronía y evitando llamadas duplicadas al backend en el ciclo de vida.
  }

  async loadDashboardData() {
    // El ganado ya se refresca vía CattleDataService (su propio effect reacciona al
    // cambio de tenant); aquí solo se cargan los gastos, que no forman parte de esa fuente.
    this.isLoading.set(true);
    try {
      // 🔒 cattle_expenses es financiero y no-ADMIN no debe verlo (ver fix de Cattle Event Log) —
      // ni siquiera se intenta el fetch para un rol sin acceso: evita un 403 inútil contra el
      // gateway y la fila de `expensesList` nunca llega a existir en memoria para ese rol.
      if (this.isAdminForActiveTenant()) {
        const expensesRaw = await this.cattleApi.getExpenses();
        this.expensesList.set((Array.isArray(expensesRaw) ? expensesRaw : []) as Expense[]);
      } else {
        this.expensesList.set([]);
      }
    } catch (error) {
      console.error('Error en el Data Pipeline:', error);
    } finally {
      this.isLoading.set(false);
    }
  }

  // 🚀 Extracción dinámica de especies existentes en el hato para los selectores de la UI.
  // Fuente compartida con el "Censo Biológico Activo" (cattle-list) vía @shared/utils/species.util.
  public availableSpecies = computed(() => deriveAvailableSpecies(this.cattleList()));

  // 🚀 Extracción dinámica de lotes existentes en el hato. Fuente compartida con el
  // "Censo Biológico Activo" (cattle-list) vía @shared/utils/lot.util.
  public availableLots = computed(() => deriveAvailableLots(this.cattleList()));

  // 🚀 Filtrado Jerárquico: Módulo (Tab) + Especie + Lote (Selectores, combinables por AND) con sanitización.
  // No aplica el filtro de estado de vida — ese se superpone en `filteredCattleList`.
  private scopedCattleList = computed(() => {
    const currentTab = this.activeTab();
    const currentSpecies = this.selectedSpecies();
    const currentLot = this.selectedLot();

    return this.cattleList().filter(animal => {
      if (!animal.business_model) return false;

      const matchesTab = animal.business_model.trim() === currentTab;
      const matchesSpecies = currentSpecies === SPECIES_FILTER_ALL || getAnimalSpecies(animal) === currentSpecies;
      const matchesLot = currentLot === LOT_FILTER_ALL || getAnimalLot(animal) === currentLot;

      return matchesTab && matchesSpecies && matchesLot;
    });
  });

  // Lista base de todas las vistas de KPI/inventario: módulo + especie + estado de vida.
  // Por defecto (`ACTIVOS`) excluye VENDIDO y BAJA_MORTANDAD; el toggle del tab Inventario
  // permite auditarlos ("Todos" / "Solo bajas y ventas") sin ocultarlos de forma permanente.
  public filteredCattleList = computed(() =>
    filterByHerdStatus(this.scopedCattleList(), this.herdStatusFilter())
  );

  // Alcance del Cattle Event Log: SOLO módulo (tab). Deliberadamente sin especie/lote y sin
  // herdStatusFilter — un animal vendido/muerto conserva su historial dentro de su módulo (ver
  // 624b918). Mismo criterio que scopedCattleList para animales sin business_model: excluidos.
  public eventLogCattleList = computed(() => {
    const currentTab = this.activeTab();
    return this.cattleList().filter(animal =>
      !!animal.business_model && animal.business_model.trim() === currentTab
    );
  });

  // Card "Cabezas Totales Activas": siempre el hato vivo, sin importar el toggle de auditoría.
  public activeHeadCount = computed(() =>
    filterByHerdStatus(this.scopedCattleList(), 'ACTIVOS').length
  );

  // Filtrado de Gastos por Módulo y Especie vinculada
  public filteredExpensesList = computed(() => {
    const currentTab = this.activeTab();
    const currentSpecies = this.selectedSpecies();
    const currentLot = this.selectedLot();

    return this.expensesList().filter(expense => {
      // Cruzar con la tabla de ganado si el gasto tiene un livestock_id para saber su especie/lote
      if (expense.livestock_id) {
        const animal = this.cattleList().find(a => a.id === expense.livestock_id);
        if (animal) {
          const matchesTab = animal.business_model === currentTab;
          const matchesSpecies = currentSpecies === SPECIES_FILTER_ALL || getAnimalSpecies(animal) === currentSpecies;
          const matchesLot = currentLot === LOT_FILTER_ALL || getAnimalLot(animal) === currentLot;
          return matchesTab && matchesSpecies && matchesLot;
        }
      }
      return !expense.business_model || expense.business_model === currentTab;
    });
  });

  // 🚩 Cuenta de animales sin UPP asignada, para el badge de alerta del inventario.
  // Se evalúa contra `production_unit_id` (FK real), no contra `upp_origen` (texto libre
  // que solo está poblado en parte del hato y daba falsos "sin UPP").
  public missingUppCount = computed(() =>
    this.filteredCattleList().filter(a => !a.production_unit_id).length
  );

  // 👷 Panel Operativo (no-ADMIN): conteos por especie/categoría/lote y animales que requieren
  // atención biológica — cero cifras financieras (precio, capitalización, gasto). Reutiliza
  // `filteredCattleList()`, ya cargado para el resto del dashboard; no agrega ningún fetch nuevo.
  private static countBy<T>(
    list: readonly T[],
    keyFn: (item: T) => string | null | undefined,
    fallback: string
  ): Array<{ label: string; count: number }> {
    const counts = new Map<string, number>();
    for (const item of list) {
      const key = keyFn(item) || fallback;
      counts.set(key, (counts.get(key) ?? 0) + 1);
    }
    return Array.from(counts.entries())
      .map(([label, count]) => ({ label, count }))
      .sort((a, b) => b.count - a.count);
  }

  public herdCountsBySpecies = computed(() =>
    MainDashboardComponent.countBy(this.filteredCattleList(), getAnimalSpecies, 'Sin especie')
  );

  public herdCountsByCategory = computed(() =>
    MainDashboardComponent.countBy(this.filteredCattleList(), a => a.category, 'Sin categoría')
  );

  public herdCountsByLot = computed(() =>
    MainDashboardComponent.countBy(this.filteredCattleList(), getAnimalLot, 'Sin lote')
  );

  // Estados biológicos que piden revisión humana — ninguno es financiero (venta/gasto aparte).
  private static readonly ATTENTION_STATUSES = new Set(['RIESGO', 'CUARENTENA', 'EN_TRANSITO']);

  public animalsNeedingAttention = computed(() =>
    this.filteredCattleList().filter(a =>
      MainDashboardComponent.ATTENTION_STATUSES.has((a.current_status || '').toUpperCase())
    )
  );

  // Promedio solo sobre animales con peso > 0 — un animal sin pesaje (current_weight_kg en 0/null)
  // no debe arrastrar el promedio hacia abajo como si realmente pesara 0 kg. `weighedCount` vs.
  // `totalCount` quedan ambos expuestos para la columna "Con peso" (ej. "2 de 3").
  public averageWeightByLotAndCategory = computed(() => {
    const groups = new Map<string, { lot: string; category: string; totalWeight: number; weighedCount: number; totalCount: number }>();
    for (const animal of this.filteredCattleList()) {
      const lot = animal.lot_name || 'Sin lote';
      const category = animal.category || 'Sin categoría';
      const key = `${lot}__${category}`;
      const entry = groups.get(key) ?? { lot, category, totalWeight: 0, weighedCount: 0, totalCount: 0 };
      const weight = Number(animal.current_weight_kg || 0);
      if (weight > 0) {
        entry.totalWeight += weight;
        entry.weighedCount += 1;
      }
      entry.totalCount += 1;
      groups.set(key, entry);
    }
    return Array.from(groups.values())
      .map(g => ({
        lot: g.lot,
        category: g.category,
        avgWeight: g.weighedCount > 0 ? g.totalWeight / g.weighedCount : null,
        weighedCount: g.weighedCount,
        totalCount: g.totalCount
      }))
      .sort((a, b) => a.lot.localeCompare(b.lot) || a.category.localeCompare(b.category));
  });

  // "Sin SINIIGA" cubre tanto el vacío real como el placeholder 'S/N' que usa el formulario de
  // alta por default (cattle-detail-modal.component.ts) — ambos significan "no identificado".
  public animalsMissingIdentifier = computed(() =>
    this.filteredCattleList().filter(a => {
      const missingSiniiga = !a.rfid_siniiga || a.rfid_siniiga === 'S/N';
      const missingRfid = !a.electronic_rfid;
      return missingSiniiga || missingRfid;
    })
  );

  // 🔎 Inventario filtrado por búsqueda reactiva (rfid_siniiga, numero_fuego o electronic_rfid)
  public inventorySearchedList = computed(() => {
    const query = this.inventorySearch().trim().toLowerCase();
    const list = this.filteredCattleList();
    if (!query) return list;

    return list.filter(animal =>
      animal.rfid_siniiga?.toLowerCase().includes(query) ||
      animal.numero_fuego?.toLowerCase().includes(query) ||
      animal.electronic_rfid?.toLowerCase().includes(query)
    );
  });

  private currentDataset = computed(() => {
    const tab = this.activeSubTab();
    if (tab === 'GASTOS') return this.filteredExpensesList();
    if (tab === 'INVENTARIO') return this.inventorySearchedList();
    return this.filteredCattleList();
  });

  public paginatedCattleList = computed(() => {
    if (this.activeSubTab() !== 'INVENTARIO') return [];
    const startIndex = (this.pagination.currentPage() - 1) * this.pagination.pageSize();
    return this.inventorySearchedList().slice(startIndex, startIndex + this.pagination.pageSize());
  });

  public paginatedExpensesList = computed(() => {
    if (this.activeSubTab() !== 'GASTOS') return [];
    const startIndex = (this.pagination.currentPage() - 1) * this.pagination.pageSize();
    return this.filteredExpensesList().slice(startIndex, startIndex + this.pagination.pageSize());
  });

  public setTab(tab: BusinessModel) {
    // Solo navega — activeTab es un computed derivado de la URL, se recalcula solo.
    // El effect del constructor reacciona a ese cambio y resetea subTab/paginación.
    this.router.navigate([], {
      relativeTo: this.route,
      queryParams: { tab: tab.toLowerCase() },
      queryParamsHandling: 'merge'
    });
  }

  public setSubTab(subTab: 'RESUMEN' | 'INVENTARIO' | 'GASTOS' | 'POR_ANIMAL' | 'EVENT_LOG') {
    // Defensa en profundidad: aunque el <li> del tab esté oculto en el template, esto bloquea
    // cualquier intento de activar un tab ADMIN-only programáticamente (consola, binding forzado,
    // etc.) para un rol no-ADMIN en la empresa activa.
    if (MainDashboardComponent.ADMIN_ONLY_SUBTABS.has(subTab) && !this.isAdminForActiveTenant()) return;
    this.activeSubTab.set(subTab);
    this.pagination.reset();
  }

  public setSpecies(species: string) {
    this.selectedSpecies.set(species);
    this.pagination.reset();
  }

  public setLot(lot: string) {
    this.selectedLot.set(lot);
    this.pagination.reset();
  }

  public setInventorySearch(query: string) {
    this.inventorySearch.set(query);
    this.pagination.reset();
  }

  public setHerdStatusFilter(value: HerdStatusFilter) {
    this.herdStatusFilter.set(value);
    this.pagination.reset();
  }

  public biomasaTotal = computed(() => {
    return this.filteredCattleList().reduce((acc, curr) => acc + Number(curr.current_weight_kg || 0), 0);
  });

  public capitalizacionTotal = computed(() => {
    return this.biomasaTotal() * this.PRECIO_KILO;
  });

  /** Ranking de gastos por animal: agrupa filteredExpensesList por livestock_id y cruza con cattleList */
  public animalCostSummary = computed(() => {
    const expenses = this.filteredExpensesList().filter(
      (e): e is Expense & { livestock_id: string } => !!e.livestock_id
    );
    const grouped = new Map<string, { total: number; count: number }>();

    for (const e of expenses) {
      const existing = grouped.get(e.livestock_id) ?? { total: 0, count: 0 };
      grouped.set(e.livestock_id, {
        total: existing.total + Number(e.amount || 0),
        count: existing.count + 1
      });
    }

    return Array.from(grouped.entries())
      .map(([livestockId, stats]) => {
        const animal = this.cattleList().find(a => a.id === livestockId);
        const weightKg = Number(animal?.current_weight_kg || 0);
        const valorEstimado = weightKg * this.PRECIO_KILO;
        return {
          livestockId,
          rfid:        animal?.rfid_siniiga ?? 'Desconocido',
          numero_fuego: animal?.numero_fuego ?? '',
          category:    animal?.category ?? '',
          weightKg,
          total:       stats.total,
          count:       stats.count,
          costPerKg:   weightKg > 0 ? stats.total / weightKg : 0,
          valorEstimado,
          balance:     valorEstimado - stats.total
        };
      })
      .sort((a, b) => b.total - a.total);
  });

  public totalAnimalCosts = computed(() =>
    this.animalCostSummary().reduce((sum, row) => sum + row.total, 0)
  );

  /** Top 10 animales con más gasto registrado: balance (valor estimado - gasto) para detectar rendimiento negativo */
  public animalBalanceChartOptions = computed(() => {
    const rows = this.animalCostSummary().slice(0, 10);
    return {
      series: [{
        name: 'Balance',
        data: rows.map(r => Number(r.balance.toFixed(2)))
      }],
      xaxis: {
        categories: rows.map(r => r.numero_fuego || `...${r.rfid.slice(-4)}`),
        labels: { rotate: -45, style: { cssClass: 'text-muted font-monospace' } }
      }
    };
  });

  private static readonly SIN_UPP = 'Sin UPP Asignada';
  private static readonly GASTOS_GENERALES = 'Gastos Generales';

  /**
   * Balance por UPP: cruza capitalización del hato (agrupado por `production_unit_id`, mostrando
   * el `upp_code` oficial vía `vw_cattle_kpi`) contra los gastos vinculados a esos mismos animales.
   * Se agrupa por `production_unit_id` — no por `upp_origen` (texto libre legacy, con huecos NULL
   * en registros históricos que no reflejan la asignación real) — porque es el campo relacional
   * real, validado por el trigger `fn_guard_livestock_production_unit`. Los gastos sin livestock_id
   * (o cuyo animal no tiene UPP asignada) no pueden atribuirse a una UPP real y se agrupan aparte
   * en "Gastos Generales".
   */
  public uppBalanceSummary = computed(() => {
    const cattle = this.filteredCattleList();
    const expenses = this.filteredExpensesList();

    const grouped = new Map<string, { capitalizacion: number; cabezas: number; gasto: number }>();

    for (const animal of cattle) {
      const upp = (animal.production_unit_id && String(animal.upp_code ?? '').trim()) || MainDashboardComponent.SIN_UPP;
      const entry = grouped.get(upp) ?? { capitalizacion: 0, cabezas: 0, gasto: 0 };
      entry.capitalizacion += Number(animal.current_weight_kg || 0) * this.PRECIO_KILO;
      entry.cabezas += 1;
      grouped.set(upp, entry);
    }

    let gastosGenerales = 0;
    for (const expense of expenses) {
      const animal = expense.livestock_id ? cattle.find(a => a.id === expense.livestock_id) : null;
      const upp = animal?.production_unit_id && String(animal.upp_code ?? '').trim();

      if (upp) {
        const entry = grouped.get(upp) ?? { capitalizacion: 0, cabezas: 0, gasto: 0 };
        entry.gasto += Number(expense.amount || 0);
        grouped.set(upp, entry);
      } else {
        gastosGenerales += Number(expense.amount || 0);
      }
    }

    const rows = Array.from(grouped.entries())
      .map(([upp, v]) => ({
        upp,
        capitalizacion: v.capitalizacion,
        gasto:          v.gasto,
        cabezas:        v.cabezas,
        balance:        v.capitalizacion - v.gasto
      }))
      .sort((a, b) => b.capitalizacion - a.capitalizacion);

    if (gastosGenerales > 0) {
      rows.push({
        upp: MainDashboardComponent.GASTOS_GENERALES,
        capitalizacion: 0,
        gasto: gastosGenerales,
        cabezas: 0,
        balance: -gastosGenerales
      });
    }

    return rows;
  });

  /** Fila "Sin UPP Asignada" separada del chart: se muestra como tarjeta de alerta en vez de barra,
   *  ya que su magnitud (mayoría del hato) aplasta visualmente a los UPP operativamente relevantes. */
  public sinUppSummary = computed(() =>
    this.uppBalanceSummary().find(row => row.upp === MainDashboardComponent.SIN_UPP)
  );

  // Filas que sí se grafican en el chart de Balance por UPP (excluye "Sin UPP Asignada")
  public uppChartDisplayRows = computed(() =>
    this.uppBalanceSummary().filter(row => row.upp !== MainDashboardComponent.SIN_UPP)
  );

  public uppChartOptions = computed(() => {
    const rows = this.uppChartDisplayRows();
    return {
      series: [
        { name: 'Capitalización', data: rows.map(r => Number(r.capitalizacion.toFixed(2))) },
        { name: 'Gasto', data: rows.map(r => Number(r.gasto.toFixed(2))) }
      ],
      xaxis: { categories: rows.map(r => r.upp) },
      colors: ['#2fb344', '#d63939']
    };
  });

  public balanceNetoUpp = computed(() =>
    this.uppBalanceSummary().reduce((sum, row) => sum + row.balance, 0)
  );
}