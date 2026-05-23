import { Component, inject, signal, computed, OnInit, ChangeDetectionStrategy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { CattleApiService } from '@core/services/cattle-api.service';
import { NgApexchartsModule } from 'ng-apexcharts';
import { ReproductiveDashboardComponent } from '../reproductive-dashboard/reproductive-dashboard.component';

@Component({
  selector: 'app-main-dashboard',
  standalone: true,
  imports: [CommonModule, NgApexchartsModule, ReproductiveDashboardComponent],
  templateUrl: './main-dashboard.component.html',
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class MainDashboardComponent implements OnInit {
  private cattleApi = inject(CattleApiService);

  public PRECIO_KILO = 65.00;

  public cattleList = signal<any[]>([]);
  public isLoading = signal<boolean>(true);

  // Controladores de Navegación
  public activeTab = signal<'CRIA' | 'ENGORDA'>('CRIA');
  public activeSubTab = signal<'RESUMEN' | 'INVENTARIO'>('RESUMEN');

  // Controladores de Paginación
  public currentPage = signal(1);
  public pageSize = signal(10);

  async ngOnInit() {
    await this.loadDashboardData();
  }

  async loadDashboardData() {
    this.isLoading.set(true);
    try {
      const rawData = await this.cattleApi.getAllLivestock();
      this.cattleList.set(rawData);
    } catch (error) {
      console.error('Error en el Data Pipeline de Ganadería:', error);
    } finally {
      this.isLoading.set(false);
    }
  }

  public filteredCattleList = computed(() => {
    const currentTab = this.activeTab();
    return this.cattleList().filter(animal => animal.business_model === currentTab);
  });

  public totalPages = computed(() => Math.ceil(this.filteredCattleList().length / this.pageSize()) || 1);

  public showingStart = computed(() => {
    if (this.filteredCattleList().length === 0) return 0;
    return ((this.currentPage() - 1) * this.pageSize()) + 1;
  });

  public showingEnd = computed(() => Math.min(this.currentPage() * this.pageSize(), this.filteredCattleList().length));

  public paginatedCattleList = computed(() => {
    const startIndex = (this.currentPage() - 1) * this.pageSize();
    return this.filteredCattleList().slice(startIndex, startIndex + this.pageSize());
  });

  public setTab(tab: 'CRIA' | 'ENGORDA') {
    this.activeTab.set(tab);
    this.activeSubTab.set('RESUMEN');
    this.currentPage.set(1);
  }

  public setSubTab(subTab: 'RESUMEN' | 'INVENTARIO') {
    this.activeSubTab.set(subTab);
    this.currentPage.set(1);
  }

  public changePageSize(event: Event) {
    const size = Number((event.target as HTMLSelectElement).value);
    this.pageSize.set(size);
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

  public chartOptions: any = {
    donut: { type: 'donut', height: 280, animations: { enabled: true } }
  };
}