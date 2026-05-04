import { Injectable, signal, computed } from '@angular/core';

export interface CattleAdgView {
  rfid_tag: string;
  dueno: string;
  categoria: string;
  peso_anterior: number;
  peso_actual: number;
  ganancia_diaria_kg: number;
  estatus_salud: 'ÓPTIMO' | 'PREVENTIVO' | 'CRÍTICO';
  proximo_evento: string;
}

@Injectable({
  providedIn: 'root'
})
export class CattleDataService {
  // Precio de mercado simulado para calcular capitalización
  public readonly PRECIO_KILO_MXN = 55;

  private cattleState = signal<CattleAdgView[]>([
    { rfid_tag: 'RFID-9820001', dueno: 'Dueño 1 (Engorda)', categoria: 'NOVILLO', peso_anterior: 345.5, peso_actual: 380.0, ganancia_diaria_kg: 1.15, estatus_salud: 'ÓPTIMO', proximo_evento: 'Venta (30 días)' },
    { rfid_tag: 'RFID-9820003', dueno: 'Dueño 1 (Engorda)', categoria: 'BECERRO', peso_anterior: 159.5, peso_actual: 185.0, ganancia_diaria_kg: 0.85, estatus_salud: 'PREVENTIVO', proximo_evento: 'Vacunación' },
    { rfid_tag: 'RFID-9820004', dueno: 'Dueño 3 (Mixto)', categoria: 'BECERRA', peso_anterior: 138.5, peso_actual: 140.0, ganancia_diaria_kg: 0.05, estatus_salud: 'CRÍTICO', proximo_evento: 'Revisión Nutricional' },
    { rfid_tag: 'RFID-9820002', dueno: 'Dueño 2 (Cría)', categoria: 'VACA', peso_anterior: 456.0, peso_actual: 450.0, ganancia_diaria_kg: -0.20, estatus_salud: 'CRÍTICO', proximo_evento: 'Ecografía' },
    { rfid_tag: 'RFID-9820005', dueno: 'Dueño 2 (Cría)', categoria: 'TORO', peso_anterior: 810.0, peso_actual: 815.0, ganancia_diaria_kg: 0.16, estatus_salud: 'ÓPTIMO', proximo_evento: 'Evaluación Reproductiva' }
  ]);

  public readonly cattleList = this.cattleState.asReadonly();

  // KPIs
  public totalHeads = computed(() => this.cattleState().length);
  public biomasaTotal = computed(() => this.cattleState().reduce((acc, curr) => acc + curr.peso_actual, 0));
  public capitalizacionTotal = computed(() => this.biomasaTotal() * this.PRECIO_KILO_MXN);
  public criticalAlerts = computed(() => this.cattleState().filter(a => a.estatus_salud === 'CRÍTICO').length);
  public averageAdg = computed(() => {
    const list = this.cattleState();
    return list.length ? (list.reduce((acc, curr) => acc + curr.ganancia_diaria_kg, 0) / list.length).toFixed(2) : '0';
  });
}