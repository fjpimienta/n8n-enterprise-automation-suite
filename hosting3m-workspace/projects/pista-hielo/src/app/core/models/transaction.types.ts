// ==========================================================
// 1. METADATA (Datos Operativos en JSONB)
// ==========================================================
export interface PhTransactionMetadata {
  // --- Campos Nuevos ---
  skate_number?: string;
  rental_type?: string;
  client_category?: 'GENERAL' | 'ALUMNO';
  duration?: number;
  notes?: string;

  // --- Campos Legacy (Compatibilidad con Reportes Viejos) ---
  // Agregamos esto para que ShiftReport deje de marcar error TS4111
  client_number?: string; 
  client_type?: string; 
  client_name?: string;

  // Flexibilidad
  [key: string]: any; 
}

// ==========================================================
// 2. TRANSACTION (Mapeo de Base de Datos)
// ==========================================================
export interface PhTransaction {
  id: number;
  id_company: number;
  amount: number;
  transaction_date: string;
  status: string;

  client_id?: number;
  instructor_id?: number;
  start_time: string;
  end_time?: string;
  
  payment_method?: string;
  transaction_type?: string;
  
  // JSONB (Opcional)
  metadata?: PhTransactionMetadata; 

  // --- Propiedades Calculadas ---
  elapsedMinutes?: number;
  currentCost?: number;
  isOvertime?: boolean;
  displayName?: string;
  categoryLabel?: string;
}