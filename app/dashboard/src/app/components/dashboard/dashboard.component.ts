import { Component, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { AuthService } from '../../services/auth.service';
import { Router } from '@angular/router';
import { HotelService } from '../../services/hotel.service';
import { HttpClient } from '@angular/common/http';

@Component({
  selector: 'app-dashboard',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './dashboard.component.html'
})
export class DashboardComponent {
  private authService = inject(AuthService);
  private router = inject(Router);
  public hotelService = inject(HotelService);
  private http = inject(HttpClient);

  // URL de tu Webhook de n8n para notificaciones
  private readonly N8N_WHATSAPP_WEBHOOK = 'https://tu-n8n.com/webhook/whatsapp-notifications';

  ngOnInit() {
    this.refresh();
  }

  refresh() {
    this.hotelService.loadRooms();
  }

  logout() {
    this.authService.logout();
    this.router.navigate(['/login']);
  }

  // Nueva función para botones de acción
  notifyN8N(action: 'checkin' | 'checkout' | 'maintenance') {
    const room = this.hotelService.selectedRoom();
    if (!room) return;

    if (confirm(`¿Confirmas la acción: ${action} para la habitación ${room.room_number}?`)) {

      const payload = {
        action: action,
        room_number: room.room_number,
        room_id: room.id,
        user: this.authService.currentUser()?.name || 'Recepción'
      };

      // Llamada "Fire and Forget" al webhook
      this.http.post(this.N8N_WHATSAPP_WEBHOOK, payload).subscribe({
        next: () => {
          alert('Solicitud enviada a n8n ✅');
          this.hotelService.clearSelection(); // Cierra modal
          // Opcional: Recargar estado
          setTimeout(() => this.refresh(), 1000);
        },
        error: () => alert('Error conectando con n8n ❌')
      });
    }
  }
}