export type RoomStatus = 'available' | 'occupied' | 'maintenance' | 'dirty';
export type CleaningStatus = 'clean' | 'dirty' | 'inspected';

export interface Room {
  id: number;
  room_number: string;
  type: string;
  status: RoomStatus;
  price_night: number;
  description?: string;
  cleaning_status: CleaningStatus;
  next_reservation?: string; // Campo calculado que podemos traer del backend
  hasIncomingToday?: boolean; // Campo calculado para saber si hay reserva que entra hoy
}

export interface Booking {
  id: number;
  room_id: number;
  guest_id: number;
  check_in: string; // Date string
  check_out: string;
  status: 'confirmed' | 'cancelled' | 'pending';
}

export interface Company {
  id_company: number;
  company_name: string;
  relation_type?: string;
  industry?: string;
  company_size?: string;
  location?: string;
  employees?: number;
  annual_revenue?: string;
  priority_level?: string;
  registration_date?: string | Date; // Date de Postgres llega como string ISO
  last_contact?: string | Date;
  notes?: string;
  is_default: boolean;
}

export interface User {
  email: string;
  id_company: number;
  names: string;
  lastname?: string;   // Opcional en DB
  password?: string;   // Opcional en la interfaz si no quieres exponerlo en el frontend
  is_active: boolean;
  phone?: string;
  role: 'ADMIN' | 'EDITOR' | 'CUSTOMER'; // Basado en tu CHECK constraint
  created_at: string | Date; // Al igual que Company, llega como ISO string
}

export interface Guest {
  id: number;
  full_name: string;
  phone?: string;
  email?: string;
  doc_id?: string;
  vip_status: boolean;
  created_at: string | Date;
  ine_front_url?: string;
  ine_back_url?: string;
  id_company: number;
  city?: string;
  state?: string;
  country: string;
  notes?: string;
  requires_invoice: boolean;
  is_active: boolean;
}