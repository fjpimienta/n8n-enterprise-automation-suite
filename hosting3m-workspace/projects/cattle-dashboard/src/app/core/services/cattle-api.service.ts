import { Injectable, inject, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { lastValueFrom } from 'rxjs';
import { environment } from '@env/environment';
import { AuthService, TenantService } from 'core-auth';
// 🚀 FIX: Importamos el LoggerService para poder usarlo
import { LoggerService } from './logger.service';

//import { LoggerService } from 'core-auth';

@Injectable({ providedIn: 'root' })
export class CattleApiService {
    private http = inject(HttpClient);
    private authService = inject(AuthService);
    // 🚀 FIX: Inyectamos el logger
    private logger = inject(LoggerService);
    private apiUrl_crud = environment.apiUrl_crud;

    public isProcessing = signal<boolean>(false);

    private tenantService = inject(TenantService);

    // 0. Obtener Inventario Completo (Ahora lee de la Vista SQL con los KPIs integrados)
    public async getAllLivestock(): Promise<any[]> {
        try {
            const payload = {
                operation: 'getall',
                id_company: this.tenantService.activeTenantId() // 🚀 Extraemos el ID del rancho activo
            };

            const res: any = await lastValueFrom(
                this.http.post(`${this.apiUrl_crud}/vw_cattle_kpi`, payload)
            );

            // 🛡️ NULL SAFETY: Verificamos que res y res.data existan antes de leerlos
            if (!res || !res.data) {
                this.logger.warn('La API no devolvió datos (res o res.data es null)');
                return []; // Retornamos un arreglo vacío para evitar el colapso del Dashboard
            }

            return res.data;

        } catch (error) {
            this.logger.error('Error crítico en el data pipeline (getAllLivestock):', error);
            return []; // Fallback seguro
        }
    }

    async getInventario() {
        // 🚀 Extraes el ID del rancho que el usuario seleccionó en el login
        const idRanchoActivo = this.tenantService.activeTenantId();

        if (!idRanchoActivo) {
            console.error("No hay un rancho seleccionado");
            return;
        }

        // Envías ese ID a tu backend para filtrar los datos
        return this.http.post('tu-url-api/vw_cattle_kpi', {
            operation: 'getall',
            id_company: idRanchoActivo
        }).toPromise();
    }

    // 1. Crear Alta de Animal
    public async createLivestock(fields: any): Promise<void> {
        const companyId = this.authService.currentUser()?.id_company;
        if (!companyId) throw new Error('Sesión inválida: No se detectó una empresa activa.');

        fields.tenant_id = companyId;

        const res: any = await lastValueFrom(
            this.http.post(`${this.apiUrl_crud}/cattle_livestock`, {
                operation: 'insert',
                fields: fields
            })
        );

        if (res && res.error) throw new Error(res.message);
    }

    // 2. Crear Evento Sanitario
    public async createHealthLog(fields: any): Promise<void> {
        const res: any = await lastValueFrom(
            this.http.post(`${this.apiUrl_crud}/cattle_health_logs`, {
                operation: 'insert',
                fields: fields
            })
        );
        if (res && res.error) throw new Error(res.message);
    }

    // 3. Crear Registro de Peso
    public async createWeightLog(fields: any): Promise<void> {
        const res: any = await lastValueFrom(
            this.http.post(`${this.apiUrl_crud}/cattle_weight_logs`, {
                operation: 'insert',
                fields: fields
            })
        );
        if (res && res.error) throw new Error(res.message);
    }

    /**
     * Registra un nuevo Gasto Operativo
     */
    public async createExpense(fields: any): Promise<void> {
        const companyId = this.authService.currentUser()?.id_company;
        if (!companyId) throw new Error('Sesión inválida: No se detectó una empresa activa.');

        fields.tenant_id = companyId;

        const res: any = await lastValueFrom(
            this.http.post(`${this.apiUrl_crud}/cattle_expenses`, {
                operation: 'insert',
                fields: fields
            })
        );

        if (res && res.error) throw new Error(res.message);
    }

    /**
     * 🚀 FIX: Obtener historial de gastos operativos refactorizado
     * Utiliza async/await para ser compatible con main-dashboard.component.ts
     * y aplica el patrón defensivo contra nulos.
     */
    public async getExpenses(): Promise<any[]> {
        const companyId = this.authService.currentUser()?.id_company;

        // El payload que n8n espera para leer datos
        const payload = {
            operation: 'getall'
        };

        try {
            // Hacemos la petición HTTP al endpoint de gastos (ajusta la URL si es necesario)
            const res: any = await lastValueFrom(
                // OJO: No necesitas getAuthHeaders porque tu Interceptor ya los inyecta
                this.http.post(`${this.apiUrl_crud}/cattle_expenses`, payload)
            );

            // 🛡️ PATRÓN DEFENSIVO: Si res y res.data existen, devolvemos el arreglo
            if (res && Array.isArray(res.data)) {
                // Filtramos por seguridad para que solo vea los de su empresa
                return res.data.filter((expense: any) => Number(expense.tenant_id) === Number(companyId));
            } else if (res && res.data && Array.isArray(res.data.data)) {
                // Por si n8n manda el doble envoltorio
                return res.data.data.filter((expense: any) => Number(expense.tenant_id) === Number(companyId));
            }

            return []; // Si no hay datos, retornamos arreglo vacío

        } catch (error) {
            // Capturamos el error 404/500 silenciosamente para que no rompa la UI
            this.logger.warn('No se pudieron cargar los gastos del Tenant:', error);
            return [];
        }
    }
}