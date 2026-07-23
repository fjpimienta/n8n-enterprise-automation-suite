import { Component, inject, signal, computed, OnInit, ChangeDetectionStrategy, effect } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ActivatedRoute, Router } from '@angular/router';
import { toSignal } from '@angular/core/rxjs-interop';
import { CattleApiService } from '@core/services/cattle-api.service';
import { NgApexchartsModule } from 'ng-apexcharts';
import { ReproductiveDashboardComponent } from '../reproductive-dashboard/reproductive-dashboard.component';
import { EngordaDashboardComponent } from '../engorda-dashboard/engorda-dashboard.component';
import { ExpenseModalComponent } from '../../../expenses/components/expense-modal/expense-modal.component';
import { TenantService } from 'core-auth';
import { Livestock } from '../../../models/livestock.model';
import { Expense } from '../../../models/expense.model';
import { Paginator } from '../../utils/paginator';

@Component({
  selector: 'app-main-dashboard',
  standalone: true,
  imports: [CommonModule, NgApexchartsModule, ReproductiveDashboardComponent, EngordaDashboardComponent, ExpenseModalComponent],
  templateUrl: './main-dashboard.component.html',
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class MainDashboardComponent implements OnInit {
  private cattleApi = inject(CattleApiService);
  private tenantService = inject(TenantService);
  private router = inject(Router);
  private route = inject(ActivatedRoute);

  public PRECIO_KILO = 65.00;

  public cattleList = signal<Livestock[]>([]);
  public expensesList = signal<Expense[]>([]);
  public isLoading = signal<boolean>(true);

  // Navegación y Filtros de Trazabilidad Biológica
  public activeTab = signal<'CRIA' | 'ENGORDA'>('CRIA');
  public activeSubTab = signal<'RESUMEN' | 'INVENTARIO' | 'GASTOS' | 'POR_ANIMAL'>('RESUMEN');
  public selectedSpecies = signal<string>('TODOS'); // 🚀 Filtro maestro de especie
  public showExpenseModal = signal<boolean>(false);

  // 🔎 Búsqueda reactiva del tab Inventario Detallado
  public inventorySearch = signal<string>('');

  // Controlador de Paginación Reutilizable (ver mejora #3: composable basado en signals)
  public pagination = new Paginator(() => this.currentDataset().length);

  // Bridge reactivo: convierte los queryParams del Router en un Signal nativo de Angular
  private queryParams = toSignal(this.route.queryParamMap);

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
  }

  ngOnInit() {
    // La carga inicial ahora es gestionada de manera única por el constructor a través del effect nativo,
    // garantizando sincronía y evitando llamadas duplicadas al backend en el ciclo de vida.
  }

  async loadDashboardData() {
    this.isLoading.set(true);
    try {
      const [cattleRaw, expensesRaw] = await Promise.all([
        this.cattleApi.getAllLivestock(),
        this.cattleApi.getExpenses()
      ]);

      // 🎯 DIAGNÓSTICO: Monitoreo del pipeline en consola
      // console.log('🚀 [DataPipeline] Respuesta de n8n:', cattleRaw);

      // 🛡️ SOLUCIÓN AL ERROR TS2339:
      // Castor intermedio a 'any' para evadir la restricción estricta del compilador sobre el objeto/arreglo
      const rawResponse: any = cattleRaw;

      // Si n8n regresa el array directo, se asigna. Si viene envuelto en { data: [...] }, se extrae de forma segura.
      this.cattleList.set((Array.isArray(rawResponse) ? rawResponse : (rawResponse?.data || [])) as Livestock[]);
      this.expensesList.set((Array.isArray(expensesRaw) ? expensesRaw : []) as Expense[]);

    } catch (error) {
      console.error('Error en el Data Pipeline:', error);
    } finally {
      this.isLoading.set(false);
    }
  }

  // 🚀 Extracción dinámica de especies existentes en el hato para los selectores de la UI
  public availableSpecies = computed(() => {
    const list = this.cattleList();
    // 🛡️ BLINDAJE: Si no es un array, devuelve array vacío inmediatamente
    if (!Array.isArray(list)) {
      console.warn('⚠️ [availableSpecies] Se recibió un tipo no iterable:', list);
      return [];
    }

    const speciesSet = new Set<string>(
      list.map(animal => { // Aquí ya no fallará
        if (animal.species) return animal.species;
        if (animal.metadata) {
          const meta = typeof animal.metadata === 'string' ? JSON.parse(animal.metadata) : animal.metadata;
          return meta.species;
        }
        return null;
      }).filter(Boolean)
    );
    return Array.from(speciesSet);
  });

  // 🚀 Filtrado Jerárquico: Módulo (Tab) + Especie (Selector) con sanitización
  public filteredCattleList = computed(() => {
    const currentTab = this.activeTab();
    const currentSpecies = this.selectedSpecies();

    return this.cattleList().filter(animal => {
      if (!animal.business_model) return false;

      const matchesTab = animal.business_model.trim() === currentTab;

      // Extrae la especie de forma segura desde la raíz o metadata
      const animalSpecies = animal.species || (animal.metadata ? (typeof animal.metadata === 'string' ? JSON.parse(animal.metadata).species : animal.metadata.species) : null);
      const matchesSpecies = currentSpecies === 'TODOS' || animalSpecies === currentSpecies;

      return matchesTab && matchesSpecies;
    });
  });

  // Filtrado de Gastos por Módulo y Especie vinculada
  public filteredExpensesList = computed(() => {
    const currentTab = this.activeTab();
    const currentSpecies = this.selectedSpecies();

    return this.expensesList().filter(expense => {
      // Cruzar con la tabla de ganado si el gasto tiene un livestock_id para saber su especie
      if (expense.livestock_id) {
        const animal = this.cattleList().find(a => a.id === expense.livestock_id);
        if (animal) {
          const matchesTab = animal.business_model === currentTab;
          const matchesSpecies = currentSpecies === 'TODOS' || animal.species === currentSpecies;
          return matchesTab && matchesSpecies;
        }
      }
      return !expense.business_model || expense.business_model === currentTab;
    });
  });

  // 🚩 Cuenta de animales sin UPP asignada, para el badge de alerta del inventario
  public missingUppCount = computed(() =>
    this.filteredCattleList().filter(a => !a.upp_origen?.trim()).length
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

  public setTab(tab: 'CRIA' | 'ENGORDA') {
    // Navega actualizando solo el query param 'tab'. El EFECTO 1 en el constructor
    // escucha el cambio y propaga la actualización a activeTab, activeSubTab y currentPage.
    this.router.navigate([], {
      relativeTo: this.route,
      queryParams: { tab: tab.toLowerCase() },
      queryParamsHandling: 'merge'
    });
  }

  public setSubTab(subTab: 'RESUMEN' | 'INVENTARIO' | 'GASTOS' | 'POR_ANIMAL') {
    this.activeSubTab.set(subTab);
    this.pagination.reset();
  }

  public setSpecies(species: string) {
    this.selectedSpecies.set(species);
    this.pagination.reset();
  }

  public setInventorySearch(query: string) {
    this.inventorySearch.set(query);
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
   * Balance por UPP: cruza capitalización del hato (agrupado por upp_origen) contra los gastos
   * vinculados a esos mismos animales. Los gastos sin livestock_id (o cuyo animal no tiene UPP
   * asignada) no pueden atribuirse a una UPP real y se agrupan aparte en "Gastos Generales".
   */
  public uppBalanceSummary = computed(() => {
    const cattle = this.filteredCattleList();
    const expenses = this.filteredExpensesList();

    const grouped = new Map<string, { capitalizacion: number; cabezas: number; gasto: number }>();

    for (const animal of cattle) {
      const upp = (animal.upp_origen && String(animal.upp_origen).trim()) || MainDashboardComponent.SIN_UPP;
      const entry = grouped.get(upp) ?? { capitalizacion: 0, cabezas: 0, gasto: 0 };
      entry.capitalizacion += Number(animal.current_weight_kg || 0) * this.PRECIO_KILO;
      entry.cabezas += 1;
      grouped.set(upp, entry);
    }

    let gastosGenerales = 0;
    for (const expense of expenses) {
      const animal = expense.livestock_id ? cattle.find(a => a.id === expense.livestock_id) : null;
      const upp = animal?.upp_origen && String(animal.upp_origen).trim();

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

  public uppChartOptions = computed(() => {
    const rows = this.uppBalanceSummary();
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