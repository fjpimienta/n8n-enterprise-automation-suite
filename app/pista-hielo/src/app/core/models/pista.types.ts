// src/app/core/models/pista.types.ts

export type ClientCategory = 'ALUMNO' | 'GENERAL' | 'VIP';
export type TransactionStatus = 'ACT' | 'PAG' | 'CAN'; // Mapeo de PHP Legacy

export interface PhClient {
  id: number;
  full_name: string;
  tutor_name?: string;
  phone?: string;
  email?: string;
  client_category: ClientCategory;
  is_vip: boolean;
  membership_expiry?: string;
  status: string;
}

export interface PhTransaction {
  id: number;
  client_id: number;
  amount: number;
  transaction_type: string;
  status: TransactionStatus;
  start_time: string;
  end_time?: string;
  metadata?: any; // Para guardar el ID del Patín y Zamboni
}