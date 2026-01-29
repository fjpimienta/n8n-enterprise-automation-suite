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
  transaction_type: 'RENTAL' | 'SALE';
  status: 'ACT' | 'FIN' | 'CAN';
  start_time: string;
  transaction_date: string;

  end_time?: string;
  amount?: number | string;
  payment_method?: 'CASH' | 'CARD';

  metadata: {
    skate_number?: string;
    client_type?: 'GENERAL' | 'ALUMNO';
    client_name?: string;

    // --- AGREGAR ESTO ---
    client_number?: string; // <--- El campo que faltaba
    // --------------------

    notes?: string;
  };

}