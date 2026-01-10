export type RoomStatus = 'available' | 'occupied' | 'maintenance';
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
}

export interface Booking {
  id: number;
  room_id: number;
  guest_id: number;
  check_in: string; // Date string
  check_out: string;
  status: 'confirmed' | 'cancelled' | 'pending';
}