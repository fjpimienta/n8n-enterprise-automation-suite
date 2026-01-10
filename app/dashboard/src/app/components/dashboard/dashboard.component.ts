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
  notifyN8N(action: 'checkin' | 'checkout' | 'maintenance' | 'clean_complete' | 'inspected') {
    const room = this.hotelService.selectedRoom();
    if (!room) return;

    // Definimos los mensajes asegurando que cubran todas las acciones posibles
    const messages: Record<'checkin' | 'checkout' | 'maintenance' | 'clean_complete' | 'inspected', string> = {
      checkin: `¿Confirmar ingreso (Check-in) en Habitación ${room.room_number}?`,
      checkout: `¿Confirmar salida (Check-out) de Habitación ${room.room_number}? La habitación pasará a estado SUCIA.`,
      maintenance: `¿Enviar Habitación ${room.room_number} a mantenimiento?`,
      clean_complete: `¿Confirmar que la Habitación ${room.room_number} ya está limpia?`,
      inspected: `¿Confirmar que la Habitación ${room.room_number} ha sido inspeccionada y está lista para venta?`
    };

    if (confirm(messages[action])) {
      const payload = {
        action: action,
        room_number: room.room_number,
        room_id: room.id,
        user: this.authService.currentUser()?.name || 'Recepción'
      };

      this.http.post(this.N8N_WHATSAPP_WEBHOOK, payload).subscribe({
        next: () => {
          alert('Estado actualizado correctamente ✅');
          this.hotelService.clearSelection();
          this.refresh();
        },
        error: () => alert('Error al conectar con el servidor ❌')
      });
    }
  }

  // Dentro de tu DashboardComponent
  isArrivalToday(reservationDate?: string): boolean {
    if (!reservationDate) return false;

    const today = new Date().toISOString().split('T')[0]; // Formato YYYY-MM-DD
    return reservationDate.startsWith(today);
  }
}