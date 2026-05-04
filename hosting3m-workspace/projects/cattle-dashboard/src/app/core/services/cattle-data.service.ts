import { Injectable, signal, computed } from '@angular/core';

export interface CattleAdgView {
  rfid_tag: string;
  dueno: string;
  peso_anterior: number;
  peso_actual: number;
  ganancia_diaria_kg: number;
}

@Injectable({
  providedIn: 'root'
})
export class CattleDataService {
  // Estado inmutable de la Fase 0
  private cattleState = signal<CattleAdgView[]>([
    { rfid_tag: 'RFID-9820001', dueno: 'Dueño 1 (Modelo Engorda)', peso_anterior: 345.50, peso_actual: 380.00, ganancia_diaria_kg: 1.15 },
    { rfid_tag: 'RFID-9820003', dueno: 'Dueño 1 (Modelo Engorda)', peso_anterior: 159.50, peso_actual: 185.00, ganancia_diaria_kg: 0.85 },
    { rfid_tag: 'RFID-9820004', dueno: 'Dueño 3 (Modelo Mixto)', peso_anterior: 138.50, peso_actual: 140.00, ganancia_diaria_kg: 0.05 },
    { rfid_tag: 'RFID-9820002', dueno: 'Dueño 2 (Modelo Cría)', peso_anterior: 456.00, peso_actual: 450.00, ganancia_diaria_kg: -0.20 }
  ]);

  public readonly cattleList = this.cattleState.asReadonly();

  // KPIs Estratégicos
  public totalHeads = computed(() => this.cattleState().length);
  public criticalAlerts = computed(() => this.cattleState().filter(a => a.ganancia_diaria_kg < 0.2).length);
  public averageAdg = computed(() => {
    const list = this.cattleState();
    if (list.length === 0) return 0;
    return (list.reduce((acc, curr) => acc + curr.ganancia_diaria_kg, 0) / list.length).toFixed(2);
  });
}