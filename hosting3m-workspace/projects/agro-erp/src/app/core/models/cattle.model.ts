export interface CattleRecord {
    id: number;
    rfid_tag: string;
    tenant_id: number;
    category: string;
    breed: string;
    status: string;
    // El campo metadata nos permite mapear los 12 escenarios
    metadata: {
        adg_proyectado?: number;
        dias_abiertos?: number;
        proxima_vacuna?: string;
        valor_mercado_est?: number;
        potrero?: string;
        [key: string]: any; // Firma de índice para flexibilidad total
    };
}