import { Component, inject, signal, computed, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { CattleApiService } from '@core/services/cattle-api.service';
import { NgApexchartsModule } from 'ng-apexcharts';

@Component({
  selector: 'app-main-dashboard',
  standalone: true,
  imports: [CommonModule, NgApexchartsModule],
  templateUrl: './main-dashboard.component.html'
})
export class MainDashboardComponent implements OnInit {
  private cattleApi = inject(CattleApiService);

  // Variables de Negocio
  public PRECIO_KILO = 65.00; // Precio de mercado (Puedes cambiarlo después a una configuración de la DB)

  public cattleList = signal<any[]>([]);
  public isLoading = signal<boolean>(true);
  public activeTab = signal<'TODOS' | 'CRIA' | 'ENGORDA'>('TODOS');

  async ngOnInit() {
    await this.loadDashboardData();
  }

  // 🚀 Descarga y procesa la data real de PostgreSQL
  async loadDashboardData() {
    this.isLoading.set(true);
    try {
      const rawData = await this.cattleApi.getAllLivestock();

      // Mapeamos los datos de la vista SQL (vw_cattle_kpi) al formato visual del Dashboard
      const mappedData = rawData.map(animal => {

        // Regla de Negocio: Semáforo de Salud basado en días de abandono
        let salud = 'ÓPTIMO';
        const diasSinRevision = animal.days_since_last_event;

        if (diasSinRevision === null || diasSinRevision > 90) {
          salud = 'CRÍTICO'; // Más de 3 meses sin checar
        } else if (diasSinRevision > 45) {
          salud = 'PREVENTIVO'; // Alerta amarilla
        }

        return {
          ...animal,
          rfid_tag: animal.rfid_siniiga,
          modelo: animal.business_model,
          peso_actual: Number(animal.current_weight_kg) || 0,
          ganancia_diaria_kg: Number(animal.adg_lifetime_kg) || 0,
          estatus_salud: salud,
          proximo_evento: animal.last_palpation_result ? `DX: ${animal.last_palpation_result}` : 'Sin DX Reciente'
        };
      });

      this.cattleList.set(mappedData);
    } catch (error) {
      console.error('Error cargando KPIs:', error);
    } finally {
      this.isLoading.set(false);
    }
  }

  // Lógica de Filtrado (Reactiva)
  public filteredCattleList = computed(() => {
    const currentTab = this.activeTab();
    const list = this.cattleList();
    if (currentTab === 'TODOS') return list;
    return list.filter(animal => animal.modelo === currentTab);
  });

  // ==========================================
  // KPIs (Matemáticas en tiempo real)
  // ==========================================
  public biomasaTotal = computed(() => this.filteredCattleList().reduce((acc, curr) => acc + curr.peso_actual, 0));
  public capitalizacionTotal = computed(() => this.biomasaTotal() * this.PRECIO_KILO);
  public criticalAlerts = computed(() => this.filteredCattleList().filter(a => a.estatus_salud === 'CRÍTICO').length);
  public averageAdg = computed(() => {
    const list = this.filteredCattleList();
    return list.length ? (list.reduce((acc, curr) => acc + curr.ganancia_diaria_kg, 0) / list.length).toFixed(2) : '0.00';
  });

  // ==========================================
  // CONFIGURACIÓN DE GRÁFICAS (SERIES REACTIVAS)
  // ==========================================
  public get healthSeries(): any {
    const list = this.filteredCattleList();
    return [
      list.filter(a => a.estatus_salud === 'ÓPTIMO').length,
      list.filter(a => a.estatus_salud === 'PREVENTIVO').length,
      list.filter(a => a.estatus_salud === 'CRÍTICO').length
    ];
  }

  public get biomasaSeries(): any {
    return [{
      name: 'Peso (kg)',
      data: this.filteredCattleList().map(a => a.peso_actual)
    }];
  }

  public get biomasaX(): any {
    return {
      categories: this.filteredCattleList().map(a => a.rfid_tag),
      labels: { show: false },
      axisBorder: { show: false }
    };
  }

  public setTab(tab: 'TODOS' | 'CRIA' | 'ENGORDA') {
    this.activeTab.set(tab);
  }

  // ==========================================
  // CONFIGURACIÓN DE TENDENCIAS (MOCK DATA TEMPORAL)
  // ==========================================
  public get biomassTrendSeries(): any {
    return [{
      name: 'Biomasa Total (kg)',
      data: [3200, 3450, 3600, 3750, 3890, 3985] // Próxima iteración: leeremos el histórico
    }];
  }

  public get biomassTrendX(): any {
    return { categories: ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun'], tooltip: { enabled: true } };
  }

  public chartOptions: any = {
    donut: { type: 'donut', height: 280, animations: { enabled: true } },
    bar: { type: 'bar', height: 280, toolbar: { show: false } },
    area: {
      type: 'area', height: 300, toolbar: { show: false },
      stroke: { curve: 'smooth', width: 2 },
      fill: { type: 'gradient', gradient: { shadeIntensity: 1, opacityFrom: 0.7, opacityTo: 0.2, stops: [0, 90, 100] } },
      dataLabels: { enabled: false }
    },
    plotOptions: { bar: { borderRadius: 4, columnWidth: '60%', dataLabels: { position: 'top' } } },
    colors: { health: ['#2fb344', '#f76707', '#d63939'], primary: ['#206bc4'], trend: ['#206bc4'] }
  };
}