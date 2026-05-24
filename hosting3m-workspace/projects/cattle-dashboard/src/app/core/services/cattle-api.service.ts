import { Injectable, inject, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { lastValueFrom } from 'rxjs';
import { AuthService } from './auth.service';
import { environment } from '@env/environment';


@Injectable({ providedIn: 'root' })
export class CattleApiService {
    private http = inject(HttpClient);
    private authService = inject(AuthService);
    private apiUrl_crud = environment.apiUrl_crud;

    public isProcessing = signal<boolean>(false);

    // 0. Obtener Inventario Completo (Censo Biológico)
    // 0. Obtener Inventario Completo (Ahora lee de la Vista SQL con los KPIs integrados)
    public async getAllLivestock(): Promise<any[]> {
        const companyId = this.authService.currentUser()?.id_company;
        if (!companyId) throw new Error('Sesión inválida: No se detectó una empresa activa.');

        const res: any = await lastValueFrom(
            // 🚀 CAMBIO AQUÍ: Apuntamos a la vista vw_cattle_kpi en lugar de la tabla base
            this.http.post(`${this.apiUrl_crud}/vw_cattle_kpi`, {
                operation: 'getall'
            })
        );

        if (res && res.error) throw new Error(res.message);

        const data = res.data || [];
        return data.filter((animal: any) => animal.tenant_id === companyId);
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
   * 🚀 Registra un nuevo Gasto Operativo (Alimentación, Medicina, etc.)
   * Endpoint orquestado a través del webhook de n8n para insertar en 'cattle_expenses'
   */
    public async createExpense(fields: any): Promise<void> {
        // 1. Extraemos dinámicamente la empresa del usuario actual (Mejor que dejarlo fijo)
        const companyId = this.authService.currentUser()?.id_company;
        if (!companyId) throw new Error('Sesión inválida: No se detectó una empresa activa.');

        // 2. Sobrescribimos el tenant_id por seguridad
        fields.tenant_id = companyId;

        // 3. Ejecutamos la petición con la estructura estándar de n8n
        const res: any = await lastValueFrom(
            this.http.post(`${this.apiUrl_crud}/cattle_expenses`, {
                operation: 'insert',
                fields: fields
            })
        );

        if (res && res.error) throw new Error(res.message);
    }

    // 🚀 Obtener historial de gastos operativos
    public async getExpenses(): Promise<any[]> {
        const companyId = this.authService.currentUser()?.id_company;
        if (!companyId) throw new Error('Sesión inválida: No se detectó una empresa activa.');

        const res: any = await lastValueFrom(
            this.http.post(`${this.apiUrl_crud}/cattle_expenses`, {
                operation: 'getall'
            })
        );

        if (res && res.error) throw new Error(res.message);
        const data = res.data || [];
        return data.filter((expense: any) => expense.tenant_id === companyId);
    }
}