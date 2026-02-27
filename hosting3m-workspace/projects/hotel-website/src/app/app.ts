import { Component, OnInit, inject, signal, HostListener } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { HttpClient } from '@angular/common/http';
import { AiChatComponent } from 'ui-chat';
import { environment } from '../environments/environment';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [CommonModule, FormsModule, AiChatComponent],
  templateUrl: './app.html'
})
export class App implements OnInit {
  private http = inject(HttpClient);

  // Extraemos las URLs correctas de tu environment
  private apiUrl_public = environment.apiUrl_public;

  // Estados de la Interfaz UI
  isMenuOpen = signal(false);
  isScrolled = signal(false);

  // --- WIZARD DE RESERVAS B2C ---
  bookingStep = signal<1 | 2 | 3>(1);
  isSearching = signal(false);
  isSubmitting = signal(false);

  formStatus = signal<'idle' | 'success' | 'invalid_email' | 'sold_out' | 'email_bounce' | 'error'>('idle');

  // 👇 CORRECCIÓN: Regresamos a objetos planos compatibles con [(ngModel)]
  dates = { checkin: '', checkout: '' };
  guest = { name: '', email: '', phone: '', guests: '2' };

  // Catálogo simulado (Mock - Conexión visual Paso 2)
  availableRoomTypes = signal<any[]>([]);
  selectedRoomType = signal<any | null>(null);

  minDate = new Date().toISOString().split('T')[0];

  ngOnInit() {
    setTimeout(() => {
      // @ts-ignore
      if (window.lucide) window.lucide.createIcons();
    }, 100);
  }

  @HostListener('window:scroll', [])
  onWindowScroll() {
    this.isScrolled.set(window.scrollY > 20);
  }

  toggleMenu() {
    this.isMenuOpen.update(val => !val);
  }

  // --- LÓGICA DEL MOTOR DE RESERVAS ---

  searchAvailability() {
    // Leemos directamente del objeto plano
    if (!this.dates.checkin || !this.dates.checkout) return;
    this.isSearching.set(true);

    const payload = {
      checkin: this.dates.checkin,
      checkout: this.dates.checkout
    };

    // Conexión real a n8n /public/availability
    this.http.post(`${this.apiUrl_public}/availability`, payload).subscribe({
      next: (res: any) => {
        if (res.status === 'success' && res.data) {

          const mappedRooms = res.data.map((room: any) => {
            const typeKey = room.type.toLowerCase();
            let icon = 'bed';
            let desc = 'Habitación confortable';
            let name = room.type;

            if (typeKey.includes('sencilla')) {
              icon = 'user'; desc = '1 Cama Matrimonial'; name = 'Sencilla';
            } else if (typeKey.includes('king')) {
              icon = 'crown'; desc = '1 Cama King Size'; name = 'King Size';
            } else if (typeKey.includes('doble')) {
              icon = 'users'; desc = '2 Camas Matrimoniales'; name = 'Doble';
            } else if (typeKey.includes('triple')) {
              icon = 'bed-double'; desc = 'Máxima Capacidad'; name = 'Triple';
            }

            return {
              id: room.type, // ID Exacto para n8n ("Kingsize", "sencilla")
              name: name,
              desc: desc,
              price: parseFloat(room.price),
              icon: icon,
              availableCount: parseInt(room.available_count, 10)
            };
          });

          this.availableRoomTypes.set(mappedRooms);
          this.isSearching.set(false);

          if (mappedRooms.length === 0) {
            alert('Lo sentimos, no hay habitaciones disponibles de ningún tipo para las fechas seleccionadas.');
          } else {
            this.bookingStep.set(2);
          }
        }
      },
      error: (err) => {
        console.error('Error buscando disponibilidad en n8n:', err);
        this.isSearching.set(false);
        alert('Ocurrió un error al buscar disponibilidad. Por favor, intenta nuevamente.');
      }
    });
  }

  selectRoom(roomType: any) {
    this.selectedRoomType.set(roomType);
    this.bookingStep.set(3);
  }

  goBack(step: 1 | 2) {
    this.bookingStep.set(step);
    if (step === 1) this.availableRoomTypes.set([]);
  }

  submitForm() {
    this.isSubmitting.set(true);
    this.formStatus.set('idle');

    // 👇 CORRECCIÓN: Leemos directamente del objeto plano
    const payload = {
      name: this.guest.name,
      phone: this.guest.phone,
      email: this.guest.email,
      checkin: this.dates.checkin,
      checkout: this.dates.checkout,
      room_type: this.selectedRoomType()?.id,
      guests: this.guest.guests,
      origen: "Web Frontend Angular (Public)"
    };

    this.http.post(`${this.apiUrl_public}/lead`, payload).subscribe({
      next: (res: any) => {
        this.formStatus.set('success');
        this.isSubmitting.set(false);
        setTimeout(() => this.resetWizard(), 20000);
      },
      error: (err) => {
        this.isSubmitting.set(false);
        if (err.status === 400) {
          this.formStatus.set('invalid_email');
        } else if (err.status === 409) {
          this.formStatus.set('sold_out');
        } else if (err.status === 422) {
          // 👇 NUEVO: El servidor de correo de n8n rechazó la entrega
          this.formStatus.set('email_bounce');
        } else {
          this.formStatus.set('error');
          console.error('Error de conexión crítica con n8n:', err);
        }
      }
    });
  }

  resetWizard() {
    // La reactividad se dispara por los Signals .set()
    this.bookingStep.set(1);
    this.selectedRoomType.set(null);
    this.formStatus.set('idle');

    // 👇 CORRECCIÓN: Limpieza de objetos planos normal
    this.dates = { checkin: '', checkout: '' };
    this.guest = { name: '', email: '', phone: '', guests: '2' };
  }
}