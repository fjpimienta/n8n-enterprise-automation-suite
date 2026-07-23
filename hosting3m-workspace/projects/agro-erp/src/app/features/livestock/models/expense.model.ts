export interface Expense {
  id: string;
  expense_date: string;
  category: string;
  description?: string;
  amount: number;
  quantity?: number;
  unit_measure?: string;
  livestock_id?: string;
  rfid_siniiga?: string;
  business_model?: string;
  health_event_id?: string;
}
