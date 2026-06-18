import { Injectable, inject, signal, effect } from '@angular/core';
import { CattleApiService } from './cattle-api.service';
import { TenantService } from 'core-auth';

@Injectable({
  providedIn: 'root'
})
export class CattleDataService {
  private cattleApi = inject(CattleApiService);
  private tenantService = inject(TenantService);

  // States reactivos globales del dominio ganadero
  public cattleList = signal<any[]>([]);
  public isLoading = signal<boolean>(false);

  constructor() {
    // Orquestador del ciclo de vida de los datos basado en el contexto de la empresa
    effect(() => {
      const tenantId = this.tenantService.activeTenantId();
      if (tenantId) {
        this.loadCattleData();
      }
    }, { allowSignalWrites: true });
  }

  /**
   * Ejecuta la petición HTTP hacia la capa Meta-CRUD a través de n8n
   * utilizando el contexto del Tenant activo actual.
   */
  public async loadCattleData() {
    this.isLoading.set(true);
    try {
      const data = await this.cattleApi.getAllLivestock();
      this.cattleList.set(data || []);
    } catch (error) {
      console.error('Error crítico en el Data Pipeline de CattleDataService:', error);
    } finally {
      this.isLoading.set(false);
    }
  }
}