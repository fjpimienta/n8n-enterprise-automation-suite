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
    registration_date?: string | Date;
    last_contact?: string | Date;
    notes?: string;
    is_default: boolean;
    business_type?: 'AGRICULTURE' | 'LIVESTOCK' | 'ADMIN';
    metadata?: {
        nombre_productor?: string;
        clave_upp?: string;
        folio_holograma?: string;
        curp?: string;
        rfc?: string;
        superficie_ha?: number;
        fecha_alta?: string;
        [key: string]: any;
    };
}