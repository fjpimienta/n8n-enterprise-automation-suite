import { Component, inject, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { CattleDataService } from '../../../../core/services/cattle-data.service';
import { NgApexchartsModule } from 'ng-apexcharts';

@Component({
  selector: 'app-main-dashboard',
  standalone: true,
  imports: [CommonModule, NgApexchartsModule],
  templateUrl: './main-dashboard.component.html'
})
export class MainDashboardComponent {
  private dataService = inject(CattleDataService);

  // Variables de Negocio
  public PRECIO_KILO = this.dataService.PRECIO_KILO_MXN;
  public cattleList = this.dataService.cattleList;
  public mortandadActual = this.dataService.mortandadActual;
  public bullEfficiency = this.dataService.bullEfficiency;
  public sementalesActivos = this.dataService.sementalesActivos;
  public vacasEnEmpadre = this.dataService.vacasEnEmpadre;

  public activeTab = signal<'TODOS' | 'CRIA' | 'ENGORDA'>('TODOS');

  // Lógica de Filtrado (Reactiva)
  public filteredCattleList = computed(() => {
    const currentTab = this.activeTab();
    const list = this.cattleList();
    if (currentTab === 'TODOS') return list;
    return list.filter(animal => animal.modelo === currentTab);
  });

  // KPIs
  public biomasaTotal = computed(() => this.filteredCattleList().reduce((acc, curr) => acc + curr.peso_actual, 0));
  public capitalizacionTotal = computed(() => this.biomasaTotal() * this.PRECIO_KILO);
  public criticalAlerts = computed(() => this.filteredCattleList().filter(a => a.estatus_salud === 'CRÍTICO').length);
  public averageAdg = computed(() => {
    const list = this.filteredCattleList();
    return list.length ? (list.reduce((acc, curr) => acc + curr.ganancia_diaria_kg, 0) / list.length).toFixed(2) : '0.00';
  });

  // ==========================================
  // CONFIGURACIÓN DE GRÁFICAS (MODO COMPATIBILIDAD)
  // ==========================================

  // Forzamos el retorno a 'any' para evitar que el compilador de Angular busque Signals en la librería
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

  // Opciones Estáticas (sin Signals)
 /* public chartOptions: any = {
    donut: {
      type: 'donut',
      height: 280,
      animations: { enabled: true }
    },
    bar: {
      type: 'bar',
      height: 280,
      toolbar: { show: false }
    },
    plotOptions: {
      bar: { borderRadius: 4, columnWidth: '60%', dataLabels: { position: 'top' } }
    },
    colors: {
      health: ['#2fb344', '#f76707', '#d63939'],
      primary: ['#206bc4']
    }
  };
  */

  public setTab(tab: 'TODOS' | 'CRIA' | 'ENGORDA') {
    this.activeTab.set(tab);
  }

  // ==========================================
  // CONFIGURACIÓN DE TENDENCIAS (MOCK DATA)
  // ==========================================

  public get biomassTrendSeries(): any {
    return [{
      name: 'Biomasa Total (kg)',
      data: [3200, 3450, 3600, 3750, 3890, 3985] // Datos estáticos simulados
    }];
  }

  public get biomassTrendX(): any {
    return {
      categories: ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun'],
      tooltip: { enabled: true }
    };
  }

  // Actualiza tu objeto chartOptions agregando la configuración "area"
  public chartOptions: any = {
    // ... (mantén tu configuración donut y bar intacta)
    donut: { type: 'donut', height: 280, animations: { enabled: true } },
    bar: { type: 'bar', height: 280, toolbar: { show: false } },
    area: {
      type: 'area',
      height: 300,
      toolbar: { show: false },
      stroke: { curve: 'smooth', width: 2 },
      fill: {
        type: 'gradient',
        gradient: { shadeIntensity: 1, opacityFrom: 0.7, opacityTo: 0.2, stops: [0, 90, 100] }
      },
      dataLabels: { enabled: false }
    },
    plotOptions: {
      bar: { borderRadius: 4, columnWidth: '60%', dataLabels: { position: 'top' } }
    },
    colors: {
      health: ['#2fb344', '#f76707', '#d63939'],
      primary: ['#206bc4'],
      trend: ['#206bc4'] // Azul estándar de Tabler
    }
  };
}