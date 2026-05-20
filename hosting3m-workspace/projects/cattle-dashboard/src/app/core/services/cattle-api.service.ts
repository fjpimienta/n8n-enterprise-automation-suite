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
    public async getAllLivestock(): Promise<any[]> {
        const companyId = this.authService.currentUser()?.id_company;
        if (!companyId) throw new Error('Sesión inválida: No se detectó una empresa activa.');

        const res: any = await lastValueFrom(
            this.http.post(`${this.apiUrl_crud}/cattle_livestock`, {
                operation: 'getall'
                // Si tu Meta-CRUD lo soporta, aquí podrías enviar: where: `tenant_id = ${companyId}`
            })
        );

        if (res && res.error) throw new Error(res.message);

        // Filtramos localmente por seguridad multi-tenant (por si el backend envía todo)
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
}