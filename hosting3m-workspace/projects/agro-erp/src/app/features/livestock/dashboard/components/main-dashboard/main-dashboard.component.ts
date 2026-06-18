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

  public cattleList = signal<any[]>([]);
  public expensesList = signal<any[]>([]);
  public isLoading = signal<boolean>(true);

  // Navegación y Filtros de Trazabilidad Biológica
  public activeTab = signal<'CRIA' | 'ENGORDA'>('CRIA');
  public activeSubTab = signal<'RESUMEN' | 'INVENTARIO' | 'GASTOS'>('RESUMEN');
  public selectedSpecies = signal<string>('TODOS'); // 🚀 Filtro maestro de especie
  public showExpenseModal = signal<boolean>(false);

  // Controladores de Paginación Única
  public currentPage = signal(1);
  public pageSize = signal(10);

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
      this.cattleList.set(Array.isArray(rawResponse) ? rawResponse : (rawResponse?.data || []));
      this.expensesList.set(Array.isArray(expensesRaw) ? expensesRaw : []);

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

  private currentDataset = computed(() => {
    return this.activeSubTab() === 'GASTOS' ? this.filteredExpensesList() : this.filteredCattleList();
  });

  public totalPages = computed(() => Math.ceil(this.currentDataset().length / this.pageSize()) || 1);

  public showingStart = computed(() => {
    if (this.currentDataset().length === 0) return 0;
    return ((this.currentPage() - 1) * this.pageSize()) + 1;
  });

  public showingEnd = computed(() => Math.min(this.currentPage() * this.pageSize(), this.currentDataset().length));

  public paginatedCattleList = computed(() => {
    if (this.activeSubTab() !== 'INVENTARIO') return [];
    const startIndex = (this.currentPage() - 1) * this.pageSize();
    return this.filteredCattleList().slice(startIndex, startIndex + this.pageSize());
  });

  public paginatedExpensesList = computed(() => {
    if (this.activeSubTab() !== 'GASTOS') return [];
    const startIndex = (this.currentPage() - 1) * this.pageSize();
    return this.filteredExpensesList().slice(startIndex, startIndex + this.pageSize());
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

  public setSubTab(subTab: 'RESUMEN' | 'INVENTARIO' | 'GASTOS') {
    this.activeSubTab.set(subTab);
    this.currentPage.set(1);
  }

  public setSpecies(species: string) {
    this.selectedSpecies.set(species);
    this.currentPage.set(1);
  }

  public changePageSize(event: Event) {
    this.pageSize.set(Number((event.target as HTMLSelectElement).value));
    this.currentPage.set(1);
  }

  public changePage(delta: number) {
    const newPage = this.currentPage() + delta;
    if (newPage >= 1 && newPage <= this.totalPages()) {
      this.currentPage.set(newPage);
    }
  }

  public biomasaTotal = computed(() => {
    return this.filteredCattleList().reduce((acc, curr) => acc + Number(curr.current_weight_kg || 0), 0);
  });

  public capitalizacionTotal = computed(() => {
    return this.biomasaTotal() * this.PRECIO_KILO;
  });
}