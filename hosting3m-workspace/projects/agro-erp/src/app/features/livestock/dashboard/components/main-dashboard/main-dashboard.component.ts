import { Component, inject, signal, computed, OnInit, ChangeDetectionStrategy, effect, DestroyRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ActivatedRoute, Router } from '@angular/router';
import { toSignal } from '@angular/core/rxjs-interop';
import { CattleApiService } from '@core/services/cattle-api.service';
import { CattleDataService } from '@core/services/cattle-data.service';
import { ReproductiveDashboardComponent } from '../reproductive-dashboard/reproductive-dashboard.component';
import { EngordaDashboardComponent } from '../engorda-dashboard/engorda-dashboard.component';
import { ReproduccionDashboardComponent } from '../reproduccion-dashboard/reproduccion-dashboard.component';
import { CattleEventLogComponent } from '../cattle-event-log/cattle-event-log.component';
import { SaleIncomeLogComponent } from '../sale-income-log/sale-income-log.component';
import { ExpenseModalComponent } from '../../../expenses/components/expense-modal/expense-modal.component';
import { ComplianceAlertCardComponent } from '../../../../compliance/components/compliance-alert-card/compliance-alert-card.component';
import { ComplianceService } from '../../../../compliance/services/compliance.service';
import { MetadataDetailModalComponent } from '@shared/components/metadata-detail-modal/metadata-detail-modal.component';
import { TableToolbarComponent } from '@shared/components/table-toolbar/table-toolbar.component';
import { TableFooterComponent } from '@shared/components/table-footer/table-footer.component';
import { PagedTable } from '@shared/utils/paged-table.util';
import { hasDisplayableMetadata } from '@shared/utils/metadata-view.util';
import { withoutFinancialMetadata } from '@shared/utils/financial-metadata.util';
import { HERD_STATUS_FILTER_OPTIONS, HerdStatusFilter, filterByHerdStatus } from '@shared/utils/herd-status.util';
import { SPECIES_FILTER_ALL, deriveAvailableSpecies, getAnimalSpecies } from '@shared/utils/species.util';
import { LOT_FILTER_ALL, deriveAvailableLots, getAnimalLot } from '@shared/utils/lot.util';
import { isAutoRefreshDue } from '@shared/utils/auto-refresh.util';
import { TenantService } from 'core-auth';
import { ThemeService } from '@core/services/theme.service';
import { Expense } from '../../../models/expense.model';
import { BusinessModel } from '../../../models/livestock.model';
import { Paginator } from '../../utils/paginator';
import { REFERENCE_PRICE_PER_KG } from '../../../expenses/livestock-expense.util';
import { LivestockExpenseSummaryComponent } from '../../../expenses/components/livestock-expense-summary/livestock-expense-summary.component';
import { LivestockExpenseHistoryComponent } from '../../../expenses/components/livestock-expense-history/livestock-expense-history.component';
import { LivestockAnimalCostsComponent } from '../../../expenses/components/livestock-animal-costs/livestock-animal-costs.component';

