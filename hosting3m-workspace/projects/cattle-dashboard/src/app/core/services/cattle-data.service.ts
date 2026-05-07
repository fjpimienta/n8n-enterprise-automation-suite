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
  caso_uso: string;
  contexto_estrategico: string;
  // Campos unificados para los modelos de negocio
  modelo: 'CRIA' | 'ENGORDA';
  estatus?: string;
  etapa?: string;
  meses_gestacion?: number;
  dias_abiertos?: number;
  alerta?: string;
}

@Injectable({
  providedIn: 'root'
})
export class CattleDataService {
  public readonly PRECIO_KILO_MXN = 55;

  private cattleState = signal<CattleAdgView[]>([
    // --- MODELO: CRÍA ---
    { rfid_tag: 'C-3524-071122', dueno: 'Socio 2', modelo: 'CRIA', categoria: 'VACA', peso_anterior: 480, peso_actual: 480, ganancia_diaria_kg: 0, estatus_salud: 'ÓPTIMO', proximo_evento: 'Monitoreo Normal', caso_uso: '1. Gestación', contexto_estrategico: 'Proyección de parto en 2 meses', estatus: 'PREÑADA', meses_gestacion: 7, alerta: '' },
    { rfid_tag: 'C-2601-100523', dueno: 'Socio 2', modelo: 'CRIA', categoria: 'VACA', peso_anterior: 450, peso_actual: 450, ganancia_diaria_kg: -0.1, estatus_salud: 'CRÍTICO', proximo_evento: 'Ecografía Urgente', caso_uso: '3. Días Abiertos', contexto_estrategico: 'Supera umbral de 120 días improductivos', estatus: 'VACÍA', meses_gestacion: 0, alerta: '145 Días Abiertos' },
    { rfid_tag: 'C-RECRIA-001', dueno: 'Socio 2', modelo: 'CRIA', categoria: 'BECERRA', peso_anterior: 200, peso_actual: 210, ganancia_diaria_kg: 0.6, estatus_salud: 'ÓPTIMO', proximo_evento: 'Revisión Peso', caso_uso: '5. Desarrollo', contexto_estrategico: 'Meta de pubertad a los 24 meses', etapa: 'RECRIA', estatus: 'DESARROLLO', alerta: '' },
    { rfid_tag: 'C-9820010', dueno: 'Socio 2', modelo: 'CRIA', categoria: 'VACA', peso_anterior: 400, peso_actual: 410, ganancia_diaria_kg: 0.33, estatus_salud: 'ÓPTIMO', proximo_evento: 'Validado', caso_uso: '10. Auditoría', contexto_estrategico: 'Evidencia fotográfica de comedero limpio', estatus: 'PREÑADA', meses_gestacion: 3, alerta: '' },

    // --- MODELO: ENGORDA ---
    { rfid_tag: 'E-9820001', dueno: 'Socio 1', modelo: 'ENGORDA', categoria: 'NOVILLO', peso_anterior: 345, peso_actual: 380, ganancia_diaria_kg: 1.15, estatus_salud: 'ÓPTIMO', proximo_evento: 'Agendar Venta', caso_uso: '12. Market Timing', contexto_estrategico: 'Alcanzó peso meta de 380kg. Listo para venta.', estatus: 'FINALIZADO', alerta: '' },
    { rfid_tag: 'E-9820002', dueno: 'Socio 1', modelo: 'ENGORDA', categoria: 'NOVILLO', peso_anterior: 180, peso_actual: 225, ganancia_diaria_kg: 1.11, estatus_salud: 'ÓPTIMO', proximo_evento: 'Rotar Potrero', caso_uso: '2. Algoritmo ADG', contexto_estrategico: 'Engorda en Lote 4-B con Silo + Pasto', estatus: 'DESARROLLO', alerta: '' },
    { rfid_tag: 'E-9820003', dueno: 'Socio 3', modelo: 'ENGORDA', categoria: 'NOVILLO', peso_anterior: 185, peso_actual: 190, ganancia_diaria_kg: 0.15, estatus_salud: 'CRÍTICO', proximo_evento: 'Revisión Médica', caso_uso: '9. Nutrición', contexto_estrategico: 'ADG por debajo de 200g. Revisar dieta.', estatus: 'RIESGO', alerta: 'Bajo Rendimiento' },
    { rfid_tag: 'E-9820004', dueno: 'Socio 1', modelo: 'ENGORDA', categoria: 'NOVILLO', peso_anterior: 280, peso_actual: 295, ganancia_diaria_kg: 0.50, estatus_salud: 'ÓPTIMO', proximo_evento: 'Rotar Potrero (Día 30)', caso_uso: '8. Pastoreo', contexto_estrategico: 'Carga animal calculada en Lote 4-B', estatus: 'DESARROLLO', alerta: '' },
    { rfid_tag: 'E-9820005', dueno: 'Socio 3', modelo: 'ENGORDA', categoria: 'TORO', peso_anterior: 500, peso_actual: 500, ganancia_diaria_kg: 0.00, estatus_salud: 'ÓPTIMO', proximo_evento: 'Entregar a Comprador', caso_uso: '7. Pasaporte QR', contexto_estrategico: 'Vendido: Generando Pasaporte Digital PDF', estatus: 'VENDIDO', alerta: '' },
    { rfid_tag: 'E-9820006', dueno: 'Socio 1', modelo: 'ENGORDA', categoria: 'BECERRO', peso_anterior: 150, peso_actual: 160, ganancia_diaria_kg: 0.33, estatus_salud: 'PREVENTIVO', proximo_evento: 'Surtir Alimento', caso_uso: '9. Stock Insumos', contexto_estrategico: 'Alerta de reorden: Quedan 4kg/día de silo', estatus: 'DESARROLLO', alerta: 'Reorden' },
    { rfid_tag: 'E-9820007', dueno: 'Socio 1', modelo: 'ENGORDA', categoria: 'NOVILLO', peso_anterior: 320, peso_actual: 330, ganancia_diaria_kg: 0.33, estatus_salud: 'PREVENTIVO', proximo_evento: 'Vacunar Brucelosis', caso_uso: '5. Sanidad', contexto_estrategico: 'Compliance: Faltan 5 días para protocolo', estatus: 'DESARROLLO', alerta: 'Vacuna Próxima' },
    { rfid_tag: 'E-9820008', dueno: 'Socio 3', modelo: 'ENGORDA', categoria: 'NOVILLO', peso_anterior: 350, peso_actual: 355, ganancia_diaria_kg: 0.16, estatus_salud: 'CRÍTICO', proximo_evento: 'Llenar Tanque', caso_uso: '11. IoT Agua', contexto_estrategico: 'Sensor ultrasónico: Nivel de agua < 25%', estatus: 'RIESGO', alerta: 'Agua Crítica' }
  ]);

  // Exponemos la lista como de solo lectura
  public readonly cattleList = this.cattleState.asReadonly();

  // KPIs Estratégicos Computados en tiempo real
  public totalHeads = computed(() => this.cattleState().length);
  public biomasaTotal = computed(() => this.cattleState().reduce((acc, curr) => acc + curr.peso_actual, 0));
  public capitalizacionTotal = computed(() => this.biomasaTotal() * this.PRECIO_KILO_MXN);
  public criticalAlerts = computed(() => this.cattleState().filter(a => a.estatus_salud === 'CRÍTICO').length);

  // KPIs Segmentados por las notas del experto
  public paricionRate = computed(() => '50%');
  public targetParicion = computed(() => '75%');

  public averageAdg = computed(() => {
    const list = this.cattleState();
    return list.length ? (list.reduce((acc, curr) => acc + curr.ganancia_diaria_kg, 0) / list.length).toFixed(2) : '0';
  });
}