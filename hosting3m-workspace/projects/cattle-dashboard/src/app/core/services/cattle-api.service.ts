import { Injectable, inject, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { lastValueFrom, firstValueFrom } from 'rxjs';
import { environment } from '@env/environment';
import { AuthService, TenantService } from 'core-auth';
import { LoggerService } from './logger.service';

@Injectable({ providedIn: 'root' })
export class CattleApiService {
    private http = inject(HttpClient);
    private authService = inject(AuthService);
    private tenantService = inject(TenantService);
    private logger = inject(LoggerService);
    private apiUrl_crud = environment.apiUrl_crud;

    public isProcessing = signal<boolean>(false);

    /**
     * 0. Obtener Inventario Completo (Filtrado dinámico por Contexto de Rancho)
     */
    public async getAllLivestock(): Promise<any[]> {
        const currentTenantId = this.tenantService.activeTenantId();
        if (!currentTenantId) {
            this.logger.warn('🚫 Bypass: Intento de fetch sin contexto de Tenant activo.');
            return [];
        }

        try {
            // 🚀 SOLUCIÓN DEFENSIVA: Mandamos la propiedad de ambas formas (raíz y estructurada)
            // por si el Meta-CRUD de n8n espera la misma anatomía que el 'insert' o un query directo.
            const payload = {
                operation: 'getall',
                tenant_id: Number(currentTenantId),
                fields: {
                    tenant_id: Number(currentTenantId)
                }
            };

            this.logger.log(`📡 [CattleAPI] Solicitando vw_cattle_kpi para Tenant ID: ${currentTenantId}`, payload);

            const res: any = await firstValueFrom(
                this.http.post<any>(this.apiUrl_crud + '/vw_cattle_kpi', payload)
            );

            // Desempaquetado resiliente con logs para auditoría en vivo
            if (res && Array.isArray(res)) return res;
            if (res && Array.isArray(res.data)) return res.data;
            if (res?.data && Array.isArray(res.data.data)) return res.data.data;

            return [];
        } catch (error) {
            this.logger.error('Error en getAllLivestock:', error);
            return [];
        }
    }

    /**
     * 1. Crear Alta de Animal (Asignación automática al Tenant Activo)
     */
    public async createLivestock(fields: any): Promise<void> {
        const idRanchoActivo = this.tenantService.activeTenantId();
        if (!idRanchoActivo) throw new Error('Sesión inválida: No hay un rancho activo.');

        fields.tenant_id = Number(idRanchoActivo); // 🚀 Forzamos el ID del rancho actual

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
     * 4. Registrar un nuevo Gasto Operativo
     */
    public async createExpense(fields: any): Promise<void> {
        const idRanchoActivo = this.tenantService.activeTenantId();
        if (!idRanchoActivo) throw new Error('Sesión inválida: No se detectó un rancho activo.');

        fields.tenant_id = Number(idRanchoActivo);

        const res: any = await lastValueFrom(
            this.http.post(`${this.apiUrl_crud}/cattle_expenses`, {
                operation: 'insert',
                fields: fields
            })
        );

        if (res && res.error) throw new Error(res.message);
    }

    /**
     * 5. Obtener historial de Gastos Operativos (Aislamiento de Datos por n8n/SQL)
     */
    public async getExpenses(): Promise<any[]> {
        const idRanchoActivo = this.tenantService.activeTenantId();
        if (!idRanchoActivo) {
            this.logger.warn('🚫 No se pueden solicitar gastos sin un rancho activo.');
            return [];
        }

        const payload = {
            operation: 'getall',
            // 🚀 MEJOR PRÁCTICA: Aseguramos el nombre de propiedad idéntico a allowed_fields de la DB
            tenant_id: Number(idRanchoActivo)
        };

        try {
            const res: any = await lastValueFrom(
                this.http.post(`${this.apiUrl_crud}/cattle_expenses`, payload)
            );

            if (res && Array.isArray(res.data)) {
                return res.data;
            } else if (res?.data && Array.isArray(res.data.data)) {
                return res.data.data;
            }

            return [];
        } catch (error) {
            this.logger.warn('No se pudieron cargar los gastos del Tenant:', error);
            return [];
        }
    }
}