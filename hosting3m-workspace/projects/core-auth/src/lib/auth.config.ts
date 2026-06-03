import { InjectionToken } from '@angular/core';

// 🚀 Estructura para recibir las empresas mapeadas desde el backend (IAM Context)
export interface CompanyContext {
    id_company: number;
    company_name: string;
    role: string;
}

// Definimos la estructura de lo que la librería necesita del environment
export interface AuthEnvironmentConfig {
    apiUrl_crud: string;
    apiUrl_token: string;
    system_id: string; // <-- ID único de la app (ej. 'cattle_dashboard', 'hotel_app')
}

// Creamos el token que usaremos para inyectar esta configuración
export const AUTH_ENV_CONFIG = new InjectionToken<AuthEnvironmentConfig>('AUTH_ENV_CONFIG');