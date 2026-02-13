import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { environment } from '@env/environment';
import { AdminService } from './admin.service';
import { lastValueFrom } from 'rxjs';

@Injectable({
  providedIn: 'root'
})
export class AssetService {
  private http = inject(HttpClient);
  private apiUrl = environment.apiUrl_crud;
  private adminService = inject(AdminService);

  // Obtener todos los activos
  async getAssets() {
    return this.request({
      entity: 'hotel_assets',
      table_name: 'hotel_assets',
      operation: 'getall',
      action: 'list'
    });
  }

  // Obtener activos por habitación
  async getAssetsByRoom(roomId: number) {
    return this.request({
      entity: 'hotel_assets',
      table_name: 'hotel_assets',
      operation: 'getall', // Debe ser getall para traer la lista
      action: 'list',
      filters: {
        current_room_id: roomId // Esto ahora funcionará porque actualizamos crud_models
      }
    });
  }

  // Crear o Actualizar
  async saveAsset(asset: any, id?: number) {
    const payload = {
      entity: 'hotel_assets',
      table_name: 'hotel_assets',
      operation: id ? 'update' : 'insert',
      action: id ? 'update' : 'insert',
      id: id,
      fields: asset
    };
    return this.request(payload);
  }

  // Helper privado
  private async request(body: any) {
    try {
      const res: any = await lastValueFrom(
        this.http.post(`${this.apiUrl}/hotel_assets`, body, {
          headers: this.adminService.getAuthHeaders()
        })
      );
      // Tu backend devuelve la data dentro de la propiedad 'data'
      return res.data || [];
    } catch (error) {
      console.error('Asset API Error:', error);
      throw error;
    }
  }
}