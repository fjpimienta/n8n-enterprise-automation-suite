
export interface PhClient {
  id: number;
  id_company: number;
  legacy_id?: string;
  full_name: string;
  tutor_name?: string; // Importante para alumnos menores
  email?: string;
  phone?: string;
  client_category: 'ALUMNO' | 'GENERAL' | 'PROSPECTO';
  status: 'ACT' | 'INA' | 'SUSPENDIDO';
  notes?: string;
  membership_expiry?: string; // Viene como ISO date string de la BD
  is_vip: boolean;
  created_at?: string;
}