@Component({
  selector: 'app-main-dashboard',
  standalone: true,
  imports: [CommonModule, LivestockExpenseSummaryComponent, LivestockExpenseHistoryComponent, LivestockAnimalCostsComponent, ReproductiveDashboardComponent, EngordaDashboardComponent, ReproduccionDashboardComponent, ExpenseModalComponent, ComplianceAlertCardComponent, MetadataDetailModalComponent, CattleEventLogComponent, SaleIncomeLogComponent, TableToolbarComponent, TableFooterComponent],
  templateUrl: './main-dashboard.component.html',
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class MainDashboardComponent implements OnInit {
  private cattleApi = inject(CattleApiService);
  private cattleDataService = inject(CattleDataService);
  private complianceService = inject(ComplianceService);
  private tenantService = inject(TenantService);
  public themeService = inject(ThemeService);
  private router = inject(Router);
  private route = inject(ActivatedRoute);
  private destroyRef = inject(DestroyRef);

  public PRECIO_KILO = REFERENCE_PRICE_PER_KG;

  // Misma fuente que cattle-list, adg-alerts, etc. — evita que el dashboard muestre
  // una copia del hato desincronizada del resto de la app.
  public cattleList = this.cattleDataService.cattleList;
  public expensesList = signal<Expense[]>([]);

  // `isLoading`: SOLO la carga inicial / cambio de tenant (datos aún no visibles por primera
  // vez). `isRefreshing`: refresco manual o automático de datos ya visibles — nunca oculta ni
  // vacía nada mientras está en vuelo, el spinner vive únicamente en el botón "Actualizar".
  // Dos signals distintos a propósito: no deben compartir semántica ni UI.
  public isLoading = signal<boolean>(true);
  public isRefreshing = signal<boolean>(false);

  // Aviso no intrusivo de un refresco fallido (manual/automático) — los datos previos
  // permanecen visibles, nunca se vacía ninguna tabla. Independiente del estado de error de
  // "nunca cargamos el hato" (ver initialLoadFailed más abajo, basado en CattleDataService).
  public refreshError = signal<string | null>(null);

  // "Actualizado hh:mm" — hora local del navegador del último refresco (inicial, tenant,
  // manual o automático) que efectivamente aplicó datos nuevos.
  public lastRefreshedAt = signal<Date | null>(null);
  public lastRefreshedLabel = computed(() => {
    const at = this.lastRefreshedAt();
    return at ? at.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) : null;
  });

  // Bumped en cada refresco EXPLÍCITO (manual o automático, nunca en el cambio de tenant —
  // CattleEventLogComponent ya reacciona a ese cambio por su cuenta). CattleEventLogComponent
  // lo recibe como input y lo usa como disparador adicional de su propio fetch — es el único
  // hijo de esta pantalla con fetch propio aparte de ComplianceAlertCardComponent (cubierto más
  // abajo vía ComplianceService.loadUppStatus/loadPsgStatus con force=true). Los demás paneles
  // (reproductive/engorda/reproduccion-dashboard) son 100% [cattleData] input, sin fetch propio.
  public refreshToken = signal<number>(0);

  // "Nunca cargamos el hato" vs. "el hato está genuinamente vacío": estado de error visible y
  // bloqueante SOLO para la carga inicial (o tras un cambio de tenant que nunca llegó a
  // resolver con éxito) — nunca se confunde con una tabla vacía normal.
  public initialLoadFailed = computed(() =>
    !this.cattleDataService.hasLoadedOnce() && !!this.cattleDataService.loadError()
  );
  public cattleLoadError = computed(() => this.cattleDataService.loadError());

  private static readonly AUTO_REFRESH_MS = 5 * 60 * 1000;
  // Cadencia de verificación "¿ya toca refrescar?" — no es el intervalo de refresco en sí
  // (ver AUTO_REFRESH_MS); mismo valor de chequeo que authorization-list.component.ts.
  private static readonly AUTO_REFRESH_CHECK_INTERVAL_MS = 30_000;

  // Navegación y Filtros de Trazabilidad Biológica
  public activeSubTab = signal<'RESUMEN' | 'INVENTARIO' | 'GASTOS' | 'VENTAS' | 'POR_ANIMAL' | 'EVENT_LOG'>('RESUMEN');
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
  // un EDITOR (capataz) no debe poder ver. VENTAS (cattle_sale_income, migration 071) is financial too.
  private static readonly ADMIN_ONLY_SUBTABS = new Set(['EVENT_LOG', 'GASTOS', 'VENTAS', 'POR_ANIMAL']);

  constructor() {
    /**
     * 🔄 EFECTO REACTIVO: Escucha activa del Contexto de Rancho.
     * Cada vez que el tenantService cambie el rancho activo en el header del ERP,
     * este bloque detectará el cambio de ID y re-orquestará el pipeline automáticamente.
     *
     * Deliberadamente SIN ningún guard de "ya hay una carga en curso": un cambio de tenant
     * SIEMPRE debe disparar una carga nueva, incluso si ya había una en vuelo (ej. un refresco
     * manual todavía resolviendo) — el guard de "nunca peticiones simultáneas apiladas" es
     * exclusivo de refreshNow()/maybeAutoRefresh(). El número de secuencia dentro de
     * loadDashboardData() es lo que garantiza que la respuesta más reciente gane siempre,
     * sin importar el orden de llegada (latest-wins).
     */
    effect(() => {
      const activeTenantId = this.tenantService.activeTenantId();

      if (activeTenantId) {
        //console.log(`🔄 [Dashboard Pipeline] Detectado cambio de rancho a ID: ${activeTenantId}. Re-indexando KPIs...`);
        this.loadDashboardData('initial');
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

    // ⏱️ Auto-refresco cada AUTO_REFRESH_MS, pausado mientras la pestaña del navegador está
    // oculta. El chequeo corre cada AUTO_REFRESH_CHECK_INTERVAL_MS (no hace falta más
    // resolución) y, al volver a visible, se revisa de inmediato si ya venció el intervalo
    // mientras estuvo oculta — sin esperar al siguiente tick del setInterval.
    const intervalId = setInterval(
      () => this.maybeAutoRefresh(),
      MainDashboardComponent.AUTO_REFRESH_CHECK_INTERVAL_MS
    );
    this.destroyRef.onDestroy(() => clearInterval(intervalId));

    const onVisibilityChange = () => this.maybeAutoRefresh();
    document.addEventListener('visibilitychange', onVisibilityChange);
    this.destroyRef.onDestroy(() => document.removeEventListener('visibilitychange', onVisibilityChange));
  }

  ngOnInit() {
    // La carga inicial ahora es gestionada de manera única por el constructor a través del effect nativo,
    // garantizando sincronía y evitando llamadas duplicadas al backend en el ciclo de vida.
  }

  private maybeAutoRefresh(): void {
    if (document.visibilityState !== 'visible') return;
    if (!isAutoRefreshDue(this.lastRefreshedAt(), Date.now(), MainDashboardComponent.AUTO_REFRESH_MS)) return;
    this.refreshNow();
  }

  /** Botón "Actualizar" y tick automático — ambos entran por aquí. Si ya hay un refresco (o la
   *  carga inicial) en curso, se omite: nunca se apilan peticiones simultáneas. El cambio de
   *  tenant NUNCA pasa por este guard (ver el effect del constructor). */
  public async refreshNow(): Promise<void> {
    if (this.isLoading() || this.isRefreshing()) return;
    await this.loadDashboardData('refresh');
  }

  // Número de secuencia global ("latest-wins"): cada llamada a loadDashboardData se queda con
  // el suyo. Si al resolver (éxito o error) ya se disparó una llamada más reciente — otro
  // refresco, o un cambio de tenant — esta respuesta se descarta sin tocar ningún signal
  // compartido (expensesList, compliance, refreshToken, lastRefreshedAt).
  private dashboardLoadSeq = 0;
  // Conteo de llamadas en vuelo por tipo — permite que isLoading/isRefreshing se apaguen solo
  // cuando la ÚLTIMA llamada pendiente de ESE tipo termina (evita que una llamada vieja apague
  // el indicador mientras una más nueva del mismo tipo todavía está en curso).
  private pendingInitialLoads = 0;
  private pendingRefreshes = 0;

  private async loadDashboardData(kind: 'initial' | 'refresh'): Promise<void> {
    const seq = ++this.dashboardLoadSeq;
    if (kind === 'initial') {
      this.pendingInitialLoads++;
      this.isLoading.set(true);
    } else {
      this.pendingRefreshes++;
      this.isRefreshing.set(true);
    }

    try {
      // El hato (cattleList) ya se recarga solo en el cambio de tenant vía el propio effect de
      // CattleDataService — repetirlo aquí para 'initial' duplicaría la petición HTTP. Para
      // 'refresh' sí hace falta pedirlo explícitamente: es la única forma de que el botón
      // "Actualizar"/el tick automático traigan eventos nuevos (ej. del Agente IA) para el
      // MISMO tenant, sin esperar a que el tenant cambie.
      const cattleReload = kind === 'refresh' ? this.cattleDataService.loadCattleData() : Promise.resolve();

      // 🔒 cattle_expenses es financiero y no-ADMIN no debe verlo (ver fix de Cattle Event Log) —
      // ni siquiera se intenta el fetch para un rol sin acceso: evita un 403 inútil contra el
      // gateway y la fila de `expensesList` nunca llega a existir en memoria para ese rol.
      const [, expensesRaw] = await Promise.all([
        cattleReload,
        this.isAdminForActiveTenant() ? this.cattleApi.getExpenses() : Promise.resolve([])
      ]);

      if (seq !== this.dashboardLoadSeq) return; // una carga más reciente ya ganó — descartar sin tocar signals

      this.expensesList.set((Array.isArray(expensesRaw) ? expensesRaw : []) as Expense[]);

      // Recarga forzada de los hijos con fetch propio, acotada al mismo guard de tenant que el
      // resto de esta carga (el `return` de arriba ya descartó cualquier respuesta de un tenant
      // que dejó de ser el activo antes de llegar aquí).
      this.complianceService.loadUppStatus(true);
      this.complianceService.loadPsgStatus(true);
      if (kind === 'refresh') this.refreshToken.update(n => n + 1); // CattleEventLogComponent reacciona a esto

      this.lastRefreshedAt.set(new Date());
      this.refreshError.set(null);
    } catch (error) {
      if (seq !== this.dashboardLoadSeq) return; // idem — no mostrar un error viejo sobre un estado ya superado

      console.error('Error en el Data Pipeline:', error);
      // MetaCRUD Silent Error Shield: NUNCA se vacía expensesList ni ninguna otra tabla — se
      // conserva la última información disponible, solo se avisa de forma no intrusiva.
      this.refreshError.set('No se pudieron actualizar los datos. Se conserva la última información disponible.');
    } finally {
      if (kind === 'initial') {
        this.pendingInitialLoads--;
        if (this.pendingInitialLoads === 0) this.isLoading.set(false);
      } else {
        this.pendingRefreshes--;
        if (this.pendingRefreshes === 0) this.isRefreshing.set(false);
      }
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

  // 🔑 Clave de reinicio compartida por las tablas paginadas de este componente: cualquier
  // cambio de módulo/especie/lote/rancho activo debe regresar a la página 1. PagedTable la
  // combina internamente con su propio `searchQuery` — no hace falta llamar `reset()` a mano
  // en ningún setter, a diferencia del `Paginator` legacy.
  public readonly operationalPanelResetKey = computed(() => ({
    tab: this.activeTab(),
    species: this.selectedSpecies(),
    lot: this.selectedLot(),
    tenant: this.tenantService.activeTenantId()
  }));

  public pesoPromedioTable = new PagedTable(
    () => this.averageWeightByLotAndCategory(),
    () => this.operationalPanelResetKey(),
    { search: { fields: row => [row.lot, row.category] } }
  );

  // Filtro estructurado "Falta" — select, no texto libre, por eso vive aparte del buscador de
  // PagedTable y se filtra ANTES de entrar a la tabla paginada (mismo patrón que especie/lote).
  public identificacionFaltaFilter = signal<'TODOS' | 'SINIIGA' | 'RFID'>('TODOS');

  private identificacionFiltrada = computed(() => {
    const filter = this.identificacionFaltaFilter();
    if (filter === 'TODOS') return this.animalsMissingIdentifier();
    return this.animalsMissingIdentifier().filter(a => {
      if (filter === 'SINIIGA') return !a.rfid_siniiga || a.rfid_siniiga === 'S/N';
      return !a.electronic_rfid; // filter === 'RFID'
    });
  });

  public identificacionTable = new PagedTable(
    () => this.identificacionFiltrada(),
    () => ({ ...this.operationalPanelResetKey(), falta: this.identificacionFaltaFilter() }),
    { search: { fields: row => [row.rfid_siniiga, row.numero_fuego] } }
  );

  public setIdentificacionFaltaFilter(value: string): void {
    this.identificacionFaltaFilter.set(value as 'TODOS' | 'SINIIGA' | 'RFID');
  }

  // Filtro estructurado "Estado" — mismo patrón que "Falta" arriba.
  public atencionEstadoFilter = signal<'TODOS' | 'RIESGO' | 'CUARENTENA' | 'EN_TRANSITO'>('TODOS');

  private atencionFiltrada = computed(() => {
    const filter = this.atencionEstadoFilter();
    const list = this.animalsNeedingAttention();
    return filter === 'TODOS' ? list : list.filter(a => (a.current_status || '').toUpperCase() === filter);
  });

  public atencionTable = new PagedTable(
    () => this.atencionFiltrada(),
    () => ({ ...this.operationalPanelResetKey(), estado: this.atencionEstadoFilter() }),
    { search: { fields: row => [row.rfid_siniiga, row.numero_fuego, row.lot_name] } }
  );

  public setAtencionEstadoFilter(value: string): void {
    this.atencionEstadoFilter.set(value as 'TODOS' | 'RIESGO' | 'CUARENTENA' | 'EN_TRANSITO');
  }

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
    if (tab === 'INVENTARIO') return this.inventorySearchedList();
    return this.filteredCattleList();
  });

  public paginatedCattleList = computed(() => {
    if (this.activeSubTab() !== 'INVENTARIO') return [];
    const startIndex = (this.pagination.currentPage() - 1) * this.pagination.pageSize();
    return this.inventorySearchedList().slice(startIndex, startIndex + this.pagination.pageSize());
  });

  /** Number of distinct animals with linked expenses (tab badge). */
  public animalsWithExpensesCount = computed(() =>
    new Set(this.filteredExpensesList().filter(e => !!e.livestock_id).map(e => e.livestock_id)).size
  );

  public setTab(tab: BusinessModel) {
    // Solo navega — activeTab es un computed derivado de la URL, se recalcula solo.
    // El effect del constructor reacciona a ese cambio y resetea subTab/paginación.
    this.router.navigate([], {
      relativeTo: this.route,
      queryParams: { tab: tab.toLowerCase() },
      queryParamsHandling: 'merge'
    });
  }

  public setSubTab(subTab: 'RESUMEN' | 'INVENTARIO' | 'GASTOS' | 'VENTAS' | 'POR_ANIMAL' | 'EVENT_LOG') {
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

}