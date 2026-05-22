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
}