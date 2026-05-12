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
