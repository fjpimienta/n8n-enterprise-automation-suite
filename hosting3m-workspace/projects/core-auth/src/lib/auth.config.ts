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
    apiUrl_ai: string;
    apiUrl_upload?: string; // <-- Optional: only required by apps that upload files (e.g. compliance documents). Additive, non-breaking for existing consumers.
    system_id: string; // <-- ID único de la app (ej. 'cattle_dashboard', 'hotel_app')
    /**
     * Optional, opt-in offline grace window in milliseconds after JWT expiry.
     * Only read by `AuthService.getSessionState()`. Undefined (or not a positive finite number)
     * means no grace: behavior is exactly as before. It never changes `getStoredToken()`,
     * `isAuthenticated`, the guards or the interceptors.
     */
    offlineGraceMs?: number;
}

// Creamos el token que usaremos para inyectar esta configuración
export const AUTH_ENV_CONFIG = new InjectionToken<AuthEnvironmentConfig>('AUTH_ENV_CONFIG');