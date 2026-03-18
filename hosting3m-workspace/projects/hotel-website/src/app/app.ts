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
  private apiUrl_public = environment.apiUrl_public;
  private apiUrl_crud = environment.apiUrl_crud; // Agregado para el MetaCRUD

  isMenuOpen = signal(false);
  isScrolled = signal(false);

  bookingStep = signal<1 | 2 | 3>(1);
  isSearching = signal(false);
  isSubmitting = signal(false);

  formStatus = signal<'idle' | 'success' | 'invalid_email' | 'sold_out' | 'email_bounce' | 'error'>('idle');

  dates = { checkin: '', checkout: '' };
  guest = { name: '', email: '', phone: '', guests: 2 };

  availableRoomTypes = signal<any[]>([]);
  selectedRoomType = signal<any | null>(null);

  // --- RESEÑAS DINÁMICAS (n8n DB) ---
  dbReviews = signal<any[]>([]);
  // --- ESTADO PARA EL MODAL DE RESEÑAS ---
  showReviewModal = signal(false);
  isSubmittingReview = signal(false);
  reviewForm = { guest_name: '', rating: 5, review_text: '' };

  // --- MÉTODOS DEL MODAL ---
  openReviewModal() {
    this.showReviewModal.set(true);
  }

  closeReviewModal() {
    this.showReviewModal.set(false);
    this.reviewForm = { guest_name: '', rating: 5, review_text: '' }; // Limpiar form
  }

  setRating(stars: number) {
    this.reviewForm.rating = stars;
  }

  // --- CARGA DE RESEÑAS DESDE n8n MetaCRUD ---
  loadDbReviews() {
    // Pasamos el modelo como Query Parameter
    const url = `${this.apiUrl_crud}?model=hotel_reviews`;

    // AGREGADO: Payload vacío u operación explícita para satisfacer la firma de http.post()
    const payload = { operation: 'getall' };

    this.http.post(url, payload).subscribe({
      next: (res: any) => {
        console.log('✅ MetaCRUD Respondió (POST):', res);

        const data = res.data || res;
        if (Array.isArray(data) && data.length > 0) {
          this.dbReviews.set(data.slice(0, 3));
          setTimeout(() => {
            // @ts-ignore
            if (window.lucide) window.lucide.createIcons();
          }, 50);
        } else {
          console.warn('⚠️ N8n respondió bien, pero el arreglo de reseñas viene vacío.');
        }
      },
      error: (err) => {
        console.error('❌ Error crítico descargando reseñas desde n8n:', err);
      }
    });
  }

  submitReview() {
    if (!this.reviewForm.guest_name || !this.reviewForm.review_text) return;

    this.isSubmittingReview.set(true);
    const payload = { ...this.reviewForm, is_approved: false };

    // Ajuste arquitectónico: Pasamos el modelo como Query Parameter
    const url = `${this.apiUrl_crud}?model=hotel_reviews`;

    this.http.post(url, payload).subscribe({
      next: (res: any) => {
        console.log('✅ MetaCRUD Respondió (POST):', res);
        this.isSubmittingReview.set(false);
        this.closeReviewModal();
        alert('¡Gracias por tu reseña! Ha sido enviada a moderación y pronto aparecerá en la página.');
      },
      error: (err) => {
        console.error('❌ Error enviando reseña hacia n8n:', err);
        this.isSubmittingReview.set(false);
        alert('Hubo un error al enviar tu reseña. Por favor, intenta de nuevo.');
      }
    });
  }

  minDate = new Date().toISOString().split('T')[0];

  get guestOptions(): number[] {
    const room = this.selectedRoomType();
    if (!room) return [1, 2];
    return Array.from({ length: room.maxGuests }, (_, i) => i + 1);
  }

  get extraGuestsCount(): number {
    const room = this.selectedRoomType();
    if (!room) return 0;
    const selectedGuests = Number(this.guest.guests) || 1;
    return Math.max(0, selectedGuests - room.baseGuests);
  }

  get currentTotalPerNight(): number {
    const room = this.selectedRoomType();
    if (!room) return 0;
    return room.price + (this.extraGuestsCount * 100);
  }

  ngOnInit() {
    setTimeout(() => {
      // @ts-ignore
      if (window.lucide) window.lucide.createIcons();
    }, 100);

    // Cargar las reseñas al iniciar la aplicación
    this.loadDbReviews();
  }

  @HostListener('window:scroll', [])
  onWindowScroll() {
    this.isScrolled.set(window.scrollY > 20);
  }

  toggleMenu() {
    this.isMenuOpen.update(val => !val);
  }

  searchAvailability() {
    if (!this.dates.checkin || !this.dates.checkout) return;
    this.isSearching.set(true);

    const payload = { checkin: this.dates.checkin, checkout: this.dates.checkout };

    this.http.post(`${this.apiUrl_public}/availability`, payload).subscribe({
      next: (res: any) => {
        if (res.status === 'success' && res.data) {

          const mappedRooms = res.data.map((room: any) => {
            const typeKey = room.type.toLowerCase();
            let icon = 'bed', desc = '', name = room.type;
            let baseGuests = 2, maxGuests = 2;

            if (typeKey.includes('sencilla')) {
              icon = 'user'; desc = '1 Cama Matrimonial'; name = 'Sencilla';
              baseGuests = 2; maxGuests = 3;
            } else if (typeKey.includes('king')) {
              icon = 'crown'; desc = '1 Cama King Size'; name = 'King Size';
              baseGuests = 3; maxGuests = 4;
            } else if (typeKey.includes('doble')) {
              icon = 'users'; desc = '2 Camas Matrimoniales'; name = 'Doble';
              baseGuests = 4; maxGuests = 6;
            } else if (typeKey.includes('triple')) {
              icon = 'bed-double'; desc = 'Máxima Capacidad'; name = 'Triple';
              baseGuests = 6; maxGuests = 8;
            }

            return {
              id: room.type,
              name: name,
              desc: desc,
              price: parseFloat(room.price),
              icon: icon,
              availableCount: parseInt(room.available_count, 10),
              baseGuests: baseGuests,
              maxGuests: maxGuests
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
        console.error('Error buscando disponibilidad:', err);
        this.isSearching.set(false);
        alert('Ocurrió un error al buscar disponibilidad. Por favor, intenta nuevamente.');
      }
    });
  }

  selectRoom(roomType: any) {
    this.selectedRoomType.set(roomType);
    this.guest.guests = roomType.baseGuests;
    this.bookingStep.set(3);
  }

  goBack(step: 1 | 2) {
    this.bookingStep.set(step);
    if (step === 1) this.availableRoomTypes.set([]);
  }

  submitForm() {
    this.isSubmitting.set(true);
    this.formStatus.set('idle');

    const payload = {
      name: this.guest.name,
      phone: this.guest.phone,
      email: this.guest.email,
      checkin: this.dates.checkin,
      checkout: this.dates.checkout,
      room_type: this.selectedRoomType()?.id,
      guests: Number(this.guest.guests),
      total_price_per_night: this.currentTotalPerNight,
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
        if (err.status === 400) this.formStatus.set('invalid_email');
        else if (err.status === 409) this.formStatus.set('sold_out');
        else if (err.status === 422) this.formStatus.set('email_bounce');
        else {
          this.formStatus.set('error');
          console.error('Error de conexión con n8n:', err);
        }
      }
    });
  }

  resetWizard() {
    this.bookingStep.set(1);
    this.selectedRoomType.set(null);
    this.formStatus.set('idle');
    this.dates = { checkin: '', checkout: '' };
    this.guest = { name: '', email: '', phone: '', guests: 2 };
  }
}