export interface Expense {
    id: number;
    description: string;
    amount: number | string; // A veces la API devuelve string decimal
    category: 'Insumos' | 'Mantenimiento' | 'Limpieza' | 'Servicios' | 'Nómina' | 'Marketing' | 'Caja Chica';
    payment_method: 'Efectivo' | 'Transferencia' | 'Tarjeta Corp';
    expense_date: string;
    room_id?: number | null;
    shift_id?: number | null;
    registered_by: number;
    receipt_url?: string;
    status: 'PENDING' | 'APPROVED' | 'REJECTED';

    // Campos virtuales (JOINS)
    registered_by_name?: string;
    room_number?: string;
}