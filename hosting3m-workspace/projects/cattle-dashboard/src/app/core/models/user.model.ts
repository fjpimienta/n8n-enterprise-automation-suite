export interface User {
  email: string;
  id_company: number;
  names: string;
  lastname?: string;
  password?: string;
  is_active: boolean;
  phone?: string;
  role: 'ADMIN' | 'EDITOR' | 'CUSTOMER';
  created_at: string | Date;
}
