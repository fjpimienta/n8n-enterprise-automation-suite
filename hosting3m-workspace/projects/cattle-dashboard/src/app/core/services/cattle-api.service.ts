import { Injectable, inject, signal } from '@angular/core';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { lastValueFrom } from 'rxjs';
import { environment } from '@env/environment';

@Injectable({ providedIn: 'root' })
export class CattleApiService {
    private http = inject(HttpClient);
    private apiUrl_crud = environment.apiUrl_crud;

    public isProcessing = signal<boolean>(false);

    // Método auxiliar para headers (igual que en tu app de hotel)
    private getAuthHeaders() {
        const token = localStorage.getItem('authToken');
        console.warn('🕵️ Token actual enviado a n8n:', token);
        return new HttpHeaders({
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${token}`
        });
    }

    // 1. Crear Alta de Animal

    // 1. Crear Alta de Animal
    public async createLivestock(fields: any): Promise<void> {
        // 🛠️ FIX: Asignamos el UUID exacto que acabamos de crear en la Base de Datos
        fields.tenant_id = '11111111-1111-1111-1111-111111111111';

        const res: any = await lastValueFrom(
            this.http.post(`${this.apiUrl_crud}/cattle_livestock`, {
                operation: 'insert',
                fields: fields
            }, { headers: this.getAuthHeaders() })
        );

        // 🛑 ESCUDO: Si Meta-CRUD dice que hubo error, lanzamos la excepción para que el Modal la atrape
        if (res && res.error) throw new Error(res.message);
    }

    // 2. Crear Evento Sanitario
    public async createHealthLog(fields: any): Promise<void> {
        const res: any = await lastValueFrom(
            this.http.post(`${this.apiUrl_crud}/cattle_health_logs`, {
                operation: 'insert',
                fields: fields
            }, { headers: this.getAuthHeaders() })
        );
        if (res && res.error) throw new Error(res.message);
    }

    // 3. Crear Registro de Peso
    public async createWeightLog(fields: any): Promise<void> {
        const res: any = await lastValueFrom(
            this.http.post(`${this.apiUrl_crud}/cattle_weight_logs`, {
                operation: 'insert',
                fields: fields
            }, { headers: this.getAuthHeaders() })
        );
        if (res && res.error) throw new Error(res.message);
    }
}