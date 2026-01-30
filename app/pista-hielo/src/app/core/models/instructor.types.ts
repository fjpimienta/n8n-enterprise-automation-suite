export interface PhInstructor {
  id: number;
  full_name: string;      // En PHP era 'descripcion'
  specialty: 'HOCKEY' | 'ARTISTICO' | 'BASICO' | 'STAFF';
  phone?: string;
  email?: string;
  status: 'ACT' | 'INA';
  color_code?: string;    // Para identificarlo visualmente en el calendario
  created_at?: string;
}