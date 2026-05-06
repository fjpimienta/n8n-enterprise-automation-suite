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
  // Nuevos campos para el MVP
  caso_uso: string;
  contexto_estrategico: string;
}

@Injectable({
  providedIn: 'root'
})
export class CattleDataService {
  public readonly PRECIO_KILO_MXN = 55;

  private cattleState = signal<CattleAdgView[]>([
    // Operación y Trazabilidad
    { rfid_tag: 'RFID-001', dueno: 'Dueño 1', categoria: 'NOVILLO', peso_anterior: 300, peso_actual: 335, ganancia_diaria_kg: 1.16, estatus_salud: 'ÓPTIMO', proximo_evento: 'Monitoreo Normal', caso_uso: '1. Onboarding', contexto_estrategico: 'Alta por WhatsApp con geolocalización' },
    { rfid_tag: 'RFID-008', dueno: 'Dueño 1', categoria: 'NOVILLO', peso_anterior: 280, peso_actual: 295, ganancia_diaria_kg: 0.50, estatus_salud: 'ÓPTIMO', proximo_evento: 'Rotar Potrero (Día 30)', caso_uso: '8. Pastoreo', contexto_estrategico: 'Carga animal calculada en Lote 4-B' },
    { rfid_tag: 'RFID-009', dueno: 'Dueño 1', categoria: 'BECERRA', peso_anterior: 150, peso_actual: 160, ganancia_diaria_kg: 0.33, estatus_salud: 'PREVENTIVO', proximo_evento: 'Surtir Alimento', caso_uso: '9. Stock Insumos', contexto_estrategico: 'Alerta de reorden: Quedan 4kg/día de silo' },
    { rfid_tag: 'RFID-010', dueno: 'Dueño 2', categoria: 'VACA', peso_anterior: 400, peso_actual: 410, ganancia_diaria_kg: 0.33, estatus_salud: 'ÓPTIMO', proximo_evento: 'Validado', caso_uso: '10. Auditoría', contexto_estrategico: 'Evidencia fotográfica de comedero limpio' },

    // Salud y Biología
    { rfid_tag: 'RFID-002', dueno: 'Dueño 1', categoria: 'NOVILLO', peso_anterior: 310, peso_actual: 348, ganancia_diaria_kg: 1.26, estatus_salud: 'ÓPTIMO', proximo_evento: 'Venta Cercana', caso_uso: '2. Algoritmo ADG', contexto_estrategico: 'Engorda óptima (Dieta + Suplemento)' },
    { rfid_tag: 'RFID-003', dueno: 'Dueño 2', categoria: 'VACA', peso_anterior: 450, peso_actual: 450, ganancia_diaria_kg: 0.00, estatus_salud: 'CRÍTICO', proximo_evento: 'Ecografía Urgente', caso_uso: '3. Días Abiertos', contexto_estrategico: 'Alerta: 145 días sin preñez (Pérdida neta)' },
    { rfid_tag: 'RFID-005', dueno: 'Dueño 1', categoria: 'NOVILLO', peso_anterior: 320, peso_actual: 330, ganancia_diaria_kg: 0.33, estatus_salud: 'PREVENTIVO', proximo_evento: 'Vacunar Brucelosis', caso_uso: '5. Sanidad', contexto_estrategico: 'Compliance: Faltan 5 días para protocolo' },

    // Finanzas e Inteligencia
    { rfid_tag: 'RFID-006', dueno: 'Dueño 3', categoria: 'VACA', peso_anterior: 410, peso_actual: 425, ganancia_diaria_kg: 0.50, estatus_salud: 'ÓPTIMO', proximo_evento: 'Retención', caso_uso: '6. Equity', contexto_estrategico: 'Valuación +35% respecto a compra' },
    { rfid_tag: 'RFID-007', dueno: 'Dueño 2', categoria: 'TORO', peso_anterior: 500, peso_actual: 500, ganancia_diaria_kg: 0.00, estatus_salud: 'ÓPTIMO', proximo_evento: 'Entregar a Comprador', caso_uso: '7. Pasaporte QR', contexto_estrategico: 'Vendido: Generando Pasaporte Digital PDF' },
    { rfid_tag: 'RFID-012', dueno: 'Dueño 1', categoria: 'NOVILLO', peso_anterior: 390, peso_actual: 415, ganancia_diaria_kg: 0.83, estatus_salud: 'ÓPTIMO', proximo_evento: 'Agendar Venta', caso_uso: '12. Market Timing', contexto_estrategico: 'Punto de equilibrio financiero alcanzado' },

    // Capa de IA e IoT
    { rfid_tag: 'RFID-004', dueno: 'Dueño 3', categoria: 'BECERRO', peso_anterior: 180, peso_actual: 182, ganancia_diaria_kg: 0.06, estatus_salud: 'CRÍTICO', proximo_evento: 'Revisión Médica', caso_uso: '4. Agente IA', contexto_estrategico: 'Anomalía de comportamiento detectada por IA' },
    { rfid_tag: 'RFID-011', dueno: 'Dueño 3', categoria: 'NOVILLO', peso_anterior: 350, peso_actual: 355, ganancia_diaria_kg: 0.16, estatus_salud: 'CRÍTICO', proximo_evento: 'Llenar Tanque', caso_uso: '11. IoT Agua', contexto_estrategico: 'Sensor ultrasónico: Nivel de agua < 25%' }
  ]);

  public readonly cattleList = this.cattleState.asReadonly();

  // KPIs Estratégicos Computados en tiempo real
  public totalHeads = computed(() => this.cattleState().length);
  public biomasaTotal = computed(() => this.cattleState().reduce((acc, curr) => acc + curr.peso_actual, 0));
  public capitalizacionTotal = computed(() => this.biomasaTotal() * this.PRECIO_KILO_MXN);
  public criticalAlerts = computed(() => this.cattleState().filter(a => a.estatus_salud === 'CRÍTICO').length);

  public averageAdg = computed(() => {
    const list = this.cattleState();
    return list.length ? (list.reduce((acc, curr) => acc + curr.ganancia_diaria_kg, 0) / list.length).toFixed(2) : '0';
  });
}