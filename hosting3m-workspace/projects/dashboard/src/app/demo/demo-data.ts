/**
 * Synthetic data for the demo build. Every name, number and date here is invented.
 * 18 rooms: 5 Sencilla, 4 King, 8 Doble, 1 Triple. Numerics are strings and dates use the
 * gateway's midnight-UTC shape on purpose (parity with how real rows arrive).
 */
import { toLocalDateString } from '../shared/services/data-utils.service';

export interface DemoRoom {
  id: number;
  room_number: string;
  type: string;
  status: 'available' | 'occupied' | 'maintenance';
  price_night: string;
  description: string;
  cleaning_status: 'clean' | 'dirty' | 'inspected';
  id_company: number;
}

export interface DemoBooking {
  id: number;
  room_id: number;
  guest_id: number;
  status: 'checked_in' | 'confirmed' | 'pending';
  payment_status: 'paid' | 'pending';
  check_in: string;
  check_out: string;
  total_amount: string;
  hotel_guests_data: { full_name: string };
  id_company: number;
}

export interface DemoTicket {
  id: number;
  room_id: number;
  status: 'PENDING' | 'RESOLVED';
  priority: 'CRITICAL' | 'NORMAL' | 'LOW';
  description: string;
  created_at: string;
  id_company: number;
}

/** Deliberately synthetic; not a real tenant id. */
export const DEMO_COMPANY_ID = 9001;

/** Local calendar day shifted by `days`, as the gateway's midnight-UTC string. */
export function dayOffsetStamp(days: number, base: Date = new Date()): string {
  const d = new Date(base.getFullYear(), base.getMonth(), base.getDate() + days);
  return `${toLocalDateString(d)}T00:00:00.000Z`;
}

type RoomSeed = [number, string, string, DemoRoom['status'], DemoRoom['cleaning_status'], string];

const ROOM_SEEDS: RoomSeed[] = [
  [1, '101', 'SENCILLA', 'occupied', 'clean', '1 cama individual'],
  [2, '102', 'SENCILLA', 'available', 'clean', '1 cama individual'],
  [3, '103', 'SENCILLA', 'available', 'dirty', '1 cama individual'],
  [4, '104', 'SENCILLA', 'available', 'clean', '1 cama individual'],
  [5, '105', 'SENCILLA', 'maintenance', 'clean', '1 cama individual'],
  [6, '201', 'KING', 'occupied', 'clean', '1 cama king size'],
  [7, '202', 'KING', 'available', 'clean', '1 cama king size'],
  [8, '203', 'KING', 'occupied', 'clean', '1 cama king size'],
  [9, '204', 'KING', 'available', 'clean', '1 cama king size'],
  [10, '301', 'DOBLE', 'occupied', 'clean', '2 camas matrimoniales'],
  [11, '302', 'DOBLE', 'occupied', 'clean', '2 camas matrimoniales'],
  [12, '303', 'DOBLE', 'available', 'clean', '2 camas matrimoniales'],
  [13, '304', 'DOBLE', 'available', 'dirty', '2 camas matrimoniales'],
  [14, '305', 'DOBLE', 'available', 'clean', '2 camas matrimoniales'],
  [15, '306', 'DOBLE', 'occupied', 'clean', '2 camas matrimoniales'],
  [16, '307', 'DOBLE', 'available', 'inspected', '2 camas matrimoniales'],
  [17, '308', 'DOBLE', 'occupied', 'clean', '2 camas matrimoniales'],
  [18, '401', 'TRIPLE', 'available', 'clean', '3 camas individuales']
];

const PRICE: Record<string, string> = { SENCILLA: '650.00', KING: '950.00', DOBLE: '850.00', TRIPLE: '1100.00' };

export function buildDemoRooms(): DemoRoom[] {
  return ROOM_SEEDS.map(([id, room_number, type, status, cleaning_status, description]) => ({
    id, room_number, type, status, cleaning_status, description,
    price_night: PRICE[type] ?? '0.00',
    id_company: DEMO_COMPANY_ID
  }));
}

type BookingSeed = [number, number, DemoBooking['status'], number, number, string, DemoBooking['payment_status']];

/** [id, room_id, status, check-in offset (days), check-out offset (days), guest initials, payment] */
const BOOKING_SEEDS: BookingSeed[] = [
  [1, 1, 'checked_in', -2, 0, 'M. R.', 'paid'],
  [2, 6, 'checked_in', -1, 2, 'A. L.', 'paid'],
  [3, 8, 'checked_in', -3, 0, 'J. P.', 'pending'],
  [4, 10, 'checked_in', -1, 1, 'C. T.', 'paid'],
  [5, 11, 'checked_in', 0, 3, 'D. V.', 'pending'],
  [6, 15, 'checked_in', -2, 0, 'L. G.', 'paid'],
  [7, 17, 'checked_in', -1, 2, 'R. S.', 'paid'],
  [8, 4, 'confirmed', 0, 2, 'E. H.', 'pending'],
  [9, 14, 'confirmed', 0, 1, 'F. M.', 'paid'],
  [10, 18, 'pending', 3, 5, 'K. O.', 'pending'],
  [11, 12, 'confirmed', 2, 4, 'N. B.', 'pending'],
  // Same-day turnover: room 101 leaves today and receives this booking today (occupied, so no arrivals KPI change).
  [12, 1, 'confirmed', 0, 2, 'P. Q.', 'pending'],
  // Dirty room with an arrival today (urgent for housekeeping). Raises the demo's arrivals KPI from 2 to 3.
  [13, 3, 'confirmed', 0, 1, 'S. T.', 'pending']
];

export function buildDemoBookings(base: Date = new Date()): DemoBooking[] {
  return BOOKING_SEEDS.map(([id, room_id, status, inOff, outOff, initials, payment_status]) => ({
    id, room_id, status, payment_status,
    guest_id: 100 + id,
    check_in: dayOffsetStamp(inOff, base),
    check_out: dayOffsetStamp(outOff, base),
    total_amount: '1700.00',
    hotel_guests_data: { full_name: initials },
    id_company: DEMO_COMPANY_ID
  }));
}

export function buildDemoTickets(base: Date = new Date()): DemoTicket[] {
  const stamp = `${toLocalDateString(base)}T09:00:00.000Z`;
  return [
    { id: 1, room_id: 5, status: 'PENDING', priority: 'CRITICAL', description: 'Demo ticket', created_at: stamp, id_company: DEMO_COMPANY_ID },
    { id: 2, room_id: 9, status: 'PENDING', priority: 'NORMAL', description: 'Demo ticket', created_at: stamp, id_company: DEMO_COMPANY_ID },
    { id: 3, room_id: 2, status: 'RESOLVED', priority: 'LOW', description: 'Demo ticket', created_at: stamp, id_company: DEMO_COMPANY_ID }
  ];
}
